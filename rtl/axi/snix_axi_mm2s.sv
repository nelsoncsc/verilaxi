module snix_axi_mm2s  #(parameter int ADDR_WIDTH = 32,
                        parameter int DATA_WIDTH = 64,
                        parameter int ID_WIDTH   = 4,
                        parameter int USER_WIDTH = 1,
                        parameter int FIFO_DEPTH = 16) 
                       (// Global signals
                        input  logic                     clk,
                        input  logic                     rst_n,
                        // Control interface
                        input  logic                     ctrl_rd_start,
                        input  logic                     ctrl_rd_stop,
                        input  logic [ADDR_WIDTH-1:0]    ctrl_rd_addr,
                        input  logic [7:0]               ctrl_rd_len,
                        input  logic [2:0]               ctrl_rd_size,
                        input  logic [31:0]              ctrl_rd_transfer_len,
                        input  logic                     ctrl_rd_circular_mode,
                        output logic                     ctrl_rd_done,
                        // AXI-Stream output
                        output logic [DATA_WIDTH-1:0]    m_axis_tdata,
                        output logic                     m_axis_tvalid,
                        input  logic                     m_axis_tready,
                        output logic                     m_axis_tlast,
                        // AR Channel
                        output logic [ID_WIDTH-1:0]      mm2s_arid,
                        output logic [ADDR_WIDTH-1:0]    mm2s_araddr,
                        output logic [7:0]               mm2s_arlen,
                        output logic [2:0]               mm2s_arsize,
                        output logic [1:0]               mm2s_arburst,
                        output logic                     mm2s_arlock,
                        output logic [3:0]               mm2s_arcache,
                        output logic [2:0]               mm2s_arprot,
                        output logic [3:0]               mm2s_arqos,
                        output logic [USER_WIDTH-1:0]    mm2s_aruser,
                        output logic                     mm2s_arvalid,
                        input  logic                     mm2s_arready,
                        // R Channel
                        input  logic [ID_WIDTH-1:0]      mm2s_rid,
                        input  logic [DATA_WIDTH-1:0]    mm2s_rdata,
                        input  logic [1:0]               mm2s_rresp,
                        input  logic                     mm2s_rlast,
                        input  logic [USER_WIDTH-1:0]    mm2s_ruser,
                        input  logic                     mm2s_rvalid,
                        output logic                     mm2s_rready
                       );

    // -------------------------------------------------------------------------
    // Start / stop edge detection
    // -------------------------------------------------------------------------
    logic ctrl_rd_start_r, rd_start_edge;
    logic ctrl_rd_stop_r,  rd_stop_edge;

    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            ctrl_rd_start_r <= 1'b0;
            ctrl_rd_stop_r  <= 1'b0;
        end else begin
            ctrl_rd_start_r <= ctrl_rd_start;
            ctrl_rd_stop_r  <= ctrl_rd_stop;
        end

    assign rd_start_edge = ctrl_rd_start & ~ctrl_rd_start_r;
    assign rd_stop_edge  = ctrl_rd_stop  & ~ctrl_rd_stop_r;

    // -------------------------------------------------------------------------
    // Abort latch — set on stop edge, cleared on start edge
    // -------------------------------------------------------------------------
    logic rd_abort;

    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n)             rd_abort <= 1'b0;
        else if (rd_stop_edge)  rd_abort <= 1'b1;
        else if (rd_start_edge) rd_abort <= 1'b0;

    // -------------------------------------------------------------------------
    // FSM
    // FIX: added PREP_AR state (was missing entirely); enum widened to 3 bits.
    // -------------------------------------------------------------------------
    typedef enum logic [2:0] {IDLE, PREP1, PREP2, AR, READ, WAIT_RRESP} state_t;
    state_t state, next_state;

    logic transfer_done;

    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) state <= IDLE;
        else        state <= next_state;

    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                next_state = (ctrl_rd_start && !rd_abort) ? PREP1 : IDLE;
            end
            PREP1: begin
                next_state = rd_abort ? IDLE : PREP2;
            end
            PREP2: begin
                next_state = AR;
            end
            AR: begin
                if (rd_abort)
                    next_state = IDLE;
                else
                    // FIX: was "&" (bitwise); changed to "&&" (logical)
                    next_state = (mm2s_arvalid && mm2s_arready) ? READ : AR;
            end
            READ: begin
                next_state = (mm2s_rvalid && mm2s_rready && mm2s_rlast) ? WAIT_RRESP : READ;
            end
            WAIT_RRESP: begin
                if (rd_abort)
                    next_state = IDLE;
                else if (transfer_done)
                    next_state = IDLE;
                else
                    next_state = PREP1;
            end
            default: ;
        endcase
    end

    // -------------------------------------------------------------------------
    // 4K boundary & burst-length computation — pipelined across PREP1 / PREP2
    //
    //   PREP1  [Stage 1]: max_arlen, next_arsize, axi_next_addr (all regs)
    //                     → next_bytes → cross_4k → bytes_to_4k
    //                     → register  bytes_to_4k_r
    //
    //   PREP2  [Stage 2]: bytes_to_4k_r, pending_bytes, next_arsize (all regs)
    //                     → num_bytes_comb → next_arlen_o
    //                     → register  next_arlen  |  decrement  pending_bytes
    //
    // max_arlen holds ctrl_rd_len for the life of the transfer so that
    // next_bytes always reflects the full configured burst width.
    // -------------------------------------------------------------------------
    logic [7:0]            max_arlen;
    logic [2:0]            next_arsize;
    logic [ADDR_WIDTH-1:0] axi_next_addr;
    logic [31:0]           pending_bytes;

    // Stage 1 wires — driven from stable registered inputs
    logic [14:0] next_bytes;
    logic        cross_4k;
    logic [14:0] bytes_to_4k;
    // Stage 1 → Stage 2 pipeline register
    logic [14:0] bytes_to_4k_r;
    // Stage 2 wires — driven from bytes_to_4k_r (registered)
    logic [14:0] num_bytes_comb;
    logic [7:0]  next_arlen_o;

    // Stage 1 combinatorial
    assign next_bytes     = compute_num_bytes(max_arlen, next_arsize);
    assign cross_4k       = ({1'b0, next_bytes} + {4'b0, axi_next_addr[11:0]}) >= 16'd4096;
    assign bytes_to_4k    = cross_4k ? (15'd4096 - {3'b0, axi_next_addr[11:0]}) : next_bytes;

    // Stage 2 combinatorial — uses bytes_to_4k_r, not bytes_to_4k
    assign num_bytes_comb = ({{17{1'b0}}, bytes_to_4k_r} <= pending_bytes)
                            ? bytes_to_4k_r
                            : pending_bytes[14:0];
    assign next_arlen_o   = compute_next_len(num_bytes_comb, next_arsize);

    // -------------------------------------------------------------------------
    // Circular-mode reload trigger
    //
    // FIX: ctrl_rd_circular_mode was declared but completely unused.
    // circ_restart fires on the final WAIT_RRESP of a complete transfer when
    // circular mode is active.  It reloads the start address and counters so
    // the DMA seamlessly restarts from ctrl_rd_addr on the next IDLE→PREP1.
    // -------------------------------------------------------------------------
    logic circ_restart;
    assign circ_restart = ctrl_rd_circular_mode && !rd_abort &&
                          (state == WAIT_RRESP) && transfer_done;

    // -------------------------------------------------------------------------
    // Transfer length alignment (registered for timing)
    // 
    // AXI reads always return full beats. When the requested transfer length
    // is not a multiple of the beat size, round up to the next beat boundary.
    // Example: 258 bytes with size=3 (8 bytes/beat) → 264 bytes (33 beats)
    //
    // NOTE: Uses case statement instead of barrel shifter (1 << size) for
    // better timing closure at high frequencies.
    // -------------------------------------------------------------------------
    logic [31:0] aligned_transfer_len;
    
    // Combinatorial alignment using case statement (no barrel shifter)
    always_comb begin
        case (ctrl_rd_size)
            3'b000: aligned_transfer_len = ctrl_rd_transfer_len;  // 1-byte aligned (no change)
            3'b001: aligned_transfer_len = (ctrl_rd_transfer_len + 32'd1) & ~32'd1;   // 2-byte
            3'b010: aligned_transfer_len = (ctrl_rd_transfer_len + 32'd3) & ~32'd3;   // 4-byte
            3'b011: aligned_transfer_len = (ctrl_rd_transfer_len + 32'd7) & ~32'd7;   // 8-byte
            3'b100: aligned_transfer_len = (ctrl_rd_transfer_len + 32'd15) & ~32'd15; // 16-byte
            3'b101: aligned_transfer_len = (ctrl_rd_transfer_len + 32'd31) & ~32'd31; // 32-byte
            3'b110: aligned_transfer_len = (ctrl_rd_transfer_len + 32'd63) & ~32'd63; // 64-byte
            3'b111: aligned_transfer_len = (ctrl_rd_transfer_len + 32'd127) & ~32'd127; // 128-byte
        endcase
    end

    // -------------------------------------------------------------------------
    // Transfer-state registers
    //
    // TIMING FIX: Added burst_actual_bytes register to avoid calling
    //             compute_num_bytes in AR state (combinatorial function).
    //             Also moved pending_bytes update to AR state.
    // -------------------------------------------------------------------------
    logic [31:0] transfer_len;
    logic [31:0] read_bytes;
    logic [7:0]  next_arlen;
    logic [14:0] burst_actual_bytes;  // Registered burst size for timing

    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            axi_next_addr      <= '0;
            next_arlen         <= '0;
            max_arlen          <= '0;
            next_arsize        <= '0;
            read_bytes         <= '0;
            transfer_len       <= '0;
            bytes_to_4k_r      <= '0;
            burst_actual_bytes <= '0;
        end else if (rd_start_edge || circ_restart) begin
            axi_next_addr      <= ctrl_rd_addr;
            next_arlen         <= ctrl_rd_len;
            max_arlen          <= ctrl_rd_len;
            next_arsize        <= ctrl_rd_size;
            read_bytes         <= '0;
            transfer_len       <= aligned_transfer_len;  // Use aligned length
            burst_actual_bytes <= '0;
        end else if (state == PREP1) begin
            bytes_to_4k_r <= bytes_to_4k;   // Stage 1 → Stage 2 pipeline register
        end else if (state == PREP2) begin
            next_arlen         <= next_arlen_o;      // Stage 2 result captured before AR
            burst_actual_bytes <= num_bytes_comb;    // Store actual bytes for this burst
        end else if (state == AR && mm2s_arready) begin
            // Use registered burst_actual_bytes instead of compute_num_bytes
            axi_next_addr <= axi_next_addr + {{(ADDR_WIDTH-15){1'b0}}, burst_actual_bytes};
            read_bytes    <= read_bytes    + {17'b0, burst_actual_bytes};
        end

    // pending_bytes — decremented in AR state after burst_actual_bytes is registered
    // TIMING FIX: Moved from PREP2 to AR state to break critical path.
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n)
            pending_bytes <= '0;
        else if (rd_start_edge || circ_restart)
            pending_bytes <= aligned_transfer_len;  // Use aligned length
        else if (state == AR && mm2s_arready)
            pending_bytes <= pending_bytes - {17'b0, burst_actual_bytes};

    // -------------------------------------------------------------------------
    // Transfer-done flag
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n)
            transfer_done <= 1'b0;
        else if (rd_start_edge || state == IDLE || state == AR || state == PREP1 || state == PREP2)
            transfer_done <= 1'b0;
        else
            transfer_done <= (read_bytes == transfer_len) && (read_bytes != '0);

    // FIX: ctrl_rd_done was a combinatorial level signal (stayed asserted for the
    // entire time the FSM remained in IDLE).  Now a single-cycle registered pulse
    // that fires exactly when the FSM transitions into IDLE (completion or abort).
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) ctrl_rd_done <= 1'b0;
        else        ctrl_rd_done <= (next_state == IDLE) && (state != IDLE);

    // -------------------------------------------------------------------------
    // FIFO
    //
    // FIX: mm2s_rready was driven directly by the FIFO's s_axis_tready, meaning
    // the DMA accepted R-channel beats regardless of FSM state.  For an
    // aggressive interconnect that responds in the same cycle as arready, R data
    // could arrive while the FSM was still in AR, causing the rlast beat to be
    // consumed before READ was entered, leaving the FSM stuck waiting forever.
    //
    // Fix: use an intermediate wire (fifo_s_tready) for the FIFO port and gate
    // mm2s_rready so the R channel is only accepted in READ state.
    // -------------------------------------------------------------------------
    logic [DATA_WIDTH-1:0] fifo_tdata;
    logic                  fifo_tvalid;
    logic                  fifo_tlast;
    logic                  fifo_tuser;
    logic                  fifo_s_tready;  // FIFO input-side backpressure

    assign mm2s_rready = fifo_s_tready && (state == READ);

    snix_axis_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) axis_fifo_u0 (
        .clk           (clk),
        .rst_n         (rst_n),
        // Input from AXI R channel — gated so data only enters in READ state
        .s_axis_tdata  (mm2s_rdata),
        .s_axis_tlast  (mm2s_rlast),
        .s_axis_tuser  (1'b0),
        .s_axis_tvalid (mm2s_rvalid && (state == READ)),
        .s_axis_tready (fifo_s_tready),
        // Output to AXI-Stream — downstream may drain the FIFO at any time
        .m_axis_tdata  (fifo_tdata),
        .m_axis_tlast  (fifo_tlast),
        .m_axis_tuser  (fifo_tuser),
        .m_axis_tvalid (fifo_tvalid),
        .m_axis_tready (m_axis_tready)
    );

    // -------------------------------------------------------------------------
    // AXI output assignments
    // -------------------------------------------------------------------------
    assign m_axis_tdata   = fifo_tdata;
    assign m_axis_tvalid  = fifo_tvalid;
    assign m_axis_tlast   = fifo_tlast;

    assign mm2s_arvalid = (state == AR);
    assign mm2s_araddr  = axi_next_addr;
    assign mm2s_arlen   = next_arlen;
    assign mm2s_arsize  = next_arsize;
    assign mm2s_arburst = 2'b01;      // INCR
    assign mm2s_arlock  = 1'b0;
    assign mm2s_arcache = 4'b0;
    assign mm2s_arprot  = 3'b0;
    assign mm2s_arqos   = 4'b0;
    assign mm2s_arid    = '0;
    assign mm2s_aruser  = '0;

    // -------------------------------------------------------------------------
    // Functions
    // -------------------------------------------------------------------------

    // Returns total byte count for a burst: (awlen+1) << awsize.
    // No special-case guard needed (unlike the original s2mm version).
    function automatic [14:0] compute_num_bytes(
        input logic [7:0] len,
        input logic [2:0] size
    );
        case (size)
            3'b000: compute_num_bytes = {7'b0, len + 1'b1};
            3'b001: compute_num_bytes = {6'b0, len + 1'b1, 1'b0};
            3'b010: compute_num_bytes = {5'b0, len + 1'b1, 2'b0};
            3'b011: compute_num_bytes = {4'b0, len + 1'b1, 3'b0};
            3'b100: compute_num_bytes = {3'b0, len + 1'b1, 4'b0};
            3'b101: compute_num_bytes = {2'b0, len + 1'b1, 5'b0};
            3'b110: compute_num_bytes = {1'b0, len + 1'b1, 6'b0};
            3'b111: compute_num_bytes = {      len + 1'b1, 7'b0};
        endcase
    endfunction

     // Returns arlen = ceil(bytes / beat_size) - 1, i.e. the number of beats minus 1.
    // NOTE: Uses case statement with pre-computed constants for timing closure.
    function automatic [7:0] compute_next_len(input logic [14:0] bytes_i,
                                              input logic [2:0]  size
                                             );
        logic [14:0] num_beats;
        
        // Ceiling division: (bytes + beat_size - 1) / beat_size
        // Using constant shifts (wire routing only, no barrel shifter)
        case(size)
            3'b000: num_beats = bytes_i;                    // /1
            3'b001: num_beats = (bytes_i + 15'd1) >> 1;     // /2
            3'b010: num_beats = (bytes_i + 15'd3) >> 2;     // /4
            3'b011: num_beats = (bytes_i + 15'd7) >> 3;     // /8
            3'b100: num_beats = (bytes_i + 15'd15) >> 4;    // /16
            3'b101: num_beats = (bytes_i + 15'd31) >> 5;    // /32
            3'b110: num_beats = (bytes_i + 15'd63) >> 6;    // /64
            3'b111: num_beats = (bytes_i + 15'd127) >> 7;   // /128
        endcase
        
        if (num_beats == 15'd0)
            compute_next_len = 8'd0;
        else
            compute_next_len = num_beats[7:0] - 8'd1;
            
    endfunction

endmodule : snix_axi_mm2s

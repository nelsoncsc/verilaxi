module snix_axi_s2mm  #(parameter int ADDR_WIDTH = 32,
                        parameter int DATA_WIDTH = 64,
                        parameter int ID_WIDTH   = 4,
                        parameter int USER_WIDTH = 1,
                        parameter int FIFO_DEPTH = 16) 
                       (// Global signals
                        input  logic                     clk,
                        input  logic                     rst_n,
                        // Control interface
                        input  logic                     ctrl_wr_start,
                        input  logic                     ctrl_wr_stop,
                        input  logic [ADDR_WIDTH-1:0]    ctrl_wr_addr,
                        input  logic [7:0]               ctrl_wr_len,
                        input  logic [2:0]               ctrl_wr_size,
                        input  logic [31:0]              ctrl_wr_transfer_len,
                        input  logic                     ctrl_wr_circular_mode,
                        output logic                     ctrl_wr_done,
                        // AXI-Stream input
                        input  logic [DATA_WIDTH-1:0]    s_axis_tdata,
                        input  logic                     s_axis_tvalid,
                        output logic                     s_axis_tready,
                        input  logic                     s_axis_tlast,
                        // AW Channel
                        output logic [ID_WIDTH-1:0]      s2mm_awid,
                        output logic [ADDR_WIDTH-1:0]    s2mm_awaddr,
                        output logic [7:0]               s2mm_awlen,
                        output logic [2:0]               s2mm_awsize,
                        output logic [1:0]               s2mm_awburst,
                        output logic                     s2mm_awlock,
                        output logic [3:0]               s2mm_awcache,
                        output logic [2:0]               s2mm_awprot,
                        output logic [3:0]               s2mm_awqos,
                        output logic [USER_WIDTH-1:0]    s2mm_awuser,
                        output logic                     s2mm_awvalid,
                        input  logic                     s2mm_awready,
                        // W Channel
                        output logic [DATA_WIDTH-1:0]    s2mm_wdata,
                        output logic [DATA_WIDTH/8-1:0]  s2mm_wstrb,
                        output logic                     s2mm_wlast,
                        output logic [USER_WIDTH-1:0]    s2mm_wuser,
                        output logic                     s2mm_wvalid,
                        input  logic                     s2mm_wready,
                        // B Channel
                        input  logic [ID_WIDTH-1:0]      s2mm_bid,
                        input  logic [1:0]               s2mm_bresp,
                        input  logic [USER_WIDTH-1:0]    s2mm_buser,
                        input  logic                     s2mm_bvalid,
                        output logic                     s2mm_bready
                       );

    // -------------------------------------------------------------------------
    // Local parameters
    // -------------------------------------------------------------------------
    localparam int STRB_WIDTH = DATA_WIDTH / 8;
    localparam int STRB_IDX_WIDTH = $clog2(STRB_WIDTH) + 1;  // +1 to hold full width value

    // -------------------------------------------------------------------------
    // Start / stop edge detection
    // -------------------------------------------------------------------------
    logic ctrl_wr_start_r, wr_start_edge;
    logic ctrl_wr_stop_r,  wr_stop_edge;

    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            ctrl_wr_start_r <= 1'b0;
            ctrl_wr_stop_r  <= 1'b0;
        end else begin
            ctrl_wr_start_r <= ctrl_wr_start;
            ctrl_wr_stop_r  <= ctrl_wr_stop;
        end

    assign wr_start_edge = ctrl_wr_start & ~ctrl_wr_start_r;
    assign wr_stop_edge  = ctrl_wr_stop  & ~ctrl_wr_stop_r;

    // -------------------------------------------------------------------------
    // Abort latch — set on stop edge, cleared on start edge
    // -------------------------------------------------------------------------
    logic wr_abort;

    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n)            wr_abort <= 1'b0;
        else if (wr_stop_edge) wr_abort <= 1'b1;
        else if (wr_start_edge)wr_abort <= 1'b0;

    // -------------------------------------------------------------------------
    // FSM
    // -------------------------------------------------------------------------
    typedef enum logic [2:0] {IDLE, PREP1, PREP2, AW, WRITE, WAIT_BRESP} state_t;
    state_t state, next_state;

    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) state <= IDLE;
        else        state <= next_state;

    logic transfer_done;

    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                next_state = (ctrl_wr_start && !wr_abort) ? PREP1 : IDLE;
            end
            PREP1: begin
                next_state = wr_abort ? IDLE : PREP2;
            end
            PREP2: begin
                next_state = AW;
            end
            AW: begin
                if (wr_abort)
                    next_state = IDLE;
                else
                    next_state = (s2mm_awvalid && s2mm_awready) ? WRITE : AW;
            end
            WRITE: begin
                next_state = (s2mm_wvalid && s2mm_wready && s2mm_wlast) ? WAIT_BRESP : WRITE;
            end
            WAIT_BRESP: begin
                if (s2mm_bvalid && s2mm_bready) begin
                    if (wr_abort)
                        next_state = IDLE;
                    else if (transfer_done)
                        next_state = IDLE;
                    else
                        next_state = PREP1;
                end
            end
            default: ;
        endcase
    end

    // -------------------------------------------------------------------------
    // 4K boundary & burst-length computation — pipelined across PREP1 / PREP2
    //
    // Splitting into two registered stages halves the combinatorial depth:
    //
    //   PREP1  [Stage 1]: max_awlen, next_awsize, axi_next_addr (all regs)
    //                     → next_bytes → cross_4k → bytes_to_4k
    //                     → register  bytes_to_4k_r
    //
    //   PREP2  [Stage 2]: bytes_to_4k_r, pending_bytes, next_awsize (all regs)
    //                     → num_bytes_comb → next_awlen_o
    //                     → register  next_awlen  |  decrement  pending_bytes
    //
    // max_awlen holds ctrl_wr_len for the life of the transfer so that
    // next_bytes always reflects the full configured burst width.
    // -------------------------------------------------------------------------
    logic [7:0]            max_awlen;
    logic [2:0]            next_awsize;
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
    logic [7:0]  next_awlen_o;

    // Stage 1 combinatorial
    assign next_bytes     = compute_num_bytes(max_awlen, next_awsize);
    assign cross_4k       = ({1'b0, next_bytes} + {4'b0, axi_next_addr[11:0]}) >= 16'd4096;
    assign bytes_to_4k    = cross_4k ? (15'd4096 - {3'b0, axi_next_addr[11:0]}) : next_bytes;

    // Stage 2 combinatorial — uses bytes_to_4k_r, not bytes_to_4k
    assign num_bytes_comb = ({{17{1'b0}}, bytes_to_4k_r} <= pending_bytes)
                            ? bytes_to_4k_r
                            : pending_bytes[14:0];
    assign next_awlen_o   = compute_next_len(num_bytes_comb, next_awsize);

    // -------------------------------------------------------------------------
    // Circular-mode reload trigger
    //
    // circ_restart fires on the last B-response of a complete transfer when
    // circular mode is active, causing the address and counters to reload from
    // the control inputs before the FSM re-enters IDLE (and immediately PREP1).
    // -------------------------------------------------------------------------
    logic circ_restart;
    assign circ_restart = ctrl_wr_circular_mode && !wr_abort &&
                          (state == WAIT_BRESP) && s2mm_bvalid && s2mm_bready &&
                          transfer_done;

    // -------------------------------------------------------------------------
    // Transfer-state registers
    // -------------------------------------------------------------------------
    logic [31:0]           transfer_len;
    logic [31:0]           written_bytes;
    logic [7:0]            next_awlen;        // actual awlen for the current burst
    logic [14:0]           burst_actual_bytes; // actual bytes in current burst (for wstrb & tracking)

    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            axi_next_addr      <= '0;
            next_awlen         <= '0;
            max_awlen          <= '0;
            next_awsize        <= '0;
            written_bytes      <= '0;
            transfer_len       <= '0;
            bytes_to_4k_r      <= '0;
            burst_actual_bytes <= '0;
        end else if (wr_start_edge || circ_restart) begin
            axi_next_addr      <= ctrl_wr_addr;
            next_awlen         <= ctrl_wr_len;
            max_awlen          <= ctrl_wr_len;
            next_awsize        <= ctrl_wr_size;
            written_bytes      <= '0;
            transfer_len       <= ctrl_wr_transfer_len;
            burst_actual_bytes <= '0;
        end else if (state == PREP1) begin
            bytes_to_4k_r <= bytes_to_4k;   // Stage 1 → Stage 2 pipeline register
        end else if (state == PREP2) begin
            next_awlen         <= next_awlen_o;        // Stage 2 result captured before AW
            burst_actual_bytes <= num_bytes_comb;      // Store actual bytes for this burst
        end else if (state == AW && s2mm_awready) begin
            // Use burst_actual_bytes (the true byte count) for address and written tracking
            axi_next_addr <= axi_next_addr + {{(ADDR_WIDTH-15){1'b0}}, burst_actual_bytes};
            written_bytes <= written_bytes + {17'b0, burst_actual_bytes};
        end

    // pending_bytes — decremented in AW state after burst_actual_bytes is registered.
    // Subtraction uses registered burst_actual_bytes to avoid a critical path
    // from Stage 2 combinatorial → 32-bit subtract → register.
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n)
            pending_bytes <= '0;
        else if (wr_start_edge || circ_restart)
            pending_bytes <= ctrl_wr_transfer_len;
        else if (state == AW && s2mm_awready)
            pending_bytes <= pending_bytes - {17'b0, burst_actual_bytes};

    // -------------------------------------------------------------------------
    // Transfer-done flag
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n)
            transfer_done <= 1'b0;
        else if (wr_start_edge || state == IDLE || state == AW || state == PREP1 || state == PREP2)
            transfer_done <= 1'b0;
        else
            transfer_done <= (written_bytes == transfer_len) && (written_bytes != '0);

    // ctrl_wr_done: single-cycle pulse on transition into IDLE
    // (fires on both normal completion and abort).
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) ctrl_wr_done <= 1'b0;
        else        ctrl_wr_done <= (next_state == IDLE) && (state != IDLE);

    // -------------------------------------------------------------------------
    // Beat counter — drives wlast
    // -------------------------------------------------------------------------
    logic [7:0] beat_cnt;

    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n)
            beat_cnt <= '0;
        else if (state == AW && s2mm_awready)
            beat_cnt <= '0;  // Reset at start of each burst
        else if (s2mm_wvalid && s2mm_wready)
            beat_cnt <= beat_cnt + 1'b1;

    // -------------------------------------------------------------------------
    // Write strobe generation for partial last beat
    //
    // bytes_in_burst: loaded with burst_actual_bytes at AW handshake,
    //                 decremented by STRB_WIDTH on each beat handshake.
    // On the last beat (wlast), if bytes_in_burst < STRB_WIDTH, generate a
    // partial strobe mask for only the valid bytes.
    // -------------------------------------------------------------------------
    logic [14:0]              bytes_in_burst;
    logic [STRB_WIDTH-1:0]    wstrb_mask;
    logic [STRB_IDX_WIDTH-1:0] valid_bytes;

    // Track bytes remaining in the current burst
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n)
            bytes_in_burst <= '0;
        else if (state == AW && s2mm_awready)
            bytes_in_burst <= burst_actual_bytes;  // Load at start of burst
        else if (s2mm_wvalid && s2mm_wready)
            bytes_in_burst <= (bytes_in_burst > STRB_WIDTH[14:0]) 
                            ? (bytes_in_burst - STRB_WIDTH[14:0]) 
                            : 15'd0;

    // Calculate valid bytes for strobe generation
    assign valid_bytes = (bytes_in_burst <= STRB_WIDTH[14:0])
                         ? bytes_in_burst[STRB_IDX_WIDTH-1:0]
                         : STRB_WIDTH[STRB_IDX_WIDTH-1:0];

    // Generate strobe mask using case statement (no barrel shifter for timing)
    // wstrb = (1 << valid_bytes) - 1, implemented as LUT
    logic [STRB_WIDTH-1:0] partial_strb_mask;
    
    always_comb begin
        case (valid_bytes)
            4'd0:  partial_strb_mask = 8'b00000000;
            4'd1:  partial_strb_mask = 8'b00000001;
            4'd2:  partial_strb_mask = 8'b00000011;
            4'd3:  partial_strb_mask = 8'b00000111;
            4'd4:  partial_strb_mask = 8'b00001111;
            4'd5:  partial_strb_mask = 8'b00011111;
            4'd6:  partial_strb_mask = 8'b00111111;
            4'd7:  partial_strb_mask = 8'b01111111;
            default: partial_strb_mask = 8'b11111111;
        endcase
    end

    // Generate strobe: full strobe unless last beat with partial data
    always_comb begin
        if (s2mm_wlast && (bytes_in_burst < STRB_WIDTH[14:0]) && (bytes_in_burst != '0))
            wstrb_mask = partial_strb_mask;
        else if (bytes_in_burst == '0)
            wstrb_mask = '0;  // Should not happen in normal operation
        else
            wstrb_mask = {STRB_WIDTH{1'b1}};
    end

    // -------------------------------------------------------------------------
    // FIFO
    // -------------------------------------------------------------------------
    logic [DATA_WIDTH-1:0] fifo_tdata;
    logic                  fifo_tvalid;
    logic                  fifo_tlast;
    logic                  fifo_tuser;

    snix_axis_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) axis_fifo_u0 (
        .clk           (clk),
        .rst_n         (rst_n),
        .s_axis_tdata  (s_axis_tdata),
        .s_axis_tlast  (s_axis_tlast),
        .s_axis_tuser  (1'b0),
        .s_axis_tvalid (s_axis_tvalid),
        .s_axis_tready (s_axis_tready),
        .m_axis_tdata  (fifo_tdata),
        .m_axis_tlast  (fifo_tlast),
        .m_axis_tuser  (fifo_tuser),
        .m_axis_tvalid (fifo_tvalid),
        .m_axis_tready (s2mm_wready && (state == WRITE))
    );

    // -------------------------------------------------------------------------
    // AXI output assignments
    // -------------------------------------------------------------------------
    assign s2mm_awaddr  = axi_next_addr;
    assign s2mm_awlen   = next_awlen;
    assign s2mm_awsize  = next_awsize;
    assign s2mm_awvalid = (state == AW);
    
    // Mask wdata based on wstrb - zero out invalid byte lanes
    // This prevents leaking stale FIFO data and aids debug visibility
    generate
        for (genvar i = 0; i < STRB_WIDTH; i++) begin : gen_wdata_mask
            assign s2mm_wdata[i*8 +: 8] = wstrb_mask[i] ? fifo_tdata[i*8 +: 8] : 8'h00;
        end
    endgenerate
    
    assign s2mm_wvalid  = (state == WRITE) && fifo_tvalid;
    assign s2mm_wlast   = (beat_cnt == s2mm_awlen) && s2mm_wvalid;
    assign s2mm_wstrb   = wstrb_mask;
    assign s2mm_bready  = (state == WAIT_BRESP);
    assign s2mm_awburst = 2'b01;
    assign s2mm_awid    = '0;
    assign s2mm_awlock  = 1'b0;
    assign s2mm_awcache = 4'b0;
    assign s2mm_awprot  = 3'b0;
    assign s2mm_awqos   = 4'b0;
    assign s2mm_awuser  = '0;
    assign s2mm_wuser   = '0;

    // -------------------------------------------------------------------------
    // Functions
    // -------------------------------------------------------------------------

    // Returns the total byte count for an AXI burst: (awlen+1) << awsize.
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

    // Returns awlen = ceil(bytes / beat_size) - 1, i.e. number of beats minus 1.
    // Uses ceiling division to handle partial last beats.
    // Case statement avoids barrel shifters for better timing.
    function automatic [7:0] compute_next_len(
        input logic [14:0] bytes_i,
        input logic [2:0]  size
    );
        logic [14:0] num_beats;
        
        // Ceiling division: (bytes + beat_size - 1) / beat_size
        // Using case statement to avoid barrel shifters
        case (size)
            3'b000: num_beats = bytes_i;                              // /1
            3'b001: num_beats = (bytes_i + 15'd1) >> 1;               // /2
            3'b010: num_beats = (bytes_i + 15'd3) >> 2;               // /4
            3'b011: num_beats = (bytes_i + 15'd7) >> 3;               // /8
            3'b100: num_beats = (bytes_i + 15'd15) >> 4;              // /16
            3'b101: num_beats = (bytes_i + 15'd31) >> 5;              // /32
            3'b110: num_beats = (bytes_i + 15'd63) >> 6;              // /64
            3'b111: num_beats = (bytes_i + 15'd127) >> 7;             // /128
        endcase
        
        if (num_beats == 0)
            compute_next_len = 8'd0;
        else
            compute_next_len = num_beats[7:0] - 8'd1;
    endfunction

endmodule : snix_axi_s2mm

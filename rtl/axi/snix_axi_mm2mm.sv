module snix_axi_mm2mm #(parameter int ADDR_WIDTH = 32,
                        parameter int DATA_WIDTH = 64,
                        parameter int ID_WIDTH   = 4,
                        parameter int USER_WIDTH = 1,
                        parameter int FIFO_DEPTH = 16)
                       (// Global signals
                        input  logic                                clk,
                        input  logic                                rst_n,

                        // Control interface
                        input  logic                                ctrl_start,
                        input  logic                                ctrl_stop,
                        input  logic [ADDR_WIDTH-1:0]               ctrl_src_addr,
                        input  logic [ADDR_WIDTH-1:0]               ctrl_dst_addr,
                        input  logic [7:0]                          ctrl_len,
                        input  logic [2:0]                          ctrl_size,
                        input  logic [31:0]                         ctrl_transfer_len,
                        output logic                                ctrl_done,

                        // AW Channel
                        output logic [ID_WIDTH-1:0]                 mm2mm_awid,
                        output logic [ADDR_WIDTH-1:0]               mm2mm_awaddr,
                        output logic [7:0]                          mm2mm_awlen,
                        output logic [2:0]                          mm2mm_awsize,
                        output logic [1:0]                          mm2mm_awburst,
                        output logic                                mm2mm_awlock,
                        output logic [3:0]                          mm2mm_awcache,
                        output logic [2:0]                          mm2mm_awprot,
                        output logic [3:0]                          mm2mm_awqos,
                        output logic [USER_WIDTH-1:0]               mm2mm_awuser,
                        output logic                                mm2mm_awvalid,
                        input  logic                                mm2mm_awready,

                        // W Channel
                        output logic [DATA_WIDTH-1:0]               mm2mm_wdata,
                        output logic [DATA_WIDTH/8-1:0]             mm2mm_wstrb,
                        output logic                                mm2mm_wlast,
                        output logic [USER_WIDTH-1:0]               mm2mm_wuser,
                        output logic                                mm2mm_wvalid,
                        input  logic                                mm2mm_wready,

                        // B Channel
                        input  logic [ID_WIDTH-1:0]                 mm2mm_bid,
                        input  logic [1:0]                          mm2mm_bresp,
                        input  logic [USER_WIDTH-1:0]               mm2mm_buser,
                        input  logic                                mm2mm_bvalid,
                        output logic                                mm2mm_bready,

                        // AR Channel
                        output logic [ID_WIDTH-1:0]                 mm2mm_arid,
                        output logic [ADDR_WIDTH-1:0]               mm2mm_araddr,
                        output logic [7:0]                          mm2mm_arlen,
                        output logic [2:0]                          mm2mm_arsize,
                        output logic [1:0]                          mm2mm_arburst,
                        output logic                                mm2mm_arlock,
                        output logic [3:0]                          mm2mm_arcache,
                        output logic [2:0]                          mm2mm_arprot,
                        output logic [3:0]                          mm2mm_arqos,
                        output logic [USER_WIDTH-1:0]               mm2mm_aruser,
                        output logic                                mm2mm_arvalid,
                        input  logic                                mm2mm_arready,

                        // R Channel
                        input  logic [ID_WIDTH-1:0]                 mm2mm_rid,
                        input  logic [DATA_WIDTH-1:0]               mm2mm_rdata,
                        input  logic [1:0]                          mm2mm_rresp,
                        input  logic                                mm2mm_rlast,
                        input  logic [USER_WIDTH-1:0]               mm2mm_ruser,
                        input  logic                                mm2mm_rvalid,
                        output logic                                mm2mm_rready
                       );

    // -------------------------------------------------------------------------
    // Local parameters
    // -------------------------------------------------------------------------
    localparam int STRB_WIDTH     = DATA_WIDTH / 8;
    localparam int STRB_IDX_WIDTH = $clog2(STRB_WIDTH) + 1;  // +1 to hold full-width value

    // -------------------------------------------------------------------------
    // Start / stop edge detection
    // -------------------------------------------------------------------------
    logic ctrl_start_r, wr_start_edge;
    logic ctrl_stop_r,  wr_stop_edge;

    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            ctrl_start_r <= 1'b0;
            ctrl_stop_r  <= 1'b0;
        end else begin
            ctrl_start_r <= ctrl_start;
            ctrl_stop_r  <= ctrl_stop;
        end

    assign wr_start_edge = ctrl_start & ~ctrl_start_r;
    assign wr_stop_edge  = ctrl_stop  & ~ctrl_stop_r;

    // -------------------------------------------------------------------------
    // Abort latch — set on stop edge, cleared on start edge
    // -------------------------------------------------------------------------
    logic wr_abort;

    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n)             wr_abort <= 1'b0;
        else if (wr_stop_edge)  wr_abort <= 1'b1;
        else if (wr_start_edge) wr_abort <= 1'b0;

    // -------------------------------------------------------------------------
    // FSM
    // -------------------------------------------------------------------------
    typedef enum logic [2:0] {IDLE, PREP1, PREP2, AR, READ, AW, WRITE, WAIT_BRESP} state_t;
    state_t state, next_state;

    logic transfer_done;

    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) state <= IDLE;
        else        state <= next_state;

    always_comb begin
        next_state = state;  // default holds state; prevents latches
        case (state)
            IDLE: begin
                next_state = (ctrl_start && !wr_abort) ? PREP1 : IDLE;
            end
            PREP1: begin
                next_state = wr_abort ? IDLE : PREP2;
            end
            PREP2: begin
                next_state = AR;
            end
            AR: begin
                if (wr_abort)
                    next_state = IDLE;
                else
                    next_state = (mm2mm_arvalid && mm2mm_arready) ? READ : AR;
            end
            READ: begin
                next_state = (mm2mm_rvalid && mm2mm_rready && mm2mm_rlast) ? AW : READ;
            end
            AW: begin
                if (wr_abort)
                    next_state = IDLE;
                else
                    next_state = (mm2mm_awvalid && mm2mm_awready) ? WRITE : AW;
            end
            WRITE: begin
                next_state = (mm2mm_wvalid && mm2mm_wready && mm2mm_wlast) ? WAIT_BRESP : WRITE;
            end
            WAIT_BRESP: begin
                if (mm2mm_bvalid && mm2mm_bready) begin
                    if (wr_abort || transfer_done)
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
    // Identical two-stage pipeline to s2mm / mm2s.  The src address is used
    // for the 4K check; burst_actual_bytes is applied to both pointers so
    // they stay in lock-step.
    //
    //   PREP1 [Stage 1]: max_len, next_size, src_axi_addr (all regs)
    //                    → next_bytes → cross_4k → bytes_to_4k
    //                    → register bytes_to_4k_r
    //
    //   PREP2 [Stage 2]: bytes_to_4k_r, pending_bytes, next_size (all regs)
    //                    → num_bytes_comb → next_len_o
    //                    → register next_arlen / next_awlen | burst_actual_bytes
    // -------------------------------------------------------------------------
    logic [7:0]            max_len;
    logic [2:0]            next_size;
    logic [ADDR_WIDTH-1:0] src_axi_addr;
    logic [ADDR_WIDTH-1:0] dst_axi_addr;
    logic [31:0]           pending_bytes;

    // Stage 1 wires
    logic [14:0] next_bytes;
    logic        cross_4k;
    logic [14:0] bytes_to_4k;
    // Stage 1 → Stage 2 pipeline register
    logic [14:0] bytes_to_4k_r;
    // Stage 2 wires
    logic [14:0] num_bytes_comb;
    logic [7:0]  next_len_o;

    // Stage 1 combinatorial
    assign next_bytes  = compute_num_bytes(max_len, next_size);
    assign cross_4k    = ({1'b0, next_bytes} + {4'b0, src_axi_addr[11:0]}) >= 16'd4096;
    assign bytes_to_4k = cross_4k ? (15'd4096 - {3'b0, src_axi_addr[11:0]}) : next_bytes;

    // Stage 2 combinatorial
    assign num_bytes_comb = ({{17{1'b0}}, bytes_to_4k_r} <= pending_bytes)
                            ? bytes_to_4k_r
                            : pending_bytes[14:0];
    assign next_len_o     = compute_next_len(num_bytes_comb, next_size);

    // -------------------------------------------------------------------------
    // Transfer-state registers
    // -------------------------------------------------------------------------
    logic [31:0] transfer_len;
    logic [31:0] copied_bytes;
    logic [7:0]  next_arlen;
    logic [7:0]  next_awlen;
    logic [14:0] burst_actual_bytes;

    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            src_axi_addr       <= '0;
            dst_axi_addr       <= '0;
            next_arlen         <= '0;
            next_awlen         <= '0;
            max_len            <= '0;
            next_size          <= '0;
            copied_bytes       <= '0;
            transfer_len       <= '0;
            bytes_to_4k_r      <= '0;
            burst_actual_bytes <= '0;
        end else if (wr_start_edge) begin
            src_axi_addr       <= ctrl_src_addr;
            dst_axi_addr       <= ctrl_dst_addr;
            next_arlen         <= ctrl_len;
            next_awlen         <= ctrl_len;
            max_len            <= ctrl_len;
            next_size          <= ctrl_size;
            copied_bytes       <= '0;
            transfer_len       <= ctrl_transfer_len;
            burst_actual_bytes <= '0;
        end else if (state == PREP1) begin
            bytes_to_4k_r <= bytes_to_4k;
        end else if (state == PREP2) begin
            next_arlen         <= next_len_o;
            next_awlen         <= next_len_o;
            burst_actual_bytes <= num_bytes_comb;
        end else if (state == AR && mm2mm_arready) begin
            src_axi_addr <= src_axi_addr + {{(ADDR_WIDTH-15){1'b0}}, burst_actual_bytes};
        end else if (state == AW && mm2mm_awready) begin
            dst_axi_addr <= dst_axi_addr + {{(ADDR_WIDTH-15){1'b0}}, burst_actual_bytes};
            copied_bytes <= copied_bytes + {17'b0, burst_actual_bytes};
        end

    // pending_bytes — decremented in AR state after burst_actual_bytes is registered.
    // TIMING FIX: reg(burst_actual_bytes) → subtractor → reg(pending_bytes)
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n)
            pending_bytes <= '0;
        else if (wr_start_edge)
            pending_bytes <= ctrl_transfer_len;
        else if (state == AR && mm2mm_arready)
            pending_bytes <= pending_bytes - {17'b0, burst_actual_bytes};

    // -------------------------------------------------------------------------
    // Transfer-done flag
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n)
            transfer_done <= 1'b0;
        else if (wr_start_edge || state == IDLE || state == AR ||
                 state == PREP1 || state == PREP2)
            transfer_done <= 1'b0;
        else
            transfer_done <= (copied_bytes == transfer_len) && (copied_bytes != '0);

    // -------------------------------------------------------------------------
    // ctrl_done — single-cycle pulse when FSM transitions into IDLE
    // -------------------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) ctrl_done <= 1'b0;
        else        ctrl_done <= (next_state == IDLE) && (state != IDLE);

    // -------------------------------------------------------------------------
    // Beat counter — drives wlast
    // -------------------------------------------------------------------------
    logic [7:0] beat_cnt;

    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n)
            beat_cnt <= '0;
        else if (state == AW && mm2mm_awready)
            beat_cnt <= '0;
        else if (mm2mm_wvalid && mm2mm_wready)
            beat_cnt <= beat_cnt + 1'b1;

    // -------------------------------------------------------------------------
    // Write strobe generation for partial last beat
    //
    // partial_strb_mask uses a per-bit comparator loop rather than a hardcoded
    // case statement, making it correct for any DATA_WIDTH (including 1024-bit).
    // Synthesises as a parallel comparator tree with no barrel shifter.
    // -------------------------------------------------------------------------
    logic [14:0]               bytes_in_burst;
    logic [STRB_WIDTH-1:0]     wstrb_mask;
    logic [STRB_IDX_WIDTH-1:0] valid_bytes;

    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n)
            bytes_in_burst <= '0;
        else if (state == AW && mm2mm_awready)
            bytes_in_burst <= burst_actual_bytes;
        else if (mm2mm_wvalid && mm2mm_wready)
            bytes_in_burst <= (bytes_in_burst > STRB_WIDTH[14:0])
                            ? (bytes_in_burst - STRB_WIDTH[14:0])
                            : '0;

    assign valid_bytes = (bytes_in_burst <= STRB_WIDTH[14:0])
                         ? bytes_in_burst[STRB_IDX_WIDTH-1:0]
                         : STRB_WIDTH[STRB_IDX_WIDTH-1:0];

    logic [STRB_WIDTH-1:0] partial_strb_mask;

    always_comb begin
        for (int i = 0; i < STRB_WIDTH; i++)
            partial_strb_mask[i] = (i < valid_bytes);
    end

    always_comb begin
        if (mm2mm_wlast && (bytes_in_burst < STRB_WIDTH[14:0]) && (bytes_in_burst != '0))
            wstrb_mask = partial_strb_mask;
        else if (bytes_in_burst == '0)
            wstrb_mask = '0;
        else
            wstrb_mask = {STRB_WIDTH{1'b1}};
    end

    // -------------------------------------------------------------------------
    // FIFO — bridges R channel (read path) to W channel (write path)
    //
    // R-channel data is accepted only in READ state to prevent beats arriving
    // before READ is entered from being silently dropped (same fix as mm2s).
    // The write side drains only in WRITE state for symmetric gating.
    // -------------------------------------------------------------------------
    logic [DATA_WIDTH-1:0] fifo_tdata;
    logic                  fifo_tvalid;
    logic                  fifo_tlast;
    logic                  fifo_tuser;
    logic                  fifo_s_tready;

    assign mm2mm_rready = fifo_s_tready && (state == READ);

    snix_axis_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) axis_fifo_u0 (
        .clk           (clk),
        .rst_n         (rst_n),
        .s_axis_tdata  (mm2mm_rdata),
        .s_axis_tlast  (mm2mm_rlast),
        .s_axis_tuser  (1'b0),
        .s_axis_tvalid (mm2mm_rvalid && (state == READ)),
        .s_axis_tready (fifo_s_tready),
        .m_axis_tdata  (fifo_tdata),
        .m_axis_tlast  (fifo_tlast),
        .m_axis_tuser  (fifo_tuser),
        .m_axis_tvalid (fifo_tvalid),
        .m_axis_tready (mm2mm_wready && (state == WRITE))
    );

    // -------------------------------------------------------------------------
    // AXI output assignments — AR channel
    // -------------------------------------------------------------------------
    assign mm2mm_arvalid = (state == AR);
    assign mm2mm_araddr  = src_axi_addr;
    assign mm2mm_arlen   = next_arlen;
    assign mm2mm_arsize  = next_size;
    assign mm2mm_arburst = 2'b01;
    assign mm2mm_arlock  = 1'b0;
    assign mm2mm_arcache = 4'b0;
    assign mm2mm_arprot  = 3'b0;
    assign mm2mm_arqos   = 4'b0;
    assign mm2mm_arid    = '0;
    assign mm2mm_aruser  = '0;

    // -------------------------------------------------------------------------
    // AXI output assignments — AW channel
    // -------------------------------------------------------------------------
    assign mm2mm_awvalid = (state == AW);
    assign mm2mm_awaddr  = dst_axi_addr;
    assign mm2mm_awlen   = next_awlen;
    assign mm2mm_awsize  = next_size;
    assign mm2mm_awburst = 2'b01;
    assign mm2mm_awlock  = 1'b0;
    assign mm2mm_awcache = 4'b0;
    assign mm2mm_awprot  = 3'b0;
    assign mm2mm_awqos   = 4'b0;
    assign mm2mm_awid    = '0;
    assign mm2mm_awuser  = '0;

    // -------------------------------------------------------------------------
    // AXI output assignments — W channel
    // -------------------------------------------------------------------------
    generate
        for (genvar i = 0; i < STRB_WIDTH; i++) begin : gen_wdata_mask
            assign mm2mm_wdata[i*8 +: 8] = wstrb_mask[i] ? fifo_tdata[i*8 +: 8] : 8'h00;
        end
    endgenerate

    assign mm2mm_wvalid = (state == WRITE) && fifo_tvalid;
    assign mm2mm_wlast  = (beat_cnt == next_awlen) && mm2mm_wvalid;
    assign mm2mm_wstrb  = wstrb_mask;
    assign mm2mm_wuser  = '0;

    // -------------------------------------------------------------------------
    // AXI output assignments — B channel
    // -------------------------------------------------------------------------
    assign mm2mm_bready = (state == WAIT_BRESP);

    // -------------------------------------------------------------------------
    // Functions (identical to s2mm / mm2s)
    // -------------------------------------------------------------------------

    // Returns total byte count for an AXI burst: (len+1) << size.
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

    // Returns arlen/awlen = ceil(bytes / beat_size) - 1.
    function automatic [7:0] compute_next_len(
        input logic [14:0] bytes_i,
        input logic [2:0]  size
    );
        logic [14:0] num_beats;
        case (size)
            3'b000: num_beats = bytes_i;
            3'b001: num_beats = (bytes_i + 15'd1)   >> 1;
            3'b010: num_beats = (bytes_i + 15'd3)   >> 2;
            3'b011: num_beats = (bytes_i + 15'd7)   >> 3;
            3'b100: num_beats = (bytes_i + 15'd15)  >> 4;
            3'b101: num_beats = (bytes_i + 15'd31)  >> 5;
            3'b110: num_beats = (bytes_i + 15'd63)  >> 6;
            3'b111: num_beats = (bytes_i + 15'd127) >> 7;
        endcase
        if (num_beats == 15'd0)
            compute_next_len = 8'd0;
        else
            compute_next_len = num_beats[7:0] - 8'd1;
    endfunction

endmodule : snix_axi_mm2mm

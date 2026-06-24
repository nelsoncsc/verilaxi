module snix_axi_vdma #(
    parameter int ADDR_WIDTH      = 32,
    parameter int DATA_WIDTH      = 32,
    parameter int AXIL_ADDR_WIDTH = 32,
    parameter int AXIL_DATA_WIDTH = 32,
    parameter int ID_WIDTH        = 4,
    parameter int USER_WIDTH      = 1,
    parameter int LINE_FIFO_DEPTH = 64
) (
    input  logic                                clk,
    input  logic                                rst_n,

    input  logic [AXIL_ADDR_WIDTH-1:0]          s_axil_awaddr,
    input  logic                                s_axil_awvalid,
    output logic                                s_axil_awready,
    input  logic [AXIL_DATA_WIDTH-1:0]          s_axil_wdata,
    input  logic [AXIL_DATA_WIDTH/8-1:0]        s_axil_wstrb,
    input  logic                                s_axil_wvalid,
    output logic                                s_axil_wready,
    output logic [1:0]                          s_axil_bresp,
    output logic                                s_axil_bvalid,
    input  logic                                s_axil_bready,
    input  logic [AXIL_ADDR_WIDTH-1:0]          s_axil_araddr,
    input  logic                                s_axil_arvalid,
    output logic                                s_axil_arready,
    output logic [AXIL_DATA_WIDTH-1:0]          s_axil_rdata,
    output logic [1:0]                          s_axil_rresp,
    output logic                                s_axil_rvalid,
    input  logic                                s_axil_rready,

    input  logic [DATA_WIDTH-1:0]               s_axis_tdata,
    input  logic [USER_WIDTH-1:0]               s_axis_tuser,
    input  logic [DATA_WIDTH/8-1:0]             s_axis_tkeep,
    input  logic                                s_axis_tvalid,
    output logic                                s_axis_tready,
    input  logic                                s_axis_tlast,

    output logic [DATA_WIDTH-1:0]               m_axis_tdata,
    output logic [USER_WIDTH-1:0]               m_axis_tuser,
    output logic [DATA_WIDTH/8-1:0]             m_axis_tkeep,
    output logic                                m_axis_tvalid,
    input  logic                                m_axis_tready,
    output logic                                m_axis_tlast,

    output logic                                wr_busy,
    output logic                                wr_done,
    output logic                                wr_error,
    output logic                                wr_axi_error,
    output logic                                rd_busy,
    output logic                                rd_done,
    output logic                                rd_error,
    output logic                                rd_axi_error,
    output logic                                irq,
    output logic [31:0]                         vdma_status,
    output logic [1:0]                          write_slot,
    output logic [1:0]                          read_slot,
    output logic [1:0]                          newest_complete_slot,
    output logic [2:0]                          valid_slots,

    output logic [ID_WIDTH-1:0]                 s2mm_awid,
    output logic [ADDR_WIDTH-1:0]               s2mm_awaddr,
    output logic [7:0]                          s2mm_awlen,
    output logic [2:0]                          s2mm_awsize,
    output logic [1:0]                          s2mm_awburst,
    output logic                                s2mm_awlock,
    output logic [3:0]                          s2mm_awcache,
    output logic [2:0]                          s2mm_awprot,
    output logic [3:0]                          s2mm_awqos,
    output logic [USER_WIDTH-1:0]               s2mm_awuser,
    output logic                                s2mm_awvalid,
    input  logic                                s2mm_awready,
    output logic [DATA_WIDTH-1:0]               s2mm_wdata,
    output logic [DATA_WIDTH/8-1:0]             s2mm_wstrb,
    output logic                                s2mm_wlast,
    output logic [USER_WIDTH-1:0]               s2mm_wuser,
    output logic                                s2mm_wvalid,
    input  logic                                s2mm_wready,
    input  logic [ID_WIDTH-1:0]                 s2mm_bid,
    input  logic [1:0]                          s2mm_bresp,
    input  logic [USER_WIDTH-1:0]               s2mm_buser,
    input  logic                                s2mm_bvalid,
    output logic                                s2mm_bready,

    output logic [ID_WIDTH-1:0]                 mm2s_arid,
    output logic [ADDR_WIDTH-1:0]               mm2s_araddr,
    output logic [7:0]                          mm2s_arlen,
    output logic [2:0]                          mm2s_arsize,
    output logic [1:0]                          mm2s_arburst,
    output logic                                mm2s_arlock,
    output logic [3:0]                          mm2s_arcache,
    output logic [2:0]                          mm2s_arprot,
    output logic [3:0]                          mm2s_arqos,
    output logic [USER_WIDTH-1:0]               mm2s_aruser,
    output logic                                mm2s_arvalid,
    input  logic                                mm2s_arready,
    input  logic [ID_WIDTH-1:0]                 mm2s_rid,
    input  logic [DATA_WIDTH-1:0]               mm2s_rdata,
    input  logic [1:0]                          mm2s_rresp,
    input  logic                                mm2s_rlast,
    input  logic [USER_WIDTH-1:0]               mm2s_ruser,
    input  logic                                mm2s_rvalid,
    output logic                                mm2s_rready
);

    localparam int NUM_REGS = 16;
    localparam int WR_CTRL_IDX   = 0;  // 0x00
    localparam int WR_ADDR_IDX   = 1;  // 0x04
    localparam int WR_STRIDE_IDX = 2;  // 0x08
    localparam int RD_CTRL_IDX   = 3;  // 0x0c
    localparam int RD_ADDR_IDX   = 4;  // 0x10
    localparam int RD_STRIDE_IDX = 5;  // 0x14
    localparam int WR_HSIZE_IDX  = 7;  // 0x1c
    localparam int WR_VSIZE_IDX  = 8;  // 0x20
    localparam int RD_HSIZE_IDX  = 9;  // 0x24
    localparam int RD_VSIZE_IDX  = 10; // 0x28
    localparam int FRAME_ADDR0_IDX = 11; // 0x2c
    localparam int FRAME_ADDR1_IDX = 12; // 0x30
    localparam int FRAME_ADDR2_IDX = 13; // 0x34
    localparam int FRAME_CTRL_IDX  = 14; // 0x38
    localparam int IRQ_ACK_IDX     = 15; // 0x3c

    logic [NUM_REGS-1:0][AXIL_DATA_WIDTH-1:0] regs;
    logic [AXIL_DATA_WIDTH-1:0] status_event;

    logic wr_start, wr_stop, rd_start, rd_stop;
    logic wr_frame_start, rd_frame_start;
    logic wr_restart_pending, rd_restart_pending;
    logic wr_circular, rd_circular;
    logic frame_store_enable, park_mode;
    logic [1:0] park_slot;
    logic [1:0] frame_delay;
    logic genlock_enable, genlock_pending, genlock_start;
    logic rd_frame_available;
    logic wr_axi_error_sticky, rd_axi_error_sticky;
    logic wr_axi_error_d, rd_axi_error_d;
    logic irq_clear, fault_clear, telemetry_clear;
    logic underrun_event, overwrite_event, sync_loss_event;
    logic [3:0] underrun_count, overwrite_count, sync_loss_count;
    logic [ADDR_WIDTH-1:0] frame_store_wr_addr, frame_store_rd_addr;
    logic [ADDR_WIDTH-1:0] selected_wr_addr, selected_rd_addr;
    logic [7:0] wr_burst_len, rd_burst_len;
    logic [2:0] wr_beat_size, rd_beat_size;

    assign wr_start     = regs[WR_CTRL_IDX][0];
    assign wr_stop      = regs[WR_CTRL_IDX][1];
    assign wr_beat_size = regs[WR_CTRL_IDX][5:3];
    assign wr_burst_len = regs[WR_CTRL_IDX][13:6];
    assign wr_circular  = regs[WR_CTRL_IDX][2];
    assign rd_start     = regs[RD_CTRL_IDX][0];
    assign rd_stop      = regs[RD_CTRL_IDX][1];
    assign rd_beat_size = regs[RD_CTRL_IDX][5:3];
    assign rd_burst_len = regs[RD_CTRL_IDX][13:6];
    assign rd_circular  = regs[RD_CTRL_IDX][2];
    assign frame_store_enable = regs[FRAME_CTRL_IDX][0];
    assign park_mode           = regs[FRAME_CTRL_IDX][1];
    assign park_slot           = regs[FRAME_CTRL_IDX][3:2];
    assign genlock_enable      = regs[FRAME_CTRL_IDX][4];
    assign frame_delay         = regs[FRAME_CTRL_IDX][6:5];
    assign irq_clear           = regs[FRAME_CTRL_IDX][16] || regs[IRQ_ACK_IDX][0];
    assign fault_clear         = regs[FRAME_CTRL_IDX][16] || regs[IRQ_ACK_IDX][1];
    assign telemetry_clear     = regs[FRAME_CTRL_IDX][16] || regs[IRQ_ACK_IDX][2];
    assign wr_frame_start      = wr_start || wr_restart_pending;
    assign genlock_start       = genlock_enable && genlock_pending &&
                                 !rd_busy && rd_frame_available;
    assign rd_frame_start      = rd_start || rd_restart_pending || genlock_start;
    assign underrun_event      = frame_store_enable && rd_frame_start &&
                                 !rd_frame_available;
    assign sync_loss_event     = genlock_enable &&
                                 (overwrite_event ||
                                  (wr_done && !wr_error &&
                                   ((genlock_pending && !genlock_start) ||
                                    rd_busy)));
    assign selected_wr_addr = frame_store_enable ? frame_store_wr_addr :
                              regs[WR_ADDR_IDX][ADDR_WIDTH-1:0];
    assign selected_rd_addr = frame_store_enable ? frame_store_rd_addr :
                              regs[RD_ADDR_IDX][ADDR_WIDTH-1:0];

    // Delay free-run restart by one clock so a completed write slot is
    // published before the following frame latches its address.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_restart_pending <= 1'b0;
            rd_restart_pending <= 1'b0;
        end else begin
            wr_restart_pending <= wr_done && wr_circular && !wr_stop && !wr_error;
            rd_restart_pending <= rd_done && rd_circular && !rd_stop &&
                                  !rd_error && !genlock_enable;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_axi_error_sticky <= 1'b0;
            rd_axi_error_sticky <= 1'b0;
            wr_axi_error_d      <= 1'b0;
            rd_axi_error_d      <= 1'b0;
        end else if (fault_clear) begin
            wr_axi_error_sticky <= 1'b0;
            rd_axi_error_sticky <= 1'b0;
            wr_axi_error_d      <= wr_axi_error;
            rd_axi_error_d      <= rd_axi_error;
        end else begin
            wr_axi_error_d <= wr_axi_error;
            rd_axi_error_d <= rd_axi_error;
            if (wr_axi_error && !wr_axi_error_d)
                wr_axi_error_sticky <= 1'b1;
            if (rd_axi_error && !rd_axi_error_d)
                rd_axi_error_sticky <= 1'b1;
        end
    end

    function automatic logic [3:0] sat_inc4(input logic [3:0] value);
        if (value == 4'hf)
            sat_inc4 = 4'hf;
        else
            sat_inc4 = value + 4'd1;
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            underrun_count  <= '0;
            overwrite_count <= '0;
            sync_loss_count <= '0;
        end else if (telemetry_clear) begin
            underrun_count  <= '0;
            overwrite_count <= '0;
            sync_loss_count <= '0;
        end else begin
            if (underrun_event)
                underrun_count <= sat_inc4(underrun_count);
            if (overwrite_event)
                overwrite_count <= sat_inc4(overwrite_count);
            if (sync_loss_event)
                sync_loss_count <= sat_inc4(sync_loss_count);
        end
    end

    // Capture-driven playback. Multiple capture completions while playback is
    // busy coalesce into one pending event, which launches the newest eligible
    // delayed frame as soon as the reader becomes idle.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            genlock_pending <= 1'b0;
        else if (!genlock_enable)
            genlock_pending <= 1'b0;
        else begin
            if (genlock_start)
                genlock_pending <= 1'b0;
            if (wr_done && !wr_error)
                genlock_pending <= 1'b1;
        end
    end

    // Sticky interrupt: WR done, RD done, and errors have independent enables.
    // FRAME_CTRL[16] clears the latch; software writes it back low afterward.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            irq <= 1'b0;
        else if (irq_clear)
            irq <= 1'b0;
        else if ((regs[FRAME_CTRL_IDX][8]  && wr_done) ||
                 (regs[FRAME_CTRL_IDX][9]  && rd_done) ||
                 (regs[FRAME_CTRL_IDX][10] &&
                  ((wr_done && wr_error) || (rd_done && rd_error))))
            irq <= 1'b1;
    end

    // The reused DMA CSR clears start/stop pulses and latches done bits in
    // STATUS[1:0]. Live busy/error state is also exposed as top-level outputs.
    always_comb begin
        status_event = '0;
        status_event[0] = wr_done;
        status_event[1] = rd_done;
        status_event[2] = wr_busy;
        status_event[3] = rd_busy;
        status_event[4] = wr_error;
        status_event[5] = rd_error;
        status_event[6] = wr_axi_error_sticky;
        status_event[7] = rd_axi_error_sticky;
        status_event[8] = irq;
        status_event[10:9]  = write_slot;
        status_event[12:11] = read_slot;
        status_event[14:13] = newest_complete_slot;
        status_event[17:15] = valid_slots;
        status_event[18] = genlock_pending;
        status_event[19] = rd_frame_available;
        status_event[23:20] = underrun_count;
        status_event[27:24] = overwrite_count;
        status_event[31:28] = sync_loss_count;
    end
    assign vdma_status = regs[6][31:0];

    snix_axi_dma_csr #(
        .DATA_WIDTH(AXIL_DATA_WIDTH), .ADDR_WIDTH(AXIL_ADDR_WIDTH),
        .NUM_REGS(NUM_REGS),
        .PULSE_REG0_INDEX(FRAME_CTRL_IDX),
        .PULSE_REG0_MASK(32'h0001_0000),
        .PULSE_REG1_INDEX(IRQ_ACK_IDX),
        .PULSE_REG1_MASK(32'h0000_0007)
    ) u_csr (
        .clk, .rst_n,
        .s_axil_awaddr, .s_axil_awvalid, .s_axil_awready,
        .s_axil_wdata, .s_axil_wstrb, .s_axil_wvalid, .s_axil_wready,
        .s_axil_bresp, .s_axil_bvalid, .s_axil_bready,
        .s_axil_araddr, .s_axil_arvalid, .s_axil_arready,
        .s_axil_rdata, .s_axil_rresp, .s_axil_rvalid, .s_axil_rready,
        .read_status_reg(status_event), .config_status_reg(regs)
    );

    snix_axi_vdma_frame_store #(.ADDR_WIDTH(ADDR_WIDTH)) u_frame_store (
        .clk, .rst_n, .enable(frame_store_enable), .park_mode, .park_slot,
        .frame_delay,
        .frame_addr0(regs[FRAME_ADDR0_IDX][ADDR_WIDTH-1:0]),
        .frame_addr1(regs[FRAME_ADDR1_IDX][ADDR_WIDTH-1:0]),
        .frame_addr2(regs[FRAME_ADDR2_IDX][ADDR_WIDTH-1:0]),
        .wr_frame_start, .wr_frame_done(wr_done && !wr_error),
        .rd_frame_start, .rd_frame_busy(rd_busy),
        .wr_frame_addr(frame_store_wr_addr),
        .rd_frame_addr(frame_store_rd_addr),
        .write_slot, .read_slot, .newest_complete_slot, .valid_slots,
        .rd_frame_available, .overwrite_event
    );

    snix_axi_vdma_s2mm #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH(ID_WIDTH), .USER_WIDTH(USER_WIDTH),
        .FIFO_DEPTH(LINE_FIFO_DEPTH)
    ) u_s2mm (
        .clk, .rst_n,
        .frame_start(wr_frame_start), .frame_stop(wr_stop),
        .frame_addr(selected_wr_addr),
        .frame_stride(regs[WR_STRIDE_IDX]),
        .frame_hsize_bytes(regs[WR_HSIZE_IDX]),
        .frame_vsize_lines(regs[WR_VSIZE_IDX]),
        .burst_len(wr_burst_len), .beat_size(wr_beat_size),
        .frame_busy(wr_busy), .frame_done(wr_done), .frame_error(wr_error),
        .axi_error(wr_axi_error),
        .s_axis_tdata, .s_axis_tuser, .s_axis_tkeep, .s_axis_tvalid,
        .s_axis_tready, .s_axis_tlast,
        .s2mm_awid, .s2mm_awaddr, .s2mm_awlen, .s2mm_awsize,
        .s2mm_awburst, .s2mm_awlock, .s2mm_awcache, .s2mm_awprot,
        .s2mm_awqos, .s2mm_awuser, .s2mm_awvalid, .s2mm_awready,
        .s2mm_wdata, .s2mm_wstrb, .s2mm_wlast, .s2mm_wuser,
        .s2mm_wvalid, .s2mm_wready,
        .s2mm_bid, .s2mm_bresp, .s2mm_buser, .s2mm_bvalid, .s2mm_bready
    );

    snix_axi_vdma_mm2s #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH(ID_WIDTH), .USER_WIDTH(USER_WIDTH),
        .FIFO_DEPTH(LINE_FIFO_DEPTH)
    ) u_mm2s (
        .clk, .rst_n,
        .frame_start(rd_frame_start), .frame_stop(rd_stop),
        .frame_addr(selected_rd_addr),
        .frame_stride(regs[RD_STRIDE_IDX]),
        .frame_hsize_bytes(regs[RD_HSIZE_IDX]),
        .frame_vsize_lines(regs[RD_VSIZE_IDX]),
        .burst_len(rd_burst_len), .beat_size(rd_beat_size),
        .frame_busy(rd_busy), .frame_done(rd_done), .frame_error(rd_error),
        .axi_error(rd_axi_error),
        .m_axis_tdata, .m_axis_tuser, .m_axis_tkeep, .m_axis_tvalid,
        .m_axis_tready, .m_axis_tlast,
        .mm2s_arid, .mm2s_araddr, .mm2s_arlen, .mm2s_arsize,
        .mm2s_arburst, .mm2s_arlock, .mm2s_arcache, .mm2s_arprot,
        .mm2s_arqos, .mm2s_aruser, .mm2s_arvalid, .mm2s_arready,
        .mm2s_rid, .mm2s_rdata, .mm2s_rresp, .mm2s_rlast,
        .mm2s_ruser, .mm2s_rvalid, .mm2s_rready
    );

endmodule : snix_axi_vdma

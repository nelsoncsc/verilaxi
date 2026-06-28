// snix_axi_multi_vdma — multi-tap temporal frame-buffer Video DMA
//
// NUM_TAPS independent MM2S read ports, each reading a different frame
// from an (NUM_TAPS+1)-slot frame store.
//   tap 0 = newest complete frame (current)
//   tap 1 = previous frame
//   tap N-1 = oldest frame
//
// Each tap has its own AXI4 read master and AXI-Stream output.
// The S2MM write path is identical to snix_axi_vdma.
//
// All array ports are flat-packed for Yosys compatibility.
// For a port of element width W and NUM_TAPS elements:
//   element i is at [i*W +: W].
//
// CSR map (AXI-Lite, 32-bit registers):
//   0x00  WR_CTRL         — S2MM control
//   0x04  WR_ADDR         — ignored when frame store enabled
//   0x08  WR_STRIDE
//   0x0c  RD_CTRL         — applied to all MM2S taps
//   0x10  RD_ADDR         — ignored when frame store enabled
//   0x14  RD_STRIDE
//   0x18  STATUS          — read-only
//   0x1c  WR_HSIZE
//   0x20  WR_VSIZE
//   0x24  RD_HSIZE
//   0x28  RD_VSIZE
//   0x2c  FRAME_ADDR0     — slot 0 base
//   0x30  FRAME_ADDR1     — slot 1 base
//   0x34  FRAME_ADDR2     — slot 2 base (NUM_TAPS >= 2)
//   0x38  FRAME_ADDR3     — slot 3 base (NUM_TAPS == 3)
//   0x3c  FRAME_CTRL      — [0] frame_store_enable, [8] wr_irq_en,
//                           [9] rd_irq_en, [10] err_irq_en, [16] sw_clear
//   0x40  IRQ_ACK         — [0] irq_ack, [1] fault_clear, [2] telemetry_clear

module snix_axi_multi_vdma #(
    parameter int NUM_TAPS        = 2,    // 1, 2, or 3
    parameter int ADDR_WIDTH      = 32,
    parameter int DATA_WIDTH      = 32,
    parameter int AXIL_ADDR_WIDTH = 32,
    parameter int AXIL_DATA_WIDTH = 32,
    parameter int ID_WIDTH        = 4,
    parameter int USER_WIDTH      = 1,
    parameter int LINE_FIFO_DEPTH = 64
) (
    input  logic clk,
    input  logic rst_n,

    // ── AXI-Lite CSR ─────────────────────────────────────────────────
    input  logic [AXIL_ADDR_WIDTH-1:0]   s_axil_awaddr,
    input  logic                         s_axil_awvalid,
    output logic                         s_axil_awready,
    input  logic [AXIL_DATA_WIDTH-1:0]   s_axil_wdata,
    input  logic [AXIL_DATA_WIDTH/8-1:0] s_axil_wstrb,
    input  logic                         s_axil_wvalid,
    output logic                         s_axil_wready,
    output logic [1:0]                   s_axil_bresp,
    output logic                         s_axil_bvalid,
    input  logic                         s_axil_bready,
    input  logic [AXIL_ADDR_WIDTH-1:0]   s_axil_araddr,
    input  logic                         s_axil_arvalid,
    output logic                         s_axil_arready,
    output logic [AXIL_DATA_WIDTH-1:0]   s_axil_rdata,
    output logic [1:0]                   s_axil_rresp,
    output logic                         s_axil_rvalid,
    input  logic                         s_axil_rready,

    // ── S2MM AXI-Stream input ─────────────────────────────────────────
    input  logic [DATA_WIDTH-1:0]        s_axis_tdata,
    input  logic [USER_WIDTH-1:0]        s_axis_tuser,
    input  logic [DATA_WIDTH/8-1:0]      s_axis_tkeep,
    input  logic                         s_axis_tvalid,
    output logic                         s_axis_tready,
    input  logic                         s_axis_tlast,

    // ── MM2S AXI-Stream outputs (flat-packed, NUM_TAPS elements) ─────
    // tap i: [i*DATA_WIDTH +: DATA_WIDTH] etc.
    output logic [NUM_TAPS*DATA_WIDTH-1:0]        m_axis_tdata,
    output logic [NUM_TAPS*USER_WIDTH-1:0]        m_axis_tuser,
    output logic [NUM_TAPS*(DATA_WIDTH/8)-1:0]    m_axis_tkeep,
    output logic [NUM_TAPS-1:0]                   m_axis_tvalid,
    input  logic [NUM_TAPS-1:0]                   m_axis_tready,
    output logic [NUM_TAPS-1:0]                   m_axis_tlast,

    // ── Status / IRQ ──────────────────────────────────────────────────
    output logic                         irq,
    output logic [31:0]                  vdma_status,
    output logic                         wr_busy,
    output logic                         wr_done,
    output logic                         wr_error,
    output logic                         wr_axi_error,

    // ── S2MM AXI4 write master ────────────────────────────────────────
    output logic [ID_WIDTH-1:0]          s2mm_awid,
    output logic [ADDR_WIDTH-1:0]        s2mm_awaddr,
    output logic [7:0]                   s2mm_awlen,
    output logic [2:0]                   s2mm_awsize,
    output logic [1:0]                   s2mm_awburst,
    output logic                         s2mm_awlock,
    output logic [3:0]                   s2mm_awcache,
    output logic [2:0]                   s2mm_awprot,
    output logic [3:0]                   s2mm_awqos,
    output logic [USER_WIDTH-1:0]        s2mm_awuser,
    output logic                         s2mm_awvalid,
    input  logic                         s2mm_awready,
    output logic [DATA_WIDTH-1:0]        s2mm_wdata,
    output logic [DATA_WIDTH/8-1:0]      s2mm_wstrb,
    output logic                         s2mm_wlast,
    output logic [USER_WIDTH-1:0]        s2mm_wuser,
    output logic                         s2mm_wvalid,
    input  logic                         s2mm_wready,
    input  logic [ID_WIDTH-1:0]          s2mm_bid,
    input  logic [1:0]                   s2mm_bresp,
    input  logic [USER_WIDTH-1:0]        s2mm_buser,
    input  logic                         s2mm_bvalid,
    output logic                         s2mm_bready,

    // ── MM2S AXI4 read masters (flat-packed, NUM_TAPS elements) ──────
    output logic [NUM_TAPS*ID_WIDTH-1:0]      mm2s_arid,
    output logic [NUM_TAPS*ADDR_WIDTH-1:0]    mm2s_araddr,
    output logic [NUM_TAPS*8-1:0]             mm2s_arlen,
    output logic [NUM_TAPS*3-1:0]             mm2s_arsize,
    output logic [NUM_TAPS*2-1:0]             mm2s_arburst,
    output logic [NUM_TAPS-1:0]               mm2s_arlock,
    output logic [NUM_TAPS*4-1:0]             mm2s_arcache,
    output logic [NUM_TAPS*3-1:0]             mm2s_arprot,
    output logic [NUM_TAPS*4-1:0]             mm2s_arqos,
    output logic [NUM_TAPS*USER_WIDTH-1:0]    mm2s_aruser,
    output logic [NUM_TAPS-1:0]               mm2s_arvalid,
    input  logic [NUM_TAPS-1:0]               mm2s_arready,
    input  logic [NUM_TAPS*ID_WIDTH-1:0]      mm2s_rid,
    input  logic [NUM_TAPS*DATA_WIDTH-1:0]    mm2s_rdata,
    input  logic [NUM_TAPS*2-1:0]             mm2s_rresp,
    input  logic [NUM_TAPS-1:0]               mm2s_rlast,
    input  logic [NUM_TAPS*USER_WIDTH-1:0]    mm2s_ruser,
    input  logic [NUM_TAPS-1:0]               mm2s_rvalid,
    output logic [NUM_TAPS-1:0]               mm2s_rready
);
    localparam int NS       = NUM_TAPS + 1;
    localparam int NUM_REGS = 17;

    localparam int WR_CTRL_IDX     = 0;
    localparam int WR_ADDR_IDX     = 1;
    localparam int WR_STRIDE_IDX   = 2;
    localparam int RD_CTRL_IDX     = 3;
    localparam int RD_ADDR_IDX     = 4;
    localparam int RD_STRIDE_IDX   = 5;
    // 6 = STATUS (read-only mirror)
    localparam int WR_HSIZE_IDX    = 7;
    localparam int WR_VSIZE_IDX    = 8;
    localparam int RD_HSIZE_IDX    = 9;
    localparam int RD_VSIZE_IDX    = 10;
    localparam int FRAME_ADDR0_IDX = 11;
    localparam int FRAME_ADDR1_IDX = 12;
    localparam int FRAME_ADDR2_IDX = 13;
    localparam int FRAME_ADDR3_IDX = 14;
    localparam int FRAME_CTRL_IDX  = 15;
    localparam int IRQ_ACK_IDX     = 16;

    logic [NUM_REGS-1:0][AXIL_DATA_WIDTH-1:0] regs;
    logic [AXIL_DATA_WIDTH-1:0]               status_event;

    logic [7:0]  wr_burst_len, rd_burst_len;
    logic [2:0]  wr_beat_size, rd_beat_size;
    logic        wr_start, wr_stop, wr_circular;
    logic        rd_start_global, rd_stop, rd_circular;
    logic        frame_store_enable;
    logic        irq_clear, fault_clear, telemetry_clear;

    logic        wr_frame_start, wr_restart_pending;
    logic        wr_axi_error_sticky, wr_axi_error_d;
    logic        overwrite_event;
    logic [3:0]  overwrite_count;

    logic [NUM_TAPS-1:0] rd_busy, rd_done, rd_error, rd_axi_error;
    logic [NUM_TAPS-1:0] rd_axi_error_sticky, rd_axi_error_d;
    logic [NUM_TAPS-1:0] rd_frame_start, rd_restart_pending;
    logic                rd_taps_available;

    logic [NUM_TAPS*ADDR_WIDTH-1:0] rd_frame_addr_flat;
    logic [(NS)*ADDR_WIDTH-1:0]     frame_addr_flat;

    assign wr_start        = regs[WR_CTRL_IDX][0];
    assign wr_stop         = regs[WR_CTRL_IDX][1];
    assign wr_circular     = regs[WR_CTRL_IDX][2];
    assign wr_beat_size    = regs[WR_CTRL_IDX][5:3];
    assign wr_burst_len    = regs[WR_CTRL_IDX][13:6];
    assign rd_start_global = regs[RD_CTRL_IDX][0];
    assign rd_stop         = regs[RD_CTRL_IDX][1];
    assign rd_circular     = regs[RD_CTRL_IDX][2];
    assign rd_beat_size    = regs[RD_CTRL_IDX][5:3];
    assign rd_burst_len    = regs[RD_CTRL_IDX][13:6];
    assign frame_store_enable = regs[FRAME_CTRL_IDX][0];
    assign irq_clear       = regs[FRAME_CTRL_IDX][16] || regs[IRQ_ACK_IDX][0];
    assign fault_clear     = regs[FRAME_CTRL_IDX][16] || regs[IRQ_ACK_IDX][1];
    assign telemetry_clear = regs[FRAME_CTRL_IDX][16] || regs[IRQ_ACK_IDX][2];
    assign wr_frame_start  = wr_start || wr_restart_pending;

    // Pack slot addresses from individual CSR regs
    always_comb begin
        frame_addr_flat = '0;
        frame_addr_flat[0*ADDR_WIDTH +: ADDR_WIDTH] = regs[FRAME_ADDR0_IDX][ADDR_WIDTH-1:0];
        frame_addr_flat[1*ADDR_WIDTH +: ADDR_WIDTH] = regs[FRAME_ADDR1_IDX][ADDR_WIDTH-1:0];
        if (NS > 2)
            frame_addr_flat[2*ADDR_WIDTH +: ADDR_WIDTH] = regs[FRAME_ADDR2_IDX][ADDR_WIDTH-1:0];
        if (NS > 3)
            frame_addr_flat[3*ADDR_WIDTH +: ADDR_WIDTH] = regs[FRAME_ADDR3_IDX][ADDR_WIDTH-1:0];
    end

    // All taps start together once warm; triggered by global rd_start
    always_comb begin
        for (int i = 0; i < NUM_TAPS; i++)
            rd_frame_start[i] = (rd_start_global || rd_restart_pending[i]) &&
                                 rd_taps_available;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_restart_pending <= 1'b0;
            rd_restart_pending <= '0;
        end else begin
            wr_restart_pending <= wr_done && wr_circular && !wr_stop && !wr_error;
            for (int i = 0; i < NUM_TAPS; i++)
                rd_restart_pending[i] <= rd_done[i] && rd_circular &&
                                         !rd_stop && !rd_error[i];
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_axi_error_sticky <= 1'b0; wr_axi_error_d <= 1'b0;
            rd_axi_error_sticky <= '0;   rd_axi_error_d <= '0;
        end else if (fault_clear) begin
            wr_axi_error_sticky <= 1'b0; wr_axi_error_d <= wr_axi_error;
            rd_axi_error_sticky <= '0;   rd_axi_error_d <= rd_axi_error;
        end else begin
            wr_axi_error_d <= wr_axi_error;
            rd_axi_error_d <= rd_axi_error;
            if (wr_axi_error && !wr_axi_error_d) wr_axi_error_sticky <= 1'b1;
            for (int i = 0; i < NUM_TAPS; i++)
                if (rd_axi_error[i] && !rd_axi_error_d[i])
                    rd_axi_error_sticky[i] <= 1'b1;
        end
    end

    function automatic logic [3:0] sat_inc4(input logic [3:0] v);
        sat_inc4 = (v == 4'hf) ? 4'hf : v + 4'd1;
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)               overwrite_count <= '0;
        else if (telemetry_clear) overwrite_count <= '0;
        else if (overwrite_event) overwrite_count <= sat_inc4(overwrite_count);
    end

    // IRQ fires on tap-0 (current frame) read-done or write-done
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)         irq <= 1'b0;
        else if (irq_clear) irq <= 1'b0;
        else if ((regs[FRAME_CTRL_IDX][8]  && wr_done)    ||
                 (regs[FRAME_CTRL_IDX][9]  && rd_done[0]) ||
                 (regs[FRAME_CTRL_IDX][10] &&
                  ((wr_done && wr_error) || (rd_done[0] && rd_error[0]))))
            irq <= 1'b1;
    end

    always_comb begin
        status_event        = '0;
        status_event[0]     = wr_done;
        status_event[1]     = rd_done[0];
        status_event[2]     = wr_busy;
        status_event[3]     = rd_busy[0];
        status_event[4]     = wr_error;
        status_event[5]     = rd_error[0];
        status_event[6]     = wr_axi_error_sticky;
        status_event[7]     = rd_axi_error_sticky[0];
        status_event[8]     = irq;
        status_event[9]     = rd_taps_available;
        for (int i = 0; i < NUM_TAPS; i++)
            status_event[10+i] = rd_busy[i];
        status_event[27:24] = overwrite_count;
    end
    assign vdma_status = regs[6][31:0];

    // ── CSR ───────────────────────────────────────────────────────────
    snix_axi_dma_csr #(
        .DATA_WIDTH(AXIL_DATA_WIDTH), .ADDR_WIDTH(AXIL_ADDR_WIDTH),
        .NUM_REGS(NUM_REGS),
        .PULSE_REG0_INDEX(FRAME_CTRL_IDX), .PULSE_REG0_MASK(32'h0001_0000),
        .PULSE_REG1_INDEX(IRQ_ACK_IDX),    .PULSE_REG1_MASK(32'h0000_0007)
    ) u_csr (
        .clk, .rst_n,
        .s_axil_awaddr, .s_axil_awvalid, .s_axil_awready,
        .s_axil_wdata, .s_axil_wstrb, .s_axil_wvalid, .s_axil_wready,
        .s_axil_bresp, .s_axil_bvalid, .s_axil_bready,
        .s_axil_araddr, .s_axil_arvalid, .s_axil_arready,
        .s_axil_rdata, .s_axil_rresp, .s_axil_rvalid, .s_axil_rready,
        .read_status_reg(status_event), .config_status_reg(regs)
    );

    // ── frame store ───────────────────────────────────────────────────
    logic [1:0]              write_slot;
    logic [NUM_TAPS*2-1:0]  tap_slot_flat;
    logic [NS-1:0]           valid_slots;
    logic [NS-1:0]           slot_read_locked;
    logic                    wr_slot_available;
    logic [ADDR_WIDTH-1:0]   wr_frame_addr;

    snix_axi_multi_vdma_frame_store #(
        .NUM_TAPS(NUM_TAPS), .ADDR_WIDTH(ADDR_WIDTH)
    ) u_frame_store (
        .clk, .rst_n, .enable(frame_store_enable),
        .frame_addr_flat,
        .wr_frame_start, .wr_frame_done(wr_done && !wr_error),
        .wr_frame_addr, .wr_slot_available, .overwrite_event,
        .rd_frame_start, .rd_frame_done(rd_done),
        .rd_frame_addr_flat, .rd_taps_available,
        .write_slot, .tap_slot_flat, .valid_slots, .slot_read_locked
    );

    // ── S2MM engine ───────────────────────────────────────────────────
    logic [ADDR_WIDTH-1:0] selected_wr_addr;
    assign selected_wr_addr = frame_store_enable
                            ? wr_frame_addr
                            : regs[WR_ADDR_IDX][ADDR_WIDTH-1:0];

    snix_axi_vdma_s2mm #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH(ID_WIDTH), .USER_WIDTH(USER_WIDTH),
        .FIFO_DEPTH(LINE_FIFO_DEPTH)
    ) u_s2mm (
        .clk, .rst_n,
        .frame_start(wr_frame_start && (!frame_store_enable || wr_slot_available)),
        .frame_stop(wr_stop),
        .frame_addr(selected_wr_addr),
        .frame_stride(regs[WR_STRIDE_IDX]),
        .frame_hsize_bytes(regs[WR_HSIZE_IDX]),
        .frame_vsize_lines(regs[WR_VSIZE_IDX]),
        .burst_len(wr_burst_len), .beat_size(wr_beat_size),
        .frame_busy(wr_busy), .frame_done(wr_done), .frame_error(wr_error),
        .axi_error(wr_axi_error),
        .s_axis_tdata, .s_axis_tuser, .s_axis_tkeep,
        .s_axis_tvalid, .s_axis_tready, .s_axis_tlast,
        .s2mm_awid, .s2mm_awaddr, .s2mm_awlen, .s2mm_awsize,
        .s2mm_awburst, .s2mm_awlock, .s2mm_awcache, .s2mm_awprot,
        .s2mm_awqos, .s2mm_awuser, .s2mm_awvalid, .s2mm_awready,
        .s2mm_wdata, .s2mm_wstrb, .s2mm_wlast, .s2mm_wuser,
        .s2mm_wvalid, .s2mm_wready,
        .s2mm_bid, .s2mm_bresp, .s2mm_buser, .s2mm_bvalid, .s2mm_bready
    );

    // ── MM2S engines, one per tap ─────────────────────────────────────
    generate
        for (genvar i = 0; i < NUM_TAPS; i++) begin : g_mm2s
            logic [ADDR_WIDTH-1:0] tap_rd_addr;
            assign tap_rd_addr = frame_store_enable
                               ? rd_frame_addr_flat[i*ADDR_WIDTH +: ADDR_WIDTH]
                               : regs[RD_ADDR_IDX][ADDR_WIDTH-1:0];

            snix_axi_vdma_mm2s #(
                .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
                .ID_WIDTH(ID_WIDTH), .USER_WIDTH(USER_WIDTH),
                .FIFO_DEPTH(LINE_FIFO_DEPTH)
            ) u_mm2s (
                .clk, .rst_n,
                .frame_start(rd_frame_start[i]),
                .frame_stop(rd_stop),
                .frame_addr(tap_rd_addr),
                .frame_stride(regs[RD_STRIDE_IDX]),
                .frame_hsize_bytes(regs[RD_HSIZE_IDX]),
                .frame_vsize_lines(regs[RD_VSIZE_IDX]),
                .burst_len(rd_burst_len), .beat_size(rd_beat_size),
                .frame_busy (rd_busy [i]),
                .frame_done (rd_done [i]),
                .frame_error(rd_error[i]),
                .axi_error  (rd_axi_error[i]),
                .m_axis_tdata (m_axis_tdata [i*DATA_WIDTH   +: DATA_WIDTH  ]),
                .m_axis_tuser (m_axis_tuser [i*USER_WIDTH   +: USER_WIDTH  ]),
                .m_axis_tkeep (m_axis_tkeep [i*(DATA_WIDTH/8) +: DATA_WIDTH/8]),
                .m_axis_tvalid(m_axis_tvalid[i]),
                .m_axis_tready(m_axis_tready[i]),
                .m_axis_tlast (m_axis_tlast [i]),
                .mm2s_arid   (mm2s_arid   [i*ID_WIDTH   +: ID_WIDTH  ]),
                .mm2s_araddr (mm2s_araddr [i*ADDR_WIDTH +: ADDR_WIDTH]),
                .mm2s_arlen  (mm2s_arlen  [i*8          +: 8         ]),
                .mm2s_arsize (mm2s_arsize [i*3          +: 3         ]),
                .mm2s_arburst(mm2s_arburst[i*2          +: 2         ]),
                .mm2s_arlock (mm2s_arlock [i]),
                .mm2s_arcache(mm2s_arcache[i*4          +: 4         ]),
                .mm2s_arprot (mm2s_arprot [i*3          +: 3         ]),
                .mm2s_arqos  (mm2s_arqos  [i*4          +: 4         ]),
                .mm2s_aruser (mm2s_aruser [i*USER_WIDTH +: USER_WIDTH]),
                .mm2s_arvalid(mm2s_arvalid[i]),
                .mm2s_arready(mm2s_arready[i]),
                .mm2s_rid    (mm2s_rid    [i*ID_WIDTH   +: ID_WIDTH  ]),
                .mm2s_rdata  (mm2s_rdata  [i*DATA_WIDTH +: DATA_WIDTH]),
                .mm2s_rresp  (mm2s_rresp  [i*2          +: 2         ]),
                .mm2s_rlast  (mm2s_rlast  [i]),
                .mm2s_ruser  (mm2s_ruser  [i*USER_WIDTH +: USER_WIDTH]),
                .mm2s_rvalid (mm2s_rvalid [i]),
                .mm2s_rready (mm2s_rready [i])
            );
        end
    endgenerate

endmodule : snix_axi_multi_vdma

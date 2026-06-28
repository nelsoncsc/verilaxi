`timescale 1ns/1ps
// test_multi_vdma — functional verification for snix_axi_multi_vdma
//
// Tests:
//   1. Warmup: capture NUM_TAPS+1 frames, verify rd_taps_available asserts
//   2. Parallel playback: all N taps start together, each receives a different
//      frame generation — tap 0 = newest, tap 1 = previous, tap 2 = oldest
//   3. Rolling advance: capture one more frame in circular mode, repeat
//      playback; tap assignments must shift (old tap-0 content appears on tap-1)
//   4. Memory readback: verify AXI slave holds correct frame data per slot
//
// NUM_TAPS is driven by the MULTI_VDMA_TAPS plusarg (default 2).

module test_multi_vdma #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 64,
    parameter int ID_WIDTH   = 4,
    parameter int USER_WIDTH = 1
) (
    input logic clk,
    input logic rst_n
);
    import axi_pkg::*;
    import axi_vdma_pkg::*;

    // ── geometry ────────────────────────────────────────────────────────
    localparam int WIDTH_PIXELS   = 8;
    localparam int HEIGHT_LINES   = 4;
    localparam int BYTES_PER_PIXEL = DATA_WIDTH / 8;
    localparam int HSIZE_BYTES    = WIDTH_PIXELS * BYTES_PER_PIXEL;
    localparam int STRIDE_BYTES   = 128;
    localparam int PIXELS_PER_FRAME = WIDTH_PIXELS * HEIGHT_LINES;

    // Slot base addresses (NUM_TAPS+1 slots, up to 4)
    localparam int SLOT_ADDR [0:3] = '{
        32'h0000_1000,
        32'h0000_2000,
        32'h0000_3000,
        32'h0000_4000
    };

    // multi_vdma CSR addresses (same as vdma but FRAME_ADDR3 at 0x38, FRAME_CTRL at 0x3c)
    localparam int MV_WR_CTRL      = 32'h00;
    localparam int MV_WR_STRIDE    = 32'h08;
    localparam int MV_RD_CTRL      = 32'h0c;
    localparam int MV_RD_STRIDE    = 32'h14;
    localparam int MV_WR_HSIZE     = 32'h1c;
    localparam int MV_WR_VSIZE     = 32'h20;
    localparam int MV_RD_HSIZE     = 32'h24;
    localparam int MV_RD_VSIZE     = 32'h28;
    localparam int MV_FRAME_ADDR0  = 32'h2c;
    localparam int MV_FRAME_ADDR1  = 32'h30;
    localparam int MV_FRAME_ADDR2  = 32'h34;
    localparam int MV_FRAME_ADDR3  = 32'h38;
    localparam int MV_FRAME_CTRL   = 32'h3c;
    localparam int MV_STATUS       = 32'h18;

    localparam int MEM_DEPTH = 65536;
    localparam int AXIL_ADDR_WIDTH = 32;
    localparam int AXIL_DATA_WIDTH = 32;

    // ── PNG DPI imports (used by MVDMA_PNG phase) ────────────────────────────
    import "DPI-C" function void vf_src_load(input string path);
    import "DPI-C" function void vf_src_load_append(input string path);
    import "DPI-C" function int  vf_src_get_pixel(input int idx);
    import "DPI-C" function int  vf_src_total_pixels();
    import "DPI-C" function void vf_sink_push_n(input int tap, input int rgb24);
    import "DPI-C" function void vf_sink_write_n(input int tap, input string path,
                                                 input int width, input int height);
    import "DPI-C" function void vf_diff_write(input int tap_a, input int tap_b,
                                               input string path,
                                               input int width, input int height,
                                               input int amplify);
    import "DPI-C" function int  vf_diff_count(input int tap_a, input int tap_b,
                                               input int width, input int height);
    import "DPI-C" function int  vf_diff_energy_x1000(input int tap_a, input int tap_b,
                                                      input int width, input int height);

    // Run-time: number of taps to exercise (1,2,3)
    int num_taps;

    // Throughput accounting (per tap): beats moved and the measurement
    // windows. tap_cycles_total = first-tready to last-beat (startup latency
    // included); tap_cycles_steady = first-valid to last-beat (steady state).
    int tap_beats        [0:2];
    int tap_cycles_total [0:2];
    int tap_cycles_steady[0:2];

    // ── stress: seeded reproducible PRNG (independent of $urandom so the
    //    same SEED plusarg replays the exact backpressure pattern) ─────────
    int stress_fid;   // running capture frame id for concurrent stress
    int unsigned rng_state;
    function automatic int unsigned next_rand();
        rng_state = rng_state * 32'd1103515245 + 32'd12345;
        return rng_state;
    endfunction
    function automatic int rand_range(input int lo, input int hi);  // inclusive
        return lo + int'(next_rand() % (hi - lo + 1));
    endfunction

    // ── interfaces ──────────────────────────────────────────────────────
    axil_if #(
        .ADDR_WIDTH(AXIL_ADDR_WIDTH), .DATA_WIDTH(AXIL_DATA_WIDTH)
    ) axil (.ACLK(clk), .ARESETn(rst_n));

    axis_if #(.DATA_WIDTH(DATA_WIDTH), .USER_WIDTH(USER_WIDTH))
        capture_axis (.ACLK(clk), .ARESETn(rst_n));

    // Three independent MM2S AXI4 memory interfaces + AXIS outputs
    axi4_if #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH(ID_WIDTH), .USER_WIDTH(USER_WIDTH)
    ) s2mm_mem (.ACLK(clk), .ARESETn(rst_n));

    axi4_if #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH(ID_WIDTH), .USER_WIDTH(USER_WIDTH)
    ) mm2s_mem [0:2] (.ACLK(clk), .ARESETn(rst_n));

    axis_if #(.DATA_WIDTH(DATA_WIDTH), .USER_WIDTH(USER_WIDTH))
        tap_axis [0:2] (.ACLK(clk), .ARESETn(rst_n));

    // ── DUT signals (flat-packed, NUM_TAPS=3 elaborated, taps>num_taps unused) ─
    logic [3*DATA_WIDTH-1:0]        m_axis_tdata;
    logic [3*USER_WIDTH-1:0]        m_axis_tuser;
    logic [3*(DATA_WIDTH/8)-1:0]    m_axis_tkeep;
    logic [2:0]                     m_axis_tvalid;
    logic [2:0]                     m_axis_tready;
    logic [2:0]                     m_axis_tlast;

    logic [3*ID_WIDTH-1:0]          mm2s_arid;
    logic [3*ADDR_WIDTH-1:0]        mm2s_araddr;
    logic [3*8-1:0]                 mm2s_arlen;
    logic [3*3-1:0]                 mm2s_arsize;
    logic [3*2-1:0]                 mm2s_arburst;
    logic [2:0]                     mm2s_arlock;
    logic [3*4-1:0]                 mm2s_arcache;
    logic [3*3-1:0]                 mm2s_arprot;
    logic [3*4-1:0]                 mm2s_arqos;
    logic [3*USER_WIDTH-1:0]        mm2s_aruser;
    logic [2:0]                     mm2s_arvalid;
    logic [2:0]                     mm2s_arready;
    logic [3*ID_WIDTH-1:0]          mm2s_rid;
    logic [3*DATA_WIDTH-1:0]        mm2s_rdata;
    logic [3*2-1:0]                 mm2s_rresp;
    logic [2:0]                     mm2s_rlast;
    logic [3*USER_WIDTH-1:0]        mm2s_ruser;
    logic [2:0]                     mm2s_rvalid;
    logic [2:0]                     mm2s_rready;

    logic wr_busy, wr_done, wr_error, wr_axi_error, irq;
    logic [31:0] vdma_status;

    // ── connect flat DUT signals to per-tap interfaces ──────────────────
    genvar gi;
    generate
        for (gi = 0; gi < 3; gi++) begin : g_tap_if
            assign tap_axis[gi].tdata  = m_axis_tdata [gi*DATA_WIDTH   +: DATA_WIDTH];
            assign tap_axis[gi].tuser  = m_axis_tuser [gi*USER_WIDTH   +: USER_WIDTH];
            assign tap_axis[gi].tkeep  = m_axis_tkeep [gi*(DATA_WIDTH/8) +: DATA_WIDTH/8];
            assign tap_axis[gi].tvalid = m_axis_tvalid[gi];
            assign tap_axis[gi].tready = m_axis_tready[gi];
            assign tap_axis[gi].tlast  = m_axis_tlast[gi];

            assign mm2s_arready[gi]            = mm2s_mem[gi].arready;
            assign mm2s_mem[gi].arid           = mm2s_arid   [gi*ID_WIDTH   +: ID_WIDTH];
            assign mm2s_mem[gi].araddr         = mm2s_araddr [gi*ADDR_WIDTH +: ADDR_WIDTH];
            assign mm2s_mem[gi].arlen          = mm2s_arlen  [gi*8          +: 8];
            assign mm2s_mem[gi].arsize         = mm2s_arsize [gi*3          +: 3];
            assign mm2s_mem[gi].arburst        = mm2s_arburst[gi*2          +: 2];
            assign mm2s_mem[gi].arlock         = mm2s_arlock [gi];
            assign mm2s_mem[gi].arcache        = mm2s_arcache[gi*4          +: 4];
            assign mm2s_mem[gi].arprot         = mm2s_arprot [gi*3          +: 3];
            assign mm2s_mem[gi].arqos          = mm2s_arqos  [gi*4          +: 4];
            assign mm2s_mem[gi].aruser         = mm2s_aruser [gi*USER_WIDTH +: USER_WIDTH];
            assign mm2s_mem[gi].arvalid        = mm2s_arvalid[gi];
            assign mm2s_rdata  [gi*DATA_WIDTH +: DATA_WIDTH] = mm2s_mem[gi].rdata;
            assign mm2s_rresp  [gi*2          +: 2]         = mm2s_mem[gi].rresp;
            assign mm2s_rlast  [gi]                         = mm2s_mem[gi].rlast;
            assign mm2s_ruser  [gi*USER_WIDTH +: USER_WIDTH] = mm2s_mem[gi].ruser;
            assign mm2s_rvalid [gi]                         = mm2s_mem[gi].rvalid;
            assign mm2s_rid    [gi*ID_WIDTH   +: ID_WIDTH]  = mm2s_mem[gi].rid;
            assign mm2s_mem[gi].rready                      = mm2s_rready[gi];
        end
    endgenerate

    // ── DUT ─────────────────────────────────────────────────────────────
    snix_axi_multi_vdma #(
        .NUM_TAPS(3),
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
        .AXIL_ADDR_WIDTH(AXIL_ADDR_WIDTH), .AXIL_DATA_WIDTH(AXIL_DATA_WIDTH),
        .ID_WIDTH(ID_WIDTH), .USER_WIDTH(USER_WIDTH), .LINE_FIFO_DEPTH(64)
    ) dut (
        .clk, .rst_n,
        .s_axil_awaddr(axil.awaddr), .s_axil_awvalid(axil.awvalid),
        .s_axil_awready(axil.awready),
        .s_axil_wdata(axil.wdata), .s_axil_wstrb(axil.wstrb),
        .s_axil_wvalid(axil.wvalid), .s_axil_wready(axil.wready),
        .s_axil_bresp(axil.bresp), .s_axil_bvalid(axil.bvalid),
        .s_axil_bready(axil.bready),
        .s_axil_araddr(axil.araddr), .s_axil_arvalid(axil.arvalid),
        .s_axil_arready(axil.arready),
        .s_axil_rdata(axil.rdata), .s_axil_rresp(axil.rresp),
        .s_axil_rvalid(axil.rvalid), .s_axil_rready(axil.rready),
        .s_axis_tdata(capture_axis.tdata), .s_axis_tuser(capture_axis.tuser),
        .s_axis_tkeep(capture_axis.tkeep),
        .s_axis_tvalid(capture_axis.tvalid), .s_axis_tready(capture_axis.tready),
        .s_axis_tlast(capture_axis.tlast),
        .m_axis_tdata, .m_axis_tuser, .m_axis_tkeep,
        .m_axis_tvalid, .m_axis_tready, .m_axis_tlast,
        .irq, .vdma_status,
        .wr_busy, .wr_done, .wr_error, .wr_axi_error,
        .s2mm_awid(s2mm_mem.awid), .s2mm_awaddr(s2mm_mem.awaddr),
        .s2mm_awlen(s2mm_mem.awlen), .s2mm_awsize(s2mm_mem.awsize),
        .s2mm_awburst(s2mm_mem.awburst), .s2mm_awlock(s2mm_mem.awlock),
        .s2mm_awcache(s2mm_mem.awcache), .s2mm_awprot(s2mm_mem.awprot),
        .s2mm_awqos(s2mm_mem.awqos), .s2mm_awuser(s2mm_mem.awuser),
        .s2mm_awvalid(s2mm_mem.awvalid), .s2mm_awready(s2mm_mem.awready),
        .s2mm_wdata(s2mm_mem.wdata), .s2mm_wstrb(s2mm_mem.wstrb),
        .s2mm_wlast(s2mm_mem.wlast), .s2mm_wuser(s2mm_mem.wuser),
        .s2mm_wvalid(s2mm_mem.wvalid), .s2mm_wready(s2mm_mem.wready),
        .s2mm_bid(s2mm_mem.bid), .s2mm_bresp(s2mm_mem.bresp),
        .s2mm_buser(s2mm_mem.buser), .s2mm_bvalid(s2mm_mem.bvalid),
        .s2mm_bready(s2mm_mem.bready),
        .mm2s_arid, .mm2s_araddr, .mm2s_arlen, .mm2s_arsize,
        .mm2s_arburst, .mm2s_arlock, .mm2s_arcache, .mm2s_arprot,
        .mm2s_arqos, .mm2s_aruser, .mm2s_arvalid, .mm2s_arready,
        .mm2s_rid, .mm2s_rdata, .mm2s_rresp, .mm2s_rlast,
        .mm2s_ruser, .mm2s_rvalid, .mm2s_rready
    );

    // ── SVA checkers ────────────────────────────────────────────────────
    axi_mm_checker #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH(ID_WIDTH), .LABEL("MVDMA_S2MM")
    ) u_s2mm_checker (
        .clk, .rst_n,
        .awaddr(s2mm_mem.awaddr), .awlen(s2mm_mem.awlen),
        .awsize(s2mm_mem.awsize), .awburst(s2mm_mem.awburst),
        .awid(s2mm_mem.awid), .awvalid(s2mm_mem.awvalid), .awready(s2mm_mem.awready),
        .wdata(s2mm_mem.wdata), .wstrb(s2mm_mem.wstrb),
        .wlast(s2mm_mem.wlast), .wvalid(s2mm_mem.wvalid), .wready(s2mm_mem.wready),
        .bid(s2mm_mem.bid), .bresp(s2mm_mem.bresp),
        .bvalid(s2mm_mem.bvalid), .bready(s2mm_mem.bready),
        .araddr('0), .arlen('0), .arsize('0), .arburst('0),
        .arid('0), .arvalid('0), .arready('0),
        .rid('0), .rdata('0), .rresp('0), .rlast('0), .rvalid('0), .rready('0)
    );

    generate
        for (gi = 0; gi < 3; gi++) begin : g_mm2s_checker
            axi_mm_checker #(
                .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
                .ID_WIDTH(ID_WIDTH), .LABEL("MVDMA_MM2S")
            ) u_mm2s_checker (
                .clk, .rst_n,
                .awaddr('0), .awlen('0), .awsize('0), .awburst('0),
                .awid('0), .awvalid('0), .awready('0),
                .wdata('0), .wstrb('0), .wlast('0), .wvalid('0), .wready('0),
                .bid('0), .bresp('0), .bvalid('0), .bready('0),
                .araddr(mm2s_mem[gi].araddr), .arlen(mm2s_mem[gi].arlen),
                .arsize(mm2s_mem[gi].arsize), .arburst(mm2s_mem[gi].arburst),
                .arid(mm2s_mem[gi].arid), .arvalid(mm2s_mem[gi].arvalid),
                .arready(mm2s_mem[gi].arready),
                .rid(mm2s_mem[gi].rid), .rdata(mm2s_mem[gi].rdata),
                .rresp(mm2s_mem[gi].rresp), .rlast(mm2s_mem[gi].rlast),
                .rvalid(mm2s_mem[gi].rvalid), .rready(mm2s_mem[gi].rready)
            );

            axil_checker #(
                .ADDR_WIDTH(AXIL_ADDR_WIDTH), .DATA_WIDTH(AXIL_DATA_WIDTH),
                .LABEL("MVDMA_AXIL")
            ) u_axil_checker (
                .clk, .rst_n,
                .awaddr(axil.awaddr), .awvalid(axil.awvalid), .awready(axil.awready),
                .wdata(axil.wdata), .wstrb(axil.wstrb),
                .wvalid(axil.wvalid), .wready(axil.wready),
                .bresp(axil.bresp), .bvalid(axil.bvalid), .bready(axil.bready),
                .araddr(axil.araddr), .arvalid(axil.arvalid), .arready(axil.arready),
                .rdata(axil.rdata), .rresp(axil.rresp),
                .rvalid(axil.rvalid), .rready(axil.rready)
            );
        end
    endgenerate

    // ── memory slaves ────────────────────────────────────────────────────
    // One shared logical address space, implemented by four slave instances
    // sharing the same mem[] array via a common axi_slave handle for the
    // S2MM writer; the MM2S slaves use separate handles but share addresses.
    axi_slave #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH(ID_WIDTH), .MEM_DEPTH(MEM_DEPTH)
    ) wr_slave, rd_slave[0:2];

    axil_master #(
        .ADDR_WIDTH(AXIL_ADDR_WIDTH), .DATA_WIDTH(AXIL_DATA_WIDTH)
    ) axil_m;

    // ── pixel encoding: frame_id in [23:16], row in [15:8], col in [7:0] ─
    function automatic logic [DATA_WIDTH-1:0] tap_pixel(
        input int frame_id, input int row, input int col
    );
        tap_pixel = 64'hbeef_0000_0000_0000 |
                    (DATA_WIDTH'(frame_id) << 16) |
                    (DATA_WIDTH'(row)      <<  8) |
                    DATA_WIDTH'(col);
    endfunction

    // ── send one frame (frame_id identifies the pixel content) ────────────
    task automatic send_frame(input int frame_id);
        for (int row = 0; row < HEIGHT_LINES; row++) begin
            for (int col = 0; col < WIDTH_PIXELS; col++) begin
                @(negedge clk);
                capture_axis.tdata  = tap_pixel(frame_id, row, col);
                capture_axis.tuser  = USER_WIDTH'((row == 0) && (col == 0));
                capture_axis.tlast  = (col == WIDTH_PIXELS - 1);
                capture_axis.tvalid = 1'b1;
                @(posedge clk);
                while (!capture_axis.tready) @(posedge clk);
            end
        end
        @(negedge clk);
        capture_axis.tvalid = 1'b0;
        capture_axis.tlast  = 1'b0;
        capture_axis.tuser  = '0;
    endtask

    // ── receive and verify one tap stream ────────────────────────────────
    // Accesses flat packed signals directly (Verilator requires constant
    // indices on interface arrays; variable-indexed interface access is
    // not supported in procedural contexts).
    task automatic receive_and_verify_tap(
        input int tap_idx,
        input int expected_frame_id,
        output int errors
    );
        int received = 0;
        int ready_cycle = 0;
        logic [DATA_WIDTH-1:0]   pkt_tdata;
        logic [USER_WIDTH-1:0]   pkt_tuser;
        logic                    pkt_tvalid;
        logic                    pkt_tlast;
        errors = 0;

        while (received < PIXELS_PER_FRAME) begin
            @(negedge clk);
            // Drive tready for this tap via the flat signal
            case (tap_idx)
                0: m_axis_tready[0] = ((ready_cycle % 4) != 0);
                1: m_axis_tready[1] = ((ready_cycle % 4) != 0);
                2: m_axis_tready[2] = ((ready_cycle % 4) != 0);
                default: ;
            endcase
            ready_cycle++;
            @(posedge clk);
            // Sample from flat signals
            case (tap_idx)
                0: begin
                    pkt_tdata  = m_axis_tdata [0*DATA_WIDTH +: DATA_WIDTH];
                    pkt_tuser  = m_axis_tuser [0*USER_WIDTH +: USER_WIDTH];
                    pkt_tvalid = m_axis_tvalid[0];
                    pkt_tlast  = m_axis_tlast [0];
                end
                1: begin
                    pkt_tdata  = m_axis_tdata [1*DATA_WIDTH +: DATA_WIDTH];
                    pkt_tuser  = m_axis_tuser [1*USER_WIDTH +: USER_WIDTH];
                    pkt_tvalid = m_axis_tvalid[1];
                    pkt_tlast  = m_axis_tlast [1];
                end
                default: begin
                    pkt_tdata  = m_axis_tdata [2*DATA_WIDTH +: DATA_WIDTH];
                    pkt_tuser  = m_axis_tuser [2*USER_WIDTH +: USER_WIDTH];
                    pkt_tvalid = m_axis_tvalid[2];
                    pkt_tlast  = m_axis_tlast [2];
                end
            endcase
            if (pkt_tvalid && m_axis_tready[tap_idx]) begin
                int row = received / WIDTH_PIXELS;
                int col = received % WIDTH_PIXELS;
                logic [DATA_WIDTH-1:0] exp = tap_pixel(expected_frame_id, row, col);
                if (pkt_tdata !== exp) begin
                    $error("[MVDMA] tap%0d pixel mismatch frame=%0d row=%0d col=%0d exp=%h got=%h",
                           tap_idx, expected_frame_id, row, col, exp, pkt_tdata);
                    errors++;
                end
                if (pkt_tuser[0] !== ((row == 0) && (col == 0))) begin
                    $error("[MVDMA] tap%0d SOF mismatch row=%0d col=%0d",
                           tap_idx, row, col);
                    errors++;
                end
                if (pkt_tlast !== (col == WIDTH_PIXELS - 1)) begin
                    $error("[MVDMA] tap%0d EOL mismatch row=%0d col=%0d",
                           tap_idx, row, col);
                    errors++;
                end
                received++;
            end
        end
        @(negedge clk);
        m_axis_tready[tap_idx] = 1'b0;
    endtask

    // ── receive one tap at full rate, measure throughput + verify ─────────
    // tready held high the whole frame.  Records into the module-level
    // tap_beats / tap_cycles_* arrays for the calling round to report.
    //   tap_cycles_total  = cycles from first tready assert to last beat
    //                       (includes AR-issue + slave read latency)
    //   tap_cycles_steady = cycles from first valid beat to last beat
    //                       (steady-state delivery, latency removed)
    task automatic receive_tap_throughput(
        input int tap_idx,
        input int expected_frame_id,
        output int errors
    );
        int received     = 0;
        int total_cycles = 0;
        int first_valid  = -1;
        logic [DATA_WIDTH-1:0] pkt_tdata;
        logic                  pkt_tvalid;
        errors = 0;

        while (received < PIXELS_PER_FRAME) begin
            @(negedge clk);
            case (tap_idx)               // full rate: tready always high
                0: m_axis_tready[0] = 1'b1;
                1: m_axis_tready[1] = 1'b1;
                2: m_axis_tready[2] = 1'b1;
                default: ;
            endcase
            @(posedge clk);
            total_cycles++;
            case (tap_idx)
                0: begin pkt_tdata = m_axis_tdata[0*DATA_WIDTH +: DATA_WIDTH];
                         pkt_tvalid = m_axis_tvalid[0]; end
                1: begin pkt_tdata = m_axis_tdata[1*DATA_WIDTH +: DATA_WIDTH];
                         pkt_tvalid = m_axis_tvalid[1]; end
                default: begin pkt_tdata = m_axis_tdata[2*DATA_WIDTH +: DATA_WIDTH];
                         pkt_tvalid = m_axis_tvalid[2]; end
            endcase
            if (pkt_tvalid && m_axis_tready[tap_idx]) begin
                automatic int row = received / WIDTH_PIXELS;
                automatic int col = received % WIDTH_PIXELS;
                if (first_valid < 0) first_valid = total_cycles;
                if (pkt_tdata !== tap_pixel(expected_frame_id, row, col)) begin
                    $error("[MVDMA] tap%0d tput pixel mismatch frame=%0d row=%0d col=%0d",
                           tap_idx, expected_frame_id, row, col);
                    errors++;
                end
                received++;
            end
        end
        @(negedge clk);
        case (tap_idx)
            0: m_axis_tready[0] = 1'b0;
            1: m_axis_tready[1] = 1'b0;
            2: m_axis_tready[2] = 1'b0;
            default: ;
        endcase

        tap_beats        [tap_idx] = received;
        tap_cycles_total [tap_idx] = total_cycles;
        tap_cycles_steady[tap_idx] = total_cycles - first_valid + 1;
    endtask

    // ── full-rate throughput round: start all active taps, measure each ───
    task automatic throughput_round(
        input int expected_frames[0:2],
        input int n_taps,
        output int total_errors
    );
        int e[0:2];
        total_errors = 0;
        axil_m.write(MV_RD_CTRL, vdma_ctrl_word(1'b1, 1'b0, 3'd3, 8'd3));
        axil_m.write(MV_RD_CTRL, vdma_ctrl_word(1'b0, 1'b0, 3'd3, 8'd3)); // clear start only; keep burst params stable
        fork
            receive_tap_throughput(0, expected_frames[0], e[0]);
            if (n_taps > 1) receive_tap_throughput(1, expected_frames[1], e[1]);
            else            drain_tap(1);
            if (n_taps > 2) receive_tap_throughput(2, expected_frames[2], e[2]);
            else            drain_tap(2);
        join
        for (int i = 0; i < n_taps; i++) total_errors += e[i];
    endtask

    // ════════════════════════════════════════════════════════════════════
    //  STRESS SUITE  (gated by MVDMA_STRESS plusarg)
    //  Covers: variable geometry, asymmetric per-tap backpressure, seeds,
    //  and concurrent capture+playback coherence. Uses the existing
    //  fixed-latency behavioral slave (bandwidth optimistic; logic-exact).
    // ════════════════════════════════════════════════════════════════════

    // Program frame-store geometry + 4 slot bases sized for a WxH frame.
    // Slots are spaced by a 4KB-aligned slot size so they never overlap.
    task automatic stress_program_geometry(
        input int w, input int h, output int stride_bytes, output int slot_bytes);
        automatic int sb = w * BYTES_PER_PIXEL;            // tightly packed line
        automatic int ss = h * sb;
        ss = ((ss + 'h0fff) / 'h1000) * 'h1000;            // round up to 4KB
        stride_bytes = sb;
        slot_bytes   = ss;
        axil_m.write(MV_FRAME_ADDR0, 32'h0000_1000 + 0*ss);
        axil_m.write(MV_FRAME_ADDR1, 32'h0000_1000 + 1*ss);
        axil_m.write(MV_FRAME_ADDR2, 32'h0000_1000 + 2*ss);
        axil_m.write(MV_FRAME_ADDR3, 32'h0000_1000 + 3*ss);
        axil_m.write(MV_WR_STRIDE, sb); axil_m.write(MV_RD_STRIDE, sb);
        axil_m.write(MV_WR_HSIZE,  sb); axil_m.write(MV_RD_HSIZE,  sb);
        axil_m.write(MV_WR_VSIZE,  h);  axil_m.write(MV_RD_VSIZE,  h);
    endtask

    // Capture one WxH frame into the writer slave; mirror the 4-slot region
    // into every read slave once wr_done fires.
    task automatic stress_send_frame(input int frame_id, input int w, input int h);
        for (int row = 0; row < h; row++) begin
            for (int col = 0; col < w; col++) begin
                @(negedge clk);
                capture_axis.tdata  = tap_pixel(frame_id, row, col);
                capture_axis.tuser  = USER_WIDTH'((row == 0) && (col == 0));
                capture_axis.tlast  = (col == w - 1);
                capture_axis.tvalid = 1'b1;
                @(posedge clk);
                if (!capture_axis.tready) begin
                    automatic int tmo = 0;
                    while (!capture_axis.tready) begin
                        @(posedge clk);
                        tmo++;
                        if (tmo == 5000)
                            $fatal(1, "[MVDMA] TIMEOUT: tready stuck 0 fid=%0d r=%0d c=%0d wr_busy=%0b wr_done=%0b",
                                   frame_id, row, col, wr_busy, wr_done);
                    end
                end
            end
        end
        @(negedge clk);
        capture_axis.tvalid = 1'b0;
        capture_axis.tlast  = 1'b0;
        capture_axis.tuser  = '0;
    endtask

    // Drain an unused hardware tap of a full WxH frame (release its read lock).
    task automatic stress_drain_tap(input int tap_idx, input int w, input int h);
        automatic int n = 0;
        automatic int total = w * h;
        while (n < total) begin
            @(negedge clk);
            case (tap_idx)
                0: m_axis_tready[0] = 1;
                1: m_axis_tready[1] = 1;
                2: m_axis_tready[2] = 1;
                default: ;
            endcase
            @(posedge clk);
            case (tap_idx)
                0: if (m_axis_tvalid[0] && m_axis_tready[0]) n++;
                1: if (m_axis_tvalid[1] && m_axis_tready[1]) n++;
                2: if (m_axis_tvalid[2] && m_axis_tready[2]) n++;
                default: ;
            endcase
        end
        @(negedge clk);
        case (tap_idx)
            0: m_axis_tready[0] = 0;
            1: m_axis_tready[1] = 0;
            2: m_axis_tready[2] = 0;
            default: ;
        endcase
    endtask

    task automatic stress_mirror_region(input int n_words);
        for (int j = 0; j < n_words; j++) begin
            rd_slave[0].mem[j] = wr_slave.mem[j];
            rd_slave[1].mem[j] = wr_slave.mem[j];
            rd_slave[2].mem[j] = wr_slave.mem[j];
        end
    endtask

    // Receive one WxH frame on a tap with randomized backpressure (stall_mod
    // sets the average stall: higher = less stalling). Verifies pixel-exact
    // content, SOF/EOL, and that the whole frame carries one frame_id (no tear).
    task automatic stress_recv_tap(
        input int tap_idx, input int expected_frame_id,
        input int w, input int h, input int stall_mod, output int errors);
        automatic int received = 0;
        automatic int total    = w * h;
        logic [DATA_WIDTH-1:0] d; logic v, u, l;
        errors = 0;
        while (received < total) begin
            @(negedge clk);
            case (tap_idx)
                0: m_axis_tready[0] = ((next_rand() % stall_mod) != 0);
                1: m_axis_tready[1] = ((next_rand() % stall_mod) != 0);
                2: m_axis_tready[2] = ((next_rand() % stall_mod) != 0);
                default: ;
            endcase
            @(posedge clk);
            case (tap_idx)
                0: begin d=m_axis_tdata[0*DATA_WIDTH+:DATA_WIDTH]; v=m_axis_tvalid[0];
                         u=m_axis_tuser[0*USER_WIDTH+:USER_WIDTH]; l=m_axis_tlast[0]; end
                1: begin d=m_axis_tdata[1*DATA_WIDTH+:DATA_WIDTH]; v=m_axis_tvalid[1];
                         u=m_axis_tuser[1*USER_WIDTH+:USER_WIDTH]; l=m_axis_tlast[1]; end
                default: begin d=m_axis_tdata[2*DATA_WIDTH+:DATA_WIDTH]; v=m_axis_tvalid[2];
                         u=m_axis_tuser[2*USER_WIDTH+:USER_WIDTH]; l=m_axis_tlast[2]; end
            endcase
            if (v && m_axis_tready[tap_idx]) begin
                automatic int row = received / w;
                automatic int col = received % w;
                if (d !== tap_pixel(expected_frame_id, row, col)) begin
                    $error("[MVDMA-STRESS] tap%0d tear/mismatch f=%0d r=%0d c=%0d got=%h",
                           tap_idx, expected_frame_id, row, col, d);
                    errors++;
                end
                if (u !== ((row == 0) && (col == 0))) begin
                    $error("[MVDMA-STRESS] tap%0d SOF err r=%0d c=%0d", tap_idx, row, col);
                    errors++;
                end
                if (l !== (col == w - 1)) begin
                    $error("[MVDMA-STRESS] tap%0d EOL err r=%0d c=%0d", tap_idx, row, col);
                    errors++;
                end
                received++;
            end
        end
        @(negedge clk);
        case (tap_idx)
            0: m_axis_tready[0] = 1'b0;
            1: m_axis_tready[1] = 1'b0;
            2: m_axis_tready[2] = 1'b0;
            default: ;
        endcase
    endtask

    // One sequential stress iteration: program WxH, warm up 3 frames, then
    // replay all active taps with DIFFERENT per-tap backpressure simultaneously.
    task automatic stress_iter_seq(
        input int w, input int h, output int errors);
        automatic int stride_bytes, slot_bytes;
        automatic int e[0:2];
        automatic int region_words;
        automatic int stall[0:2];
        errors = 0;

        // Clear any leftover wr_start/rd_start from previous phases before
        // reprogramming geometry — otherwise rd_start_global=1 triggers
        // spurious tap reads that lock the write slot the warmup needs.
        axil_m.write(MV_WR_CTRL, vdma_ctrl_word(1'b0, 1'b0, 3'd3, 8'd3));
        axil_m.write(MV_RD_CTRL, vdma_ctrl_word(1'b0, 1'b0, 3'd3, 8'd3));
        axil_m.write(MV_FRAME_CTRL, 32'h0001_0301);   // sw_clear pulse + enable
        axil_m.write(MV_FRAME_CTRL, 32'h0000_0301);
        stress_program_geometry(w, h, stride_bytes, slot_bytes);
        // Cover the 0x1000 base offset + all 4 slots so no stale data
        // from a previous iteration/phase survives in any slot.
        region_words = (32'h1000 + 4 * slot_bytes) / BYTES_PER_PIXEL;

        // warmup: 3 frames (ids 0,1,2) fill slots 0,1,2 -> taps available
        for (int f = 0; f < 3; f++) begin
            axil_m.write(MV_WR_CTRL, vdma_ctrl_word(1'b1, 1'b0, 3'd3, 8'd3));
            axil_m.write(MV_WR_CTRL, vdma_ctrl_word(1'b0, 1'b0, 3'd3, 8'd3));
            fork stress_send_frame(f, w, h); begin wait (wr_done); end join
            assert (!wr_error) else $fatal(1, "[MVDMA-STRESS] capture err frame %0d", f);
            stress_mirror_region(region_words);
        end

        // asymmetric stall: tap0 heavy (stall_mod=2), tap1 medium(4), tap2 light(8)
        stall[0] = 2; stall[1] = 4; stall[2] = 8;
        axil_m.write(MV_RD_CTRL, vdma_ctrl_word(1'b1, 1'b0, 3'd3, 8'd3));
        axil_m.write(MV_RD_CTRL, vdma_ctrl_word(1'b0, 1'b0, 3'd3, 8'd3));
        fork
            stress_recv_tap(0, 2, w, h, stall[0], e[0]);   // tap0 = newest = frame 2
            if (num_taps > 1) stress_recv_tap(1, 1, w, h, stall[1], e[1]);
            else              stress_drain_tap(1, w, h);
            if (num_taps > 2) stress_recv_tap(2, 0, w, h, stall[2], e[2]);
            else              stress_drain_tap(2, w, h);
        join
        for (int i = 0; i < num_taps; i++) errors += e[i];
    endtask

    // Receive one frame on a tap WITHOUT a predicted frame id: latch the id
    // from beat 0, then require every subsequent beat to belong to that same
    // frame (tear detection) with correct SOF/EOL. Returns the observed id.
    task automatic stress_recv_coherent(
        input int tap_idx, input int w, input int h, input int stall_mod,
        output int obs_fid, output int errors);
        automatic int received = 0;
        automatic int total    = w * h;
        logic [DATA_WIDTH-1:0] d; logic v, u, l;
        obs_fid = -1;
        errors  = 0;
        while (received < total) begin
            @(negedge clk);
            case (tap_idx)
                0: m_axis_tready[0] = ((next_rand() % stall_mod) != 0);
                1: m_axis_tready[1] = ((next_rand() % stall_mod) != 0);
                2: m_axis_tready[2] = ((next_rand() % stall_mod) != 0);
                default: ;
            endcase
            @(posedge clk);
            case (tap_idx)
                0: begin d=m_axis_tdata[0*DATA_WIDTH+:DATA_WIDTH]; v=m_axis_tvalid[0];
                         u=m_axis_tuser[0*USER_WIDTH+:USER_WIDTH]; l=m_axis_tlast[0]; end
                1: begin d=m_axis_tdata[1*DATA_WIDTH+:DATA_WIDTH]; v=m_axis_tvalid[1];
                         u=m_axis_tuser[1*USER_WIDTH+:USER_WIDTH]; l=m_axis_tlast[1]; end
                default: begin d=m_axis_tdata[2*DATA_WIDTH+:DATA_WIDTH]; v=m_axis_tvalid[2];
                         u=m_axis_tuser[2*USER_WIDTH+:USER_WIDTH]; l=m_axis_tlast[2]; end
            endcase
            if (v && m_axis_tready[tap_idx]) begin
                automatic int row = received / w;
                automatic int col = received % w;
                automatic int fid = int'(d[23:16]);
                if (received == 0) obs_fid = fid;
                if (d !== tap_pixel(obs_fid, row, col)) begin
                    $error("[MVDMA-STRESS-C] tap%0d TEAR: frame %0d expected, r=%0d c=%0d got=%h",
                           tap_idx, obs_fid, row, col, d);
                    errors++;
                end
                if (u !== ((row == 0) && (col == 0))) begin
                    $error("[MVDMA-STRESS-C] tap%0d SOF err r=%0d c=%0d", tap_idx, row, col);
                    errors++;
                end
                if (l !== (col == w - 1)) begin
                    $error("[MVDMA-STRESS-C] tap%0d EOL err r=%0d c=%0d", tap_idx, row, col);
                    errors++;
                end
                received++;
            end
        end
        @(negedge clk);
        case (tap_idx)
            0: m_axis_tready[0] = 1'b0;
            1: m_axis_tready[1] = 1'b0;
            2: m_axis_tready[2] = 1'b0;
            default: ;
        endcase
    endtask

    // One concurrent iteration (overlap model): the writer captures a fresh
    // frame WHILE all active taps replay the currently-available generations.
    // Validates slot-lock arbitration (writer must dodge read-locked slots)
    // and that each tap delivers one coherent, untorn frame with newest-first
    // ordering. region_words/geometry must already be programmed + warm.
    task automatic stress_iter_concurrent(
        input int w, input int h, input int region_words, output int errors);
        automatic int e[0:2];
        automatic int obs[0:2];
        errors = 0; obs[0]=-1; obs[1]=-1; obs[2]=-1;

        // Prevent spontaneous tap re-arm from previous iteration's drain
        axil_m.write(MV_WR_CTRL, vdma_ctrl_word(1'b0, 1'b0, 3'd3, 8'd3));
        axil_m.write(MV_RD_CTRL, vdma_ctrl_word(1'b0, 1'b0, 3'd3, 8'd3));

        // The AXI-Lite master model is a single bus driver, not re-entrant.
        // Start WR/RD sequentially here, then overlap only the AXIS data
        // movement below.  Concurrent axil_m.write() calls corrupt the
        // one-cycle start pulses and can leave S2MM never armed (tready=0).
        axil_m.write(MV_WR_CTRL, vdma_ctrl_word(1'b1, 1'b0, 3'd3, 8'd3));
        axil_m.write(MV_WR_CTRL, vdma_ctrl_word(1'b0, 1'b0, 3'd3, 8'd3));
        axil_m.write(MV_RD_CTRL, vdma_ctrl_word(1'b1, 1'b0, 3'd3, 8'd3));
        axil_m.write(MV_RD_CTRL, vdma_ctrl_word(1'b0, 1'b0, 3'd3, 8'd3));

        fork
            begin : writer  // capture one fresh frame concurrently
                fork stress_send_frame(stress_fid, w, h); begin wait (wr_done); end join
                assert (!wr_error)
                    else $fatal(1, "[MVDMA-STRESS-C] capture err fid %0d", stress_fid);
            end
            begin : readers // replay all active taps simultaneously
                fork
                    stress_recv_coherent(0, w, h, 2, obs[0], e[0]);
                    if (num_taps > 1) stress_recv_coherent(1, w, h, 4, obs[1], e[1]);
                    else              stress_drain_tap(1, w, h);
                    if (num_taps > 2) stress_recv_coherent(2, w, h, 8, obs[2], e[2]);
                    else              stress_drain_tap(2, w, h);
                join
            end
        join

        stress_mirror_region(region_words);
        stress_fid++;

        for (int i = 0; i < num_taps; i++) errors += e[i];
        // newest-first ordering: tap0 >= tap1 >= tap2 (monotone ids, no wrap)
        for (int t = 1; t < num_taps; t++)
            if (obs[t] > obs[t-1]) begin
                $error("[MVDMA-STRESS-C] tap ordering violated: tap%0d=%0d > tap%0d=%0d",
                       t, obs[t], t-1, obs[t-1]);
                errors++;
            end
    endtask

    // ── verify tap frame via memory readback (bypass playback path) ───────
    task automatic verify_slot_memory(
        input int  slot_idx,
        input int  expected_frame_id,
        input axi_slave slave,
        output int errors
    );
        int base_word = SLOT_ADDR[slot_idx] / BYTES_PER_PIXEL;
        int stride_words = STRIDE_BYTES / BYTES_PER_PIXEL;
        errors = 0;
        for (int row = 0; row < HEIGHT_LINES; row++) begin
            for (int col = 0; col < WIDTH_PIXELS; col++) begin
                logic [DATA_WIDTH-1:0] got = slave.mem[base_word + row*stride_words + col];
                logic [DATA_WIDTH-1:0] exp = tap_pixel(expected_frame_id, row, col);
                if (got !== exp) begin
                    $error("[MVDMA] slot%0d mem mismatch row=%0d col=%0d exp=%h got=%h",
                           slot_idx, row, col, exp, got);
                    errors++;
                end
            end
        end
    endtask

    // ── drain an unused hardware tap (accept all pixels, no verification) ──
    // Needed because the DUT is always elaborated with NUM_TAPS=3; all 3 taps
    // start when rd_start_global fires regardless of the runtime num_taps value.
    // An undriven tready=0 would leave tap_rd_lock asserted forever.
    task automatic drain_tap(input int tap_idx);
        automatic int n = 0;
        while (n < PIXELS_PER_FRAME) begin
            @(negedge clk);
            case (tap_idx)
                0: m_axis_tready[0] = 1;
                1: m_axis_tready[1] = 1;
                2: m_axis_tready[2] = 1;
                default: ;
            endcase
            @(posedge clk);
            case (tap_idx)
                0: if (m_axis_tvalid[0] && m_axis_tready[0]) n++;
                1: if (m_axis_tvalid[1] && m_axis_tready[1]) n++;
                2: if (m_axis_tvalid[2] && m_axis_tready[2]) n++;
                default: ;
            endcase
        end
        @(negedge clk);
        case (tap_idx)
            0: m_axis_tready[0] = 0;
            1: m_axis_tready[1] = 0;
            2: m_axis_tready[2] = 0;
            default: ;
        endcase
    endtask

    // ── full playback round: start all active taps, receive in parallel ──
    // expected_frames[tap] = the frame_id that tap should deliver.
    // Unused hardware taps (i >= n_taps) are drained to release read locks.
    task automatic playback_round(
        input int expected_frames[0:2],
        input int n_taps,
        output int total_errors
    );
        int tap_errors[0:2];
        total_errors = 0;
        // start all taps; immediately clear to prevent spontaneous re-arm after drain
        axil_m.write(MV_RD_CTRL, vdma_ctrl_word(1'b1, 1'b0, 3'd3, 8'd3));
        axil_m.write(MV_RD_CTRL, vdma_ctrl_word(1'b0, 1'b0, 3'd3, 8'd3));
        // receive/drain in parallel
        fork
            receive_and_verify_tap(0, expected_frames[0], tap_errors[0]);
            if (n_taps > 1) receive_and_verify_tap(1, expected_frames[1], tap_errors[1]);
            else            drain_tap(1);
            if (n_taps > 2) receive_and_verify_tap(2, expected_frames[2], tap_errors[2]);
            else            drain_tap(2);
        join
        for (int i = 0; i < n_taps; i++) total_errors += tap_errors[i];
    endtask

    // ── configure writer ─────────────────────────────────────────────────
    task automatic configure_writer();
        axil_m.write(MV_WR_STRIDE, STRIDE_BYTES);
        axil_m.write(MV_WR_HSIZE, HSIZE_BYTES);
        axil_m.write(MV_WR_VSIZE, HEIGHT_LINES);
    endtask

    // ── configure reader (all taps share same geometry) ──────────────────
    task automatic configure_reader();
        axil_m.write(MV_RD_STRIDE, STRIDE_BYTES);
        axil_m.write(MV_RD_HSIZE, HSIZE_BYTES);
        axil_m.write(MV_RD_VSIZE, HEIGHT_LINES);
    endtask

    // ── PNG source/sink tasks (MVDMA_PNG phase) ──────────────────────────────
    //
    // png_send_frame: drives capture_axis with squirrel pixels (RGB24 in
    //   bits [23:0] of each 64-bit beat; upper 40 bits = 0).
    //   fid is the zero-based frame index into the loaded DPI pixel buffer.
    task automatic png_send_frame(input int fid, input int w, input int h);
        for (int row = 0; row < h; row++) begin
            for (int col = 0; col < w; col++) begin
                @(negedge clk);
                capture_axis.tdata  = 64'(vf_src_get_pixel(fid * w * h + row * w + col));
                capture_axis.tuser  = USER_WIDTH'((row == 0) && (col == 0));
                capture_axis.tlast  = (col == w - 1);
                capture_axis.tvalid = 1'b1;
                @(posedge clk);
                if (!capture_axis.tready) begin
                    automatic int tmo = 0;
                    while (!capture_axis.tready) begin
                        @(posedge clk); tmo++;
                        if (tmo == 8000)
                            $fatal(1, "[MVDMA-PNG] TIMEOUT: tready stuck fid=%0d r=%0d c=%0d",
                                   fid, row, col);
                    end
                end
            end
        end
        @(negedge clk);
        capture_axis.tvalid = 1'b0;
        capture_axis.tlast  = 1'b0;
        capture_axis.tuser  = '0;
    endtask

    // png_recv_tap: receive one frame from tap `tap_idx`, push RGB24 (lower
    //   24 bits of each beat) to the per-tap DPI sink buffer.  Drives tready at
    //   full speed (no backpressure) and records throughput into the module
    //   arrays so the caller can report per-frame steady vs total efficiency:
    //     tap_cycles_total  = first tready assert → last beat  (incl. AR latency)
    //     tap_cycles_steady = first valid beat   → last beat  (in-frame delivery)
    //   steady% near 100 means the MM2S streams continuously (no inter-beat
    //   bubbles); total% lower than steady% is the fixed startup/AR latency.
    task automatic png_recv_tap(input int tap_idx, input int w, input int h);
        automatic int received     = 0;
        automatic int total        = w * h;
        automatic int idle         = 0;
        automatic int cyc          = 0;   // cycles since first tready assert
        automatic int first_valid  = -1;  // cycle index of first delivered beat
        logic [DATA_WIDTH-1:0] pkt;
        logic                  vld;
        // Idiom matches receive_tap_throughput: set tready on negedge, sample
        // on posedge, hold tready through one trailing negedge after the last
        // beat so the MM2S reaches output_complete and clears tap_rd_lock.
        while (received < total) begin
            @(negedge clk);
            case (tap_idx)
                0: m_axis_tready[0] = 1'b1;
                1: m_axis_tready[1] = 1'b1;
                2: m_axis_tready[2] = 1'b1;
                default: ;
            endcase
            @(posedge clk);
            cyc++;
            case (tap_idx)
                0: begin pkt = m_axis_tdata[0*DATA_WIDTH +: DATA_WIDTH]; vld = m_axis_tvalid[0]; end
                1: begin pkt = m_axis_tdata[1*DATA_WIDTH +: DATA_WIDTH]; vld = m_axis_tvalid[1]; end
                default: begin pkt = m_axis_tdata[2*DATA_WIDTH +: DATA_WIDTH]; vld = m_axis_tvalid[2]; end
            endcase
            if (vld && m_axis_tready[tap_idx]) begin
                if (first_valid < 0) first_valid = cyc;
                vf_sink_push_n(tap_idx, int'(pkt[23:0]));
                received++; idle = 0;
            end else begin
                idle++;
                if (idle == 20000)
                    $fatal(1, "[MVDMA-PNG] TIMEOUT: tap%0d stuck after %0d/%0d beats (tap not armed?)",
                           tap_idx, received, total);
            end
        end
        @(negedge clk);
        m_axis_tready[tap_idx] = 1'b0;
        tap_beats        [tap_idx] = received;
        tap_cycles_total [tap_idx] = cyc;
        tap_cycles_steady[tap_idx] = cyc - first_valid + 1;
    endtask

    // ── PNG round-trip phase ─────────────────────────────────────────────────
    // Opt in with either:
    //   +MVDMA_PNG_SRC_DIR=<fixtures> +MVDMA_PNG_OUT_DIR=<artifacts>
    // or legacy:
    //   +MVDMA_PNG_DIR=<dir>   (same directory for input and output)
    // Runs from a FRESH frame store (called right after configure_reader, before
    // any checkpoint capture) so no stale slot data interferes.  Streams 6 real
    // squirrel frames through capture → N-tap VDMA, writes per-tap output PNGs
    // plus inter-tap frame-diff PNGs (which visualize squirrel motion since each
    // tap lags its predecessor by one captured generation).
    task automatic run_png_phase(input string png_src_dir, input string png_out_dir);
        automatic int PNG_W      = 64;
        automatic int PNG_H      = 48;
        automatic int PNG_FRAMES = 6;
        automatic int png_hsize  = PNG_W * (DATA_WIDTH / 8);  // bytes/line
        automatic int png_stride = png_hsize;
        automatic int png_slot   = png_stride * PNG_H;
        // Words covering all 4 slots — the multi_vdma TB uses separate write
        // and read memory models, so captured data must be mirrored from the
        // S2MM slave into the three MM2S slaves before the taps can read it.
        automatic int png_region_words = (32'h1000 + 4 * png_slot) / (DATA_WIDTH / 8);

        $display("[MVDMA-PNG] ===== PNG round-trip: %0d frames %0dx%0d, taps=%0d =====",
                 PNG_FRAMES, PNG_W, PNG_H, num_taps);

        // Load squirrel frames into the DPI source buffer
        begin
            automatic string p;
            $sformat(p, "%s/frame_00.png", png_src_dir); vf_src_load(p);
            $sformat(p, "%s/frame_01.png", png_src_dir); vf_src_load_append(p);
            $sformat(p, "%s/frame_02.png", png_src_dir); vf_src_load_append(p);
            $sformat(p, "%s/frame_03.png", png_src_dir); vf_src_load_append(p);
            $sformat(p, "%s/frame_04.png", png_src_dir); vf_src_load_append(p);
            $sformat(p, "%s/frame_05.png", png_src_dir); vf_src_load_append(p);
        end
        if (vf_src_total_pixels() != PNG_FRAMES * PNG_W * PNG_H)
            $fatal(1, "[MVDMA-PNG] frame load failed: got %0d pixels, expected %0d — check MVDMA_PNG_SRC_DIR=%s",
                   vf_src_total_pixels(), PNG_FRAMES * PNG_W * PNG_H, png_src_dir);

        // Program 64x48 geometry + per-slot base addresses (store is fresh)
        axil_m.write(MV_WR_HSIZE,  png_hsize);
        axil_m.write(MV_WR_VSIZE,  PNG_H);
        axil_m.write(MV_WR_STRIDE, png_stride);
        axil_m.write(MV_RD_HSIZE,  png_hsize);
        axil_m.write(MV_RD_VSIZE,  PNG_H);
        axil_m.write(MV_RD_STRIDE, png_stride);
        axil_m.write(MV_FRAME_ADDR0, 32'h0000_1000 + 0 * png_slot);
        axil_m.write(MV_FRAME_ADDR1, 32'h0000_1000 + 1 * png_slot);
        axil_m.write(MV_FRAME_ADDR2, 32'h0000_1000 + 2 * png_slot);
        axil_m.write(MV_FRAME_ADDR3, 32'h0000_1000 + 3 * png_slot);

        // Warmup: always capture HW_TAPS+1 frames (the DUT is elaborated with
        // NUM_TAPS=3, 4 slots) so rd_taps_available asserts and ALL hardware
        // taps have valid slots — independent of the runtime num_taps we read.
        for (int f = 0; f < 4; f++) begin
            axil_m.write(MV_WR_CTRL, vdma_ctrl_word(1'b1, 1'b0, 3'd3, 8'd3));
            axil_m.write(MV_WR_CTRL, vdma_ctrl_word(1'b0, 1'b0, 3'd3, 8'd3));
            png_send_frame(f % PNG_FRAMES, PNG_W, PNG_H);
            wait (wr_done);
            stress_mirror_region(png_region_words);
            $display("[MVDMA-PNG] warmup frame %0d done", f);
        end

        // Main rounds: capture a fresh frame, THEN read all taps (sequential, to
        // avoid frame-store write/read arbitration contention).  Each round
        // advances the newest frame so tap N lags tap N-1 by one generation.
        begin
            automatic int    agg_beats   = 0;   // tap0 beats summed over rounds
            automatic int    agg_steady  = 0;   // tap0 steady cycles summed
            automatic int    agg_total   = 0;   // tap0 total cycles summed
            automatic int    motion_errs = 0;
            automatic longint BYTES_PER_FRAME = longint'(PNG_W) * PNG_H * (longint'(DATA_WIDTH)/8);

            for (int round = 0; round < PNG_FRAMES; round++) begin
                automatic int src_fid = (4 + round) % PNG_FRAMES;

                axil_m.write(MV_WR_CTRL, vdma_ctrl_word(1'b1, 1'b0, 3'd3, 8'd3));
                axil_m.write(MV_WR_CTRL, vdma_ctrl_word(1'b0, 1'b0, 3'd3, 8'd3));
                png_send_frame(src_fid, PNG_W, PNG_H);
                wait (wr_done);
                stress_mirror_region(png_region_words);

                axil_m.write(MV_RD_CTRL, vdma_ctrl_word(1'b1, 1'b0, 3'd3, 8'd3));
                axil_m.write(MV_RD_CTRL, vdma_ctrl_word(1'b0, 1'b0, 3'd3, 8'd3));
                // The DUT always elaborates NUM_TAPS=3, so rd_start fires all
                // three hardware taps.  We png_recv the active ones (num_taps)
                // and MUST drain the inactive ones — an undriven tready=0 would
                // leave their tap_rd_lock asserted forever and stall the writer.
                fork
                    png_recv_tap(0, PNG_W, PNG_H);
                    begin if (num_taps > 1) png_recv_tap(1, PNG_W, PNG_H);
                          else              stress_drain_tap(1, PNG_W, PNG_H); end
                    begin if (num_taps > 2) png_recv_tap(2, PNG_W, PNG_H);
                          else              stress_drain_tap(2, PNG_W, PNG_H); end
                join
                // Let each tap's rd_done propagate and clear tap_rd_lock before
                // the next capture.
                repeat (8) @(posedge clk);

                // ── per-frame throughput (tap0 = newest, full read) ──────────
                agg_beats  += tap_beats[0];
                agg_steady += tap_cycles_steady[0];
                agg_total  += tap_cycles_total[0];
                $display("[MVDMA-PNG] round %0d tap0: %0d beats | steady %0d cyc (%0d%%) | total %0d cyc (%0d%%) | AR-lat %0d cyc",
                         round, tap_beats[0],
                         tap_cycles_steady[0], tap_beats[0]*100/tap_cycles_steady[0],
                         tap_cycles_total[0],  tap_beats[0]*100/tap_cycles_total[0],
                         tap_cycles_total[0] - tap_cycles_steady[0]);

                begin
                    automatic string p;
                    $sformat(p, "%s/out_tap0_r%0d.png", png_out_dir, round);
                    vf_sink_write_n(0, p, PNG_W, PNG_H);
                    if (num_taps > 1) begin
                        automatic int dpx, den;
                        $sformat(p, "%s/out_tap1_r%0d.png", png_out_dir, round);
                        vf_sink_write_n(1, p, PNG_W, PNG_H);
                        $sformat(p, "%s/diff_t0_t1_r%0d.png", png_out_dir, round);
                        vf_diff_write(0, 1, p, PNG_W, PNG_H, 4);
                        // Motion check: adjacent taps must differ (proves the
                        // one-generation temporal lag actually carries motion).
                        dpx = vf_diff_count(0, 1, PNG_W, PNG_H);
                        den = vf_diff_energy_x1000(0, 1, PNG_W, PNG_H);
                        $display("[MVDMA-PNG] round %0d motion tap0-tap1: %0d/%0d px differ, energy=%0d.%03d",
                                 round, dpx, PNG_W*PNG_H, den/1000, den%1000);
                        if (dpx <= 0) begin
                            $error("[MVDMA-PNG] round %0d: tap0==tap1 (no temporal lag!)", round);
                            motion_errs++;
                        end
                    end
                    if (num_taps > 2) begin
                        $sformat(p, "%s/out_tap2_r%0d.png", png_out_dir, round);
                        vf_sink_write_n(2, p, PNG_W, PNG_H);
                        $sformat(p, "%s/diff_t1_t2_r%0d.png", png_out_dir, round);
                        vf_diff_write(1, 2, p, PNG_W, PNG_H, 4);
                    end
                end
            end

            // ── aggregate throughput report ──────────────────────────────────
            $display("[MVDMA-PNG] ---- throughput summary (tap0, %0d frames) ----", PNG_FRAMES);
            $display("[MVDMA-PNG]   total %0d beats | %0d steady cyc | %0d total cyc",
                     agg_beats, agg_steady, agg_total);
            $display("[MVDMA-PNG]   steady efficiency %0d%% (beats/cycle within the frame read)",
                     agg_beats*100/agg_steady);
            $display("[MVDMA-PNG]   total  efficiency %0d%% (incl. per-frame AR-issue latency)",
                     agg_beats*100/agg_total);
            // Projection @200 MHz AXI: bytes / (cycles / 200e6)  = bytes*200 / cyc  [MB/s]
            $display("[MVDMA-PNG]   steady BW @200MHz: %0d MB/s (%0d bytes/frame, 8B/beat)",
                     (longint'(PNG_FRAMES)*BYTES_PER_FRAME*200)/longint'(agg_steady), BYTES_PER_FRAME);
            $display("[MVDMA-PNG]   NOTE: steady<100%% means the MM2S delivers with in-frame bubbles");
            $display("[MVDMA-PNG]         (burst/line-boundary refill stalls), NOT one big frame gap.");
            $display("[MVDMA-PNG]         AR-lat≈0 here only because the behavioral slave has zero read");
            $display("[MVDMA-PNG]         latency; real DDR adds a fixed per-frame startup gap (total<steady).");
            if (motion_errs != 0)
                $fatal(1, "[MVDMA-PNG] FAIL — %0d rounds had no inter-tap motion", motion_errs);
        end

        $display("[MVDMA-PNG] PASS — %0d rounds, input PNGs from %s, output PNGs in %s",
                 PNG_FRAMES, png_src_dir, png_out_dir);
    endtask

    // ── main test sequence ────────────────────────────────────────────────
    initial begin
        automatic int total_errors = 0;
        automatic int round_errors = 0;
        automatic int exp[0:2];

        // defaults
        num_taps = 2;
        void'($value$plusargs("MULTI_VDMA_TAPS=%d", num_taps));
        if (num_taps < 1 || num_taps > 3)
            $fatal(1, "[MVDMA] MULTI_VDMA_TAPS must be 1, 2, or 3 (got %0d)", num_taps);

        capture_axis.tdata  = '0;
        capture_axis.tuser  = '0;
        capture_axis.tkeep  = '1;
        capture_axis.tvalid = 1'b0;
        capture_axis.tlast  = 1'b0;
        m_axis_tready = 3'b000;

        s2mm_mem.init();
        mm2s_mem[0].init(); mm2s_mem[1].init(); mm2s_mem[2].init();
        axil.init();

        axil_m    = new(axil);
        wr_slave  = new(s2mm_mem, "mvdma_s2mm");
        rd_slave[0] = new(mm2s_mem[0], "mvdma_mm2s0");
        rd_slave[1] = new(mm2s_mem[1], "mvdma_mm2s1");
        rd_slave[2] = new(mm2s_mem[2], "mvdma_mm2s2");

        wr_slave.reset();
        rd_slave[0].reset(); rd_slave[1].reset(); rd_slave[2].reset();
        axil_m.reset();

        for (int i = 0; i < MEM_DEPTH; i++) begin
            wr_slave.mem[i]   = '0;
            rd_slave[0].mem[i] = '0;
            rd_slave[1].mem[i] = '0;
            rd_slave[2].mem[i] = '0;
        end

        fork
            wr_slave.run();
            begin rd_slave[0].run(); end
            begin rd_slave[1].run(); end
            begin rd_slave[2].run(); end
        join_none

        wait (rst_n);
        repeat (5) @(posedge clk);

        // ── configure frame store ────────────────────────────────────
        axil_m.write(MV_FRAME_ADDR0, SLOT_ADDR[0]);
        axil_m.write(MV_FRAME_ADDR1, SLOT_ADDR[1]);
        axil_m.write(MV_FRAME_ADDR2, SLOT_ADDR[2]);
        axil_m.write(MV_FRAME_ADDR3, SLOT_ADDR[3]);
        // FRAME_CTRL[0]=enable; IRQ: wr[8], tap-0 rd[9]
        axil_m.write(MV_FRAME_CTRL, 32'h0000_0301);
        configure_writer();
        configure_reader();

        // ── PNG round-trip mode (opt-in) — run from this fresh state and
        //    finish, bypassing the synthetic checkpoints/stress entirely. ──
        begin
            automatic string png_dir;
            automatic string png_src_dir;
            automatic string png_out_dir;
            if ($value$plusargs("MVDMA_PNG_SRC_DIR=%s", png_src_dir)) begin
                if (!$value$plusargs("MVDMA_PNG_OUT_DIR=%s", png_out_dir))
                    png_out_dir = png_src_dir;
                run_png_phase(png_src_dir, png_out_dir);
                $finish;
            end else if ($value$plusargs("MVDMA_PNG_DIR=%s", png_dir)) begin
                run_png_phase(png_dir, png_dir);
                $finish;
            end
        end

        // ================================================================
        // Checkpoint 1: warmup — always capture 3 frames (= hardware
        // NUM_TAPS) so all three age slots are valid and rd_taps_available
        // (STATUS[9]) asserts regardless of the runtime num_taps value.
        // Frames 0-2 go to slots 0-2; write_slot lands on 3 after warmup.
        // ================================================================
        $display("[MVDMA] --- Checkpoint 1: warmup (3 frames, %0d active taps) ---",
                 num_taps);

        for (int f = 0; f < 3; f++) begin
            axil_m.write(MV_WR_CTRL, vdma_ctrl_word(1'b1, 1'b0, 3'd3, 8'd3));
            axil_m.write(MV_WR_CTRL, vdma_ctrl_word(1'b0, 1'b0, 3'd3, 8'd3));
            fork
                send_frame(f);
                begin wait (wr_done); end
            join
            assert (!wr_error)
                else $fatal(1, "[MVDMA] capture error on warmup frame %0d", f);
            // Mirror write slave data into all read slaves (shared logical memory)
            for (int j = 0; j < MEM_DEPTH; j++) begin
                rd_slave[0].mem[j] = wr_slave.mem[j];
                rd_slave[1].mem[j] = wr_slave.mem[j];
                rd_slave[2].mem[j] = wr_slave.mem[j];
            end
        end

        begin
            logic [31:0] status;
            axil_m.read(MV_STATUS, status);
            assert (status[9])
                else $fatal(1, "[MVDMA] rd_taps_available not set after warmup");
        end
        $display("[MVDMA] Checkpoint 1 PASS — rd_taps_available asserted");

        // ================================================================
        // Checkpoint 2: parallel playback — each active tap delivers its
        // assigned frame generation.
        // After 3 warmup captures (frames 0-2, slots 0-2):
        //   age queue: [newest=slot2=frame2, slot1=frame1, slot0=frame0]
        //   tap 0 → frame 2, tap 1 → frame 1, tap 2 → frame 0
        // Only num_taps are verified; unused hardware taps are drained.
        // ================================================================
        $display("[MVDMA] --- Checkpoint 2: parallel playback, %0d taps ---", num_taps);

        for (int t = 0; t < num_taps; t++)
            exp[t] = 2 - t;  // tap0=frame2 (newest), tap1=frame1, tap2=frame0

        playback_round(exp, num_taps, round_errors);
        total_errors += round_errors;
        assert (round_errors == 0)
            else $fatal(1, "[MVDMA] Checkpoint 2 FAIL: %0d pixel errors", round_errors);
        $display("[MVDMA] Checkpoint 2 PASS — parallel playback %0dx%0d correct",
                 num_taps, PIXELS_PER_FRAME);

        // ================================================================
        // Checkpoint 3: rolling advance — capture one more frame, verify
        // tap assignments shift: old tap-0 content appears on tap-1.
        // ================================================================
        $display("[MVDMA] --- Checkpoint 3: rolling advance ---");

        begin
            // write_slot=3 after warmup; frame 3 always goes to slot 3.
            automatic int new_frame_id = 3;
            axil_m.write(MV_WR_CTRL, vdma_ctrl_word(1'b1, 1'b0, 3'd3, 8'd3));
            axil_m.write(MV_WR_CTRL, vdma_ctrl_word(1'b0, 1'b0, 3'd3, 8'd3));
            fork
                send_frame(new_frame_id);
                begin wait (wr_done); end
            join
            assert (!wr_error) else $fatal(1, "[MVDMA] capture error on rolling frame");
            for (int j = 0; j < MEM_DEPTH; j++) begin
                rd_slave[0].mem[j] = wr_slave.mem[j];
                rd_slave[1].mem[j] = wr_slave.mem[j];
                rd_slave[2].mem[j] = wr_slave.mem[j];
            end

            // After this capture (slot 3 = frame 3, newest):
            //   age[0]=slot3=frame3, age[1]=slot2=frame2, age[2]=slot1=frame1
            for (int t = 0; t < num_taps; t++)
                exp[t] = 3 - t;  // tap0=frame3, tap1=frame2, tap2=frame1

            playback_round(exp, num_taps, round_errors);
            total_errors += round_errors;
            assert (round_errors == 0)
                else $fatal(1, "[MVDMA] Checkpoint 3 FAIL: %0d errors", round_errors);
        end
        $display("[MVDMA] Checkpoint 3 PASS — age queue shifted correctly");

        // ================================================================
        // Checkpoint 4: memory readback — direct slot verification
        // bypasses playback path; confirms S2MM wrote correct pixels.
        // ================================================================
        $display("[MVDMA] --- Checkpoint 4: memory readback ---");

        begin
            // DUT always has NUM_TAPS=3 (NS=4 slots 0-3).
            // Warmup fills slots 0-2; write_slot=3 after warmup.
            // Checkpoint 3 writes frame 3 to slot 3.
            automatic int newest_frame   = 3;
            automatic int newest_slot    = 3;
            automatic int base_word      = SLOT_ADDR[newest_slot] / BYTES_PER_PIXEL;
            automatic int stride_words   = STRIDE_BYTES / BYTES_PER_PIXEL;
            automatic int mem_errors     = 0;
            $display("[MVDMA] Checkpoint 4: expecting frame %0d in slot %0d",
                     newest_frame, newest_slot);
            for (int row = 0; row < HEIGHT_LINES; row++) begin
                for (int col = 0; col < WIDTH_PIXELS; col++) begin
                    automatic logic [DATA_WIDTH-1:0] got =
                        wr_slave.mem[base_word + row*stride_words + col];
                    automatic logic [DATA_WIDTH-1:0] exp_px =
                        tap_pixel(newest_frame, row, col);
                    if (got !== exp_px) begin
                        $error("[MVDMA] slot%0d mem mismatch row=%0d col=%0d exp=%h got=%h",
                               newest_slot, row, col, exp_px, got);
                        mem_errors++;
                    end
                end
            end
            total_errors += mem_errors;
            assert (mem_errors == 0)
                else $fatal(1, "[MVDMA] Checkpoint 4 FAIL");
        end
        $display("[MVDMA] Checkpoint 4 PASS — memory slot contents verified");

        // ================================================================
        // Checkpoint 5: throughput — replay all active taps at full rate
        // (tready held high) and report per-tap + aggregate handshake
        // efficiency (beats / cycles).
        //   total  = AR-issue/read-latency included (per-frame realized rate)
        //   steady = first-beat to last-beat (sustained MM2S delivery)
        // Sim uses a fixed-latency behavioral slave, so steady reflects the
        // engine; total reflects startup amortized over the frame size.
        // ================================================================
        $display("[MVDMA] --- Checkpoint 5: throughput (full rate, %0d taps) ---",
                 num_taps);

        begin
            automatic int tput_errors = 0;
            automatic int agg_beats   = 0;
            automatic int agg_cycles  = 0;
            // current age queue (after checkpoint 3): tap t = frame 3-t
            for (int t = 0; t < num_taps; t++)
                exp[t] = 3 - t;

            for (int i = 0; i < 3; i++) begin
                tap_beats[i] = 0; tap_cycles_total[i] = 0; tap_cycles_steady[i] = 0;
            end

            throughput_round(exp, num_taps, tput_errors);
            total_errors += tput_errors;
            assert (tput_errors == 0)
                else $fatal(1, "[MVDMA] Checkpoint 5 FAIL: %0d pixel errors", tput_errors);

            $display("[MVDMA] throughput  frame=%0d pixels  DATA_WIDTH=%0d",
                     PIXELS_PER_FRAME, DATA_WIDTH);
            for (int t = 0; t < num_taps; t++) begin
                automatic int eff_total  = tap_beats[t] * 100 / tap_cycles_total[t];
                automatic int eff_steady = tap_beats[t] * 100 / tap_cycles_steady[t];
                $display("[MVDMA]   tap%0d (frame %0d): %0d beats  total=%0d cyc (%0d%%)  steady=%0d cyc (%0d%%)",
                         t, exp[t], tap_beats[t],
                         tap_cycles_total[t], eff_total,
                         tap_cycles_steady[t], eff_steady);
                agg_beats  += tap_beats[t];
                // aggregate window = worst (longest) tap window: taps run in
                // parallel, so wall-clock cycles = max, not sum.
                if (tap_cycles_total[t] > agg_cycles)
                    agg_cycles = tap_cycles_total[t];
            end

            // Aggregate read bandwidth across all taps over the parallel window.
            // beats * (DATA_WIDTH/8) bytes delivered in agg_cycles wall-clock cyc.
            $display("[MVDMA]   aggregate: %0d beats over %0d wall-clock cyc = %0d bytes, %0d beats/100cyc",
                     agg_beats, agg_cycles, agg_beats * (DATA_WIDTH/8),
                     agg_beats * 100 / agg_cycles);
            $display("[MVDMA]   note: behavioral fixed-latency slave — steady%% reflects MM2S engine, not real DDR");
        end
        $display("[MVDMA] Checkpoint 5 PASS — throughput measured");

        // ================================================================
        // STRESS PHASE (opt-in: MVDMA_STRESS=1)
        // Part A: geometry sweep + asymmetric per-tap backpressure + seeds.
        // ================================================================
        begin
            automatic int do_stress = 0;
            automatic int seed      = 1;
            automatic int iters     = 6;
            void'($value$plusargs("MVDMA_STRESS=%d", do_stress));
            void'($value$plusargs("MVDMA_SEED=%d", seed));
            void'($value$plusargs("MVDMA_ITERS=%d", iters));

            if (do_stress != 0) begin
                automatic int s_errors = 0;
                rng_state = seed;
                $display("[MVDMA] ===== STRESS Part A: geometry + asymmetric BP (seed=%0d, iters=%0d) =====",
                         seed, iters);
                for (int it = 0; it < iters; it++) begin
                    automatic int w  = rand_range(8, 12);
                    automatic int h  = rand_range(4, 6);
                    automatic int ie = 0;
                    stress_iter_seq(w, h, ie);
                    s_errors += ie;
                    $display("[MVDMA] STRESS-A iter=%0d %0dx%0d taps=%0d -> %0d errors",
                             it, w, h, num_taps, ie);
                    assert (ie == 0)
                        else $fatal(1, "[MVDMA] STRESS-A iter %0d FAIL (%0dx%0d)", it, w, h);
                end
                total_errors += s_errors;
                $display("[MVDMA] STRESS Part A PASS — %0d iters, asymmetric BP, 0 tears", iters);

                // ── Part B: concurrent capture + playback (overlap) ──────
                begin
                    automatic int cw = 8, ch = 4;
                    automatic int stride_bytes, slot_bytes, region_words;
                    automatic int c_errors = 0;
                    // reset + program a fixed geometry, then warm 3 frames
                    axil_m.write(MV_WR_CTRL, vdma_ctrl_word(1'b0, 1'b0, 3'd3, 8'd3));
                    axil_m.write(MV_RD_CTRL, vdma_ctrl_word(1'b0, 1'b0, 3'd3, 8'd3));
                    axil_m.write(MV_FRAME_CTRL, 32'h0001_0301);
                    axil_m.write(MV_FRAME_CTRL, 32'h0000_0301);
                    stress_program_geometry(cw, ch, stride_bytes, slot_bytes);
                    region_words = (32'h1000 + 4 * slot_bytes) / BYTES_PER_PIXEL;
                    stress_fid = 0;
                    $display("[MVDMA] ===== STRESS Part B: concurrent cap+play %0dx%0d =====",
                             cw, ch);
                    for (int f = 0; f < 3; f++) begin   // warmup
                        axil_m.write(MV_WR_CTRL, vdma_ctrl_word(1'b1, 1'b0, 3'd3, 8'd3));
                        axil_m.write(MV_WR_CTRL, vdma_ctrl_word(1'b0, 1'b0, 3'd3, 8'd3));
                        fork stress_send_frame(stress_fid, cw, ch); begin wait (wr_done); end join
                        stress_mirror_region(region_words);
                        stress_fid++;
                    end
                    // concurrent rounds: writer + readers overlap
                    for (int it = 0; it < iters; it++) begin
                        automatic int ie = 0;
                        stress_iter_concurrent(cw, ch, region_words, ie);
                        c_errors += ie;
                        $display("[MVDMA] STRESS-B iter=%0d wr_fid=%0d taps=%0d -> %0d errors",
                                 it, stress_fid - 1, num_taps, ie);
                        assert (ie == 0)
                            else $fatal(1, "[MVDMA] STRESS-B iter %0d FAIL", it);
                    end
                    total_errors += c_errors;
                    $display("[MVDMA] STRESS Part B PASS — %0d concurrent rounds, 0 tears, ordering ok",
                             iters);
                end
            end
        end

        // ================================================================
        // Done
        // ================================================================
        if (total_errors == 0)
            $display("[MVDMA] PASS — all checkpoints passed, NUM_TAPS=%0d, %0dx%0d",
                     num_taps, WIDTH_PIXELS, HEIGHT_LINES);
        else
            $fatal(1, "[MVDMA] FAIL — %0d total errors across all checkpoints",
                   total_errors);

        $finish;
    end

endmodule : test_multi_vdma

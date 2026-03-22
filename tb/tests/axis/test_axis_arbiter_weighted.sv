`timescale 1ns/1ps

// -------------------------------------------------
// test_axis_arbiter_weighted
//
// Weighted packet-aware AXI-Stream arbiter test.
//
// The arbiter is configured with source weights 4:2:1:1.
// All sources offer equal-length packets, so the observed
// grant ratio should follow the configured weighted round.
// -------------------------------------------------
module test_axis_arbiter_weighted #(parameter int DATA_WIDTH = 8,
                                    parameter int USER_WIDTH = 1)
                                   (input logic clk,
                                    input logic rst_n);
    import axi_pkg::*;

    localparam int NUM_SRCS = 4;
    localparam int WEIGHT_W = 4;
    localparam int PKT_BEATS = 3;
    localparam int W0 = 4;
    localparam int W1 = 2;
    localparam int W2 = 1;
    localparam int W3 = 1;
    localparam int TOTAL_PKTS = W0 + W1 + W2 + W3;
    localparam int TOTAL_BEATS = TOTAL_PKTS * PKT_BEATS;
    localparam logic [NUM_SRCS*WEIGHT_W-1:0] WEIGHTS = {4'd1, 4'd1, 4'd2, 4'd4};

    int src_bp_en;
    int sink_bp_en;

    initial begin
        src_bp_en  = 0;
        sink_bp_en = 0;
        void'($value$plusargs("SRC_BP=%d",  src_bp_en));
        void'($value$plusargs("SINK_BP=%d", sink_bp_en));
        $display("[WARB] SRC_BP=%0d SINK_BP=%0d", src_bp_en, sink_bp_en);
        $display("[WARB] Weights: src0=%0d src1=%0d src2=%0d src3=%0d",
                 W0, W1, W2, W3);
    end

    axis_if #(.DATA_WIDTH(DATA_WIDTH), .USER_WIDTH(USER_WIDTH)) s_t [NUM_SRCS](clk, rst_n);
    axis_if #(.DATA_WIDTH(DATA_WIDTH), .USER_WIDTH(USER_WIDTH)) m_t (clk, rst_n);
    axis_if #(.DATA_WIDTH(DATA_WIDTH), .USER_WIDTH(USER_WIDTH)) m_s (clk, rst_n);

    sample_axis_if #(.DATA_WIDTH(DATA_WIDTH), .USER_WIDTH(USER_WIDTH))
        smp_m (.axis_if_t(m_t), .axis_if_s(m_s));

    logic [NUM_SRCS-1:0][DATA_WIDTH-1:0] in_tdata_w;
    logic [NUM_SRCS-1:0][USER_WIDTH-1:0] in_tuser_w;
    logic [NUM_SRCS-1:0]                 in_tvalid_w;
    logic [NUM_SRCS-1:0]                 in_tlast_w;
    logic [NUM_SRCS-1:0]                 in_tready_w;

    logic [DATA_WIDTH-1:0] arb_tdata_w;
    logic [USER_WIDTH-1:0] arb_tuser_w;
    logic                  arb_tvalid_w;
    logic                  arb_tlast_w;
    logic                  arb_tready_w;

    for (genvar i = 0; i < NUM_SRCS; i++) begin : gen_in_regs
        snix_axis_register #(.DATA_WIDTH(DATA_WIDTH), .USER_WIDTH(USER_WIDTH))
            u_in_reg (
                .clk          (clk),
                .rst_n        (rst_n),
                .s_axis_tdata (s_t[i].tdata),
                .s_axis_tuser (s_t[i].tuser),
                .s_axis_tlast (s_t[i].tlast),
                .s_axis_tvalid(s_t[i].tvalid),
                .s_axis_tready(s_t[i].tready),
                .m_axis_tdata (in_tdata_w[i]),
                .m_axis_tuser (in_tuser_w[i]),
                .m_axis_tlast (in_tlast_w[i]),
                .m_axis_tvalid(in_tvalid_w[i]),
                .m_axis_tready(in_tready_w[i])
            );
    end

    snix_axis_arbiter #(.NUM_SRCS  (NUM_SRCS),
                        .DATA_WIDTH(DATA_WIDTH),
                        .USER_WIDTH(USER_WIDTH),
                        .WEIGHT_W  (WEIGHT_W),
                        .WEIGHTS   (WEIGHTS))
        u_dut (
            .clk          (clk),
            .rst_n        (rst_n),
            .s_axis_tdata (in_tdata_w),
            .s_axis_tuser (in_tuser_w),
            .s_axis_tvalid(in_tvalid_w),
            .s_axis_tlast (in_tlast_w),
            .s_axis_tready(in_tready_w),
            .m_axis_tdata (arb_tdata_w),
            .m_axis_tuser (arb_tuser_w),
            .m_axis_tvalid(arb_tvalid_w),
            .m_axis_tlast (arb_tlast_w),
            .m_axis_tready(arb_tready_w)
        );

    snix_axis_register #(.DATA_WIDTH(DATA_WIDTH), .USER_WIDTH(USER_WIDTH))
        u_out_reg (
            .clk          (clk),
            .rst_n        (rst_n),
            .s_axis_tdata (arb_tdata_w),
            .s_axis_tuser (arb_tuser_w),
            .s_axis_tlast (arb_tlast_w),
            .s_axis_tvalid(arb_tvalid_w),
            .s_axis_tready(arb_tready_w),
            .m_axis_tdata (m_t.tdata),
            .m_axis_tuser (m_t.tuser),
            .m_axis_tlast (m_t.tlast),
            .m_axis_tvalid(m_t.tvalid),
            .m_axis_tready(m_t.tready)
        );

    for (genvar i = 0; i < NUM_SRCS; i++) begin : gen_slv_chk
        localparam string LABEL = (i == 0) ? "WARB_SLV0" :
                                  (i == 1) ? "WARB_SLV1" :
                                  (i == 2) ? "WARB_SLV2" : "WARB_SLV3";
        axis_checker #(.DATA_WIDTH(DATA_WIDTH), .USER_WIDTH(USER_WIDTH),
                       .LABEL(LABEL))
            u_chk_s(.clk(clk), .rst_n(rst_n),
                    .tdata(s_t[i].tdata), .tuser(s_t[i].tuser),
                    .tvalid(s_t[i].tvalid), .tready(s_t[i].tready),
                    .tlast(s_t[i].tlast));
    end

    axis_checker #(.DATA_WIDTH(DATA_WIDTH), .USER_WIDTH(USER_WIDTH),
                   .LABEL("WARB_MST"))
        u_chk_m (.clk(clk), .rst_n(rst_n),
                 .tdata(m_t.tdata), .tuser(m_t.tuser),
                 .tvalid(m_t.tvalid), .tready(m_t.tready), .tlast(m_t.tlast));

    axis_source #(DATA_WIDTH, USER_WIDTH) src_bfm [NUM_SRCS];
    axis_sink                             sink_bfm;

    int beats_recv;
    int pkts_recv;
    int src_grants  [NUM_SRCS];
    int src_beats   [NUM_SRCS];
    int src_packets [NUM_SRCS];
    int last_sel_mon;
    int curr_sel_mon;
    int beat_sel_mon;

    initial begin
        beats_recv = 0;
        pkts_recv  = 0;
        for (int i = 0; i < NUM_SRCS; i++) begin
            src_grants[i]  = 0;
            src_beats[i]   = 0;
            src_packets[i] = 0;
        end
        last_sel_mon = -1;
        curr_sel_mon = -1;
        beat_sel_mon = -1;
        forever begin
            @(posedge clk);
            if (m_t.tvalid && m_t.tready) begin
                beats_recv++;
                if (m_t.tlast) pkts_recv++;
            end
        end
    end

    initial begin : weighted_monitor
        forever begin
            @(posedge clk);
            if (!rst_n) begin
                last_sel_mon = -1;
                curr_sel_mon = -1;
            end else begin
                curr_sel_mon = u_dut.locked ? int'(u_dut.sel) :
                                             (u_dut.arb_valid ? int'(u_dut.arb_sel) : -1);
                beat_sel_mon = int'(u_dut.eff_sel);

                if (curr_sel_mon != last_sel_mon) begin
                    if (curr_sel_mon >= 0) begin
                        src_grants[curr_sel_mon]++;
                        if (last_sel_mon >= 0) begin
                            $display("[WARB_MON] grant %0d -> %0d (locked=%0b rr_ptr=%0d c0=%0d c1=%0d c2=%0d c3=%0d)",
                                     last_sel_mon, curr_sel_mon, u_dut.locked, u_dut.rr_ptr,
                                     u_dut.credit[0], u_dut.credit[1], u_dut.credit[2], u_dut.credit[3]);
                        end else begin
                            $display("[WARB_MON] grant -> %0d (locked=%0b rr_ptr=%0d c0=%0d c1=%0d c2=%0d c3=%0d)",
                                     curr_sel_mon, u_dut.locked, u_dut.rr_ptr,
                                     u_dut.credit[0], u_dut.credit[1], u_dut.credit[2], u_dut.credit[3]);
                        end
                    end else if (last_sel_mon >= 0) begin
                        $display("[WARB_MON] grant %0d -> idle (rr_ptr=%0d c0=%0d c1=%0d c2=%0d c3=%0d)",
                                 last_sel_mon, u_dut.rr_ptr,
                                 u_dut.credit[0], u_dut.credit[1], u_dut.credit[2], u_dut.credit[3]);
                    end
                    last_sel_mon = curr_sel_mon;
                end

                if (m_t.tvalid && m_t.tready && beat_sel_mon >= 0) begin
                    src_beats[beat_sel_mon]++;
                    if (m_t.tlast) src_packets[beat_sel_mon]++;
                end
            end
        end
    end

    initial begin
        s_t[0].init();
        s_t[1].init();
        s_t[2].init();
        s_t[3].init();
        src_bfm[0] = new(s_t[0]);
        src_bfm[1] = new(s_t[1]);
        src_bfm[2] = new(s_t[2]);
        src_bfm[3] = new(s_t[3]);
        src_bfm[0].backpressure = src_bp_en;
        src_bfm[1].backpressure = src_bp_en;
        src_bfm[2].backpressure = src_bp_en;
        src_bfm[3].backpressure = src_bp_en;
        m_t.init();
        sink_bfm = new(m_t);
        sink_bfm.backpressure = sink_bp_en;

        @(negedge rst_n);
        @(posedge rst_n);
        repeat (2) @(posedge clk);

        $display("[WARB] ---- Weighted concurrent phase ----");
        fork
            begin repeat(W0) src_bfm[0].send_packet(PKT_BEATS, 1); end
            begin repeat(W1) src_bfm[1].send_packet(PKT_BEATS, 1); end
            begin repeat(W2) src_bfm[2].send_packet(PKT_BEATS, 1); end
            begin repeat(W3) src_bfm[3].send_packet(PKT_BEATS, 1); end
            begin repeat(TOTAL_PKTS) sink_bfm.recv_packet(); end
        join

        $display("[WARB] Done: %0d beats / %0d pkts received",
                 beats_recv, pkts_recv);
        for (int i = 0; i < NUM_SRCS; i++) begin
            $display("[WARB] SRC%0d grants=%0d beats=%0d pkts=%0d",
                     i, src_grants[i], src_beats[i], src_packets[i]);
        end

        repeat (4) @(posedge clk);

        if (beats_recv !== TOTAL_BEATS)
            $error("[WARB] FAIL: expected %0d beats, got %0d", TOTAL_BEATS, beats_recv);
        else if (pkts_recv !== TOTAL_PKTS)
            $error("[WARB] FAIL: expected %0d packets, got %0d", TOTAL_PKTS, pkts_recv);
        else if (src_grants[0] !== W0)
            $error("[WARB] FAIL: src0 grants expected %0d, got %0d", W0, src_grants[0]);
        else if (src_grants[1] !== W1)
            $error("[WARB] FAIL: src1 grants expected %0d, got %0d", W1, src_grants[1]);
        else if (src_grants[2] !== W2)
            $error("[WARB] FAIL: src2 grants expected %0d, got %0d", W2, src_grants[2]);
        else if (src_grants[3] !== W3)
            $error("[WARB] FAIL: src3 grants expected %0d, got %0d", W3, src_grants[3]);
        else if (src_packets[0] !== W0 || src_packets[1] !== W1 ||
                 src_packets[2] !== W2 || src_packets[3] !== W3)
            $error("[WARB] FAIL: packet counts do not match weighted grants");
        else
            $display("[WARB] PASS: weighted grants matched %0d:%0d:%0d:%0d",
                     W0, W1, W2, W3);

        repeat (5) @(posedge clk);
        $finish;
    end

    initial begin
        #2_000_000;
        $fatal("test_axis_arbiter_weighted: simulation timeout");
    end

endmodule: test_axis_arbiter_weighted

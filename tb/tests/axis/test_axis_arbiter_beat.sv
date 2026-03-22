`timescale 1ns/1ps

// -------------------------------------------------
// test_axis_arbiter_beat
//
// Beat-based AXI-Stream arbiter test.
//
// The arbiter releases the grant after every accepted beat.
// With four always-valid sources sending 3-beat packets, the
// accepted source sequence should rotate 0,1,2,3 repeatedly.
// -------------------------------------------------
module test_axis_arbiter_beat #(parameter int DATA_WIDTH = 8,
                                parameter int USER_WIDTH = 1)
                               (input logic clk,
                                input logic rst_n);
    import axi_pkg::*;

    localparam int NUM_SRCS = 4;
    localparam int PKT_BEATS = 3;
    localparam int TOTAL_BEATS = NUM_SRCS * PKT_BEATS;
    localparam int TOTAL_PKTS  = NUM_SRCS;

    int src_bp_en;
    int sink_bp_en;

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

    axis_source #(DATA_WIDTH, USER_WIDTH) src_bfm [NUM_SRCS];

    int beats_recv;
    int tlast_recv;
    int src_beats[NUM_SRCS];
    int beat_sel_mon;
    int beat_sel_pre;
    int sel_hist[TOTAL_BEATS];

    initial begin
        src_bp_en  = 0;
        sink_bp_en = 0;
        void'($value$plusargs("SRC_BP=%d",  src_bp_en));
        void'($value$plusargs("SINK_BP=%d", sink_bp_en));
        $display("[BARB] SRC_BP=%0d SINK_BP=%0d", src_bp_en, sink_bp_en);
    end

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

    snix_axis_arbiter #(.NUM_SRCS   (NUM_SRCS),
                        .DATA_WIDTH (DATA_WIDTH),
                        .USER_WIDTH (USER_WIDTH),
                        .HOLD_PACKET(1'b0))
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
        localparam string LABEL = (i == 0) ? "BARB_SLV0" :
                                  (i == 1) ? "BARB_SLV1" :
                                  (i == 2) ? "BARB_SLV2" : "BARB_SLV3";
        axis_checker #(.DATA_WIDTH(DATA_WIDTH), .USER_WIDTH(USER_WIDTH), .LABEL(LABEL))
            u_chk_s(.clk(clk), .rst_n(rst_n),
                    .tdata(s_t[i].tdata), .tuser(s_t[i].tuser),
                    .tvalid(s_t[i].tvalid), .tready(s_t[i].tready),
                    .tlast(s_t[i].tlast));
    end

    axis_checker #(.DATA_WIDTH(DATA_WIDTH), .USER_WIDTH(USER_WIDTH), .LABEL("BARB_MST"))
        u_chk_m (.clk(clk), .rst_n(rst_n),
                 .tdata(m_t.tdata), .tuser(m_t.tuser),
                 .tvalid(m_t.tvalid), .tready(m_t.tready), .tlast(m_t.tlast));

    initial begin
        beats_recv = 0;
        tlast_recv = 0;
        for (int i = 0; i < NUM_SRCS; i++) begin
            src_beats[i] = 0;
        end
        for (int i = 0; i < TOTAL_BEATS; i++) begin
            sel_hist[i] = -1;
        end
        beat_sel_mon = -1;
        beat_sel_pre = -1;

        forever begin
            @(negedge clk);
            if (!rst_n)
                beat_sel_pre = -1;
            else
                beat_sel_pre = int'(u_dut.eff_sel);

            @(posedge clk);
            if (!rst_n) begin
                beat_sel_mon = -1;
            end else begin
                beat_sel_mon = beat_sel_pre;
                if (arb_tvalid_w && arb_tready_w) begin
                    $display("[BARB] beat%0d sel=%0d tdata=%0d tlast=%0b",
                             beats_recv, beat_sel_mon, arb_tdata_w, arb_tlast_w);
                    sel_hist[beats_recv] = beat_sel_mon;
                    beats_recv++;
                    src_beats[beat_sel_mon]++;
                    if (arb_tlast_w) tlast_recv++;
                end
            end
        end
    end

    initial begin : sink_ready_driver
        bit ready_now;
        m_t.init();
        forever begin
            ready_now = !sink_bp_en ? 1'b1
                                    : ($urandom_range(0,99) < 80);
            @(negedge clk);
            m_t.tready = ready_now;
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

        @(negedge rst_n);
        @(posedge rst_n);
        repeat (2) @(posedge clk);

        $display("[BARB] ---- Beat mode concurrent phase ----");
        fork
            src_bfm[0].send_packet(PKT_BEATS, 1);
            src_bfm[1].send_packet(PKT_BEATS, 1);
            src_bfm[2].send_packet(PKT_BEATS, 1);
            src_bfm[3].send_packet(PKT_BEATS, 1);
        join

        wait (beats_recv == TOTAL_BEATS);
        repeat (4) @(posedge clk);

        $display("[BARB] Done: beats=%0d tlasts=%0d src0=%0d src1=%0d src2=%0d src3=%0d",
                 beats_recv, tlast_recv, src_beats[0], src_beats[1], src_beats[2], src_beats[3]);

        if (beats_recv !== TOTAL_BEATS)
            $error("[BARB] FAIL: expected %0d beats, got %0d", TOTAL_BEATS, beats_recv);
        else if (tlast_recv !== TOTAL_PKTS)
            $error("[BARB] FAIL: expected %0d TLASTs, got %0d", TOTAL_PKTS, tlast_recv);
        else if (src_beats[0] !== PKT_BEATS || src_beats[1] !== PKT_BEATS ||
                 src_beats[2] !== PKT_BEATS || src_beats[3] !== PKT_BEATS)
            $error("[BARB] FAIL: per-source accepted beat counts are not balanced");
        else if (!src_bp_en) begin : seq_check
            bit seq_ok;
            seq_ok = 1'b1;
            for (int i = 0; i < TOTAL_BEATS; i++) begin
                if (sel_hist[i] !== (i % NUM_SRCS)) begin
                    $error("[BARB] FAIL: expected beat %0d from src%0d, got src%0d",
                           i, i % NUM_SRCS, sel_hist[i]);
                    seq_ok = 1'b0;
                end
            end
            if (seq_ok)
                $display("[BARB] PASS: beat arbitration rotated correctly");
        end
        else
            $display("[BARB] PASS: beat arbitration completed with source backpressure enabled");

        repeat (5) @(posedge clk);
        $finish;
    end

    initial begin
        #2_000_000;
        $fatal("test_axis_arbiter_beat: simulation timeout");
    end

endmodule: test_axis_arbiter_beat

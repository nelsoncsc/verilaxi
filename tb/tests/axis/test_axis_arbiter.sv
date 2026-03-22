`timescale 1ns/1ps

// -------------------------------------------------
// test_axis_arbiter
//
// 4-source AXI-Stream round-robin arbiter test.
//
// Architecture note:
//   Each source BFM drives a real AXI-Stream register slice
//   before the arbiter. This keeps the BFM/DUT handshake
//   aligned while still avoiding direct comb-to-interface
//   paths that can upset Verilator convergence. The arbiter
//   output is likewise pipelined through a register slice
//   before the sink BFM.
// -------------------------------------------------
module test_axis_arbiter #(parameter int DATA_WIDTH = 8,
                           parameter int USER_WIDTH = 1)
                          (input logic clk,
                           input logic rst_n);
    import axi_pkg::*;

    localparam int NUM_SRCS = 4;

    int src_bp_en;
    int sink_bp_en;

    initial begin
        src_bp_en  = 0;
        sink_bp_en = 0;
        void'($value$plusargs("SRC_BP=%d",  src_bp_en));
        void'($value$plusargs("SINK_BP=%d", sink_bp_en));
        $display("[ARB] SRC_BP=%0d SINK_BP=%0d", src_bp_en, sink_bp_en);
    end

    // -------------------------------------------------------
    // BFM-facing AXIS interfaces
    // -------------------------------------------------------
    axis_if #(.DATA_WIDTH(DATA_WIDTH), .USER_WIDTH(USER_WIDTH)) s_t [NUM_SRCS](clk, rst_n);
    axis_if #(.DATA_WIDTH(DATA_WIDTH), .USER_WIDTH(USER_WIDTH)) m_t (clk, rst_n);
    axis_if #(.DATA_WIDTH(DATA_WIDTH), .USER_WIDTH(USER_WIDTH)) m_s (clk, rst_n);

    // Sampled sink-side copy for cleaner waveform inspection only.
    sample_axis_if #(.DATA_WIDTH(DATA_WIDTH), .USER_WIDTH(USER_WIDTH))
        smp_m (.axis_if_t(m_t), .axis_if_s(m_s));

    // -------------------------------------------------------
    // Plain logic wires between input register slices and arbiter
    // -------------------------------------------------------
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

    // -------------------------------------------------------
    // Input register slices: one per source
    // -------------------------------------------------------
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

    // -------------------------------------------------------
    // DUT
    // -------------------------------------------------------
    snix_axis_arbiter #(.NUM_SRCS  (NUM_SRCS),
                        .DATA_WIDTH(DATA_WIDTH),
                        .USER_WIDTH(USER_WIDTH))
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

    // -------------------------------------------------------
    // Output register slice
    // -------------------------------------------------------
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

    // -------------------------------------------------------
    // Protocol checkers
    // -------------------------------------------------------
    for (genvar i = 0; i < NUM_SRCS; i++) begin : gen_slv_chk
        localparam string LABEL = (i == 0) ? "ARB_SLV0" :
                                  (i == 1) ? "ARB_SLV1" :
                                  (i == 2) ? "ARB_SLV2" : "ARB_SLV3";
        axis_checker #(.DATA_WIDTH(DATA_WIDTH), .USER_WIDTH(USER_WIDTH),
                       .LABEL(LABEL))
            u_chk_s(.clk(clk), .rst_n(rst_n),
                    .tdata(s_t[i].tdata), .tuser(s_t[i].tuser),
                    .tvalid(s_t[i].tvalid), .tready(s_t[i].tready),
                    .tlast(s_t[i].tlast));
    end

    axis_checker #(.DATA_WIDTH(DATA_WIDTH), .USER_WIDTH(USER_WIDTH),
                   .LABEL("ARB_MST"))
        u_chk_m (.clk(clk), .rst_n(rst_n),
                 .tdata(m_t.tdata), .tuser(m_t.tuser),
                 .tvalid(m_t.tvalid), .tready(m_t.tready), .tlast(m_t.tlast));

    // -------------------------------------------------------
    // BFMs
    // -------------------------------------------------------
    axis_source #(DATA_WIDTH, USER_WIDTH) src_bfm [NUM_SRCS];
    axis_sink                             sink_bfm;

    // -------------------------------------------------------
    // Output scoreboard
    // -------------------------------------------------------
    int beats_recv;
    int pkts_recv;
    int src_grants   [NUM_SRCS];
    int src_beats    [NUM_SRCS];
    int src_packets  [NUM_SRCS];
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

    initial begin : arbiter_monitor
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
                            $display("[ARB_MON] grant %0d -> %0d (locked=%0b rr_ptr=%0d)",
                                     last_sel_mon, curr_sel_mon, u_dut.locked, u_dut.rr_ptr);
                        end else begin
                            $display("[ARB_MON] grant -> %0d (locked=%0b rr_ptr=%0d)",
                                     curr_sel_mon, u_dut.locked, u_dut.rr_ptr);
                        end
                    end else if (last_sel_mon >= 0) begin
                        $display("[ARB_MON] grant %0d -> idle (rr_ptr=%0d)",
                                 last_sel_mon, u_dut.rr_ptr);
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

    // -------------------------------------------------------
    // Test sequence
    // -------------------------------------------------------
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

        $display("[ARB] ---- Phase 1: Sequential ----");
        fork src_bfm[0].send_packet(4, 2); sink_bfm.recv_packet(); join
        fork src_bfm[1].send_packet(5, 2); sink_bfm.recv_packet(); join
        fork src_bfm[2].send_packet(3, 2); sink_bfm.recv_packet(); join
        fork src_bfm[3].send_packet(6, 2); sink_bfm.recv_packet(); join

        $display("[ARB] Phase 1 done: %0d beats / %0d pkts received",
                 beats_recv, pkts_recv);

        $display("[ARB] ---- Phase 2: Concurrent ----");
        fork
            begin repeat(3) src_bfm[0].send_packet(4, 1); end
            begin repeat(3) src_bfm[1].send_packet(5, 1); end
            begin repeat(3) src_bfm[2].send_packet(3, 1); end
            begin repeat(3) src_bfm[3].send_packet(6, 1); end
            begin repeat(12) sink_bfm.recv_packet();    end
        join

        $display("[ARB] Phase 2 done: %0d beats / %0d pkts received",
                 beats_recv, pkts_recv);

        for (int i = 0; i < NUM_SRCS; i++) begin
            $display("[ARB] SRC%0d grants=%0d beats=%0d pkts=%0d",
                     i, src_grants[i], src_beats[i], src_packets[i]);
        end

        repeat (4) @(posedge clk);

        if (beats_recv !== 72)
            $error("[ARB] FAIL: expected 72 beats, got %0d", beats_recv);
        else if (pkts_recv !== 16)
            $error("[ARB] FAIL: expected 16 packets, got %0d", pkts_recv);
        else
            $display("[ARB] PASS: all 72 beats / 16 packets received correctly");

        repeat (5) @(posedge clk);
        $finish;
    end

    initial begin
        #2_000_000;
        $fatal("test_axis_arbiter: simulation timeout");
    end

endmodule: test_axis_arbiter

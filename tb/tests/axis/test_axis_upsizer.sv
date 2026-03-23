`timescale 1ns/1ps

// -------------------------------------------------
// test_axis_upsizer
//
// Exercises snix_axis_upsizer with IN_DATA_WIDTH=8 and OUT_DATA_WIDTH=32
// (RATIO = 4).  All input TKEEP lanes are driven all-ones so that TKEEP
// on the output TLAST beat reflects how many beats filled the last word.
//
// Phase 1 — sequential packets of 1, 2, 3, 4 input beats.
//   Each packet produces exactly one output beat.
//   TLAST TKEEP expected: 4'b0001, 4'b0011, 4'b0111, 4'b1111.
//   Total: 4 output beats, 4 output packets.
//
// Phase 2 — same four packets again, with backpressure active on both
//   source and sink when the relevant plusarg is set.
//   Additional: 4 output beats, 4 output packets.
//
// Grand total: 8 output beats, 8 output packets.
// -------------------------------------------------
module test_axis_upsizer #(
    parameter int IN_DATA_WIDTH  = 8,
    parameter int OUT_DATA_WIDTH = 32
) (
    input logic clk,
    input logic rst_n
);
    import axi_pkg::*;

    localparam int RATIO      = OUT_DATA_WIDTH / IN_DATA_WIDTH;
    localparam int IN_KEEP_W  = IN_DATA_WIDTH  / 8;
    localparam int OUT_KEEP_W = OUT_DATA_WIDTH / 8;

    int src_bp_en;
    int sink_bp_en;

    initial begin
        src_bp_en  = 0;
        sink_bp_en = 0;
        void'($value$plusargs("SRC_BP=%d",  src_bp_en));
        void'($value$plusargs("SINK_BP=%d", sink_bp_en));
        $display("[UPS] SRC_BP=%0d SINK_BP=%0d RATIO=%0d", src_bp_en, sink_bp_en, RATIO);
    end

    // -------------------------------------------------------
    // Source interface (narrow side, DATA_WIDTH=IN_DATA_WIDTH)
    // -------------------------------------------------------
    axis_if #(.DATA_WIDTH(IN_DATA_WIDTH), .USER_WIDTH(1)) s_t (clk, rst_n);

    // -------------------------------------------------------
    // Wires between register slice and DUT (narrow side)
    // -------------------------------------------------------
    logic [IN_DATA_WIDTH-1:0]  dut_s_tdata;
    logic [IN_KEEP_W-1:0]      dut_s_tkeep;  // tied to all-ones; reg slice has no tkeep port
    logic                      dut_s_tvalid;
    logic                      dut_s_tready;
    logic                      dut_s_tlast;
    logic [0:0]                dut_s_tuser_unused; // absorbs register-slice tuser output

    // -------------------------------------------------------
    // DUT output wires (wide side)
    // -------------------------------------------------------
    logic [OUT_DATA_WIDTH-1:0]  m_tdata_w;
    logic [OUT_KEEP_W-1:0]      m_tkeep_w;
    logic                       m_tvalid_w;
    logic                       m_tready_w;
    logic                       m_tlast_w;

    // -------------------------------------------------------
    // Input register slice (narrow side, no tkeep port)
    // -------------------------------------------------------
    snix_axis_register #(.DATA_WIDTH(IN_DATA_WIDTH), .USER_WIDTH(1)) u_in_reg (
        .clk          (clk),
        .rst_n        (rst_n),
        .s_axis_tdata (s_t.tdata),
        .s_axis_tuser (s_t.tuser),
        .s_axis_tlast (s_t.tlast),
        .s_axis_tvalid(s_t.tvalid),
        .s_axis_tready(s_t.tready),
        .m_axis_tdata (dut_s_tdata),
        .m_axis_tuser (dut_s_tuser_unused),
        .m_axis_tlast (dut_s_tlast),
        .m_axis_tvalid(dut_s_tvalid),
        .m_axis_tready(dut_s_tready)
    );

    // TKEEP: all input bytes are always valid in this test.
    assign dut_s_tkeep = {IN_KEEP_W{1'b1}};

    // -------------------------------------------------------
    // DUT
    // -------------------------------------------------------
    snix_axis_upsizer #(
        .IN_DATA_WIDTH (IN_DATA_WIDTH),
        .OUT_DATA_WIDTH(OUT_DATA_WIDTH)
    ) u_dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .s_axis_tdata (dut_s_tdata),
        .s_axis_tkeep (dut_s_tkeep),
        .s_axis_tvalid(dut_s_tvalid),
        .s_axis_tready(dut_s_tready),
        .s_axis_tlast (dut_s_tlast),
        .m_axis_tdata (m_tdata_w),
        .m_axis_tkeep (m_tkeep_w),
        .m_axis_tvalid(m_tvalid_w),
        .m_axis_tready(m_tready_w),
        .m_axis_tlast (m_tlast_w)
    );

    // -------------------------------------------------------
    // Protocol checkers
    // -------------------------------------------------------
    axis_checker #(.DATA_WIDTH(IN_DATA_WIDTH), .USER_WIDTH(1), .LABEL("UPS_SLV"))
        u_chk_s (.clk(clk), .rst_n(rst_n),
                 .tdata(s_t.tdata), .tuser(s_t.tuser),
                 .tvalid(s_t.tvalid), .tready(s_t.tready), .tlast(s_t.tlast));

    axis_checker #(.DATA_WIDTH(OUT_DATA_WIDTH), .USER_WIDTH(1), .LABEL("UPS_MST"))
        u_chk_m (.clk(clk), .rst_n(rst_n),
                 .tdata(m_tdata_w), .tuser(1'b0),
                 .tvalid(m_tvalid_w), .tready(m_tready_w), .tlast(m_tlast_w));

    // -------------------------------------------------------
    // Scoreboard
    // -------------------------------------------------------
    int beats_recv;
    int pkts_recv;
    int exp_beats;
    int exp_pkts;
    int exp_byte_idx;
    int exp_pkt_idx;
    int next_byte_val;
    byte unsigned exp_bytes[$];
    int exp_pkt_end_bytes[$];

    function automatic logic [OUT_KEEP_W-1:0] keep_mask(input int valid_bytes);
        logic [OUT_KEEP_W-1:0] mask;
        mask = '0;
        for (int i = 0; i < OUT_KEEP_W; i++) begin
            if (i < valid_bytes)
                mask[i] = 1'b1;
        end
        return mask;
    endfunction

    task automatic push_expected_pkt(input int num_beats);
        int beat;
        int pkt_start;
        pkt_start = exp_bytes.size();
        for (beat = 0; beat < num_beats; beat++)
            exp_bytes.push_back(byte'(next_byte_val + beat));
        exp_pkt_end_bytes.push_back(exp_bytes.size());
        exp_pkts++;
        exp_beats += (exp_bytes.size() - pkt_start + OUT_KEEP_W - 1) / OUT_KEEP_W;
        next_byte_val += num_beats;
    endtask

    task automatic send_pkt(input int num_beats, input int idle_cycles = 1);
        int beat;
        logic [IN_DATA_WIDTH-1:0] dat;
        int pkt_base;

        @(negedge clk);
        s_t.tvalid = 1'b0;
        s_t.tlast  = 1'b0;
        s_t.tuser  = '0;

        pkt_base = next_byte_val;
        push_expected_pkt(num_beats);

        beat = 0;
        while (beat < num_beats) begin
            if (!s_t.tvalid) begin
                bit launch;
                launch = !src_bp_en ? 1'b1 : ($urandom_range(0, 99) < 80);
                @(negedge clk);
                if (launch) begin
                    dat        = byte'(pkt_base + beat);
                    s_t.tdata  = dat;
                    s_t.tlast  = (beat == num_beats - 1);
                    s_t.tvalid = 1'b1;
                end
            end
            @(posedge clk);
            if (s_t.tvalid && s_t.tready) begin
                $display("[UPS][IN ] beat %0d/%0d tdata=0x%h tkeep=%01b tlast=%0b",
                         beat, num_beats - 1, s_t.tdata, 1'b1, s_t.tlast);
                beat++;
                @(negedge clk);
                s_t.tvalid = 1'b0;
                s_t.tlast  = 1'b0;
            end
        end

        repeat (idle_cycles) @(posedge clk);
    endtask

    initial begin
        beats_recv    = 0;
        pkts_recv     = 0;
        exp_beats     = 0;
        exp_pkts      = 0;
        exp_byte_idx  = 0;
        exp_pkt_idx   = 0;
        next_byte_val = 1;
        exp_bytes     = {};
        exp_pkt_end_bytes = {};

        forever begin
            @(posedge clk);
            if (m_tvalid_w && m_tready_w) begin
                int pkt_end;
                int pkt_bytes_left;
                int valid_bytes;
                logic [OUT_KEEP_W-1:0] exp_keep;
                logic exp_last;

                $display("[UPS][OUT] beat %0d tdata=0x%h tkeep=%04b tlast=%0b",
                         beats_recv, m_tdata_w, m_tkeep_w, m_tlast_w);

                if (exp_pkt_idx >= exp_pkt_end_bytes.size()) begin
                    $error("[UPS] FAIL: observed more output packets than expected");
                end else begin
                    pkt_end        = exp_pkt_end_bytes[exp_pkt_idx];
                    pkt_bytes_left = pkt_end - exp_byte_idx;
                    valid_bytes    = (pkt_bytes_left > OUT_KEEP_W) ? OUT_KEEP_W : pkt_bytes_left;
                    exp_keep       = keep_mask(valid_bytes);
                    exp_last       = (valid_bytes == pkt_bytes_left);

                    if (m_tkeep_w !== exp_keep)
                        $error("[UPS] FAIL: beat %0d expected tkeep=%04b, got %04b",
                               beats_recv, exp_keep, m_tkeep_w);

                    if (m_tlast_w !== exp_last)
                        $error("[UPS] FAIL: beat %0d expected tlast=%0b, got %0b",
                               beats_recv, exp_last, m_tlast_w);

                    for (int lane = 0; lane < valid_bytes; lane++) begin
                        if (m_tdata_w[lane*8 +: 8] !== exp_bytes[exp_byte_idx + lane]) begin
                            $error("[UPS] FAIL: beat %0d lane %0d expected byte 0x%02h, got 0x%02h",
                                   beats_recv, lane, exp_bytes[exp_byte_idx + lane],
                                   m_tdata_w[lane*8 +: 8]);
                        end
                    end

                    for (int lane = valid_bytes; lane < OUT_KEEP_W; lane++) begin
                        if (m_tkeep_w[lane] !== 1'b0)
                            $error("[UPS] FAIL: beat %0d lane %0d should be invalid", beats_recv, lane);
                    end

                    exp_byte_idx += valid_bytes;
                    if (m_tlast_w)
                        exp_pkt_idx++;
                end

                beats_recv++;
                if (m_tlast_w) begin
                    pkts_recv++;
                end
            end
        end
    end

    // -------------------------------------------------------
    // Sink ready driver
    // -------------------------------------------------------
    initial begin : sink_ready_driver
        m_tready_w = 1'b0;
        forever begin
            bit ready_now;
            ready_now = !sink_bp_en ? 1'b1 : ($urandom_range(0, 99) < 80);
            @(negedge clk);
            m_tready_w = ready_now;
        end
    end

    // -------------------------------------------------------
    // Test sequence
    // -------------------------------------------------------
    initial begin
        s_t.init();

        @(negedge rst_n);
        @(posedge rst_n);
        repeat (2) @(posedge clk);

        // ----- Phase 1: sequential, no inter-packet gap -----
        $display("[UPS] ---- Phase 1: Sequential ----");
        send_pkt(1, 1);
        send_pkt(2, 1);
        send_pkt(3, 1);
        send_pkt(4, 1);
        send_pkt(2, 1);
        wait (pkts_recv == 5);
        $display("[UPS] Phase 1 done: %0d beats / %0d pkts", beats_recv, pkts_recv);

        // ----- Phase 2: same packets, with backpressure -----
        $display("[UPS] ---- Phase 2: Backpressure ----");
        send_pkt(1, 1);
        send_pkt(2, 1);
        send_pkt(3, 1);
        send_pkt(4, 1);
        send_pkt(2, 1);
        wait (pkts_recv == exp_pkts);
        repeat (4) @(posedge clk);
        $display("[UPS] Phase 2 done: %0d beats / %0d pkts", beats_recv, pkts_recv);

        // ----- Checks -----
        if (beats_recv !== exp_beats)
            $error("[UPS] FAIL: expected %0d beats, got %0d", exp_beats, beats_recv);
        else if (pkts_recv !== exp_pkts)
            $error("[UPS] FAIL: expected %0d packets, got %0d", exp_pkts, pkts_recv);
        else if (exp_byte_idx !== exp_bytes.size())
            $error("[UPS] FAIL: consumed %0d expected bytes, expected %0d",
                   exp_byte_idx, exp_bytes.size());
        else
            $display("[UPS] PASS: %0d beats / %0d pkts, byte-accurate scoreboard matched",
                     beats_recv, pkts_recv);

        repeat (5) @(posedge clk);
        $finish;
    end

    initial begin
        #2_000_000;
        $fatal("test_axis_upsizer: simulation timeout");
    end

endmodule: test_axis_upsizer

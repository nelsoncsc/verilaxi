`timescale 1ns/1ps

// -------------------------------------------------
// test_axis_rr_downsizer
//
// Exercises snix_axis_rr_downsizer with IN=24, OUT=16  (2:3 ratio).
//   G=8, IN_RATIO=2, OUT_RATIO=3, LCM=48 bits.
//   Collect 2 × 24-bit beats, emit 3 × 16-bit beats.
//
// Phase 1 — sequential packets (in-beats → out-beats, tlast_tkeep):
//
//   2 in  → 3 out   full group          tkeep = 2'b11
//   1 in  → 2 out   TLAST at beat 0     tkeep = 2'b01  (1 valid byte)
//   2 in  → 3 out   full group          tkeep = 2'b11
//   4 in  → 6 out   two full groups     tkeep = 2'b11
//
//   Total: 14 output beats, 4 output packets.
//
// Phase 2 — same four packets, optional backpressure.
//   Additional: 14 output beats, 4 output packets.
//
// Grand total: 28 output beats, 8 output packets.
// -------------------------------------------------
module test_axis_rr_downsizer #(
    parameter int IN_DATA_WIDTH  = 24,
    parameter int OUT_DATA_WIDTH = 16
) (
    input logic clk,
    input logic rst_n
);

    localparam int IN_BYTES  = IN_DATA_WIDTH  / 8;
    localparam int OUT_BYTES = OUT_DATA_WIDTH / 8;

    int src_bp_en;
    int sink_bp_en;

    initial begin
        src_bp_en  = 0;
        sink_bp_en = 0;
        void'($value$plusargs("SRC_BP=%d",  src_bp_en));
        void'($value$plusargs("SINK_BP=%d", sink_bp_en));
        $display("[RRD] SRC_BP=%0d SINK_BP=%0d IN=%0d OUT=%0d",
                 src_bp_en, sink_bp_en, IN_DATA_WIDTH, OUT_DATA_WIDTH);
    end

    // -------------------------------------------------------
    // Source-side wires
    // -------------------------------------------------------
    logic [IN_DATA_WIDTH-1:0]  s_tdata_w;
    logic [IN_BYTES-1:0]       s_tkeep_w;
    logic                      s_tvalid_w;
    logic                      s_tready_w;
    logic                      s_tlast_w;

    // -------------------------------------------------------
    // DUT output wires
    // -------------------------------------------------------
    logic [OUT_DATA_WIDTH-1:0]  m_tdata_w;
    logic [OUT_BYTES-1:0]       m_tkeep_w;
    logic                       m_tvalid_w;
    logic                       m_tready_w;
    logic                       m_tlast_w;

    // -------------------------------------------------------
    // DUT
    // -------------------------------------------------------
    snix_axis_rr_downsizer #(
        .IN_DATA_WIDTH (IN_DATA_WIDTH),
        .OUT_DATA_WIDTH(OUT_DATA_WIDTH)
    ) u_dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .s_axis_tdata (s_tdata_w),
        .s_axis_tkeep (s_tkeep_w),
        .s_axis_tvalid(s_tvalid_w),
        .s_axis_tready(s_tready_w),
        .s_axis_tlast (s_tlast_w),
        .m_axis_tdata (m_tdata_w),
        .m_axis_tkeep (m_tkeep_w),
        .m_axis_tvalid(m_tvalid_w),
        .m_axis_tready(m_tready_w),
        .m_axis_tlast (m_tlast_w)
    );

    // -------------------------------------------------------
    // Protocol checkers
    // -------------------------------------------------------
    axis_checker #(.DATA_WIDTH(IN_DATA_WIDTH),  .USER_WIDTH(1), .LABEL("RRD_SLV"))
        u_chk_s (.clk(clk), .rst_n(rst_n),
                 .tdata(s_tdata_w), .tuser(1'b0),
                 .tvalid(s_tvalid_w), .tready(s_tready_w), .tlast(s_tlast_w));

    axis_checker #(.DATA_WIDTH(OUT_DATA_WIDTH), .USER_WIDTH(1), .LABEL("RRD_MST"))
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

    function automatic logic [OUT_BYTES-1:0] keep_mask(input int valid_bytes);
        logic [OUT_BYTES-1:0] mask;
        mask = '0;
        for (int i = 0; i < OUT_BYTES; i++) begin
            if (i < valid_bytes)
                mask[i] = 1'b1;
        end
        return mask;
    endfunction

    initial begin
        beats_recv = 0;
        pkts_recv  = 0;
        exp_beats = 0;
        exp_pkts = 0;
        exp_byte_idx = 0;
        exp_pkt_idx = 0;
        next_byte_val = 1;
        exp_bytes = {};
        exp_pkt_end_bytes = {};

        forever begin
            @(posedge clk);
            if (m_tvalid_w && m_tready_w) begin
                int pkt_end;
                int pkt_bytes_left;
                int valid_bytes;
                logic [OUT_BYTES-1:0] exp_keep;
                logic exp_last;
                $display("[RRD] beat %0d tdata=0x%h tkeep=%02b tlast=%0b",
                         beats_recv, m_tdata_w, m_tkeep_w, m_tlast_w);

                pkt_end        = exp_pkt_end_bytes[exp_pkt_idx];
                pkt_bytes_left = pkt_end - exp_byte_idx;
                valid_bytes    = (pkt_bytes_left > OUT_BYTES) ? OUT_BYTES : pkt_bytes_left;
                exp_keep       = keep_mask(valid_bytes);
                exp_last       = (valid_bytes == pkt_bytes_left);

                if (m_tkeep_w !== exp_keep)
                    $error("[RRD] FAIL: beat %0d expected tkeep=%02b, got %02b",
                           beats_recv, exp_keep, m_tkeep_w);

                if (m_tlast_w !== exp_last)
                    $error("[RRD] FAIL: beat %0d expected tlast=%0b, got %0b",
                           beats_recv, exp_last, m_tlast_w);

                for (int lane = 0; lane < valid_bytes; lane++) begin
                    if (m_tdata_w[lane*8 +: 8] !== exp_bytes[exp_byte_idx + lane]) begin
                        $error("[RRD] FAIL: beat %0d lane %0d expected byte 0x%02h, got 0x%02h",
                               beats_recv, lane, exp_bytes[exp_byte_idx + lane],
                               m_tdata_w[lane*8 +: 8]);
                    end
                end

                exp_byte_idx += valid_bytes;
                if (m_tlast_w)
                    exp_pkt_idx++;

                beats_recv++;
                if (m_tlast_w)
                    pkts_recv++;
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
    // Source task — drives one packet of num_beats 24-bit input beats.
    // -------------------------------------------------------
    task automatic send_pkt(input int num_beats, input int idle_cycles = 1);
        int beat;
        bit launch;
        int pkt_start;

        @(negedge clk);
        s_tvalid_w = 1'b0;
        s_tlast_w  = 1'b0;

        pkt_start = exp_bytes.size();
        for (beat = 0; beat < num_beats; beat++) begin
            for (int lane = 0; lane < IN_BYTES; lane++) begin
                exp_bytes.push_back(byte'(next_byte_val));
                next_byte_val++;
            end
        end
        exp_pkt_end_bytes.push_back(exp_bytes.size());
        exp_pkts++;
        exp_beats += (exp_bytes.size() - pkt_start + OUT_BYTES - 1) / OUT_BYTES;

        beat = 0;
        while (beat < num_beats) begin
            if (!s_tvalid_w) begin
                launch = !src_bp_en ? 1'b1 : ($urandom_range(0, 99) < 80);
                @(negedge clk);
                if (launch) begin
                    logic [IN_DATA_WIDTH-1:0] dat;
                    dat = '0;
                    for (int lane = 0; lane < IN_BYTES; lane++)
                        dat[lane*8 +: 8] = byte'(exp_bytes[pkt_start + beat*IN_BYTES + lane]);
                    s_tdata_w  = dat;
                    s_tkeep_w  = {IN_BYTES{1'b1}};
                    s_tlast_w  = (beat == num_beats - 1);
                    s_tvalid_w = 1'b1;
                end
            end
            @(posedge clk);
            if (s_tvalid_w && s_tready_w) begin
                $display("[SRC] beat %0d/%0d tdata=0x%h tlast=%0b",
                         beat, num_beats - 1, s_tdata_w, s_tlast_w);
                beat++;
                @(negedge clk);
                s_tvalid_w = 1'b0;
                s_tlast_w  = 1'b0;
            end
        end

        repeat (idle_cycles) @(posedge clk);
    endtask

    // -------------------------------------------------------
    // Test sequence
    // -------------------------------------------------------
    initial begin
        s_tdata_w  = '0;
        s_tkeep_w  = '0;
        s_tvalid_w = 1'b0;
        s_tlast_w  = 1'b0;

        @(negedge rst_n);
        @(posedge rst_n);
        repeat (2) @(posedge clk);

        $display("[RRD] ---- Phase 1: Sequential ----");
        send_pkt(2, 1);   // full group        → 3 out-beats, tkeep_last=11
        send_pkt(1, 1);   // TLAST at beat 0   → 2 out-beats, tkeep_last=01
        send_pkt(2, 1);   // full group        → 3 out-beats, tkeep_last=11
        send_pkt(4, 1);   // two full groups   → 6 out-beats, tkeep_last=11
        wait (pkts_recv == 4);
        $display("[RRD] Phase 1 done: %0d beats / %0d pkts", beats_recv, pkts_recv);

        $display("[RRD] ---- Phase 2: Backpressure ----");
        send_pkt(2, 1);
        send_pkt(1, 1);
        send_pkt(2, 1);
        send_pkt(4, 1);
        wait (pkts_recv == 8);
        repeat (4) @(posedge clk);
        $display("[RRD] Phase 2 done: %0d beats / %0d pkts", beats_recv, pkts_recv);

        if (beats_recv !== exp_beats)
            $error("[RRD] FAIL: expected %0d beats, got %0d", exp_beats, beats_recv);
        else if (pkts_recv !== exp_pkts)
            $error("[RRD] FAIL: expected %0d packets, got %0d", exp_pkts, pkts_recv);
        else if (exp_byte_idx !== exp_bytes.size())
            $error("[RRD] FAIL: consumed %0d expected bytes, expected %0d",
                   exp_byte_idx, exp_bytes.size());
        else
            $display("[RRD] PASS: %0d beats / %0d pkts, byte-accurate scoreboard matched",
                     beats_recv, pkts_recv);

        repeat (5) @(posedge clk);
        $finish;
    end

    initial begin
        #2_000_000;
        $fatal("test_axis_rr_downsizer: simulation timeout");
    end

endmodule: test_axis_rr_downsizer

`timescale 1ns/1ps

// -------------------------------------------------
// test_axis_rr_converter
//
// Exercises snix_axis_rr_converter with IN=16, OUT=24  (3:2 ratio, 1.5x).
//   G=8, IN_RATIO=3, OUT_RATIO=2, LCM=48 bits.
//   Collect 3 × 16-bit beats, emit 2 × 24-bit beats.
//
// The source is driven by a local task rather than the axis_source BFM
// because Verilator does not correctly resolve virtual interface types
// when a parameterized class is instantiated at a non-default DATA_WIDTH.
//
// Phase 1 — sequential packets.  Each row shows (in-beats → out-beats)
// and the expected TKEEP on the TLAST output beat:
//
//   3 in  → 2 out   full group          tlast_tkeep = 3'b111
//   1 in  → 1 out   TLAST at beat 0     tlast_tkeep = 3'b011  (2 valid bytes)
//   2 in  → 2 out   TLAST at beat 1     tlast_tkeep = 3'b001  (1 valid byte remains)
//   6 in  → 4 out   two full groups     tlast_tkeep = 3'b111
//
//   Total: 9 output beats, 4 output packets.
//
// Phase 2 — same four packets with optional backpressure.
//   Additional: 9 output beats, 4 output packets.
//
// Grand total: 18 output beats, 8 output packets.
// -------------------------------------------------
module test_axis_rr_converter #(
    parameter int IN_DATA_WIDTH  = 16,
    parameter int OUT_DATA_WIDTH = 24
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
        $display("[RRC] SRC_BP=%0d SINK_BP=%0d IN=%0d OUT=%0d",
                 src_bp_en, sink_bp_en, IN_DATA_WIDTH, OUT_DATA_WIDTH);
    end

    // -------------------------------------------------------
    // Source-side wires (narrow, IN_DATA_WIDTH bits)
    // -------------------------------------------------------
    logic [IN_DATA_WIDTH-1:0]  s_tdata_w;
    logic [IN_BYTES-1:0]       s_tkeep_w;   // all-ones in this test
    logic                      s_tvalid_w;
    logic                      s_tready_w;
    logic                      s_tlast_w;

    // -------------------------------------------------------
    // DUT output wires (wide, OUT_DATA_WIDTH bits)
    // -------------------------------------------------------
    logic [OUT_DATA_WIDTH-1:0]  m_tdata_w;
    logic [OUT_BYTES-1:0]       m_tkeep_w;
    logic                       m_tvalid_w;
    logic                       m_tready_w;
    logic                       m_tlast_w;

    // -------------------------------------------------------
    // DUT
    // -------------------------------------------------------
    snix_axis_rr_converter #(
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
    axis_checker #(.DATA_WIDTH(IN_DATA_WIDTH),  .USER_WIDTH(1), .LABEL("RRC_SLV"))
        u_chk_s (.clk(clk), .rst_n(rst_n),
                 .tdata(s_tdata_w), .tuser(1'b0),
                 .tvalid(s_tvalid_w), .tready(s_tready_w), .tlast(s_tlast_w));

    axis_checker #(.DATA_WIDTH(OUT_DATA_WIDTH), .USER_WIDTH(1), .LABEL("RRC_MST"))
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
                $display("[RRC] beat %0d tdata=0x%h tkeep=%03b tlast=%0b",
                         beats_recv, m_tdata_w, m_tkeep_w, m_tlast_w);

                pkt_end        = exp_pkt_end_bytes[exp_pkt_idx];
                pkt_bytes_left = pkt_end - exp_byte_idx;
                valid_bytes    = (pkt_bytes_left > OUT_BYTES) ? OUT_BYTES : pkt_bytes_left;
                exp_keep       = keep_mask(valid_bytes);
                exp_last       = (valid_bytes == pkt_bytes_left);

                if (m_tkeep_w !== exp_keep)
                    $error("[RRC] FAIL: beat %0d expected tkeep=%03b, got %03b",
                           beats_recv, exp_keep, m_tkeep_w);

                if (m_tlast_w !== exp_last)
                    $error("[RRC] FAIL: beat %0d expected tlast=%0b, got %0b",
                           beats_recv, exp_last, m_tlast_w);

                for (int lane = 0; lane < valid_bytes; lane++) begin
                    if (m_tdata_w[lane*8 +: 8] !== exp_bytes[exp_byte_idx + lane]) begin
                        $error("[RRC] FAIL: beat %0d lane %0d expected byte 0x%02h, got 0x%02h",
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
    // Source task — drives one packet of num_beats input beats.
    // All TKEEP lanes are asserted; idle_cycles gap after TLAST.
    // Optional source backpressure withholds TVALID randomly.
    // -------------------------------------------------------
    logic [IN_BYTES-1:0] keep_pat [0:15];

    task automatic send_pkt_pattern(input int num_beats, input int idle_cycles = 1);
        int beat;
        bit launch;
        int pkt_start;
        int pkt_base;

        @(negedge clk);
        s_tvalid_w = 1'b0;
        s_tlast_w  = 1'b0;

        pkt_start = exp_bytes.size();
        pkt_base  = next_byte_val;
        for (beat = 0; beat < num_beats; beat++) begin
            for (int lane = 0; lane < IN_BYTES; lane++) begin
                if (keep_pat[beat][lane])
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
                        dat[lane*8 +: 8] = byte'(pkt_base + beat*IN_BYTES + lane);
                    s_tdata_w  = dat;
                    s_tkeep_w  = keep_pat[beat];
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

    task automatic send_pkt(input int num_beats, input int idle_cycles = 1);
        for (int beat = 0; beat < num_beats; beat++)
            keep_pat[beat] = {IN_BYTES{1'b1}};
        send_pkt_pattern(num_beats, idle_cycles);
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

        // ----- Phase 1: sequential -----
        $display("[RRC] ---- Phase 1: Sequential ----");
        // 3 in-beats: fills one full group → 2 out-beats, tkeep_last=111
        send_pkt(3, 1);
        // Sparse packet: keep pattern 01,10,11 -> 4 valid bytes compacted into 2 outputs.
        keep_pat[0] = 2'b01;
        keep_pat[1] = 2'b10;
        keep_pat[2] = 2'b11;
        send_pkt_pattern(3, 1);
        // 1 in-beat, TLAST at beat 0: 2 valid bytes → 1 out-beat, tkeep=011
        send_pkt(1, 1);
        // 6 in-beats: two full groups → 4 out-beats, tkeep_last=111
        send_pkt(6, 1);
        wait (pkts_recv == 4);
        $display("[RRC] Phase 1 done: %0d beats / %0d pkts", beats_recv, pkts_recv);

        // ----- Phase 2: same packets, with backpressure -----
        $display("[RRC] ---- Phase 2: Backpressure ----");
        send_pkt(3, 1);
        keep_pat[0] = 2'b01;
        keep_pat[1] = 2'b10;
        keep_pat[2] = 2'b11;
        send_pkt_pattern(3, 1);
        send_pkt(1, 1);
        send_pkt(6, 1);
        wait (pkts_recv == 8);
        repeat (4) @(posedge clk);
        $display("[RRC] Phase 2 done: %0d beats / %0d pkts", beats_recv, pkts_recv);

        // ----- Checks -----
        if (beats_recv !== exp_beats)
            $error("[RRC] FAIL: expected %0d beats, got %0d", exp_beats, beats_recv);
        else if (pkts_recv !== exp_pkts)
            $error("[RRC] FAIL: expected %0d packets, got %0d", exp_pkts, pkts_recv);
        else if (exp_byte_idx !== exp_bytes.size())
            $error("[RRC] FAIL: consumed %0d expected bytes, expected %0d",
                   exp_byte_idx, exp_bytes.size());
        else
            $display("[RRC] PASS: %0d beats / %0d pkts, byte-accurate scoreboard matched",
                     beats_recv, pkts_recv);

        repeat (5) @(posedge clk);
        $finish;
    end

    initial begin
        #2_000_000;
        $fatal("test_axis_rr_converter: simulation timeout");
    end

endmodule: test_axis_rr_converter

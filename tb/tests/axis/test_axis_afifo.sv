`timescale 1ns/1ps

// test_axis_afifo.sv — CDC functional test for snix_axis_afifo
//
// Generates independent source and sink clocks; TESTTYPE selects ratio:
//   0  same rate    s=4 ns  m=4 ns
//   1  read slow    s=4 ns  m=10 ns
//   2  read fast    s=4 ns  m=2 ns
//
// SRC_BP / SINK_BP control backpressure on each side.
// Data integrity is verified beat-by-beat via a scoreboard mailbox.
//
// FRAME_FIFO (compile-time +define+FRAME_FIFO):
//   unset  -> cut-through  (FRAME_FIFO=0): tvalid follows !empty
//   set    -> store-and-forward (FRAME_FIFO=1): tvalid held until full packet written
`ifdef FRAME_FIFO
  `define AXIS_AFIFO_FRAME_MODE 1'b1
`else
  `define AXIS_AFIFO_FRAME_MODE 1'b0
`endif

module test_axis_afifo #(parameter int DATA_WIDTH = 8)
                        (input logic clk,    // unused — test generates own clocks
                         input logic rst_n); // unused

    localparam int  FIFO_DEPTH = 16;
    localparam int  N_PKTS     = 6;
    localparam bit  FRAME_MODE = `AXIS_AFIFO_FRAME_MODE;

    // -------------------------------------------------------
    // Plusargs
    // -------------------------------------------------------
    int testtype, src_bp_en, sink_bp_en;

    initial begin
        testtype   = 0;
        src_bp_en  = 0;
        sink_bp_en = 0;
        void'($value$plusargs("TESTTYPE=%d",  testtype));
        void'($value$plusargs("SRC_BP=%d",    src_bp_en));
        void'($value$plusargs("SINK_BP=%d",   sink_bp_en));
        $display("AXIS AFIFO CDC: TESTTYPE=%0d SRC_BP=%0d SINK_BP=%0d FRAME_MODE=%0d",
                 testtype, src_bp_en, sink_bp_en, int'(FRAME_MODE));
    end

    // -------------------------------------------------------
    // Clocks
    //   s_axis_clk : 4 ns period (fixed)
    //   m_axis_clk : selected by TESTTYPE
    // -------------------------------------------------------
    logic s_axis_clk;
    logic m_clk_a, m_clk_b, m_clk_c;
    logic m_axis_clk;
    logic s_axis_rst_n, m_axis_rst_n;

    initial s_axis_clk = 0; always #2 s_axis_clk = ~s_axis_clk; // 4 ns
    initial m_clk_a    = 0; always #2 m_clk_a    = ~m_clk_a;   // 4 ns (same)
    initial m_clk_b    = 0; always #5 m_clk_b    = ~m_clk_b;   // 10 ns (slow)
    initial m_clk_c    = 0; always #1 m_clk_c    = ~m_clk_c;   //  2 ns (fast)

    always_comb
        case (testtype)
            1:       m_axis_clk = m_clk_b;
            2:       m_axis_clk = m_clk_c;
            default: m_axis_clk = m_clk_a;
        endcase

    // Independent resets — m_axis reset held longer for clean CDC sync
    initial begin
        s_axis_rst_n = 1'b0;
        m_axis_rst_n = 1'b0;
        repeat (4) @(posedge s_axis_clk);
        s_axis_rst_n = 1'b1;
        repeat (6) @(posedge m_axis_clk);
        m_axis_rst_n = 1'b1;
    end

    // -------------------------------------------------------
    // Interfaces — one per clock domain
    // -------------------------------------------------------
    axis_if #(.DATA_WIDTH(DATA_WIDTH), .USER_WIDTH(1))
        s_if(s_axis_clk, s_axis_rst_n),
        m_if(m_axis_clk, m_axis_rst_n);

    // DUT has no tuser — tie to 0 so master checker is happy
    assign m_if.tuser = '0;

    // -------------------------------------------------------
    // DUT
    // -------------------------------------------------------
    snix_axis_afifo #(.DATA_WIDTH(DATA_WIDTH),
                      .FIFO_DEPTH(FIFO_DEPTH),
                      .FRAME_FIFO(FRAME_MODE))
        dut (
            .s_axis_clk   (s_axis_clk),
            .s_axis_rst_n (s_axis_rst_n),
            .s_axis_tdata (s_if.tdata),
            .s_axis_tvalid(s_if.tvalid),
            .s_axis_tlast (s_if.tlast),
            .s_axis_tready(s_if.tready),   // DUT drives back to source
            .m_axis_clk   (m_axis_clk),
            .m_axis_rst_n (m_axis_rst_n),
            .m_axis_tdata (m_if.tdata),    // DUT drives
            .m_axis_tvalid(m_if.tvalid),   // DUT drives
            .m_axis_tlast (m_if.tlast),    // DUT drives
            .m_axis_tready(m_if.tready)    // TB drives
        );

    // -------------------------------------------------------
    // Protocol checkers (each on its own clock domain)
    // -------------------------------------------------------
    axis_checker #(.DATA_WIDTH(DATA_WIDTH), .USER_WIDTH(1),
                   .LABEL("AFIFO_SLV"))
        u_slv_chk (
            .clk    (s_axis_clk),
            .rst_n  (s_axis_rst_n),
            .tdata  (s_if.tdata),
            .tuser  (s_if.tuser),
            .tvalid (s_if.tvalid),
            .tready (s_if.tready),
            .tlast  (s_if.tlast)
        );

    axis_checker #(.DATA_WIDTH(DATA_WIDTH), .USER_WIDTH(1),
                   .LABEL("AFIFO_MST"))
        u_mst_chk (
            .clk    (m_axis_clk),
            .rst_n  (m_axis_rst_n),
            .tdata  (m_if.tdata),
            .tuser  (m_if.tuser),
            .tvalid (m_if.tvalid),
            .tready (m_if.tready),
            .tlast  (m_if.tlast)
        );

    // -------------------------------------------------------
    // Scoreboard — filled by sender, drained by receiver
    // -------------------------------------------------------
    mailbox #(logic [DATA_WIDTH-1:0]) tx_q = new();

    // -------------------------------------------------------
    // Source task  (s_axis_clk domain)
    //   Drives one complete packet; pushes each beat to tx_q
    //   after handshake. With SRC_BP, inserts random idle gaps.
    // -------------------------------------------------------
    task automatic send_pkt(int n_beats);
        for (int i = 0; i < n_beats; i++) begin
            logic [DATA_WIDTH-1:0] beat;
            beat       = $urandom();
            // optional idle gap before asserting valid
            if (src_bp_en) begin
                @(negedge s_axis_clk);
                s_if.tvalid = 0;
                repeat ($urandom_range(0, 3)) @(posedge s_axis_clk);
            end
            // Drive payload away from the active sampling edge and hold it
            // stable until the handshake completes.
            @(negedge s_axis_clk);
            s_if.tdata  = beat;
            s_if.tlast  = (i == n_beats - 1);
            s_if.tvalid = 1;
            // wait for handshake
            @(posedge s_axis_clk);
            while (!(s_if.tvalid && s_if.tready))
                @(posedge s_axis_clk);
            tx_q.put(beat);
        end
        @(negedge s_axis_clk);
        s_if.tvalid = 0;
        s_if.tlast  = 0;
    endtask

    // -------------------------------------------------------
    // Sink task  (m_axis_clk domain)
    //   Receives one complete packet; compares each beat against tx_q.
    //
    //   Post-NBA read caveat: after @(posedge m_axis_clk) the async
    //   FIFO's always_ff has already updated rdata to the NEXT item.
    //   Fix: sample tdata while tready=0 (lcl_read=rd_en=0, rdata frozen),
    //   then commit the handshake in a separate posedge.
    //
    //   SINK_BP inserts a hold-off between tvalid asserting and
    //   tready asserting (all with tready=0, so rdata stays stable).
    // -------------------------------------------------------
    task automatic recv_pkt(int n_beats);
        for (int i = 0; i < n_beats; i++) begin
            logic [DATA_WIDTH-1:0] exp, rcv;
            logic                  rcv_last;

            // --- Phase 1: wait for tvalid with tready=0 (no handshake) ---
            @(negedge m_axis_clk);
            m_if.tready = 0;
            @(posedge m_axis_clk);
            while (!m_if.tvalid) begin
                @(negedge m_axis_clk);
                m_if.tready = 0;
                @(posedge m_axis_clk);
            end

            // --- Phase 2: tvalid=1, tready=0 → lcl_read=rd_en=0 → rdata frozen ---
            // Optional hold-off to exercise backpressure coverage
            if (sink_bp_en)
                repeat ($urandom_range(0, 3)) @(posedge m_axis_clk);

            // Sample data now — rdata has not moved yet
            rcv      = m_if.tdata;
            rcv_last = m_if.tlast;

            // --- Phase 3: commit handshake; rdata will update post-posedge ---
            @(negedge m_axis_clk);
            m_if.tready = 1;
            @(posedge m_axis_clk);
            @(negedge m_axis_clk);
            m_if.tready = 0;

            // Scoreboard: beat must be in tx_q by the time tvalid was seen
            // (CDC latency guarantees s_axis write completed before m_axis valid)
            wait (tx_q.num() > 0);
            void'(tx_q.try_get(exp));

            assert (rcv == exp)
                else $error("AFIFO CDC beat %0d: rcv=0x%0h exp=0x%0h", i, rcv, exp);
            if (i == n_beats - 1)
                assert (rcv_last)
                    else $error("AFIFO CDC: tlast missing on last beat (beat %0d)", i);
            else
                assert (!rcv_last)
                    else $error("AFIFO CDC: premature tlast on beat %0d", i);
        end
    endtask

    // -------------------------------------------------------
    // Test sequence
    // -------------------------------------------------------
    int pkt_sizes [N_PKTS] = '{1, 4, 8, 2, 6, 3};

    initial begin
        // Init source signals (don't touch s_if.tready — DUT drives that back)
        s_if.tvalid = 0;
        s_if.tdata  = '0;
        s_if.tlast  = 0;
        s_if.tuser  = '0;
        m_if.tready = 0;

        // Wait for both resets to release
        @(posedge s_axis_rst_n);
        @(posedge m_axis_rst_n);
        repeat (2) @(posedge s_axis_clk);

        $display("[TEST] AFIFO CDC: starting %0d packets (FRAME_MODE=%0d)",
                 N_PKTS, int'(FRAME_MODE));

        for (int p = 0; p < N_PKTS; p++) begin
            fork
                begin send_pkt(pkt_sizes[p]); end
                begin recv_pkt(pkt_sizes[p]); end
            join
            $display("[TEST] packet %0d (%0d beats) PASS", p, pkt_sizes[p]);
        end

        repeat (4) @(posedge s_axis_clk);
        $display("[TEST] AFIFO CDC: all %0d packets passed", N_PKTS);
        $finish;
    end

    // -------------------------------------------------------
    // Watchdog
    // -------------------------------------------------------
    initial begin
        #500_000;
        $fatal("test_axis_afifo: simulation timeout");
    end

endmodule : test_axis_afifo

`timescale 1ns / 1ps

module test_cdma #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 64,
    parameter int ID_WIDTH   = 4,
    parameter int USER_WIDTH = 1)
   (input logic clk,
    input logic rst_n);

    import axi_pkg::*;
    import axi_cdma_pkg::*;

    // --------------------------------------------------
    // AXI4 memory port
    // Single interface carries both AR/R (read from src)
    // and AW/W/B (write to dst) for the MM2MM engine.
    // --------------------------------------------------
    axi4_if #(.ADDR_WIDTH(ADDR_WIDTH),
              .DATA_WIDTH(DATA_WIDTH),
              .ID_WIDTH  (ID_WIDTH),
              .USER_WIDTH(USER_WIDTH))
        axi_if_r(.ACLK(clk), .ARESETn(rst_n)),  // live traffic
        axi_if_s(.ACLK(clk), .ARESETn(rst_n));  // registered sample for waveforms

    // AXI-Lite CSR port
    axil_if #(.ADDR_WIDTH(AXIL_ADDR_WIDTH),
              .DATA_WIDTH(AXIL_DATA_WIDTH))
        axil_if_lt(.ACLK(clk), .ARESETn(rst_n)),  // live
        axil_if_ls(.ACLK(clk), .ARESETn(rst_n));  // sampled

    // --------------------------------------------------
    // Objects
    // --------------------------------------------------
    axi_slave  #(.ADDR_WIDTH(ADDR_WIDTH),
                 .DATA_WIDTH(DATA_WIDTH),
                 .ID_WIDTH  (ID_WIDTH)) s;

    axil_master #(.ADDR_WIDTH(AXIL_ADDR_WIDTH),
                  .DATA_WIDTH(AXIL_DATA_WIDTH)) axil_m;

    axi_cdma_driver cdma_drv;

    // --------------------------------------------------
    // DUT: snix_axi_cdma
    // --------------------------------------------------
    snix_axi_cdma #(
        .ADDR_WIDTH     (ADDR_WIDTH),
        .DATA_WIDTH     (DATA_WIDTH),
        .AXIL_ADDR_WIDTH(AXIL_ADDR_WIDTH),
        .AXIL_DATA_WIDTH(AXIL_DATA_WIDTH),
        .ID_WIDTH       (ID_WIDTH),
        .USER_WIDTH     (USER_WIDTH))
    axi_cdma (
        .clk            (clk),
        .rst_n          (rst_n),
        // AXI-Lite CSR
        .s_axil_awaddr  (axil_if_lt.awaddr),
        .s_axil_awvalid (axil_if_lt.awvalid),
        .s_axil_awready (axil_if_lt.awready),
        .s_axil_wdata   (axil_if_lt.wdata),
        .s_axil_wstrb   (axil_if_lt.wstrb),
        .s_axil_wvalid  (axil_if_lt.wvalid),
        .s_axil_wready  (axil_if_lt.wready),
        .s_axil_bresp   (axil_if_lt.bresp),
        .s_axil_bvalid  (axil_if_lt.bvalid),
        .s_axil_bready  (axil_if_lt.bready),
        .s_axil_araddr  (axil_if_lt.araddr),
        .s_axil_arvalid (axil_if_lt.arvalid),
        .s_axil_arready (axil_if_lt.arready),
        .s_axil_rdata   (axil_if_lt.rdata),
        .s_axil_rresp   (axil_if_lt.rresp),
        .s_axil_rvalid  (axil_if_lt.rvalid),
        .s_axil_rready  (axil_if_lt.rready),
        // AXI4 MM2MM memory port
        .mm2mm_awid     (axi_if_r.awid),
        .mm2mm_awaddr   (axi_if_r.awaddr),
        .mm2mm_awlen    (axi_if_r.awlen),
        .mm2mm_awsize   (axi_if_r.awsize),
        .mm2mm_awburst  (axi_if_r.awburst),
        .mm2mm_awlock   (axi_if_r.awlock),
        .mm2mm_awcache  (axi_if_r.awcache),
        .mm2mm_awprot   (axi_if_r.awprot),
        .mm2mm_awqos    (axi_if_r.awqos),
        .mm2mm_awuser   (axi_if_r.awuser),
        .mm2mm_awvalid  (axi_if_r.awvalid),
        .mm2mm_awready  (axi_if_r.awready),
        .mm2mm_wdata    (axi_if_r.wdata),
        .mm2mm_wstrb    (axi_if_r.wstrb),
        .mm2mm_wlast    (axi_if_r.wlast),
        .mm2mm_wuser    (axi_if_r.wuser),
        .mm2mm_wvalid   (axi_if_r.wvalid),
        .mm2mm_wready   (axi_if_r.wready),
        .mm2mm_bid      (axi_if_r.bid),
        .mm2mm_bresp    (axi_if_r.bresp),
        .mm2mm_buser    (axi_if_r.buser),
        .mm2mm_bvalid   (axi_if_r.bvalid),
        .mm2mm_bready   (axi_if_r.bready),
        .mm2mm_arid     (axi_if_r.arid),
        .mm2mm_araddr   (axi_if_r.araddr),
        .mm2mm_arlen    (axi_if_r.arlen),
        .mm2mm_arsize   (axi_if_r.arsize),
        .mm2mm_arburst  (axi_if_r.arburst),
        .mm2mm_arlock   (axi_if_r.arlock),
        .mm2mm_arcache  (axi_if_r.arcache),
        .mm2mm_arprot   (axi_if_r.arprot),
        .mm2mm_arqos    (axi_if_r.arqos),
        .mm2mm_aruser   (axi_if_r.aruser),
        .mm2mm_arvalid  (axi_if_r.arvalid),
        .mm2mm_arready  (axi_if_r.arready),
        .mm2mm_rid      (axi_if_r.rid),
        .mm2mm_rdata    (axi_if_r.rdata),
        .mm2mm_rresp    (axi_if_r.rresp),
        .mm2mm_rlast    (axi_if_r.rlast),
        .mm2mm_ruser    (axi_if_r.ruser),
        .mm2mm_rvalid   (axi_if_r.rvalid),
        .mm2mm_rready   (axi_if_r.rready));

    // --------------------------------------------------
    // Registered sample interfaces for waveform clarity
    // --------------------------------------------------
    sample_axi_if #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH(ID_WIDTH),     .USER_WIDTH(USER_WIDTH))
    sample_axi_if_u0 (.axi_if_t(axi_if_r), .axi_if_s(axi_if_s));

    sample_axil_if #(.ADDR_WIDTH(AXIL_ADDR_WIDTH), .DATA_WIDTH(AXIL_DATA_WIDTH))
    sample_axil_if_u0(.axil_if_t(axil_if_lt), .axil_if_s(axil_if_ls));

    // --------------------------------------------------
    // Protocol checkers
    // --------------------------------------------------
    // AXI4 MM port: DUT is master (drives AW/W/AR, receives B/R)
    axi_mm_checker #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
                     .ID_WIDTH(ID_WIDTH), .LABEL("CDMA_MM"))
        u_mm_chk (.clk     (clk),              .rst_n   (rst_n),
                  .awaddr  (axi_if_r.awaddr),  .awlen   (axi_if_r.awlen),
                  .awsize  (axi_if_r.awsize),  .awburst (axi_if_r.awburst),
                  .awid    (axi_if_r.awid),    .awvalid (axi_if_r.awvalid),
                  .awready (axi_if_r.awready),
                  .wdata   (axi_if_r.wdata),   .wstrb   (axi_if_r.wstrb),
                  .wlast   (axi_if_r.wlast),   .wvalid  (axi_if_r.wvalid),
                  .wready  (axi_if_r.wready),
                  .bid     (axi_if_r.bid),     .bresp   (axi_if_r.bresp),
                  .bvalid  (axi_if_r.bvalid),  .bready  (axi_if_r.bready),
                  .araddr  (axi_if_r.araddr),  .arlen   (axi_if_r.arlen),
                  .arsize  (axi_if_r.arsize),  .arburst (axi_if_r.arburst),
                  .arid    (axi_if_r.arid),    .arvalid (axi_if_r.arvalid),
                  .arready (axi_if_r.arready),
                  .rid     (axi_if_r.rid),     .rdata   (axi_if_r.rdata),
                  .rresp   (axi_if_r.rresp),   .rlast   (axi_if_r.rlast),
                  .rvalid  (axi_if_r.rvalid),  .rready  (axi_if_r.rready));

    axi_4k_checker #(.ADDR_WIDTH(ADDR_WIDTH), .LABEL("CDMA_4K"))
        u_4k_chk (.clk     (clk),              .rst_n   (rst_n),
                  .awaddr  (axi_if_r.awaddr),  .awlen   (axi_if_r.awlen),
                  .awsize  (axi_if_r.awsize),  .awvalid (axi_if_r.awvalid),
                  .awready (axi_if_r.awready),
                  .araddr  (axi_if_r.araddr),  .arlen   (axi_if_r.arlen),
                  .arsize  (axi_if_r.arsize),  .arvalid (axi_if_r.arvalid),
                  .arready (axi_if_r.arready));

    // AXI-Lite CSR port: DUT is slave
    axil_checker #(.ADDR_WIDTH(AXIL_ADDR_WIDTH), .DATA_WIDTH(AXIL_DATA_WIDTH),
                   .LABEL("CDMA_AXIL"))
        u_axil_chk (.clk    (clk),               .rst_n   (rst_n),
                    .awaddr (axil_if_lt.awaddr),  .awvalid (axil_if_lt.awvalid),
                    .awready(axil_if_lt.awready),
                    .wdata  (axil_if_lt.wdata),   .wstrb   (axil_if_lt.wstrb),
                    .wvalid (axil_if_lt.wvalid),  .wready  (axil_if_lt.wready),
                    .bresp  (axil_if_lt.bresp),   .bvalid  (axil_if_lt.bvalid),
                    .bready (axil_if_lt.bready),
                    .araddr (axil_if_lt.araddr),  .arvalid (axil_if_lt.arvalid),
                    .arready(axil_if_lt.arready),
                    .rdata  (axil_if_lt.rdata),   .rresp   (axil_if_lt.rresp),
                    .rvalid (axil_if_lt.rvalid),  .rready  (axil_if_lt.rready));

    // --------------------------------------------------
    // Constants
    // --------------------------------------------------
    localparam int STRB_WIDTH = DATA_WIDTH / 8;
    localparam int BPB        = DATA_WIDTH / 8;  // bytes per beat (full-width)
    localparam logic [STRB_WIDTH-1:0] FULL_STRB = {STRB_WIDTH{1'b1}};

    // --------------------------------------------------
    // Test variables
    // --------------------------------------------------
    int len;
    int size;
    int src_base, dst_base, num_bytes;
    logic [2:0] test_type;
    int total_errors;

    // --------------------------------------------------
    // WSTRB bus monitor — captures every write-data beat
    // --------------------------------------------------
    logic [STRB_WIDTH-1:0] captured_wstrb[$];
    logic [STRB_WIDTH-1:0] last_wstrb;
    int wstrb_beat_cnt;

    always @(posedge clk) begin
        if (axi_if_r.wvalid && axi_if_r.wready) begin
            captured_wstrb.push_back(axi_if_r.wstrb);
            wstrb_beat_cnt <= wstrb_beat_cnt + 1;
            $display("[%0t] WSTRB monitor: beat=%0d wstrb=%b wlast=%b",
                     $time, wstrb_beat_cnt + 1, axi_if_r.wstrb, axi_if_r.wlast);
            if (axi_if_r.wlast)
                last_wstrb <= axi_if_r.wstrb;
        end
    end

    // --------------------------------------------------
    // calc_expected_wstrb
    //   Returns the expected strobe for the last beat of
    //   a transfer of byte_count bytes.
    // --------------------------------------------------
    function automatic logic [STRB_WIDTH-1:0] calc_expected_wstrb(input int byte_count);
        int last_bytes = byte_count % STRB_WIDTH;
        return (last_bytes == 0) ? FULL_STRB
                                 : (STRB_WIDTH'(1) << last_bytes) - STRB_WIDTH'(1);
    endfunction

    // --------------------------------------------------
    // verify_all_wstrb
    //   Checks the captured_wstrb queue against expected:
    //     - All beats except the last: FULL_STRB
    //     - Last beat: calc_expected_wstrb(test_num_bytes)
    //   Returns error count.
    // --------------------------------------------------
    function automatic int verify_all_wstrb(
        input int                          test_num_bytes,
        input logic [STRB_WIDTH-1:0]       wstrb_queue[$]);

        int errors      = 0;
        int total_beats = (test_num_bytes + STRB_WIDTH - 1) / STRB_WIDTH;
        logic [STRB_WIDTH-1:0] expected_strb;

        $display("[VERIFY_WSTRB] expected %0d beats, captured %0d",
                 total_beats, wstrb_queue.size());

        if (wstrb_queue.size() != total_beats) begin
            $error("[VERIFY_WSTRB] beat count mismatch: expected=%0d got=%0d",
                   total_beats, wstrb_queue.size());
            errors++;
        end

        for (int b = 0; b < wstrb_queue.size(); b++) begin
            expected_strb = (b == total_beats - 1) ? calc_expected_wstrb(test_num_bytes)
                                                    : FULL_STRB;
            if (wstrb_queue[b] !== expected_strb) begin
                $error("[VERIFY_WSTRB] beat %0d: expected=%b got=%b",
                       b, expected_strb, wstrb_queue[b]);
                errors++;
            end else
                $display("[VERIFY_WSTRB] beat %0d: wstrb=%b OK", b, wstrb_queue[b]);
        end
        return errors;
    endfunction

    // --------------------------------------------------
    // init_mem
    //   Fills slave memory at [byte_addr .. +num_bytes_i)
    //   with a recognisable per-word pattern.
    // --------------------------------------------------
    task automatic init_mem(input int byte_addr, input int num_bytes_i);
        int start_idx = byte_addr / BPB;
        int num_words = (num_bytes_i + BPB - 1) / BPB;
        for (int i = 0; i < num_words; i++)
            s.mem[start_idx + i] = DATA_WIDTH'(64'hFACE_CAFE_0000_0000)
                                 + DATA_WIDTH'(start_idx + i);
    endtask

    // --------------------------------------------------
    // verify_copy
    //   Compares slave memory at dst to src after a copy.
    //
    //   Full beats    : exact DATA_WIDTH-bit match.
    //   Partial last  : only the low (last_bytes*8) bits
    //                   are checked; the upper bytes were
    //                   written as 0x00 by wstrb masking.
    //
    //   Returns error count.
    // --------------------------------------------------
    function automatic int verify_copy(
        input int src_byte, input int dst_byte, input int num_bytes_i);

        int errors     = 0;
        int src_idx    = src_byte / BPB;
        int dst_idx    = dst_byte / BPB;
        int num_beats  = (num_bytes_i + BPB - 1) / BPB;
        int last_bytes = num_bytes_i % BPB;
        logic [DATA_WIDTH-1:0] mask;

        for (int i = 0; i < num_beats; i++) begin
            mask = (i == num_beats - 1 && last_bytes != 0)
                 ? (DATA_WIDTH'(1) << (last_bytes * 8)) - 1
                 : {DATA_WIDTH{1'b1}};

            if ((s.mem[dst_idx + i] & mask) !== (s.mem[src_idx + i] & mask)) begin
                $error("[%0t] verify_copy: beat %0d src[%0d]=0x%h dst[%0d]=0x%h mask=0x%h",
                       $time, i,
                       src_idx + i, s.mem[src_idx + i] & mask,
                       dst_idx + i, s.mem[dst_idx + i] & mask,
                       mask);
                errors++;
            end
        end

        if (errors == 0)
            $display("[%0t] verify_copy: PASS (%0d beats, %0d bytes, 0x%h->0x%h)",
                     $time, num_beats, num_bytes_i, src_byte, dst_byte);
        return errors;
    endfunction

    // --------------------------------------------------
    // Main test
    // --------------------------------------------------
    initial begin
        len       = 7;                      // AXI AxLEN: len+1 beats per burst request
        size      = $clog2(DATA_WIDTH / 8); // AxSIZE: log2(bytes per beat)
        num_bytes = 256;
        test_type = 3'd1;                   // default: 4KB boundary + partial last beat
        void'($value$plusargs("TESTTYPE=%d", test_type));

        axil_if_lt.init();
        axi_if_r.init();

        axil_m   = new(axil_if_lt);
        cdma_drv = new("cdma_drv", axil_m);
        axil_m.reset();

        s = new(axi_if_r, "s");
        s.reset();
        fork s.run(); join_none

        wait(rst_n);
        repeat(10) @(posedge clk);

        total_errors  = 0;
        wstrb_beat_cnt = 0;

        case (test_type)

            // ------------------------------------------
            // 0: basic aligned copy — full beats only
            //    src=0x0000  dst=0x0800  256 B (32 beats)
            // ------------------------------------------
            3'd0: begin
                src_base  = 32'h0000_0000;
                dst_base  = 32'h0000_0800;
                num_bytes = 256;

                init_mem(src_base, num_bytes);
                captured_wstrb = {};  wstrb_beat_cnt = 0;

                cdma_drv.mem_copy(src_base, dst_base, len, size, num_bytes);

                total_errors += verify_all_wstrb(num_bytes, captured_wstrb);
                total_errors += verify_copy(src_base, dst_base, num_bytes);
            end

            // ------------------------------------------
            // 1: 4KB boundary crossing + partial last beat
            //    src=0x0FF0 (16B before 4K)  dst=0x0200
            //    258 B → 33 beats, last wstrb=0x03
            //
            //    Burst split at 0x1000 boundary:
            //      burst-0: 0x0FF0, len=1 (2 beats, 16B)
            //      burst-1..N: 0x1000+, len=7 (8 beats each)
            //      final burst: remaining bytes, partial last beat
            // ------------------------------------------
            3'd1: begin
                src_base  = 32'h0000_0FF0;
                dst_base  = 32'h0000_0200;
                num_bytes = 258;

                init_mem(src_base, num_bytes);
                captured_wstrb = {};  wstrb_beat_cnt = 0;

                cdma_drv.mem_copy(src_base, dst_base, len, size, num_bytes);

                total_errors += verify_all_wstrb(num_bytes, captured_wstrb);
                total_errors += verify_copy(src_base, dst_base, num_bytes);
            end

            // ------------------------------------------
            // 2: four consecutive copies with verification
            //    frames 0-3 each 64 B, non-overlapping
            // ------------------------------------------
            3'd2: begin
                num_bytes = 64;  // 8 beats per frame
                for (int i = 0; i < 4; i++) begin
                    src_base = i * 32'h100;
                    dst_base = 32'h0800 + i * 32'h100;

                    init_mem(src_base, num_bytes);
                    captured_wstrb = {};  wstrb_beat_cnt = 0;

                    cdma_drv.mem_copy(src_base, dst_base, len, size, num_bytes);

                    total_errors += verify_all_wstrb(num_bytes, captured_wstrb);
                    total_errors += verify_copy(src_base, dst_base, num_bytes);

                    $display("[%0t] frame %0d done cumulative_errors=%0d",
                             $time, i, total_errors);
                end
            end

            // ------------------------------------------
            // 3: abort mid-transfer
            //    transfer is aborted after 20 cycles;
            //    FSM should reach IDLE and pulse ctrl_done
            // ------------------------------------------
            3'd3: begin
                src_base  = 32'h0000_0000;
                dst_base  = 32'h0000_0800;
                num_bytes = 256;

                init_mem(src_base, num_bytes);
                cdma_drv.test_abort(src_base, dst_base, len, size, num_bytes,
                                    .abort_after_cycles(20));
                // No data integrity check — transfer was intentionally incomplete
            end

            // ------------------------------------------
            // default: same as test_type 1
            // ------------------------------------------
            default: begin
                src_base  = 32'h0000_0FF0;
                dst_base  = 32'h0000_0200;
                num_bytes = 258;

                init_mem(src_base, num_bytes);
                captured_wstrb = {};  wstrb_beat_cnt = 0;

                cdma_drv.mem_copy(src_base, dst_base, len, size, num_bytes);

                total_errors += verify_all_wstrb(num_bytes, captured_wstrb);
                total_errors += verify_copy(src_base, dst_base, num_bytes);
            end

        endcase

        repeat(20) @(posedge clk);

        if (total_errors == 0)
            $display("[%0t] test_cdma: ALL TESTS PASSED", $time);
        else
            $error("[%0t] test_cdma: %0d ERROR(S) DETECTED", $time, total_errors);

        $finish;
    end

    initial begin
        #2_000_000 $fatal(1, "test_cdma: simulation timed out");
    end

endmodule : test_cdma

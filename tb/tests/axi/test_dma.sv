`timescale 1ns / 1ps

module test_dma     #(parameter int ADDR_WIDTH = 32,
                      parameter int DATA_WIDTH = 64,
                      parameter int ID_WIDTH   = 4,
                      parameter int USER_WIDTH = 1)
                     (input logic clk,
                      input logic rst_n);
                      import axi_pkg::*;
                      import axi_dma_pkg::*;

    // AXI interface
    axi4_if #(.ADDR_WIDTH(ADDR_WIDTH),
              .DATA_WIDTH(DATA_WIDTH),
              .ID_WIDTH(ID_WIDTH),
              .USER_WIDTH(USER_WIDTH)) 
              // virtual interface
              axi_if_r(.ACLK(clk),
                       .ARESETn(rst_n)),
                // sample interface
             
              axi_if_s(.ACLK(clk),
                        .ARESETn(rst_n));

    // VERILATOR WORKAROUND: Required dummy instantiation
    axis_if #(8, 1) axis_if_t0(clk, rst_n); // need to create this default to get second working
    // work if both instantiated
    axis_if #(.DATA_WIDTH(DATA_WIDTH), .USER_WIDTH(USER_WIDTH)) s_axis_if_t(clk, rst_n);
    axis_if #(.DATA_WIDTH(DATA_WIDTH), .USER_WIDTH(USER_WIDTH)) m_axis_if_t(clk, rst_n);        
    axis_if #(.DATA_WIDTH(DATA_WIDTH), .USER_WIDTH(USER_WIDTH)) s_axis_if_s(clk, rst_n);
    axis_if #(.DATA_WIDTH(DATA_WIDTH), .USER_WIDTH(USER_WIDTH)) m_axis_if_s(clk, rst_n); 
    
    

    always @(posedge clk) begin
        s_axis_if_s.tdata  <= s_axis_if_t.tdata; 
        s_axis_if_s.tvalid <= s_axis_if_t.tvalid;
        s_axis_if_s.tready <= s_axis_if_t.tready;
        s_axis_if_s.tlast  <= s_axis_if_t.tlast;

        m_axis_if_s.tdata  <= m_axis_if_t.tdata; 
        m_axis_if_s.tvalid <= m_axis_if_t.tvalid;
        m_axis_if_s.tready <= m_axis_if_t.tready;
        m_axis_if_s.tlast  <= m_axis_if_t.tlast;
    end
 

    // AXI-Lite interface
    axil_if #(.ADDR_WIDTH(AXIL_ADDR_WIDTH),
              .DATA_WIDTH(AXIL_DATA_WIDTH)) 
              // virtual interface
              axil_if_lt(.ACLK(clk),
                        .ARESETn(rst_n)),
              axil_if_ls(.ACLK(clk),
                        .ARESETn(rst_n));

    axi_slave  #(.ADDR_WIDTH(ADDR_WIDTH),
                 .DATA_WIDTH(DATA_WIDTH),
                 .ID_WIDTH(ID_WIDTH)) s;

     // Master / Slave objects
    axil_master #(.ADDR_WIDTH(AXIL_ADDR_WIDTH),
                  .DATA_WIDTH(AXIL_DATA_WIDTH)) axil_m;

    axi_dma_driver #(.DATA_WIDTH(DATA_WIDTH)) axi_dma_drv;


        snix_axi_dma  #(.ADDR_WIDTH(ADDR_WIDTH),
                        .DATA_WIDTH(DATA_WIDTH),
                        .AXIL_ADDR_WIDTH(AXIL_ADDR_WIDTH),
                        .AXIL_DATA_WIDTH(AXIL_DATA_WIDTH),
                        .ID_WIDTH(ID_WIDTH),
                        .USER_WIDTH(USER_WIDTH))

                axi_dma(.clk(clk),
                        .rst_n(rst_n),

                        .s_axil_awaddr(axil_if_lt.awaddr),
                        .s_axil_awvalid(axil_if_lt.awvalid),
                        .s_axil_awready(axil_if_lt.awready),

                        .s_axil_wdata(axil_if_lt.wdata),
                        .s_axil_wstrb(axil_if_lt.wstrb),
                        .s_axil_wvalid(axil_if_lt.wvalid),
                        .s_axil_wready(axil_if_lt.wready),

                        .s_axil_bresp(axil_if_lt.bresp),
                        .s_axil_bvalid(axil_if_lt.bvalid),
                        .s_axil_bready(axil_if_lt.bready),

                        .s_axil_araddr(axil_if_lt.araddr),
                        .s_axil_arvalid(axil_if_lt.arvalid),
                        .s_axil_arready(axil_if_lt.arready),

                        .s_axil_rdata(axil_if_lt.rdata),
                        .s_axil_rresp(axil_if_lt.rresp),
                        .s_axil_rvalid(axil_if_lt.rvalid),
                        .s_axil_rready(axil_if_lt.rready),

                        .s_axis_tdata(s_axis_if_t.tdata),
                        .s_axis_tvalid(s_axis_if_t.tvalid),
                        .s_axis_tready(s_axis_if_t.tready),
                        .s_axis_tlast(s_axis_if_t.tlast),

                        .m_axis_tdata(m_axis_if_t.tdata),
                        .m_axis_tvalid(m_axis_if_t.tvalid),
                        .m_axis_tready(m_axis_if_t.tready),
                        .m_axis_tlast(m_axis_if_t.tlast),

                        .s2mm_awid(axi_if_r.awid), 
                        .s2mm_awaddr(axi_if_r.awaddr), 
                        .s2mm_awlen(axi_if_r.awlen), 
                        .s2mm_awsize(axi_if_r.awsize), 
                        .s2mm_awburst(axi_if_r.awburst),
                        .s2mm_awlock(axi_if_r.awlock), 
                        .s2mm_awcache(axi_if_r.awcache), 
                        .s2mm_awprot(axi_if_r.awprot), 
                        .s2mm_awqos(axi_if_r.awqos), 
                        .s2mm_awuser(axi_if_r.awuser),
                        .s2mm_awvalid(axi_if_r.awvalid),
                        .s2mm_awready(axi_if_r.awready),

                        .s2mm_wdata(axi_if_r.wdata),
                        .s2mm_wstrb(axi_if_r.wstrb),
                        .s2mm_wlast(axi_if_r.wlast), 
                        .s2mm_wuser(axi_if_r.wuser), 
                        .s2mm_wvalid(axi_if_r.wvalid),
                        .s2mm_wready(axi_if_r.wready),

                        .s2mm_bid(axi_if_r.bid), 
                        .s2mm_bresp(axi_if_r.bresp), 
                        .s2mm_buser(axi_if_r.buser), 
                        .s2mm_bvalid(axi_if_r.bvalid),
                        .s2mm_bready(axi_if_r.bready),

                        .mm2s_arid(axi_if_r.arid), 
                        .mm2s_araddr(axi_if_r.araddr), 
                        .mm2s_arlen(axi_if_r.arlen), 
                        .mm2s_arsize(axi_if_r.arsize), 
                        .mm2s_arburst(axi_if_r.arburst),
                        .mm2s_arlock(axi_if_r.arlock), 
                        .mm2s_arcache(axi_if_r.arcache), 
                        .mm2s_arprot(axi_if_r.arprot), 
                        .mm2s_arqos(axi_if_r.arqos), 
                        .mm2s_aruser(axi_if_r.aruser), 
                        .mm2s_arvalid(axi_if_r.arvalid),
                        .mm2s_arready(axi_if_r.arready),

                        .mm2s_rid(axi_if_r.rid), 
                        .mm2s_rdata(axi_if_r.rdata), 
                        .mm2s_rresp(axi_if_r.rresp), 
                        .mm2s_rlast(axi_if_r.rlast), 
                        .mm2s_ruser(axi_if_r.ruser), 
                        .mm2s_rvalid(axi_if_r.rvalid),
                        .mm2s_rready(axi_if_r.rready)
                        );

    sample_axi_if #(.ADDR_WIDTH(ADDR_WIDTH),
                    .DATA_WIDTH(DATA_WIDTH),
                    .ID_WIDTH(ID_WIDTH),
                    .USER_WIDTH(USER_WIDTH)) 
               sample_axi_if_u0(.axi_if_t(axi_if_r),
                                .axi_if_s(axi_if_s));

     sample_axil_if #(.ADDR_WIDTH(AXIL_ADDR_WIDTH),
                      .DATA_WIDTH(AXIL_DATA_WIDTH))
               sample_axil_if_u0(.axil_if_t(axil_if_lt),
                                 .axil_if_s(axil_if_ls));

    // --------------------------------------------------
    // Protocol checkers
    // --------------------------------------------------
    // AXI4 MM port: DUT is master (drives AW/W/AR, receives B/R)
    axi_mm_checker #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
                     .ID_WIDTH(ID_WIDTH), .LABEL("DMA_MM"))
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

    axi_4k_checker #(.ADDR_WIDTH(ADDR_WIDTH), .LABEL("DMA_4K"))
        u_4k_chk (.clk     (clk),              .rst_n   (rst_n),
                  .awaddr  (axi_if_r.awaddr),  .awlen   (axi_if_r.awlen),
                  .awsize  (axi_if_r.awsize),  .awvalid (axi_if_r.awvalid),
                  .awready (axi_if_r.awready),
                  .araddr  (axi_if_r.araddr),  .arlen   (axi_if_r.arlen),
                  .arsize  (axi_if_r.arsize),  .arvalid (axi_if_r.arvalid),
                  .arready (axi_if_r.arready));

    // AXI-Lite CSR port: DUT is slave
    axil_checker #(.ADDR_WIDTH(AXIL_ADDR_WIDTH), .DATA_WIDTH(AXIL_DATA_WIDTH),
                   .LABEL("DMA_AXIL"))
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

    // AXI-Stream s2mm slave: source drives tdata/tvalid, DUT drives tready
    axis_checker #(.DATA_WIDTH(DATA_WIDTH), .USER_WIDTH(USER_WIDTH),
                   .LABEL("DMA_S2MM"))
        u_s2mm_chk (.clk   (clk),                .rst_n (rst_n),
                    .tdata (s_axis_if_t.tdata),   .tuser (s_axis_if_t.tuser),
                    .tvalid(s_axis_if_t.tvalid),  .tready(s_axis_if_t.tready),
                    .tlast (s_axis_if_t.tlast));

    // AXI-Stream mm2s master: DUT drives tdata/tvalid, sink drives tready
    axis_checker #(.DATA_WIDTH(DATA_WIDTH), .USER_WIDTH(USER_WIDTH),
                   .LABEL("DMA_MM2S"))
        u_mm2s_chk (.clk   (clk),                .rst_n (rst_n),
                    .tdata (m_axis_if_t.tdata),   .tuser (m_axis_if_t.tuser),
                    .tvalid(m_axis_if_t.tvalid),  .tready(m_axis_if_t.tready),
                    .tlast (m_axis_if_t.tlast));

    logic [DATA_WIDTH-1:0] wr_data[];
    logic [DATA_WIDTH-1:0] rd_data[];
    
    // --------------------------------------------------
    // Frame configuration
    // --------------------------------------------------
    int len      = 7;      // AXI len field (beats per req = len+1)
    int size     = $clog2(DATA_WIDTH/8);
    int base;
    int num_bytes;
    
    logic [2:0] test_type;
    logic [AXIL_DATA_WIDTH-1:0] axil_rdata;

    // --------------------------------------------------
    // WSTRB monitoring for test case 4
    // --------------------------------------------------
    localparam int STRB_WIDTH = DATA_WIDTH / 8;
    localparam logic [STRB_WIDTH-1:0] FULL_STRB = {STRB_WIDTH{1'b1}};

    // Captured wstrb values per beat
    logic [STRB_WIDTH-1:0] captured_wstrb[$];
    logic [STRB_WIDTH-1:0] last_wstrb;
    int wstrb_beat_cnt;
    int wstrb_error_cnt;
    int total_strb_errors;

    // Monitor wstrb on each write beat
    always @(posedge clk) begin
        if (axi_if_r.wvalid && axi_if_r.wready) begin
            captured_wstrb.push_back(axi_if_r.wstrb);
            wstrb_beat_cnt <= wstrb_beat_cnt + 1;
            $display("[%0t] WSTRB monitor: beat=%0d wstrb=%b wlast=%b", 
                     $time, wstrb_beat_cnt + 1, axi_if_r.wstrb, axi_if_r.wlast);
            if (axi_if_r.wlast) begin
                last_wstrb <= axi_if_r.wstrb;
                $display("[%0t] WSTRB on LAST beat: %b", $time, axi_if_r.wstrb);
            end
        end
    end

    // Helper function to compute expected wstrb for last beat
    function automatic logic [STRB_WIDTH-1:0] calc_expected_wstrb(int byte_count);
        int last_beat_bytes;
        last_beat_bytes = byte_count % STRB_WIDTH;
        if (last_beat_bytes == 0)
            return FULL_STRB;
        else
            return (STRB_WIDTH'(1) << last_beat_bytes) - STRB_WIDTH'(1);
    endfunction

    // Helper function to verify all captured wstrb values for a transfer
    // Returns number of errors
    function automatic int verify_all_wstrb(
        input int test_num_bytes,
        input logic [STRB_WIDTH-1:0] wstrb_queue[$]
    );
        int errors;
        int total_beats;
        int last_beat_bytes;
        logic [STRB_WIDTH-1:0] expected_strb;
        
        errors = 0;
        total_beats = (test_num_bytes + STRB_WIDTH - 1) / STRB_WIDTH;
        last_beat_bytes = test_num_bytes % STRB_WIDTH;
        if (last_beat_bytes == 0) last_beat_bytes = STRB_WIDTH;
        
        $display("[VERIFY_WSTRB] Expected %0d beats, captured %0d beats", 
                 total_beats, wstrb_queue.size());
        
        if (wstrb_queue.size() != total_beats) begin
            $error("[VERIFY_WSTRB] Beat count mismatch: expected %0d, got %0d",
                   total_beats, wstrb_queue.size());
            errors++;
        end
        
        for (int beat = 0; beat < wstrb_queue.size(); beat++) begin
            // Determine expected strobe for this beat
            if (beat == total_beats - 1)
                expected_strb = calc_expected_wstrb(test_num_bytes);
            else
                expected_strb = FULL_STRB;
            
            if (wstrb_queue[beat] !== expected_strb) begin
                $error("[VERIFY_WSTRB] Beat %0d: expected wstrb=%b, got=%b",
                       beat, expected_strb, wstrb_queue[beat]);
                errors++;
            end else begin
                $display("[VERIFY_WSTRB] Beat %0d: wstrb=%b OK", beat, wstrb_queue[beat]);
            end
        end
        
        return errors;
    endfunction

    initial begin
        //---------------------------------------------
        // Derived sizes
        //---------------------------------------------
        num_bytes = 256; // each burst is 8 beats; each beat 8 bytes; 4 bursts in total

        wr_data = new[1024]; 
        rd_data = new[1024]; 

        s_axis_if_t.init();
        m_axis_if_t.init();
        
        s_axis_if_s.init();
        m_axis_if_s.init();

        axil_if_lt.init();
        $display("axil_test: Init axi-lite interface...;");

        // Create objects
        axil_m = new(axil_if_lt);

        axi_dma_drv = new("axi_dma_drv", axil_m);
        axi_dma_drv.s_axis_vif = s_axis_if_t;
        axi_dma_drv.m_axis_vif = m_axis_if_t;

        
        // Reset master & slave 
        axil_m.reset();

        //---------------------------------------------
        // AXI slave init
        //---------------------------------------------
        axi_if_r.init();
        s = new(axi_if_r, "s");
        s.reset();

        fork
            s.run();
        join_none

        //---------------------------------------------
        // Reset wait
        //---------------------------------------------
        wait(rst_n);
        repeat(10) @(posedge clk);

        
        //---------------------------------------------
        // Initialize write data
        //---------------------------------------------
        for (int i = 0; i < 1024; i++)
            wr_data[i] = 64'hcafe_f00d_0000 + 64'(i);

        base = 0;
        test_type = 3;
        void'($value$plusargs("TESTTYPE=%d", test_type));
        case(test_type)
            3'd0    : begin
                axi_dma_drv.wr_addr      = base;
                axi_dma_drv.wr_len       = len;
                axi_dma_drv.wr_size      = $clog2(DATA_WIDTH/8); 
                axi_dma_drv.wr_num_bytes = num_bytes;
                axi_dma_drv.src_bp_mode  = 1'b1;
                axi_dma_drv.test_wr_abort(wr_data);
            end
            3'd1    : begin
                axi_dma_drv.rd_addr      = base;
                axi_dma_drv.rd_len       = len;
                axi_dma_drv.rd_size      = $clog2(DATA_WIDTH/8); 
                axi_dma_drv.rd_num_bytes = num_bytes;
                axi_dma_drv.src_bp_mode  = 1'b1;
                axi_dma_drv.test_wr_dma(0, base, len, size, num_bytes, wr_data);
                axi_dma_drv.test_rd_abort(rd_data);
            end
            3'd2    : begin
                axi_dma_drv.src_bp_mode  = 1'b1;
                axi_dma_drv.sink_bp_mode = 1'b1;
                for(int i=0; i<4; i++) begin
                    fork
                        axi_dma_drv.test_wr_dma(i, base, len, size, num_bytes, wr_data);
                        axi_dma_drv.test_rd_dma(i, base, len, size, num_bytes, rd_data);
                    join
                end
            end
            3'd3    : begin
                axi_dma_drv.src_bp_mode  = 1'b1;
                axi_dma_drv.sink_bp_mode = 1'b1;

                // Test crossing 4 KB and also write partial bytes
                base      = 32'h0FF0; // this address will cross a 4KB boundary
                num_bytes = 258;      // this transfer length will ensure partial writes with wstrb
                                      // DMA automatically aligns number of beats
                axi_dma_drv.test_wr_dma(0, base, len, size, num_bytes, wr_data);
                axi_dma_drv.test_rd_dma(0, base, len, size, num_bytes, rd_data);
            end
            default : begin
                axi_dma_drv.src_bp_mode  = 1'b1;
                axi_dma_drv.sink_bp_mode = 1'b1;
                axi_dma_drv.test_circular(base, len, size, num_bytes,
                                          3,       // num_wraps (outer k loop)
                                          wr_data, rd_data);
            end
        endcase
        
        repeat(20) @(posedge clk);
        $finish;
    end
    

// Timeout in case of simulation hang
initial begin
    #2000000 $fatal("test_axi: Simulation timed out");
end



endmodule: test_dma

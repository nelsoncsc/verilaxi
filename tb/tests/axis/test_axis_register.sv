`timescale 1ns/1ps

module test_axis_register #(parameter int DATA_WIDTH = 8,
                            parameter  int USER_WIDTH = 1)
                           (input logic clk,
                            input logic rst_n);
                            import axi_pkg::*;


    // Backpressure configuration (from plusargs)
    int src_bp_en;
    int sink_bp_en;

    initial begin
        // Defaults
        src_bp_en  = 0;
        sink_bp_en = 0;

        // Read plusargs
        void'($value$plusargs("SRC_BP=%d",  src_bp_en));
        void'($value$plusargs("SINK_BP=%d", sink_bp_en));

        $display("AXIS ENV: SRC_BP=%0d SINK_BP=%0d",
                 src_bp_en, sink_bp_en);
    end

    // -------------------------------------------------
    // AXIS interfaces
    // -------------------------------------------------
    axis_if #(.DATA_WIDTH(DATA_WIDTH),
              .USER_WIDTH(USER_WIDTH)) 
            axis_src_t(clk, rst_n),
            axis_src_s(clk, rst_n);

    axis_if #(.DATA_WIDTH(DATA_WIDTH),
              .USER_WIDTH(USER_WIDTH)) 
            axis_sink_t(clk, rst_n),
            axis_sink_s(clk, rst_n);
   
    sample_axis_if #(.DATA_WIDTH(DATA_WIDTH),
                     .USER_WIDTH(USER_WIDTH)) 
               sample_axis_src_if(.axis_if_t(axis_src_t),
                                  .axis_if_s(axis_src_s));

    sample_axis_if #(.DATA_WIDTH(DATA_WIDTH),
                     .USER_WIDTH(USER_WIDTH)) 
               sample_axis_sink_if(.axis_if_t(axis_sink_t),
                                   .axis_if_s(axis_sink_s));

    // -------------------------------------------------
    // AXIS Register
    // ------------------------------------------------- 
    snix_axis_register #(.DATA_WIDTH(DATA_WIDTH),
                         .USER_WIDTH(USER_WIDTH))                  
                         axis_reg_u0 (.clk(clk),
                                      .rst_n(rst_n),
                                      .s_axis_tdata(axis_src_s.tdata),
                                      .s_axis_tuser(axis_src_s.tuser),
                                      .s_axis_tlast(axis_src_s.tlast),
                                      .s_axis_tvalid(axis_src_s.tvalid),
                                      .s_axis_tready(axis_src_t.tready),

                                      .m_axis_tdata(axis_sink_t.tdata),
                                      .m_axis_tuser(axis_sink_t.tuser),
                                      .m_axis_tlast(axis_sink_t.tlast),
                                      .m_axis_tvalid(axis_sink_t.tvalid),
                                      .m_axis_tready(axis_sink_s.tready)
                                     );

    // -------------------------------------------------
    // AXI-Stream protocol checkers
    // -------------------------------------------------
    // Slave port: verify source BFM drives a compliant stream into the DUT
    axis_checker #(.DATA_WIDTH(DATA_WIDTH), .USER_WIDTH(USER_WIDTH),
                   .LABEL("AXIS_REG_SLV"))
        u_slv_chk (.clk    (clk),
                   .rst_n  (rst_n),
                   .tdata  (axis_src_s.tdata),
                   .tuser  (axis_src_s.tuser),
                   .tvalid (axis_src_s.tvalid),
                   .tready (axis_src_t.tready),
                   .tlast  (axis_src_s.tlast));

    // Master port: verify DUT output is a compliant AXI-Stream
    axis_checker #(.DATA_WIDTH(DATA_WIDTH), .USER_WIDTH(USER_WIDTH),
                   .LABEL("AXIS_REG_MST"))
        u_mst_chk (.clk    (clk),
                   .rst_n  (rst_n),
                   .tdata  (axis_sink_t.tdata),
                   .tuser  (axis_sink_t.tuser),
                   .tvalid (axis_sink_t.tvalid),
                   .tready (axis_sink_s.tready),
                   .tlast  (axis_sink_t.tlast));

    // -------------------------------------------------
    // AXIS BFMs (classes)
    // -------------------------------------------------
    axis_source #(DATA_WIDTH, USER_WIDTH)  src_bfm;
    axis_sink                              sink_bfm;
    axis_connect                           conn;
    axis_driver                            driver;



    // -------------------------------------------------
    // Test sequence
    // -------------------------------------------------

    initial begin
        axis_src_t.init();
        axis_sink_t.init();
        // Create BFMs
        src_bfm  = new(axis_src_t);
        sink_bfm = new(axis_sink_t);
        driver   = new(src_bfm, sink_bfm);  
        conn     = new(axis_src_t, axis_sink_t); 
       
        src_bfm.backpressure  = src_bp_en;
        sink_bfm.backpressure = sink_bp_en;
        
        // Wait for reset release
        @(negedge rst_n);
        @(posedge rst_n);
        repeat (2) @(posedge clk);

        fork
            conn.passthrough();
        join_none
        
        driver.send_and_recv(10, 2);
        driver.send_and_recv(8, 1);
        driver.send_and_recv(4, 1);

        repeat (5) @(posedge clk);
        $finish;
    end

    // -------------------------------------------------
    // Safety watchdog (never hang)
    // -------------------------------------------------
    initial begin
        #1_000_000;
        $fatal("test_axis_register: simulation timeout");
    end

endmodule: test_axis_register
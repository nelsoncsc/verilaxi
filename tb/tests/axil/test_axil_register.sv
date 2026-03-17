`timescale 1ns / 1ps

module test_axil_register #(parameter int ADDR_WIDTH = 32,
                            parameter int DATA_WIDTH = 32)
                           (input logic clk,
                            input logic rst_n);
                            import axi_pkg::*;

    // AXI interface
    axil_if #(.ADDR_WIDTH(ADDR_WIDTH),
              .DATA_WIDTH(DATA_WIDTH)) 
              // virtual interface
              axil_if_t(.ACLK(clk),
                        .ARESETn(rst_n)),
                // sample interface
                // issue: https://github.com/verilator/verilator/issues/5044     
              axil_if_s(.ACLK(clk),
                        .ARESETn(rst_n));


    localparam USE_DUT = 1; // set to: 1 to use dut; 0 to use vip
    generate
        if(USE_DUT) begin: USE_DUT_AXIL_REG
            initial $info("Instantiated axil_slave dut.");
            
            localparam NUM_REGS = 16;

            logic [NUM_REGS-1:0][DATA_WIDTH-1:0] config_status_reg;
            snix_axil_register #(.DATA_WIDTH(DATA_WIDTH),
                                .ADDR_WIDTH(ADDR_WIDTH),
                                .NUM_REGS(NUM_REGS)) 
                            csr_axil   (.clk(clk),
                                        .rst_n(rst_n),

                                        .s_axil_awaddr(axil_if_t.awaddr),
                                        .s_axil_awvalid(axil_if_t.awvalid),
                                        .s_axil_awready(axil_if_t.awready),

                                        .s_axil_wdata(axil_if_t.wdata),
                                        .s_axil_wstrb(axil_if_t.wstrb),
                                        .s_axil_wvalid(axil_if_t.wvalid),
                                        .s_axil_wready(axil_if_t.wready),

                                        .s_axil_bresp(axil_if_t.bresp),
                                        .s_axil_bvalid(axil_if_t.bvalid),
                                        .s_axil_bready(axil_if_t.bready),

                                        .s_axil_araddr(axil_if_t.araddr),
                                        .s_axil_arvalid(axil_if_t.arvalid),
                                        .s_axil_arready(axil_if_t.arready),

                                        .s_axil_rdata(axil_if_t.rdata),
                                        .s_axil_rresp(axil_if_t.rresp),
                                        .s_axil_rvalid(axil_if_t.rvalid),
                                        .s_axil_rready(axil_if_t.rready),

                                        .config_status_reg(config_status_reg)
                                    );
        end
    endgenerate

    sample_axil_if #(.ADDR_WIDTH(ADDR_WIDTH),
                    .DATA_WIDTH(DATA_WIDTH))
               sample_axil_if_u0(.axil_if_t(axil_if_t),
                                 .axil_if_s(axil_if_s));

    // -------------------------------------------------
    // AXI-Lite protocol checker
    // -------------------------------------------------
    axil_checker #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
                   .LABEL("AXIL_REG"))
        u_axil_chk (.clk    (clk),             .rst_n   (rst_n),
                    .awaddr (axil_if_t.awaddr), .awvalid (axil_if_t.awvalid),
                    .awready(axil_if_t.awready),
                    .wdata  (axil_if_t.wdata),  .wstrb   (axil_if_t.wstrb),
                    .wvalid (axil_if_t.wvalid), .wready  (axil_if_t.wready),
                    .bresp  (axil_if_t.bresp),  .bvalid  (axil_if_t.bvalid),
                    .bready (axil_if_t.bready),
                    .araddr (axil_if_t.araddr), .arvalid (axil_if_t.arvalid),
                    .arready(axil_if_t.arready),
                    .rdata  (axil_if_t.rdata),  .rresp   (axil_if_t.rresp),
                    .rvalid (axil_if_t.rvalid), .rready  (axil_if_t.rready));

    // Master / Slave objects
    axil_master #(.ADDR_WIDTH(ADDR_WIDTH),
                 .DATA_WIDTH(DATA_WIDTH)) m;

    axil_slave  #(.ADDR_WIDTH(ADDR_WIDTH),
                  .DATA_WIDTH(DATA_WIDTH)) s;

    axil_driver  #(.ADDR_WIDTH(ADDR_WIDTH),
                   .DATA_WIDTH(DATA_WIDTH)) 
                 driver;

    // Test data arrays
    logic [DATA_WIDTH-1:0] wr_data[];
    logic [DATA_WIDTH-1:0] rd_data[];
    int burst_len;

    initial begin
        axil_if_t.init();
        $display("axil_test: Init axi-lite interface...;");
        
        // Create objects
        m = new(axil_if_t);
          
        if(!USE_DUT) begin
            $info("Created axil_slave vip.");
            s = new(axil_if_t);
            s.reset();
        end
       
        driver = new(m);

        // Reset master & slave 
        m.reset();
       
        #10

        if(!USE_DUT) begin
        // Ensure slave starts driving ready/response signals properly
            fork
                s.run();
            join_none
        end
        
        // Wait for reset deassertion
        wait (rst_n == 1);
        @(posedge clk);

        // Initialize write and read data
        burst_len = 4;
        wr_data = new[burst_len];
        rd_data = new[burst_len];
        
        for(int i=0; i<burst_len; i++) begin
            wr_data[i] = 10*i;
        end
        driver.write_read_check(32'h100, wr_data, rd_data, burst_len);

        repeat(2) @(posedge clk);

        for(int i=0; i<burst_len; i++) begin
            wr_data[i] = 20*i;
        end
        driver.write_read_check(32'h100, wr_data, rd_data, burst_len);

        #20 $finish;
    end

    // Timeout in case of simulation hang
    initial begin
        #1000000 $fatal("test_axil_register: Simulation timed out");
    end

endmodule: test_axil_register

module sample_axil_if #(parameter int ADDR_WIDTH = 32,
                        parameter int DATA_WIDTH = 32)
                       (axil_if #(.ADDR_WIDTH(ADDR_WIDTH),
                                  .DATA_WIDTH(DATA_WIDTH)) axil_if_t,
 
                        axil_if #(.ADDR_WIDTH(ADDR_WIDTH),
                                  .DATA_WIDTH(DATA_WIDTH)) axil_if_s);

    always_ff @(posedge axil_if_t.ACLK or negedge axil_if_t.ARESETn)
        if(!axil_if_t.ARESETn) begin
            // AW
            axil_if_s.awaddr   <= {ADDR_WIDTH{1'b0}};
            axil_if_s.awvalid  <= 1'b0;
            axil_if_s.awready  <= 1'b0;

            // W
            axil_if_s.wdata   <= {DATA_WIDTH{1'b0}};
            axil_if_s.wstrb   <= {(DATA_WIDTH/8){1'b0}};
            axil_if_s.wvalid  <= 1'b0;
            axil_if_s.wready  <= 1'b0;

            // B
            axil_if_s.bresp   <= 2'b0;
            axil_if_s.bvalid  <= 1'b0;
            axil_if_s.bready  <= 1'b0;

            // AR
            axil_if_s.araddr  <= {ADDR_WIDTH{1'b0}};
            axil_if_s.arvalid <= 1'b0;
            axil_if_s.arready <= 1'b0;

            // R
            axil_if_s.rdata   <= {DATA_WIDTH{1'b0}};
            axil_if_s.rresp   <= 2'b0;
            axil_if_s.rvalid  <= 1'b0;
            axil_if_s.rready  <= 1'b0;
        end
        else begin
           // AW
            axil_if_s.awaddr   <= axil_if_t.awaddr;
            axil_if_s.awvalid  <= axil_if_t.awvalid;
            axil_if_s.awready  <= axil_if_t.awready;

            // W
            axil_if_s.wdata   <= axil_if_t.wdata;
            axil_if_s.wstrb   <= axil_if_t.wstrb;
            axil_if_s.wvalid  <= axil_if_t.wvalid;
            axil_if_s.wready  <= axil_if_t.wready;

            // B
            axil_if_s.bresp   <= axil_if_t.bresp;
            axil_if_s.bvalid  <= axil_if_t.bvalid;
            axil_if_s.bready  <= axil_if_t.bready;

            // AR
            axil_if_s.araddr   <= axil_if_t.araddr;
            axil_if_s.arvalid  <= axil_if_t.arvalid;
            axil_if_s.arready  <= axil_if_t.arready;

            // R
            axil_if_s.rdata   <= axil_if_t.rdata;
            axil_if_s.rresp   <= axil_if_t.rresp;
            axil_if_s.rvalid  <= axil_if_t.rvalid;
            axil_if_s.rready  <= axil_if_t.rready;
        end

endmodule: sample_axil_if
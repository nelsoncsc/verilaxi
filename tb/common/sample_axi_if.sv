module sample_axi_if #(parameter int ADDR_WIDTH = 32,
                       parameter int DATA_WIDTH = 64,
                       parameter int ID_WIDTH   = 4,
                       parameter int USER_WIDTH = 1)
                      (axi4_if #(.ADDR_WIDTH(ADDR_WIDTH),
                                 .DATA_WIDTH(DATA_WIDTH),
                                 .ID_WIDTH(ID_WIDTH),
                                 .USER_WIDTH(USER_WIDTH)) axi_if_t,

                       axi4_if #(.ADDR_WIDTH(ADDR_WIDTH),
                                 .DATA_WIDTH(DATA_WIDTH),
                                 .ID_WIDTH(ID_WIDTH),
                                 .USER_WIDTH(USER_WIDTH)) axi_if_s);

    always_ff @(posedge axi_if_t.ACLK or negedge axi_if_t.ARESETn)
        if(!axi_if_t.ARESETn) begin
            // AW
            axi_if_s.awid     <= {ID_WIDTH{1'b0}};
            axi_if_s.awaddr   <= {ADDR_WIDTH{1'b0}};
            axi_if_s.awlen    <= 8'b0;
            axi_if_s.awsize   <= 3'b0;
            axi_if_s.awburst  <= 2'b0;
            axi_if_s.awlock   <= 1'b0;
            axi_if_s.awcache  <= 4'b0;
            axi_if_s.awprot   <= 3'b0;
            axi_if_s.awqos    <= 4'b0;
            axi_if_s.awuser   <= {USER_WIDTH{1'b0}};
            axi_if_s.awvalid  <= 1'b0;
            axi_if_s.awready  <= 1'b0;

            // W
            axi_if_s.wdata   <= {DATA_WIDTH{1'b0}};
            axi_if_s.wstrb   <= {(DATA_WIDTH/8){1'b0}};
            axi_if_s.wlast   <= 1'b0;
            axi_if_s.wuser   <= {USER_WIDTH{1'b0}};
            axi_if_s.wvalid  <= 1'b0;
            axi_if_s.wready  <= 1'b0;

            // B
            axi_if_s.bid     <= {ID_WIDTH{1'b0}};
            axi_if_s.bresp   <= 2'b0;
            axi_if_s.buser   <= {USER_WIDTH{1'b0}};
            axi_if_s.bvalid  <= 1'b0;
            axi_if_s.bready  <= 1'b0;

            // AR
            axi_if_s.arid    <= {ID_WIDTH{1'b0}};
            axi_if_s.araddr  <= {ADDR_WIDTH{1'b0}};
            axi_if_s.arlen   <= 8'b0;
            axi_if_s.arsize  <= 3'b0;
            axi_if_s.arburst <= 2'b0;
            axi_if_s.arlock  <= 1'b0;
            axi_if_s.arcache <= 4'b0;
            axi_if_s.arprot  <= 3'b0;
            axi_if_s.arqos   <= 4'b0;
            axi_if_s.aruser  <= {USER_WIDTH{1'b0}};
            axi_if_s.arvalid <= 1'b0;
            axi_if_s.arready <= 1'b0;

            // R
            axi_if_s.rid     <= {ID_WIDTH{1'b0}};
            axi_if_s.rdata   <= {DATA_WIDTH{1'b0}};
            axi_if_s.rresp   <= 2'b0;
            axi_if_s.rlast   <= 1'b0;
            axi_if_s.ruser   <= {USER_WIDTH{1'b0}};
            axi_if_s.rvalid  <= 1'b0;
            axi_if_s.rready  <= 1'b0;
        end
        else begin
           // AW
            axi_if_s.awid     <= axi_if_t.awid;
            axi_if_s.awaddr   <= axi_if_t.awaddr;
            axi_if_s.awlen    <= axi_if_t.awlen;
            axi_if_s.awsize   <= axi_if_t.awsize;
            axi_if_s.awburst  <= axi_if_t.awburst;
            axi_if_s.awlock   <= axi_if_t.awlock;
            axi_if_s.awcache  <= axi_if_t.awcache;
            axi_if_s.awprot   <= axi_if_t.awprot;
            axi_if_s.awqos    <= axi_if_t.awqos;
            axi_if_s.awuser   <= axi_if_t.awuser;
            axi_if_s.awvalid  <= axi_if_t.awvalid;
            axi_if_s.awready  <= axi_if_t.awready;

            // W
            axi_if_s.wdata   <= axi_if_t.wdata;
            axi_if_s.wstrb   <= axi_if_t.wstrb;
            axi_if_s.wlast   <= axi_if_t.wlast;
            axi_if_s.wuser   <= axi_if_t.wuser;
            axi_if_s.wvalid  <= axi_if_t.wvalid;
            axi_if_s.wready  <= axi_if_t.wready;

            // B
            axi_if_s.bid     <= axi_if_t.bid;
            axi_if_s.bresp   <= axi_if_t.bresp;
            axi_if_s.buser   <= axi_if_t.buser;
            axi_if_s.bvalid  <= axi_if_t.bvalid;
            axi_if_s.bready  <= axi_if_t.bready;

            // AR
            axi_if_s.arid     <= axi_if_t.arid;
            axi_if_s.araddr   <= axi_if_t.araddr;
            axi_if_s.arlen    <= axi_if_t.arlen;
            axi_if_s.arsize   <= axi_if_t.arsize;
            axi_if_s.arburst  <= axi_if_t.arburst;
            axi_if_s.arlock   <= axi_if_t.arlock;
            axi_if_s.arcache  <= axi_if_t.arcache;
            axi_if_s.arprot   <= axi_if_t.arprot;
            axi_if_s.arqos    <= axi_if_t.arqos;
            axi_if_s.aruser   <= axi_if_t.aruser;
            axi_if_s.arvalid  <= axi_if_t.arvalid;
            axi_if_s.arready  <= axi_if_t.arready;

            // R
            axi_if_s.rid     <= axi_if_t.rid;
            axi_if_s.rdata   <= axi_if_t.rdata;
            axi_if_s.rresp   <= axi_if_t.rresp;
            axi_if_s.rlast   <= axi_if_t.rlast;
            axi_if_s.ruser   <= axi_if_t.ruser;
            axi_if_s.rvalid  <= axi_if_t.rvalid;
            axi_if_s.rready  <= axi_if_t.rready;
        end

endmodule: sample_axi_if
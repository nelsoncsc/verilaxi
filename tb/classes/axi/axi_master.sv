class axi_master #(parameter int ADDR_WIDTH = 32,
                       parameter int DATA_WIDTH = 64,
                       /* verilator lint_off UNUSEDPARAM */
                       parameter int ID_WIDTH = 4
                       /* verilator lint_on UNUSEDPARAM */);
                       
        virtual axi4_if.master vif;

        function new(virtual axi4_if.master axi_vif);
            this.vif = axi_vif;
        endfunction: new

        task reset();
            vif.awvalid <= 0;
            vif.wvalid  <= 0;
            vif.bready  <= 0;
            vif.arvalid <= 0;
            vif.rready  <= 0;
            vif.wlast   <= 0;
        endtask

        task write_burst(input logic [ADDR_WIDTH-1:0] addr,
                         ref   logic [DATA_WIDTH-1:0] data[],
                         input int unsigned beats);
            
            // AW channel
            vif.awaddr  = addr;
            vif.awlen   = beats - 1;
            vif.awsize  = $clog2(DATA_WIDTH/8);
            vif.awburst = 2'b01;
           
            vif.awvalid = 1;
            do @(posedge vif.ACLK); while (!vif.awready);
            vif.awvalid = 0;

            // ✅ ASSERT BREADY EARLY
            vif.bready = 1;


            // W channel
            for (int i = 0; i < beats; i++) begin
                vif.wdata  = data[i];
                vif.wstrb  = '1;
                vif.wlast  = (i == beats-1);
                vif.wvalid = 1;
                
                @(posedge vif.ACLK);
                while (!vif.wready) @(posedge vif.ACLK);
                
                vif.wvalid = 0;
                vif.wlast  = 0;
            end
            
            // B channel
            @(posedge vif.ACLK);
            $info("B handshake completed");
            vif.bready = 0;

        endtask: write_burst

        task read_burst(input  logic [ADDR_WIDTH-1:0] start_addr,
                        ref    logic [DATA_WIDTH-1:0] data[],
                        input  int unsigned beats);
            int i;
            // AR channel
            vif.arid    = '0;
            vif.araddr  = start_addr;
            vif.arlen   = beats - 1;
            vif.arsize  = $clog2(DATA_WIDTH/8);
            vif.arburst = 2'b01;
            vif.arvalid = 1;
            @(posedge vif.ACLK);
            while (!vif.arready) @(posedge vif.ACLK);
            vif.arvalid = 0;

            // R channel
            vif.rready = 1;
            for (i = 0; i < beats; i++) begin
                wait(vif.rvalid);
                data[i] = vif.rdata;
                @(posedge vif.ACLK);
            end
            vif.rready = 0;
        endtask: read_burst

endclass: axi_master
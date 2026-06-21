class axil_master  #(parameter int ADDR_WIDTH = 32,
                    parameter int DATA_WIDTH = 32);

        virtual axil_if.master vif;

        function new(virtual axil_if.master axil_vif);
            this.vif = axil_vif;
        endfunction: new

        // Reset master signals
        task reset();
            vif.awvalid = 0;
            vif.wvalid  = 0;
            vif.wstrb   = 0;
            vif.bready  = 0;
            vif.arvalid = 0;
            vif.rready  = 0;
        endtask: reset

        // Single AXI-Lite Write
        task write(input logic [ADDR_WIDTH-1:0] addr,
                   input logic [DATA_WIDTH-1:0] data,
                   input logic [DATA_WIDTH/8-1:0] strb = {DATA_WIDTH/8{1'b1}});

            // -----------------------------
            // Write Address Channel (AW)
            // -----------------------------
            @(negedge vif.ACLK);
            vif.awaddr  = addr;
            vif.awvalid = 1;
            do @(posedge vif.ACLK); while (!vif.awready);
            @(negedge vif.ACLK);
            vif.awvalid = 0;

            // -----------------------------
            // Write Data Channel (W)
            // -----------------------------
            vif.wdata  = data;
            vif.wstrb  = strb;
            vif.wvalid = 1;
            do @(posedge vif.ACLK); while (!vif.wready);
            @(negedge vif.ACLK);
            vif.wvalid = 0;

            // -----------------------------
            // Write Response Channel (B)
            // -----------------------------
            vif.bready = 1;
            do @(posedge vif.ACLK); while (!vif.bvalid);
            if (vif.bresp !== 2'b00) begin
                $fatal(1, "axil_m: BRESP error %b on write to %h", vif.bresp, addr);
            end
            @(negedge vif.ACLK);
            vif.bready = 0;

            $info("axil_m: wrote %h (wstrb=%h)", data, strb);
        endtask: write

        
        // Single AXI-Lite Read
        task read(input  logic [ADDR_WIDTH-1:0] addr,
                  output logic [DATA_WIDTH-1:0] data);
       
            // Issue read address away from the sampling edge.
            @(negedge vif.ACLK);
            vif.araddr  = addr;
            vif.arvalid = 1'b1;
            do @(posedge vif.ACLK); while (!vif.arready);
            @(negedge vif.ACLK);
            vif.arvalid = 0;

            // Assert READY before the edge and sample data on the handshake.
            vif.rready = 1;
            do @(posedge vif.ACLK); while (!vif.rvalid);
            if (vif.rresp !== 2'b00) begin
                $fatal(1, "axil_m: RRESP error %b on read from %h", vif.rresp, addr);
            end
            data = vif.rdata;
            @(negedge vif.ACLK);
            vif.rready = 0;

            $info("axil_m: read %h from addr %h", data, addr);
        endtask: read

endclass: axil_master

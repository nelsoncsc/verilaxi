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
            vif.awaddr  <= addr;
            vif.awvalid <= 1;
            @(posedge vif.ACLK);
            while (!vif.awready) @(posedge vif.ACLK); // wait slave
            vif.awvalid <= 0;

            // -----------------------------
            // Write Data Channel (W)
            // -----------------------------
            vif.wdata  <= data;
            vif.wstrb  <= strb;
            vif.wvalid <= 1;
            @(posedge vif.ACLK);
            while (!vif.wready) @(posedge vif.ACLK); // wait slave handshake
            vif.wvalid <= 0;

            // -----------------------------
            // Write Response Channel (B)
            // -----------------------------
            vif.bready <= 1;
            @(posedge vif.ACLK);
            while (!vif.bvalid) @(posedge vif.ACLK); // wait slave
            if (vif.bresp !== 2'b00) begin
                $fatal(1, "axil_m: BRESP error %b on write to %h", vif.bresp, addr);
            end
            vif.bready <= 0;

            $info("axil_m: wrote %h (wstrb=%h)", data, strb);
        endtask: write

        
        // Single AXI-Lite Read
        task read(input  logic [ADDR_WIDTH-1:0] addr,
                  output logic [DATA_WIDTH-1:0] data);
       
            // Issue read address
            vif.araddr  = addr;
            vif.arvalid = 1'b1;
            @(posedge vif.ACLK);
            while (!vif.arready) @(posedge vif.ACLK);
            vif.arvalid = 0;

            // Wait for read data valid
            @(posedge vif.ACLK);
            while (!vif.rvalid) @(posedge vif.ACLK);

            // Handshake: tell slave we are ready to take data
            vif.rready = 1;
            @(posedge vif.ACLK);
            if (vif.rresp !== 2'b00) begin
                $fatal(1, "axil_m: RRESP error %b on read from %h", vif.rresp, addr);
            end
            data = vif.rdata;       // Capture the data during handshake
            vif.rready = 0;

            $info("axil_m: read %h from addr %h", data, addr);
        endtask: read

endclass: axil_master

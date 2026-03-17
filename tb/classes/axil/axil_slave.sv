class axil_slave #(parameter int ADDR_WIDTH = 32,
                       parameter int DATA_WIDTH = 32,
                       parameter int MEM_DEPTH  = 1024);

        virtual axil_if.slave vif;

        logic [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];

        logic [ADDR_WIDTH-1:0] awaddr_latched;
        bit aw_handshake_done;
        bit w_handshake_done;

        function new(virtual axil_if.slave axil_vif);
            this.vif = axil_vif;
        endfunction: new

        task reset();
            vif.awready = 0;
            vif.wready  = 0;
            vif.bvalid  = 0;
            vif.arready = 0;
            vif.rvalid  = 0;
            aw_handshake_done = 0;
            w_handshake_done  = 0;
        endtask: reset

        task run();
            forever @(posedge vif.ACLK) begin
                // -----------------------------
                // WRITE ADDRESS CHANNEL
                // -----------------------------
                if (vif.awvalid && !aw_handshake_done) begin
                    awaddr_latched = vif.awaddr;
                    vif.awready    = 1;
                end else begin
                    vif.awready    = 0;
                end

                // -----------------------------
                // WRITE DATA CHANNEL
                // -----------------------------
                if (vif.wvalid && vif.wready == 0) begin
                    $info("wrote to mem %b", vif.wvalid);
                    vif.wready = 1;
                    mem[awaddr_latched[ADDR_WIDTH-1:2]] = vif.wdata; // blocking
                    aw_handshake_done = 1;
                end else begin
                    vif.wready = 0;
                end

                // -----------------------------
                // WRITE RESPONSE CHANNEL
                // -----------------------------
                if (aw_handshake_done) begin
                    vif.bvalid <= 1;
                    if (vif.bready) begin
                        aw_handshake_done = 0;
                        vif.bvalid = 0;
                    end
                end

                // -----------------------------
                // READ CHANNEL
                // -----------------------------
                if (vif.arvalid) begin
                    vif.arready <= 1;
                    vif.rdata  <= mem[vif.araddr[ADDR_WIDTH-1:2]];
                    vif.rvalid <= 1;
                end else begin
                    vif.arready <= 0;
                end

                if (vif.rvalid && vif.rready)
                    vif.rvalid <= 0;
            end
        endtask: run

endclass: axil_slave
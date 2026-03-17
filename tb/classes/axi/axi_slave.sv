class axi_slave #(parameter int ADDR_WIDTH = 32,
                      parameter int DATA_WIDTH = 64,
                      /* verilator lint_off UNUSEDPARAM */
                      parameter int ID_WIDTH = 4,
                      /* verilator lint_on UNUSEDPARAM */
                      parameter int MEM_DEPTH = 1024);

        virtual axi4_if.slave vif;
        string name;

        logic [DATA_WIDTH-1:0] mem [0:MEM_DEPTH-1];

        // Debug buffer visible in waveform
        logic [DATA_WIDTH-1:0] dbg_slice [0:255];  // max 256 beats
        int unsigned dbg_slice_len;

        logic [ADDR_WIDTH-1:0] wr_addr;
        logic [ADDR_WIDTH-1:0] rd_addr;
        logic [DATA_WIDTH-1:0] rd_data;
        logic [ADDR_WIDTH-1:0] beat_addr;
        logic [2:0]            wr_size;
        logic [2:0]            rd_size;
        logic                  rd_last;
        logic [ID_WIDTH-1:0]   rd_id;



        int unsigned wr_beats_left;
        int unsigned rd_beats_left;
        int unsigned mem_index;
        
        int bytes_per_beat;
        int word_index;
        int byte_offset;
        logic [DATA_WIDTH-1:0] mask;
                    

        bit wr_resp_pending;

        // 0–100: probability (%) that a ready signal asserts on any given cycle.
        // 100 = always ready (no backpressure). Set before calling run(), or
        // override via +READY_PROB=N plusarg.
        int ready_prob = 100;

        function new(virtual axi4_if.slave axi_vif, string obj_name = "axi_slave");
            this.vif  = axi_vif;
            this.name = obj_name;
        endfunction: new

        // Returns 1 with probability ready_prob%.
        // Called once per ready signal per clock edge.
        function automatic bit rand_ready();
            if (ready_prob >= 100) return 1'b1;
            if (ready_prob <= 0)   return 1'b0;
            return ($urandom_range(99, 0) < ready_prob);
        endfunction: rand_ready

        task reset();
            vif.awready <= 0;
            vif.wready  <= 0;
            vif.bvalid  <= 0;
            vif.arready <= 0;
            vif.rvalid  <= 0;
            vif.rlast   <= 0;

            wr_beats_left   = 0;
            rd_beats_left   = 0;
            wr_resp_pending = 0;
            wr_size         = 0;
            rd_size         = 0;
        endtask: reset

        // --------------------------------------------------
        // AXI SLAVE RUN LOOP
        // --------------------------------------------------
        task run();
            void'($value$plusargs("READY_PROB=%d", ready_prob));
            forever @(posedge vif.ACLK) begin
                // -----------------------------
                // WRITE ADDRESS CHANNEL (AW)
                // -----------------------------
                // Only claim a new write transaction if none is active
                if (vif.awvalid && wr_beats_left == 0 && rand_ready()) begin
                    $info("%s: run: AW received, addr=%h, len=%0d, size=%d", this.name, vif.awaddr, vif.awlen, vif.awsize);
                    wr_addr       = vif.awaddr;
                    wr_beats_left = int'(vif.awlen) + 1;
                    wr_size       = vif.awsize;
                    vif.awready   <= 1;
                end
                else begin
                    vif.awready <= 0;
                end

                // -----------------------------
                // WRITE DATA CHANNEL (W)
                // -----------------------------
                // Assert WREADY when data is expected; randomly deassert when ready_prob < 100
                vif.wready <= (wr_beats_left > 0) && rand_ready();

                // Only transfer when both valid and readyx
                if (vif.wvalid && vif.wready) begin
                    bytes_per_beat = 1 << wr_size;   // awsize -> bytes per beat
                    
                    // Compute memory index and byte offset
                    mem_index   = wr_addr / (DATA_WIDTH/8);
                    byte_offset = wr_addr % (DATA_WIDTH/8);

                    // Prepare mask for merging only the valid bytes
                    mask = ({DATA_WIDTH{1'b1}} >> (DATA_WIDTH - bytes_per_beat*8)) << (byte_offset*8);

                    // Merge write data into memory
                    mem[mem_index] = (mem[mem_index] & ~mask) | ((vif.wdata << (byte_offset*8)) & mask);

                    $info("%s, writing %0d bytes @0x%h -> mem[%0d]=%h, wlast=%b",
                        this.name, bytes_per_beat, wr_addr, mem_index, mem[mem_index], vif.wlast);

                    // Increment address
                    wr_addr = wr_addr + bytes_per_beat;

                    // Decrement beats left
                    wr_beats_left = wr_beats_left > 0 && !vif.wlast ? wr_beats_left - 1 : 0;

                    // WLAST
                    if (vif.wlast) begin
                        wr_resp_pending = 1;
                        $info("%s: WLAST detected, wr_resp_pending=1", this.name);
                    end
                end

                
                // -----------------------------
                // WRITE RESPONSE CHANNEL (B)
                // -----------------------------
                if (!vif.bvalid && wr_resp_pending) begin
                    vif.bid    <= vif.awid;
                    vif.bresp  <= 2'b00;
                    vif.bvalid <= 1;
                    $info("%s: run: Driving BVALID, bid=%0d", this.name, vif.awid);
                end 
                else if (vif.bvalid && vif.bready) begin
                    vif.bvalid      <= 0;
                    wr_resp_pending = 0;
                    $info("%s: run: B handshake complete, clearing BVALID", this.name);
                end

                // -----------------------------
                // READ ADDRESS CHANNEL (AR)
                // -----------------------------
                if (vif.arvalid && rd_beats_left == 0 && rand_ready()) begin
                    rd_addr       = vif.araddr;
                    rd_beats_left = int'(vif.arlen) + 1;
                    rd_size       = vif.arsize;
                    rd_id         = vif.arid;
                    vif.arready   <= 1;

                    $info("%s: AR accepted addr=0x%h len=%0d size=%0d",
                        this.name, rd_addr, vif.arlen, rd_size);
                end
                else begin
                    vif.arready <= 0;
                end

                // -----------------------------
                // READ DATA CHANNEL (R)
                // -----------------------------
                if (rd_beats_left > 0) begin

                    bytes_per_beat = 1 << rd_size;

                    // Advance pointer first so the drive block sees the NEXT address
                    if (vif.rvalid && vif.rready) begin
                        rd_addr       = rd_addr + bytes_per_beat;
                        rd_beats_left = rd_beats_left - 1;
                    end

                    // Drive next beat only if the bus is free and beats remain
                    if ((!vif.rvalid || vif.rready) && rd_beats_left > 0) begin

                        // Compute memory index and byte offset
                        mem_index   = rd_addr / (DATA_WIDTH/8);
                        byte_offset = rd_addr % (DATA_WIDTH/8);

                        mask = ({DATA_WIDTH{1'b1}} >> (DATA_WIDTH - bytes_per_beat*8))
                            << (byte_offset*8);

                        rd_data = (mem[mem_index] & mask) >> (byte_offset*8);

                        vif.rid    <= rd_id;
                        vif.rdata  <= rd_data;
                        vif.rlast  <= (rd_beats_left == 1);
                        vif.rvalid <= 1;

                        $info("%s: READ beat addr=0x%h data=%h beats_left=%0d last=%b",
                            this.name, rd_addr, rd_data,
                            rd_beats_left, (rd_beats_left == 1));
                    end
                end

// Clear rvalid after final beat handshake
if (vif.rvalid && vif.rready && vif.rlast) begin
    vif.rvalid <= 0;
end

                // -----------------------------
                // MONITOR LOGGING
                // -----------------------------
                // Optional: log WLAST on every beat even if wr_beats_left==0 (for s2)
                /*if (vif.wvalid && vif.wlast && !wr_resp_pending) begin
                    $info("%s: run: WLAST observed (monitor), wr_resp_pending=%0d", this.name, wr_resp_pending);
                end*/

            end
        endtask: run

        task read_slice(input logic [ADDR_WIDTH-1:0] addr,
                        input int unsigned N);

            int unsigned base;
            base = int'(addr >> 3); // word addressing (64-bit words)

            dbg_slice_len = N;

            $info("%s: read_slice addr=%h beats=%0d\n", name, addr, N);

            for (int i = 0; i < N; i++) begin
                dbg_slice[i] = mem[base + i];

            // Log
            $display("%s: mem[%0d] = %h",
                     name, base + i, dbg_slice[i]);
            end
        endtask: read_slice

endclass: axi_slave
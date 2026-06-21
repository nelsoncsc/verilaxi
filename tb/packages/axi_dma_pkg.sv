`timescale 1ns / 1ps
package axi_dma_pkg;

    import axi_pkg::*;

    // DMA CSRs
    localparam int WR_CTRL         = 32'h00;
    localparam int WR_BYTE_LEN     = 32'h04;
    localparam int WR_ADDR         = 32'h08;

    localparam int RD_CTRL         = 32'h0C;
    localparam int RD_BYTE_LEN     = 32'h10;
    localparam int RD_ADDR         = 32'h14;

    localparam int STATUS          = 32'h18;

    localparam int AXIL_ADDR_WIDTH = 32;
    localparam int AXIL_DATA_WIDTH = 32;

    class axi_dma_driver #(DATA_WIDTH = 32);
         // Virtual interfaces
        virtual axis_if #(.DATA_WIDTH(DATA_WIDTH)) s_axis_vif;
        virtual axis_if #(.DATA_WIDTH(DATA_WIDTH)) m_axis_vif;

        logic [AXIL_DATA_WIDTH-1:0] wr_addr;
        logic [7:0]                 wr_len;
        logic [2:0]                 wr_size;
        logic [31:0]                wr_num_bytes;

        logic [AXIL_DATA_WIDTH-1:0] rd_addr;
        logic [7:0]                 rd_len;
        logic [2:0]                 rd_size;
        logic [31:0]                rd_num_bytes;

        logic                       src_bp_mode;
        logic                       sink_bp_mode;

        int                         src_bp_high;
        int                         sink_bp_high;

        // ----------------------------------------
        // AXI-Lite master handle (must be passed in)
        // ----------------------------------------
        axil_master #(.ADDR_WIDTH(AXIL_ADDR_WIDTH), 
                      .DATA_WIDTH(AXIL_DATA_WIDTH)) axil_m;

        // we need a semaphore to lock axil-lite access to CSRs when running reads/writes concurrently
        semaphore axil_lock = new(1); 
        string name;

        function new(string                                     obj_name,
                     axil_master                                axil_mst);

            this.name       = obj_name;
            this.axil_m     = axil_mst;
            
            wr_addr         = AXIL_ADDR_WIDTH'(0);
            wr_len          = 8'd0;
            wr_size         = 3'd0;
            wr_num_bytes    = 32'd0;

            rd_addr         = AXIL_ADDR_WIDTH'(0);
            rd_len          = 8'd0;
            rd_size         = 3'd0;
            rd_num_bytes    = 32'd0;
            
            src_bp_mode     = 1'b0;
            sink_bp_mode    = 1'b0;
            
            src_bp_high     = 85;
            sink_bp_high    = 85;

        endfunction: new

        // -------------------------------------------------
        // Configure Write DMA via AXI-Lite
        // -------------------------------------------------
        task automatic config_wr_dma();

            logic [AXIL_DATA_WIDTH-1:0] ctrl_word;

            //--------------------------------------
            // 1. Write base address
            //--------------------------------------
            axil_lock.get();
            axil_m.write(WR_ADDR, wr_addr);
            axil_lock.put();
            
            //--------------------------------------
            // 2. Write number of bursts
            //--------------------------------------
            axil_lock.get(); // axil_m.write is issued; key won't be released until put is called
            axil_m.write(WR_BYTE_LEN, wr_num_bytes);
            axil_lock.put(); // axil_m.write now can release key and other thread can call axil_m.write
            
            //--------------------------------------
            // 3. Build control word (start=1)
            //--------------------------------------
            ctrl_word = AXIL_DATA_WIDTH'(0);
            ctrl_word[0]     = 1'b1;          // start
            ctrl_word[5:3]   = wr_size;    
            ctrl_word[13:6]  = wr_len;     

            axil_lock.get();
            axil_m.write(WR_CTRL, ctrl_word);
            axil_lock.put();

            $display("[%0t] %s AXIL WR_DMA start wr_addr=%h wr_len=%0d wr_size=%0d wr_num_bytes=%0d",
                     $time, this.name,           wr_addr,   wr_len,    wr_size,    wr_num_bytes);

        endtask: config_wr_dma

        // -------------------------------------------------
        // Configure Write DMA (circular mode) via AXI-Lite
        //   Same as config_wr_dma but sets ctrl_word[2]=1
        // -------------------------------------------------
        task automatic config_wr_dma_circ();

            logic [AXIL_DATA_WIDTH-1:0] ctrl_word;

            axil_lock.get();
            axil_m.write(WR_ADDR, wr_addr);
            axil_lock.put();

            axil_lock.get();
            axil_m.write(WR_BYTE_LEN, wr_num_bytes);
            axil_lock.put();

            ctrl_word        = AXIL_DATA_WIDTH'(0);
            ctrl_word[0]     = 1'b1;   // start
            ctrl_word[2]     = 1'b1;   // circular
            ctrl_word[5:3]   = wr_size;
            ctrl_word[13:6]  = wr_len;

            axil_lock.get();
            axil_m.write(WR_CTRL, ctrl_word);
            axil_lock.put();

            $display("[%0t] %s AXIL WR_DMA_CIRC start wr_addr=%h wr_len=%0d wr_size=%0d wr_num_bytes=%0d",
                     $time, this.name, wr_addr, wr_len, wr_size, wr_num_bytes);

        endtask: config_wr_dma_circ

        task wait_wr_done();
            logic [AXIL_DATA_WIDTH-1:0] status;
            logic [AXIL_DATA_WIDTH-1:0] wr_ctrl;

            begin
                //------------------------------------------
                // Read WR_CTRL to check circular bit
                //------------------------------------------
                axil_lock.get();
                axil_m.read(WR_CTRL, wr_ctrl);
                axil_lock.put();
                // If NOT circular mode, wait for done
                if (!wr_ctrl[2]) begin
                    do begin
                        axil_lock.get();
                        axil_m.read(STATUS, status);
                        axil_lock.put();
                        @(posedge axil_m.vif.ACLK);   // prevent zero-time loop
                    end
                    while (!status[0]);   // STATUS[0] = wr_done
                end
            end
        endtask: wait_wr_done

        task wait_rd_done();
            logic [AXIL_DATA_WIDTH-1:0] status;
            logic [AXIL_DATA_WIDTH-1:0] rd_ctrl;

            begin
                //------------------------------------------
                // Read RD_CTRL to check circular bit
                //------------------------------------------
                axil_lock.get();
                axil_m.read(RD_CTRL, rd_ctrl);
                axil_lock.put();
                if (!rd_ctrl[2]) begin
                    do begin
                        axil_lock.get();
                        axil_m.read(STATUS, status);
                        axil_lock.put();
                        @(posedge axil_m.vif.ACLK);
                    end
                    while (!status[1]);   // STATUS[1] = rd_done
                end
            end
        endtask: wait_rd_done

        // -------------------------------------------------
        // Configure Read DMA via AXI-Lite
        // -------------------------------------------------
        task automatic config_rd_dma();

            logic [AXIL_DATA_WIDTH-1:0] ctrl_word;

            //--------------------------------------
            // 1. Write base address
            //--------------------------------------
            axil_lock.get();
            axil_m.write(RD_ADDR, rd_addr);
            axil_lock.put();
            
            //--------------------------------------
            // 2. Write number of bursts
            //--------------------------------------
            axil_lock.get();
            axil_m.write(RD_BYTE_LEN, rd_num_bytes);
            axil_lock.put();
            
            //--------------------------------------
            // 3. Build control word (start=1)
            //--------------------------------------
            ctrl_word = AXIL_DATA_WIDTH'(0);
            ctrl_word[0]     = 1'b1;    // start
            ctrl_word[5:3]   = rd_size;    
            ctrl_word[13:6]  = rd_len;     
            axil_lock.get();
            axil_m.write(RD_CTRL, ctrl_word);
            axil_lock.put();
            $display("[%0t] %s AXIL RD_DMA start rd_addr=%h rd_len=%0d rd_size=%0d rd_num_bytes=%0d",
                     $time, this.name,           rd_addr,   rd_len,    rd_size,    rd_num_bytes);

        endtask: config_rd_dma

        // -------------------------------------------------
        // Configure Read DMA (circular mode) via AXI-Lite
        //   Same as config_rd_dma but sets ctrl_word[2]=1
        // -------------------------------------------------
        task automatic config_rd_dma_circ();

            logic [AXIL_DATA_WIDTH-1:0] ctrl_word;

            axil_lock.get();
            axil_m.write(RD_ADDR, rd_addr);
            axil_lock.put();

            axil_lock.get();
            axil_m.write(RD_BYTE_LEN, rd_num_bytes);
            axil_lock.put();

            ctrl_word        = AXIL_DATA_WIDTH'(0);
            ctrl_word[0]     = 1'b1;   // start
            ctrl_word[2]     = 1'b1;   // circular
            ctrl_word[5:3]   = rd_size;
            ctrl_word[13:6]  = rd_len;

            axil_lock.get();
            axil_m.write(RD_CTRL, ctrl_word);
            axil_lock.put();

            $display("[%0t] %s AXIL RD_DMA_CIRC start rd_addr=%h rd_len=%0d rd_size=%0d rd_num_bytes=%0d",
                     $time, this.name, rd_addr, rd_len, rd_size, rd_num_bytes);

        endtask: config_rd_dma_circ

        task automatic write_stream(ref logic [DATA_WIDTH-1:0] wr_data[]);

            int beat        = 0;
            int high_pct    = !src_bp_mode ? 100 : src_bp_high;
            int bytes_per_beat = 1 << wr_size;
            int total_beats = (wr_num_bytes + bytes_per_beat - 1) / bytes_per_beat;  // Ceiling division
            int mem_index   = wr_addr / bytes_per_beat;

            s_axis_vif.tvalid = 0;
            s_axis_vif.tlast  = 0;

            while (beat < total_beats) begin
                @(negedge s_axis_vif.ACLK);
                if (!s_axis_vif.tvalid) begin
                    s_axis_vif.tdata  = wr_data[mem_index + beat];
                    s_axis_vif.tlast  = (beat+1) % int'(int'(wr_len)+1) == 0;
                    s_axis_vif.tvalid = $urandom_range(0, 99) < high_pct;
                end

                @(posedge s_axis_vif.ACLK);
                if (s_axis_vif.tvalid && s_axis_vif.tready) begin
                    beat++;
                    @(negedge s_axis_vif.ACLK);
                    s_axis_vif.tvalid = 0;
                    s_axis_vif.tlast  = 0;
                end
            end

            @(negedge s_axis_vif.ACLK);
            s_axis_vif.tvalid = 0;
            s_axis_vif.tlast  = 0;

        endtask: write_stream

        // Circular variant: caller supplies the starting index into wr_data[]
        // so the stream keeps advancing across address wraps.
        task automatic write_stream_circ(ref logic [DATA_WIDTH-1:0] wr_data[],
                                         input int start_idx);

            int beat        = 0;
            int high_pct    = !src_bp_mode ? 100 : src_bp_high;
            int bytes_per_beat = 1 << wr_size;
            int total_beats = (wr_num_bytes + bytes_per_beat - 1) / bytes_per_beat;  // Ceiling division

            s_axis_vif.tvalid = 0;
            s_axis_vif.tlast  = 0;

            while (beat < total_beats) begin
                @(negedge s_axis_vif.ACLK);
                if (!s_axis_vif.tvalid) begin
                    s_axis_vif.tdata  = wr_data[start_idx + beat];
                    s_axis_vif.tlast  = (beat+1) % int'(int'(wr_len)+1) == 0;
                    s_axis_vif.tvalid = $urandom_range(0, 99) < high_pct;
                end

                @(posedge s_axis_vif.ACLK);
                if (s_axis_vif.tvalid && s_axis_vif.tready) begin
                    beat++;
                    @(negedge s_axis_vif.ACLK);
                    s_axis_vif.tvalid = 0;
                    s_axis_vif.tlast  = 0;
                end
            end

            @(negedge s_axis_vif.ACLK);
            s_axis_vif.tvalid = 0;
            s_axis_vif.tlast  = 0;

        endtask: write_stream_circ

        task automatic read_stream(ref logic [DATA_WIDTH-1:0] rd_data[]);

            int beat = 0;
            int high_pct = !sink_bp_mode ? 100 : sink_bp_high;
            int bytes_per_beat = 1 << rd_size;
            int total_beats = (rd_num_bytes + bytes_per_beat - 1) / bytes_per_beat;  // Ceiling division
            int mem_index   = rd_addr / bytes_per_beat;

            m_axis_vif.tready = 0;
            while (beat < total_beats) begin
                // Drive away from the active clock edge so READY is stable
                // before both the DUT and testbench sample the handshake.
                @(negedge m_axis_vif.ACLK);
                m_axis_vif.tready = $urandom_range(0, 99) < high_pct;
                @(posedge m_axis_vif.ACLK);
                if (m_axis_vif.tvalid && m_axis_vif.tready) begin
                    rd_data[mem_index + beat] = m_axis_vif.tdata;
                    beat++;
                end
            end
            @(negedge m_axis_vif.ACLK);
            m_axis_vif.tready = 0;
        endtask: read_stream

        // Circular variant: caller supplies the starting index into rd_data[]
        // so received data keeps advancing across address wraps.
        task automatic read_stream_circ(ref logic [DATA_WIDTH-1:0] rd_data[],
                                        input int start_idx);

            int beat = 0;
            int high_pct = !sink_bp_mode ? 100 : sink_bp_high;
            int bytes_per_beat = 1 << rd_size;
            int total_beats = (rd_num_bytes + bytes_per_beat - 1) / bytes_per_beat;  // Ceiling division

            m_axis_vif.tready = 0;
            while (beat < total_beats) begin
                @(negedge m_axis_vif.ACLK);
                m_axis_vif.tready = $urandom_range(0, 99) < high_pct;
                @(posedge m_axis_vif.ACLK);
                if (m_axis_vif.tvalid && m_axis_vif.tready) begin
                    rd_data[start_idx + beat] = m_axis_vif.tdata;
                    beat++;
                end
            end
            @(negedge m_axis_vif.ACLK);
            m_axis_vif.tready = 0;
        endtask: read_stream_circ

        task automatic test_wr_dma(input int frame_idx,
                                   input int base,
                                   input int len,
                                   input int size,
                                   input int num_bytes,
                                   ref logic [DATA_WIDTH-1:0] wr_data[]);
            bit stream_done = 0;

            // Configure DMA driver properties
            wr_addr      = base + frame_idx * num_bytes;
            wr_len       = len;
            wr_size      = size;
            wr_num_bytes = num_bytes;
            
            // Start the DMA
            config_wr_dma();
            fork
                begin
                    write_stream(wr_data);
                    stream_done = 1;
                end
            join_none
            while (!stream_done)
                @(posedge axil_m.vif.ACLK);
            wait_wr_done();

            $display("[%0t] %s test_wr_dma frame=%0d done", $time, name, frame_idx);
        endtask: test_wr_dma


        task automatic test_rd_dma(input int frame_idx,
                                   input int base,
                                   input int len,
                                   input int size,
                                   input int num_bytes,
                                   ref logic [DATA_WIDTH-1:0] rd_data[]);
            bit stream_done = 0;

            // Configure DMA driver properties
            rd_addr      = base + frame_idx * num_bytes;
            rd_len       = len;
            rd_size      = $clog2(DATA_WIDTH/8);
            rd_num_bytes = num_bytes;
            
            // Start the DMA
            config_rd_dma();
            fork
                begin
                    read_stream(rd_data);
                    stream_done = 1;
                end
            join_none
            while (!stream_done)
                @(posedge axil_m.vif.ACLK);
            wait_rd_done();

            $display("[%0t] %s test_rd_dma frame=%0d done", $time, name, frame_idx);
        endtask: test_rd_dma

        // Full-duplex wrapper for simulators whose timing coroutines cannot
        // reliably resume after blocking on a SystemVerilog semaphore.
        // Serialize the shared AXI-Lite control port, but keep both independent
        // AXI-Stream data paths concurrent.
        task automatic test_duplex_dma(input int frame_idx,
                                       input int base,
                                       input int len,
                                       input int size,
                                       input int num_bytes,
                                       ref logic [DATA_WIDTH-1:0] wr_data[],
                                       ref logic [DATA_WIDTH-1:0] rd_data[]);
            bit wr_stream_done = 0;
            bit rd_stream_done = 0;

            wr_addr      = base + frame_idx * num_bytes;
            wr_len       = len;
            wr_size      = size;
            wr_num_bytes = num_bytes;

            rd_addr      = base + frame_idx * num_bytes;
            rd_len       = len;
            rd_size      = size;
            rd_num_bytes = num_bytes;

            config_wr_dma();
            config_rd_dma();

            fork
                begin
                    write_stream(wr_data);
                    wr_stream_done = 1;
                    $display("[%0t] %s duplex write stream frame=%0d done", $time, name, frame_idx);
                end
                begin
                    read_stream(rd_data);
                    rd_stream_done = 1;
                    $display("[%0t] %s duplex read stream frame=%0d done", $time, name, frame_idx);
                end
            join_none
            // Poll on a real timing event. Verilator 5.048 does not reliably
            // wake a wait-expression on automatic variables written by forked
            // class-task coroutines.
            while (!(wr_stream_done && rd_stream_done))
                @(posedge axil_m.vif.ACLK);

            wait_wr_done();
            wait_rd_done();

            $display("[%0t] %s duplex frame=%0d done", $time, name, frame_idx);
        endtask: test_duplex_dma

        task test_wr_abort(ref logic [DATA_WIDTH-1:0] wr_data[]);
            // 1. Start DMA
            config_wr_dma();

            // 2. Leave only the stream in the background. Keep all AXI-Lite
            // accesses in this coroutine to avoid semaphore-resume issues.
            fork
                write_stream(wr_data);
            join_none

            repeat(5) @(posedge s_axis_vif.ACLK);
            $display("[%0t] %s Triggering WR_ABORT", $time, this.name);
            axil_lock.get();
            axil_m.write(WR_CTRL, 32'b10); // set stop bit
            axil_lock.put();

            // 3. Wait until DMA signals done (STATUS[0]=1)
            wait_wr_done();

            // 4. Kill the background write_stream (and any other child processes).
            //    write_stream may still be running after the abort; leaving it active
            //    would fill the FIFO and eventually violate the AXI-Stream VALID rule.
            disable fork;
            s_axis_vif.tvalid = 0;
            s_axis_vif.tlast  = 0;

            $display("[%0t] %s WR_ABORT test completed", $time, this.name);
        endtask: test_wr_abort

        task test_rd_abort(ref logic [DATA_WIDTH-1:0] rd_data[]);
            // 1. Start DMA
            config_rd_dma();

            // 2. Leave only the stream in the background. Keep all AXI-Lite
            // accesses in this coroutine to avoid semaphore-resume issues.
            fork
                read_stream(rd_data);
            join_none

            repeat(5) @(posedge m_axis_vif.ACLK);
            $display("[%0t] %s Triggering RD_ABORT", $time, this.name);
            axil_lock.get();
            axil_m.write(RD_CTRL, 32'b10); // set stop bit
            axil_lock.put();

            // 3. Wait until DMA indicates done or stop
            wait_rd_done();

            // Stop the sink coroutine, which otherwise waits for more data.
            disable fork;
            m_axis_vif.tready = 0;

            $display("[%0t] %s RD_ABORT test completed", $time, this.name);
        endtask: test_rd_abort

        // -------------------------------------------------
        // test_circular
        //
        // Runs num_wraps passes over NUM_FRAMES=4 frames.
        // DMA address wraps back to base each pass, but the
        // stream data index keeps advancing so every beat
        // carries fresh data from wr_data[].
        //
        // wr_wrap_cnt and rd_wrap_cnt increment together
        // after every frame.  When both equal num_wraps*4
        // (all passes done) both channels are aborted.
        // -------------------------------------------------
        task automatic test_circular(
            input int base,
            input int len,
            input int size,
            input int num_bytes,
            input int num_wraps,
            ref   logic [DATA_WIDTH-1:0] wr_data[],
            ref   logic [DATA_WIDTH-1:0] rd_data[]);

            automatic int wr_wrap_cnt    = 0;
            automatic int rd_wrap_cnt    = 0;
            automatic int NUM_FRAMES     = 4;
            automatic int bytes_per_beat = 1 << size;
            automatic int beats_per_frame = (num_bytes + bytes_per_beat - 1) / bytes_per_beat;  // Ceiling division
            automatic int wr_stream_idx  = 0;
            automatic int rd_stream_idx  = 0;

            $display("[%0t] %s test_circular start base=%0h num_wraps=%0d num_frames=%0d",
                     $time, name, base, num_wraps, NUM_FRAMES);

            for (int k = 0; k < num_wraps; k++) begin
                for (int i = 0; i < NUM_FRAMES; i++) begin
                    // DMA address wraps; stream index does not.
                    wr_addr      = base + i * num_bytes;
                    wr_len       = len;
                    wr_size      = size;
                    wr_num_bytes = num_bytes;

                    rd_addr      = base + i * num_bytes;
                    rd_len       = len;
                    rd_size      = $clog2(DATA_WIDTH/8);
                    rd_num_bytes = num_bytes;

                    fork
                        begin
                            config_wr_dma_circ();
                            write_stream_circ(wr_data, wr_stream_idx);
                        end
                        begin
                            config_rd_dma_circ();
                            read_stream_circ(rd_data, rd_stream_idx);
                        end
                    join

                    wr_stream_idx += beats_per_frame;
                    rd_stream_idx += beats_per_frame;
                    wr_wrap_cnt++;
                    rd_wrap_cnt++;

                    $display("[%0t] %s circular frame k=%0d i=%0d wr_wrap_cnt=%0d rd_wrap_cnt=%0d wr_stream_idx=%0d",
                             $time, name, k, i, wr_wrap_cnt, rd_wrap_cnt, wr_stream_idx);
                end

                // Sanity check: counters must stay in lockstep
                if (wr_wrap_cnt != rd_wrap_cnt)
                    $fatal(1, "[%0t] %s test_circular: counter mismatch wr=%0d rd=%0d",
                           $time, name, wr_wrap_cnt, rd_wrap_cnt);

                $display("[%0t] %s wrap pass %0d complete wr_wrap_cnt=%0d rd_wrap_cnt=%0d",
                         $time, name, k, wr_wrap_cnt, rd_wrap_cnt);
            end

            // Both counters are equal — safe to abort both channels together
            $display("[%0t] %s test_circular abort wr_wrap_cnt=%0d rd_wrap_cnt=%0d",
                     $time, name, wr_wrap_cnt, rd_wrap_cnt);
            fork
                begin axil_lock.get(); axil_m.write(WR_CTRL, 32'h2); axil_lock.put(); end
                begin axil_lock.get(); axil_m.write(RD_CTRL, 32'h2); axil_lock.put(); end
            join

            $display("[%0t] %s test_circular done", $time, name);
        endtask: test_circular

        // -------------------------------------------------
        // mem_copy
        //
        // Copies num_bytes from src to dst using the two
        // DMA channels in hardware loopback:
        //   MM2S  reads memory[src]  → m_axis
        //   s_axis (TB loopback)     → S2MM writes memory[dst]
        //
        // REQUIRES: m_axis_vif driven back to s_axis_vif
        //           at the testbench instantiation level.
        //           No stream driving is done here.
        //
        // S2MM (write/dst) is configured before MM2S so
        // the sink is ready before the first beat arrives.
        // wait_wr_done / wait_rd_done poll STATUS concurrently;
        // axil_lock serialises their AXI-Lite bus accesses.
        // -------------------------------------------------
        task automatic mem_copy(input int src,
                                input int dst,
                                input int len_i,
                                input int size_i,
                                input int num_bytes_i);

            wr_addr      = dst;
            wr_len       = len_i;
            wr_size      = size_i;
            wr_num_bytes = num_bytes_i;

            rd_addr      = src;
            rd_len       = len_i;
            rd_size      = size_i;
            rd_num_bytes = num_bytes_i;

            // Sink ready first, then open the source
            config_wr_dma();
            config_rd_dma();

            fork
                wait_wr_done();
                wait_rd_done();
            join

            $display("[%0t] %s mem_copy: %0d bytes 0x%h -> 0x%h done",
                     $time, name, num_bytes_i, src, dst);

        endtask: mem_copy

        // -------------------------------------------------
        // dma_wr_rd
        //
        // Runs S2MM and MM2S concurrently with independent
        // source arrays and address ranges.  Useful for
        // full-duplex bandwidth tests and concurrent AXI
        // arbitration stress.
        //
        // Both channels are configured sequentially (the
        // semaphore would serialise a fork anyway), then
        // write_stream and read_stream execute in parallel
        // on their respective independent AXI-Stream ports.
        // -------------------------------------------------
        task automatic dma_wr_rd(input int                    wr_base,
                                 input int                    rd_base,
                                 input int                    len_i,
                                 input int                    size_i,
                                 input int                    num_bytes_i,
                                 ref   logic [DATA_WIDTH-1:0] wr_data[],
                                 ref   logic [DATA_WIDTH-1:0] rd_data[]);

            wr_addr      = wr_base;
            wr_len       = len_i;
            wr_size      = size_i;
            wr_num_bytes = num_bytes_i;

            rd_addr      = rd_base;
            rd_len       = len_i;
            rd_size      = size_i;
            rd_num_bytes = num_bytes_i;

            // Sequential config — semaphore serialises bus writes anyway
            config_wr_dma();
            config_rd_dma();

            // Stream and status in parallel
            fork
                begin write_stream(wr_data); wait_wr_done(); end
                begin read_stream(rd_data);  wait_rd_done(); end
            join

            $display("[%0t] %s dma_wr_rd: %0d bytes wr@0x%h rd@0x%h done",
                     $time, name, num_bytes_i, wr_base, rd_base);

        endtask: dma_wr_rd

    endclass: axi_dma_driver

endpackage: axi_dma_pkg

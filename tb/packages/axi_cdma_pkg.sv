`timescale 1ns / 1ps

package axi_cdma_pkg;

    import axi_pkg::*;

    // CDMA CSR address map (matches snix_axi_cdma_csr)
    localparam int CDMA_CTRL      = 32'h00;  // [0]=start [1]=stop [5:3]=size [13:6]=len
    localparam int CDMA_NUM_BYTES = 32'h04;  // [31:0] = transfer_len
    localparam int CDMA_SRC_ADDR  = 32'h08;  // [31:0] = source base address
    localparam int CDMA_DST_ADDR  = 32'h0C;  // [31:0] = destination base address
    localparam int CDMA_STATUS    = 32'h10;  // [0]    = done (sticky, read-only)

    localparam int AXIL_ADDR_WIDTH = 32;
    localparam int AXIL_DATA_WIDTH = 32;

    // =========================================================================
    //  axi_cdma_driver
    //
    //  Drives snix_axi_cdma via AXI-Lite.  No stream interfaces — all data
    //  movement is internal to the MM2MM engine.
    //
    //  Typical usage:
    //    cdma.mem_copy(.src(32'h1000), .dst(32'h2000), .len(15),
    //                  .size(3), .num_bytes(512));
    // =========================================================================
    class axi_cdma_driver;

        axil_master #(.ADDR_WIDTH(AXIL_ADDR_WIDTH),
                      .DATA_WIDTH(AXIL_DATA_WIDTH)) axil_m;

        semaphore axil_lock = new(1);
        string    name;

        // Transfer geometry (set by mem_copy / config_cdma before use)
        logic [AXIL_DATA_WIDTH-1:0] src_addr;
        logic [AXIL_DATA_WIDTH-1:0] dst_addr;
        logic [7:0]                 xfer_len;
        logic [2:0]                 xfer_size;
        logic [31:0]                xfer_num_bytes;

        function new(string      obj_name,
                     axil_master axil_mst);
            this.name      = obj_name;
            this.axil_m    = axil_mst;
            src_addr       = '0;
            dst_addr       = '0;
            xfer_len       = '0;
            xfer_size      = '0;
            xfer_num_bytes = '0;
        endfunction : new

        // -------------------------------------------------
        // config_cdma
        //
        // Writes CDMA_SRC_ADDR, CDMA_DST_ADDR, CDMA_NUM_BYTES
        // then issues the start pulse via CDMA_CTRL.
        //
        // Member variables src_addr/dst_addr/xfer_*/xfer_num_bytes
        // must be set before calling (mem_copy does this for you).
        // -------------------------------------------------
        task automatic config_cdma();
            logic [AXIL_DATA_WIDTH-1:0] ctrl_word;

            axil_lock.get();
            axil_m.write(CDMA_SRC_ADDR, src_addr);
            axil_lock.put();

            axil_lock.get();
            axil_m.write(CDMA_DST_ADDR, dst_addr);
            axil_lock.put();

            axil_lock.get();
            axil_m.write(CDMA_NUM_BYTES, xfer_num_bytes);
            axil_lock.put();

            ctrl_word         = '0;
            ctrl_word[0]      = 1'b1;       // start (pulse; CSR clears on next cycle)
            ctrl_word[5:3]    = xfer_size;
            ctrl_word[13:6]   = xfer_len;

            axil_lock.get();
            axil_m.write(CDMA_CTRL, ctrl_word);
            axil_lock.put();

            $display("[%0t] %s config_cdma: src=0x%h dst=0x%h len=%0d size=%0d bytes=%0d",
                     $time, name, src_addr, dst_addr, xfer_len, xfer_size, xfer_num_bytes);
        endtask : config_cdma

        // -------------------------------------------------
        // wait_done
        //
        // Polls CDMA_STATUS[0] until the done bit is set.
        // STATUS is sticky (set by HW, cleared on the next
        // start by the CSR) so polling is safe.
        // -------------------------------------------------
        task automatic wait_done();
            logic [AXIL_DATA_WIDTH-1:0] status;
            do begin
                axil_lock.get();
                axil_m.read(CDMA_STATUS, status);
                axil_lock.put();
                @(posedge axil_m.vif.ACLK);    // prevent zero-time loop
            end
            while (!status[0]);
        endtask : wait_done

        // -------------------------------------------------
        // mem_copy
        //
        // Full configure-and-wait convenience task.
        // Sets member variables, calls config_cdma, waits
        // for completion, and emits a display message.
        // -------------------------------------------------
        task automatic mem_copy(input int src,
                                input int dst,
                                input int len_i,
                                input int size_i,
                                input int num_bytes_i);
            src_addr       = src;
            dst_addr       = dst;
            xfer_len       = len_i;
            xfer_size      = size_i;
            xfer_num_bytes = num_bytes_i;

            config_cdma();
            wait_done();

            $display("[%0t] %s mem_copy: %0d bytes 0x%h -> 0x%h done",
                     $time, name, num_bytes_i, src, dst);
        endtask : mem_copy

        // -------------------------------------------------
        // test_abort
        //
        // Starts a transfer then asserts stop after a short
        // delay. wait_done returns once the FSM reaches IDLE.
        // -------------------------------------------------
        task automatic test_abort(input int src,
                                  input int dst,
                                  input int len_i,
                                  input int size_i,
                                  input int num_bytes_i,
                                  input int abort_after_cycles = 10);
            src_addr       = src;
            dst_addr       = dst;
            xfer_len       = len_i;
            xfer_size      = size_i;
            xfer_num_bytes = num_bytes_i;

            config_cdma();

            fork
                begin
                    repeat(abort_after_cycles) @(posedge axil_m.vif.ACLK);
                    $display("[%0t] %s test_abort: asserting stop", $time, name);
                    axil_lock.get();
                    axil_m.write(CDMA_CTRL, 32'h2);  // stop bit
                    axil_lock.put();
                end
            join_none

            wait_done();
            $display("[%0t] %s test_abort: done", $time, name);
        endtask : test_abort

    endclass : axi_cdma_driver

endpackage : axi_cdma_pkg

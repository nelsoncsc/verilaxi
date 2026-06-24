`timescale 1ns/1ps

module test_vdma #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 64,
    parameter int ID_WIDTH   = 4,
    parameter int USER_WIDTH = 1
) (
    input logic clk,
    input logic rst_n
);
    import axi_pkg::*;
    import axi_vdma_pkg::*;

    localparam int WIDTH_PIXELS = 8;
    localparam int HEIGHT_LINES = 4;
    localparam int BYTES_PER_PIXEL = DATA_WIDTH / 8;
    localparam int HSIZE_BYTES = WIDTH_PIXELS * BYTES_PER_PIXEL;
    localparam int STRIDE_BYTES = 128;
    localparam int BASE_ADDR = 32'h0000_0200;
    localparam int THR_WIDTH_PIXELS = 16;
    localparam int THR_HEIGHT_LINES = 8;
    localparam int THR_BASE_ADDR = 32'h0000_2000;
    localparam int THR_HSIZE_BYTES = THR_WIDTH_PIXELS * BYTES_PER_PIXEL;
    localparam int THR_STRIDE_BYTES = 256;
    localparam int MEM_DEPTH = 4096;
    localparam int AXIL_ADDR_WIDTH = 32;
    localparam int AXIL_DATA_WIDTH = 32;

    axi4_if #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH(ID_WIDTH), .USER_WIDTH(USER_WIDTH)
    ) axi_mem (.ACLK(clk), .ARESETn(rst_n));

    axil_if #(
        .ADDR_WIDTH(AXIL_ADDR_WIDTH), .DATA_WIDTH(AXIL_DATA_WIDTH)
    ) axil (.ACLK(clk), .ARESETn(rst_n));

    axis_if #(.DATA_WIDTH(DATA_WIDTH), .USER_WIDTH(USER_WIDTH))
        capture_axis (.ACLK(clk), .ARESETn(rst_n));
    axis_if #(.DATA_WIDTH(DATA_WIDTH), .USER_WIDTH(USER_WIDTH))
        playback_axis (.ACLK(clk), .ARESETn(rst_n));

    logic wr_busy, wr_done, wr_error;
    logic rd_busy, rd_done, rd_error;
    logic wr_axi_error, rd_axi_error;
    logic irq;
    logic [31:0] vdma_status;
    logic [1:0] write_slot, read_slot, newest_complete_slot;
    logic [2:0] valid_slots;

    axi_slave #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH(ID_WIDTH), .MEM_DEPTH(MEM_DEPTH)
    ) mem_slave;
    axil_master #(
        .ADDR_WIDTH(AXIL_ADDR_WIDTH), .DATA_WIDTH(AXIL_DATA_WIDTH)
    ) axil_m;

    function automatic logic [DATA_WIDTH-1:0] pixel_word(input int row, input int col);
        return 64'ha500_0000_0000_0000 |
               (DATA_WIDTH'(row) << 8) | DATA_WIDTH'(col);
    endfunction

    function automatic logic [DATA_WIDTH-1:0] frame_pixel_word(
        input int frame, input int row, input int col
    );
        return 64'hc300_0000_0000_0000 |
               (DATA_WIDTH'(frame) << 16) |
               (DATA_WIDTH'(row) << 8) | DATA_WIDTH'(col);
    endfunction

    function automatic logic [DATA_WIDTH-1:0] partial_word(input int beat);
        return 64'hf8f7_f6f5_f4f3_f2f1 + DATA_WIDTH'(beat * 64'h0808_0808_0808_0808);
    endfunction

    snix_axi_vdma #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
        .AXIL_ADDR_WIDTH(AXIL_ADDR_WIDTH), .AXIL_DATA_WIDTH(AXIL_DATA_WIDTH),
        .ID_WIDTH(ID_WIDTH), .USER_WIDTH(USER_WIDTH), .LINE_FIFO_DEPTH(64)
    ) dut (
        .clk, .rst_n,
        .s_axil_awaddr(axil.awaddr), .s_axil_awvalid(axil.awvalid),
        .s_axil_awready(axil.awready),
        .s_axil_wdata(axil.wdata), .s_axil_wstrb(axil.wstrb),
        .s_axil_wvalid(axil.wvalid), .s_axil_wready(axil.wready),
        .s_axil_bresp(axil.bresp), .s_axil_bvalid(axil.bvalid),
        .s_axil_bready(axil.bready),
        .s_axil_araddr(axil.araddr), .s_axil_arvalid(axil.arvalid),
        .s_axil_arready(axil.arready),
        .s_axil_rdata(axil.rdata), .s_axil_rresp(axil.rresp),
        .s_axil_rvalid(axil.rvalid), .s_axil_rready(axil.rready),
        .s_axis_tdata(capture_axis.tdata), .s_axis_tuser(capture_axis.tuser),
        .s_axis_tkeep(capture_axis.tkeep),
        .s_axis_tvalid(capture_axis.tvalid), .s_axis_tready(capture_axis.tready),
        .s_axis_tlast(capture_axis.tlast),
        .m_axis_tdata(playback_axis.tdata), .m_axis_tuser(playback_axis.tuser),
        .m_axis_tkeep(playback_axis.tkeep),
        .m_axis_tvalid(playback_axis.tvalid), .m_axis_tready(playback_axis.tready),
        .m_axis_tlast(playback_axis.tlast),
        .wr_busy, .wr_done, .wr_error, .wr_axi_error,
        .rd_busy, .rd_done, .rd_error, .rd_axi_error,
        .vdma_status,
        .irq, .write_slot, .read_slot, .newest_complete_slot, .valid_slots,
        .s2mm_awid(axi_mem.awid), .s2mm_awaddr(axi_mem.awaddr),
        .s2mm_awlen(axi_mem.awlen), .s2mm_awsize(axi_mem.awsize),
        .s2mm_awburst(axi_mem.awburst), .s2mm_awlock(axi_mem.awlock),
        .s2mm_awcache(axi_mem.awcache), .s2mm_awprot(axi_mem.awprot),
        .s2mm_awqos(axi_mem.awqos), .s2mm_awuser(axi_mem.awuser),
        .s2mm_awvalid(axi_mem.awvalid), .s2mm_awready(axi_mem.awready),
        .s2mm_wdata(axi_mem.wdata), .s2mm_wstrb(axi_mem.wstrb),
        .s2mm_wlast(axi_mem.wlast), .s2mm_wuser(axi_mem.wuser),
        .s2mm_wvalid(axi_mem.wvalid), .s2mm_wready(axi_mem.wready),
        .s2mm_bid(axi_mem.bid), .s2mm_bresp(axi_mem.bresp),
        .s2mm_buser(axi_mem.buser), .s2mm_bvalid(axi_mem.bvalid),
        .s2mm_bready(axi_mem.bready),
        .mm2s_arid(axi_mem.arid), .mm2s_araddr(axi_mem.araddr),
        .mm2s_arlen(axi_mem.arlen), .mm2s_arsize(axi_mem.arsize),
        .mm2s_arburst(axi_mem.arburst), .mm2s_arlock(axi_mem.arlock),
        .mm2s_arcache(axi_mem.arcache), .mm2s_arprot(axi_mem.arprot),
        .mm2s_arqos(axi_mem.arqos), .mm2s_aruser(axi_mem.aruser),
        .mm2s_arvalid(axi_mem.arvalid), .mm2s_arready(axi_mem.arready),
        .mm2s_rid(axi_mem.rid), .mm2s_rdata(axi_mem.rdata),
        .mm2s_rresp(axi_mem.rresp), .mm2s_rlast(axi_mem.rlast),
        .mm2s_ruser(axi_mem.ruser), .mm2s_rvalid(axi_mem.rvalid),
        .mm2s_rready(axi_mem.rready)
    );

    axi_mm_checker #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH(ID_WIDTH), .ALLOW_ERROR_RESP(1'b1), .LABEL("VDMA_MM")
    ) u_mm_checker (
        .clk, .rst_n,
        .awaddr(axi_mem.awaddr), .awlen(axi_mem.awlen),
        .awsize(axi_mem.awsize), .awburst(axi_mem.awburst),
        .awid(axi_mem.awid), .awvalid(axi_mem.awvalid), .awready(axi_mem.awready),
        .wdata(axi_mem.wdata), .wstrb(axi_mem.wstrb),
        .wlast(axi_mem.wlast), .wvalid(axi_mem.wvalid), .wready(axi_mem.wready),
        .bid(axi_mem.bid), .bresp(axi_mem.bresp),
        .bvalid(axi_mem.bvalid), .bready(axi_mem.bready),
        .araddr(axi_mem.araddr), .arlen(axi_mem.arlen),
        .arsize(axi_mem.arsize), .arburst(axi_mem.arburst),
        .arid(axi_mem.arid), .arvalid(axi_mem.arvalid), .arready(axi_mem.arready),
        .rid(axi_mem.rid), .rdata(axi_mem.rdata), .rresp(axi_mem.rresp),
        .rlast(axi_mem.rlast), .rvalid(axi_mem.rvalid), .rready(axi_mem.rready)
    );

    axi_4k_checker #(.ADDR_WIDTH(ADDR_WIDTH), .LABEL("VDMA_4K")) u_4k_checker (
        .clk, .rst_n,
        .awaddr(axi_mem.awaddr), .awlen(axi_mem.awlen),
        .awsize(axi_mem.awsize), .awvalid(axi_mem.awvalid),
        .awready(axi_mem.awready),
        .araddr(axi_mem.araddr), .arlen(axi_mem.arlen),
        .arsize(axi_mem.arsize), .arvalid(axi_mem.arvalid),
        .arready(axi_mem.arready)
    );

    axil_checker #(
        .ADDR_WIDTH(AXIL_ADDR_WIDTH), .DATA_WIDTH(AXIL_DATA_WIDTH),
        .LABEL("VDMA_AXIL")
    ) u_axil_checker (
        .clk, .rst_n,
        .awaddr(axil.awaddr), .awvalid(axil.awvalid), .awready(axil.awready),
        .wdata(axil.wdata), .wstrb(axil.wstrb),
        .wvalid(axil.wvalid), .wready(axil.wready),
        .bresp(axil.bresp), .bvalid(axil.bvalid), .bready(axil.bready),
        .araddr(axil.araddr), .arvalid(axil.arvalid), .arready(axil.arready),
        .rdata(axil.rdata), .rresp(axil.rresp),
        .rvalid(axil.rvalid), .rready(axil.rready)
    );

    axis_checker #(.DATA_WIDTH(DATA_WIDTH), .USER_WIDTH(USER_WIDTH),
                   .LABEL("VDMA_CAPTURE")) u_capture_checker (
        .clk, .rst_n, .tdata(capture_axis.tdata), .tuser(capture_axis.tuser),
        .tvalid(capture_axis.tvalid), .tready(capture_axis.tready),
        .tlast(capture_axis.tlast)
    );

    axis_checker #(.DATA_WIDTH(DATA_WIDTH), .USER_WIDTH(USER_WIDTH),
                   .LABEL("VDMA_PLAYBACK")) u_playback_checker (
        .clk, .rst_n, .tdata(playback_axis.tdata), .tuser(playback_axis.tuser),
        .tvalid(playback_axis.tvalid), .tready(playback_axis.tready),
        .tlast(playback_axis.tlast)
    );

    task automatic configure_write();
        axil_m.write(VDMA_WR_ADDR, BASE_ADDR);
        axil_m.write(VDMA_WR_STRIDE, STRIDE_BYTES);
        axil_m.write(VDMA_WR_HSIZE, HSIZE_BYTES);
        axil_m.write(VDMA_WR_VSIZE, HEIGHT_LINES);
        axil_m.write(VDMA_WR_CTRL,
                     vdma_ctrl_word(1'b1, 1'b0, 3'd3, 8'd3));
    endtask

    task automatic configure_read();
        axil_m.write(VDMA_RD_ADDR, BASE_ADDR);
        axil_m.write(VDMA_RD_STRIDE, STRIDE_BYTES);
        axil_m.write(VDMA_RD_HSIZE, HSIZE_BYTES);
        axil_m.write(VDMA_RD_VSIZE, HEIGHT_LINES);
        axil_m.write(VDMA_RD_CTRL,
                     vdma_ctrl_word(1'b1, 1'b0, 3'd3, 8'd3));
    endtask

    task automatic configure_write_custom(
        input int base_addr,
        input int stride_bytes,
        input int hsize_bytes,
        input int vsize_lines
    );
        axil_m.write(VDMA_WR_ADDR, base_addr);
        axil_m.write(VDMA_WR_STRIDE, stride_bytes);
        axil_m.write(VDMA_WR_HSIZE, hsize_bytes);
        axil_m.write(VDMA_WR_VSIZE, vsize_lines);
    endtask

    task automatic configure_read_custom(
        input int base_addr,
        input int stride_bytes,
        input int hsize_bytes,
        input int vsize_lines
    );
        axil_m.write(VDMA_RD_ADDR, base_addr);
        axil_m.write(VDMA_RD_STRIDE, stride_bytes);
        axil_m.write(VDMA_RD_HSIZE, hsize_bytes);
        axil_m.write(VDMA_RD_VSIZE, vsize_lines);
    endtask

    task automatic send_frame();
        for (int row = 0; row < HEIGHT_LINES; row++) begin
            for (int col = 0; col < WIDTH_PIXELS; col++) begin
                @(negedge clk);
                capture_axis.tdata  = pixel_word(row, col);
                capture_axis.tuser  = USER_WIDTH'((row == 0) && (col == 0));
                capture_axis.tlast  = (col == WIDTH_PIXELS - 1);
                capture_axis.tvalid = 1'b1;
                @(posedge clk);
                while (!capture_axis.tready)
                    @(posedge clk);
            end
        end
        @(negedge clk);
        capture_axis.tvalid = 1'b0;
        capture_axis.tlast  = 1'b0;
        capture_axis.tuser  = '0;
    endtask

    task automatic receive_frame();
        int received;
        int row;
        int col;
        int ready_cycle;

        received = 0;
        ready_cycle = 0;
        while (received < WIDTH_PIXELS * HEIGHT_LINES) begin
            @(negedge clk);
            // Deterministic output backpressure while preserving AXI stability.
            playback_axis.tready = ((ready_cycle % 5) != 0);
            ready_cycle++;
            @(posedge clk);
            if (playback_axis.tvalid && playback_axis.tready) begin
                row = received / WIDTH_PIXELS;
                col = received % WIDTH_PIXELS;
                assert (playback_axis.tdata == pixel_word(row, col))
                    else $fatal(1, "VDMA pixel mismatch row=%0d col=%0d exp=%h got=%h",
                                row, col, pixel_word(row, col), playback_axis.tdata);
                assert (playback_axis.tuser[0] == ((row == 0) && (col == 0)))
                    else $fatal(1, "VDMA SOF mismatch row=%0d col=%0d", row, col);
                assert (playback_axis.tlast == (col == WIDTH_PIXELS - 1))
                    else $fatal(1, "VDMA EOL mismatch row=%0d col=%0d", row, col);
                $display("[VDMA PIXEL] row=%0d col=%0d data=%h sof=%0b eol=%0b",
                         row, col, playback_axis.tdata,
                         playback_axis.tuser[0], playback_axis.tlast);
                received++;
            end
        end
        @(negedge clk);
        playback_axis.tready = 1'b0;
    endtask

    task automatic send_frame_id(input int frame);
        for (int row = 0; row < HEIGHT_LINES; row++) begin
            for (int col = 0; col < WIDTH_PIXELS; col++) begin
                @(negedge clk);
                capture_axis.tdata  = frame_pixel_word(frame, row, col);
                capture_axis.tuser  = USER_WIDTH'((row == 0) && (col == 0));
                capture_axis.tlast  = (col == WIDTH_PIXELS - 1);
                capture_axis.tvalid = 1'b1;
                @(posedge clk);
                while (!capture_axis.tready)
                    @(posedge clk);
            end
        end
        @(negedge clk);
        capture_axis.tvalid = 1'b0;
        capture_axis.tlast  = 1'b0;
        capture_axis.tuser  = '0;
    endtask

    task automatic receive_frame_id(input int frame);
        int received = 0;
        int ready_cycle = 0;
        while (received < WIDTH_PIXELS * HEIGHT_LINES) begin
            @(negedge clk);
            playback_axis.tready = ((ready_cycle % 5) != 0);
            ready_cycle++;
            @(posedge clk);
            if (playback_axis.tvalid && playback_axis.tready) begin
                int row = received / WIDTH_PIXELS;
                int col = received % WIDTH_PIXELS;
                assert (playback_axis.tdata == frame_pixel_word(frame, row, col))
                    else $fatal(1, "VDMA frame-slot mismatch frame=%0d row=%0d col=%0d", frame, row, col);
                assert (playback_axis.tuser[0] == ((row == 0) && (col == 0)));
                assert (playback_axis.tlast == (col == WIDTH_PIXELS - 1));
                received++;
            end
        end
        @(negedge clk);
        playback_axis.tready = 1'b0;
    endtask

    task automatic discard_frame(input int beats);
        int received = 0;
        playback_axis.tready = 1'b1;
        while (received < beats) begin
            @(posedge clk);
            if (playback_axis.tvalid && playback_axis.tready)
                received++;
        end
        @(negedge clk);
        playback_axis.tready = 1'b0;
    endtask

    task automatic send_partial_line;
        for (int beat = 0; beat < 3; beat++) begin
            @(negedge clk);
            capture_axis.tdata  = partial_word(beat);
            capture_axis.tkeep  = (beat == 2) ? 8'h1f : 8'hff;
            capture_axis.tuser  = USER_WIDTH'(beat == 0);
            capture_axis.tlast  = (beat == 2);
            capture_axis.tvalid = 1'b1;
            @(posedge clk);
            while (!capture_axis.tready)
                @(posedge clk);
        end
        @(negedge clk);
        capture_axis.tvalid = 1'b0;
        capture_axis.tkeep  = '1;
        capture_axis.tuser  = '0;
        capture_axis.tlast  = 1'b0;
    endtask

    task automatic receive_partial_line;
        int beat = 0;
        playback_axis.tready = 1'b1;
        while (beat < 3) begin
            @(posedge clk);
            if (playback_axis.tvalid && playback_axis.tready) begin
                logic [7:0] expected_keep;
                logic [63:0] data_mask;
                expected_keep = (beat == 2) ? 8'h1f : 8'hff;
                data_mask = (beat == 2) ? 64'h0000_00ff_ffff_ffff : 64'hffff_ffff_ffff_ffff;
                assert (playback_axis.tkeep == expected_keep)
                    else $fatal(1, "VDMA partial TKEEP mismatch beat=%0d got=%h", beat, playback_axis.tkeep);
                assert ((playback_axis.tdata & data_mask) == (partial_word(beat) & data_mask))
                    else $fatal(1, "VDMA partial data mismatch beat=%0d", beat);
                assert (playback_axis.tlast == (beat == 2));
                beat++;
            end
        end
        @(negedge clk);
        playback_axis.tready = 1'b0;
    endtask

    task automatic send_frame_rect_count(
        input  int frame,
        input  int width_pixels,
        input  int height_lines,
        output int beats,
        output int cycles
    );
        int sent;
        int row;
        int col;

        sent   = 0;
        beats  = width_pixels * height_lines;
        cycles = 0;
        while (sent < beats) begin
            row = sent / width_pixels;
            col = sent % width_pixels;
            @(negedge clk);
            capture_axis.tdata  = frame_pixel_word(frame, row, col);
            capture_axis.tkeep  = '1;
            capture_axis.tuser  = USER_WIDTH'((row == 0) && (col == 0));
            capture_axis.tlast  = (col == width_pixels - 1);
            capture_axis.tvalid = 1'b1;
            @(posedge clk);
            cycles++;
            if (capture_axis.tready)
                sent++;
        end
        @(negedge clk);
        capture_axis.tvalid = 1'b0;
        capture_axis.tlast  = 1'b0;
        capture_axis.tuser  = '0;
    endtask

    task automatic receive_frame_rect_count(
        input  int frame,
        input  int width_pixels,
        input  int height_lines,
        output int beats,
        output int cycles
    );
        int received;
        int row;
        int col;

        received = 0;
        beats    = width_pixels * height_lines;
        cycles   = 0;
        playback_axis.tready = 1'b1;
        while (received < beats) begin
            @(posedge clk);
            cycles++;
            if (playback_axis.tvalid && playback_axis.tready) begin
                row = received / width_pixels;
                col = received % width_pixels;
                assert (playback_axis.tdata == frame_pixel_word(frame, row, col))
                    else $fatal(1, "VDMA throughput playback mismatch frame=%0d row=%0d col=%0d",
                                frame, row, col);
                assert (playback_axis.tuser[0] == ((row == 0) && (col == 0)))
                    else $fatal(1, "VDMA throughput SOF mismatch row=%0d col=%0d", row, col);
                assert (playback_axis.tlast == (col == width_pixels - 1))
                    else $fatal(1, "VDMA throughput EOL mismatch row=%0d col=%0d", row, col);
                received++;
            end
        end
        @(negedge clk);
        playback_axis.tready = 1'b0;
    endtask

    initial begin
        capture_axis.tdata  = '0;
        capture_axis.tuser  = '0;
        capture_axis.tkeep  = '1;
        capture_axis.tvalid = 1'b0;
        capture_axis.tlast  = 1'b0;
        playback_axis.tready = 1'b0;

        axi_mem.init();
        axil.init();
        axil_m = new(axil);
        axil_m.reset();
        mem_slave = new(axi_mem, "vdma_mem");
        mem_slave.reset();
        for (int i = 0; i < MEM_DEPTH; i++)
            mem_slave.mem[i] = '0;

        fork
            mem_slave.run();
        join_none

        wait (rst_n);
        repeat (5) @(posedge clk);

        configure_write();
        fork
            send_frame();
            begin
                wait (wr_done);
            end
        join

        assert (!wr_error)
            else $fatal(1, "VDMA capture reported framing/configuration error");
        begin
            logic [31:0] status;
            axil_m.read(VDMA_STATUS, status);
            assert (status[0]) else $fatal(1, "VDMA capture done status missing");
        end

        for (int row = 0; row < HEIGHT_LINES; row++) begin
            for (int col = 0; col < WIDTH_PIXELS; col++) begin
                int mem_word;
                mem_word = (BASE_ADDR + row * STRIDE_BYTES) / BYTES_PER_PIXEL + col;
                assert (mem_slave.mem[mem_word] == pixel_word(row, col))
                    else $fatal(1, "VDMA memory mismatch row=%0d col=%0d", row, col);
            end
        end
        $display("[VDMA] 8x4 capture passed with stride=%0d bytes", STRIDE_BYTES);

        configure_read();
        receive_frame();
        wait (rd_done);
        assert (!rd_error)
            else $fatal(1, "VDMA playback reported configuration error");
        begin
            logic [31:0] status;
            axil_m.read(VDMA_STATUS, status);
            assert (status[1:0] == 2'b11)
                else $fatal(1, "VDMA done status mismatch: %h", status);
        end

        $display("[VDMA] 8x4 playback passed with regenerated SOF/EOL");

        // Triple-buffer publication and interrupt test. The writer owns one
        // slot for a complete frame and publishes it only on wr_done.
        axil_m.write(VDMA_FRAME_ADDR0, 32'h0000_0800);
        axil_m.write(VDMA_FRAME_ADDR1, 32'h0000_0c00);
        axil_m.write(VDMA_FRAME_ADDR2, 32'h0000_1000);
        axil_m.write(VDMA_FRAME_CTRL,
                     vdma_frame_ctrl_word(1'b1, 1'b0, 2'd0,
                                          1'b1, 1'b1, 1'b1, 1'b0));

        for (int frame = 0; frame < 3; frame++) begin
            axil_m.write(VDMA_WR_CTRL,
                         vdma_ctrl_word(1'b1, 1'b0, 3'd3, 8'd3));
            fork
                send_frame_id(frame);
                wait (wr_done);
            join
            @(posedge clk);
            @(negedge clk);
            assert (newest_complete_slot == frame[1:0])
                else $fatal(1, "VDMA published wrong slot for frame %0d", frame);
            assert (valid_slots[frame])
                else $fatal(1, "VDMA did not mark slot %0d valid", frame);
            assert (irq) else $fatal(1, "VDMA write-complete IRQ missing");
            axil_m.write(VDMA_IRQ_ACK,
                         vdma_irq_ack_word(1'b1, 1'b0, 1'b0));
            repeat (2) @(posedge clk);
            assert (!irq) else $fatal(1, "VDMA IRQ clear failed");
        end

        assert (valid_slots == 3'b111 && write_slot == 2'd0)
            else $fatal(1, "VDMA slot rotation mismatch valid=%b write=%0d",
                        valid_slots, write_slot);

        // With park disabled, playback acquires newest_complete_slot only at
        // this frame start and therefore must return frame 2 from slot 2.
        axil_m.write(VDMA_RD_CTRL,
                     vdma_ctrl_word(1'b1, 1'b0, 3'd3, 8'd3));
        receive_frame_id(2);
        wait (rd_done);
        @(posedge clk);
        @(negedge clk);
        assert (read_slot == 2'd2)
            else $fatal(1, "VDMA reader did not acquire newest slot");
        assert (irq) else $fatal(1, "VDMA read-complete IRQ missing");
        $display("[VDMA] triple-buffer publication, newest-frame playback, and IRQ passed");

        // Capture-driven genlock with a one-frame delay. Publishing frame 3 in
        // slot 0 must automatically launch playback from previous slot 2.
        axil_m.write(VDMA_FRAME_CTRL,
                     vdma_frame_policy_word(1'b1, 1'b0, 2'd0,
                                            1'b1, 2'd1,
                                            1'b1, 1'b1, 1'b1, 1'b0));
        axil_m.write(VDMA_WR_CTRL,
                     vdma_ctrl_word(1'b1, 1'b0, 3'd3, 8'd3));
        fork
            send_frame_id(3);
            receive_frame_id(2);
        join
        wait (rd_done);
        @(posedge clk);
        @(negedge clk);
        assert (read_slot == 2'd2 && newest_complete_slot == 2'd0)
            else $fatal(1, "VDMA delayed genlock mismatch read=%0d newest=%0d",
                        read_slot, newest_complete_slot);
        begin
            logic [31:0] status;
            axil_m.read(VDMA_STATUS, status);
            assert (status[14:13] == 2'd0 && status[12:11] == 2'd2 &&
                    status[17:15] == 3'b111)
                else $fatal(1, "VDMA readable frame status mismatch: %h", status);
        end
        $display("[VDMA] capture-driven genlock with one-frame delay passed");

        // Return to free-run policy for the circular restart stress below.
        axil_m.write(VDMA_FRAME_CTRL,
                     vdma_frame_policy_word(1'b1, 1'b0, 2'd0,
                                            1'b0, 2'd0,
                                            1'b1, 1'b1, 1'b1, 1'b0));

        // Inject a write response failure. A failed capture must raise status
        // and IRQ, invalidate its destination, and never publish/advance it.
        force axi_mem.bresp = 2'b10;
        axil_m.write(VDMA_WR_CTRL,
                     vdma_ctrl_word(1'b1, 1'b0, 3'd3, 8'd3));
        fork
            send_frame_id(6);
            wait (wr_done);
        join
        release axi_mem.bresp;
        axi_mem.bresp = 2'b00;
        @(posedge clk);
        @(negedge clk);
        assert (wr_axi_error && wr_error && irq)
            else $fatal(1, "VDMA failed to report injected BRESP error");
        assert (newest_complete_slot == 2'd0 && write_slot == 2'd1 &&
                !valid_slots[1])
            else $fatal(1, "VDMA published or advanced failed capture");
        begin
            logic [31:0] status;
            axil_m.read(VDMA_STATUS, status);
            assert (status[6] && status[4] && status[8])
                else $fatal(1, "VDMA BRESP status mismatch: %h", status);
        end

        // Read errors are reported even though AXI still returns data. The
        // frame payload is checked so response handling cannot corrupt flow.
        force axi_mem.rresp = 2'b10;
        axil_m.write(VDMA_RD_CTRL,
                     vdma_ctrl_word(1'b1, 1'b0, 3'd3, 8'd3));
        receive_frame_id(3);
        wait (rd_done);
        release axi_mem.rresp;
        axi_mem.rresp = 2'b00;
        @(posedge clk);
        @(negedge clk);
        assert (rd_axi_error && rd_error && irq)
            else $fatal(1, "VDMA failed to report injected RRESP error");
        begin
            logic [31:0] status;
            axil_m.read(VDMA_STATUS, status);
            assert (status[7] && status[5] && status[8])
                else $fatal(1, "VDMA RRESP status mismatch: %h", status);
        end
        $display("[VDMA] AXI BRESP/RRESP fault reporting and failed-slot suppression passed");

        // Telemetry: empty frame-store playback attempts count as underruns.
        // Repeated capture into all three slots without display consumption
        // counts dropped/overwritten buffered frames. Genlocked capture while
        // playback remains busy counts sync pressure/loss.
        axil_m.write(VDMA_FRAME_CTRL, 32'h0);
        axil_m.write(VDMA_FRAME_CTRL,
                     vdma_frame_policy_word(1'b1, 1'b0, 2'd0,
                                            1'b0, 2'd0,
                                            1'b1, 1'b1, 1'b1, 1'b0));
        axil_m.write(VDMA_IRQ_ACK,
                     vdma_irq_ack_word(1'b1, 1'b1, 1'b1));
        axil_m.write(VDMA_RD_CTRL,
                     vdma_ctrl_word(1'b1, 1'b0, 3'd3, 8'd3));
        discard_frame(WIDTH_PIXELS * HEIGHT_LINES);
        wait (rd_done);
        begin
            logic [31:0] status;
            axil_m.read(VDMA_STATUS, status);
            assert (status[23:20] == 4'd1)
                else $fatal(1, "VDMA underrun counter mismatch: %h", status);
        end

        axil_m.write(VDMA_IRQ_ACK,
                     vdma_irq_ack_word(1'b1, 1'b1, 1'b1));
        for (int frame = 0; frame < 4; frame++) begin
            axil_m.write(VDMA_WR_CTRL,
                         vdma_ctrl_word(1'b1, 1'b0, 3'd3, 8'd3));
            fork
                send_frame_id(20 + frame);
                wait (wr_done);
            join
        end
        begin
            logic [31:0] status;
            axil_m.read(VDMA_STATUS, status);
            assert (status[27:24] == 4'd1)
                else $fatal(1, "VDMA overwrite counter mismatch: %h", status);
        end

        axil_m.write(VDMA_IRQ_ACK,
                     vdma_irq_ack_word(1'b1, 1'b1, 1'b1));
        axil_m.write(VDMA_RD_HSIZE, HSIZE_BYTES);
        axil_m.write(VDMA_RD_STRIDE, STRIDE_BYTES);
        axil_m.write(VDMA_RD_VSIZE, HEIGHT_LINES * 4);
        axil_m.write(VDMA_FRAME_CTRL,
                     vdma_frame_policy_word(1'b1, 1'b0, 2'd0,
                                            1'b1, 2'd0,
                                            1'b1, 1'b1, 1'b1, 1'b0));
        axil_m.write(VDMA_WR_CTRL,
                     vdma_ctrl_word(1'b1, 1'b0, 3'd3, 8'd3));
        fork
            send_frame_id(30);
            wait (wr_done);
        join
        repeat (4) @(posedge clk);
        assert (rd_busy)
            else $fatal(1, "VDMA genlock reader did not start for telemetry stress");
        axil_m.write(VDMA_WR_CTRL,
                     vdma_ctrl_word(1'b1, 1'b0, 3'd3, 8'd3));
        fork
            send_frame_id(31);
            wait (wr_done);
        join
        begin
            logic [31:0] status;
            axil_m.read(VDMA_STATUS, status);
            assert (status[31:28] != 4'd0)
                else $fatal(1, "VDMA sync-loss counter mismatch: %h", status);
        end
        axil_m.write(VDMA_FRAME_CTRL, 32'h0);
        discard_frame(WIDTH_PIXELS * HEIGHT_LINES * 4);
        wait (!rd_busy);
        $display("[VDMA] underrun/overwrite/sync-loss telemetry counters passed");

        // A 21-byte RGB888-style line occupies three 64-bit beats. The final
        // beat has five valid bytes and must produce/return TKEEP=0x1f.
        axil_m.write(VDMA_FRAME_CTRL, 32'h0);
        axil_m.write(VDMA_WR_ADDR, 32'h0000_1800);
        axil_m.write(VDMA_RD_ADDR, 32'h0000_1800);
        axil_m.write(VDMA_WR_STRIDE, 32'd32);
        axil_m.write(VDMA_RD_STRIDE, 32'd32);
        axil_m.write(VDMA_WR_HSIZE, 32'd21);
        axil_m.write(VDMA_RD_HSIZE, 32'd21);
        axil_m.write(VDMA_WR_VSIZE, 32'd1);
        axil_m.write(VDMA_RD_VSIZE, 32'd1);
        axil_m.write(VDMA_WR_CTRL,
                     vdma_ctrl_word(1'b1, 1'b0, 3'd3, 8'd3));
        fork
            send_partial_line();
            wait (wr_done);
        join
        assert (!wr_error) else $fatal(1, "VDMA partial capture failed");

        axil_m.write(VDMA_RD_CTRL,
                     vdma_ctrl_word(1'b1, 1'b0, 3'd3, 8'd3));
        receive_partial_line();
        wait (rd_done);
        assert (!rd_error) else $fatal(1, "VDMA partial playback failed");
        $display("[VDMA] partial final memory beat passed (21-byte line, TKEEP=1f)");

        // Throughput smoke: a larger frame with no stream-side backpressure.
        // This is not a DDR model; it catches accidental bubbles in the VDMA
        // datapath/control path while allowing current MM2S line/burst gaps.
        axil_m.write(VDMA_FRAME_CTRL, 32'h0);
        configure_write_custom(THR_BASE_ADDR, THR_STRIDE_BYTES,
                               THR_HSIZE_BYTES, THR_HEIGHT_LINES);
        begin
            int wr_beats;
            int wr_cycles;
            axil_m.write(VDMA_WR_CTRL,
                         vdma_ctrl_word(1'b1, 1'b0, 3'd3, 8'd15));
            fork
                send_frame_rect_count(40, THR_WIDTH_PIXELS, THR_HEIGHT_LINES,
                                      wr_beats, wr_cycles);
                wait (wr_done);
            join
            assert (!wr_error) else $fatal(1, "VDMA throughput capture failed");
            assert ((wr_beats * 100 / wr_cycles) >= 90)
                else $fatal(1, "VDMA S2MM throughput too low: beats=%0d cycles=%0d",
                            wr_beats, wr_cycles);
            $display("[VDMA THROUGHPUT] S2MM %0d beats in %0d cycles (%0d%%)",
                     wr_beats, wr_cycles, wr_beats * 100 / wr_cycles);
        end

        configure_read_custom(THR_BASE_ADDR, THR_STRIDE_BYTES,
                              THR_HSIZE_BYTES, THR_HEIGHT_LINES);
        begin
            int rd_beats;
            int rd_cycles;
            axil_m.write(VDMA_RD_CTRL,
                         vdma_ctrl_word(1'b1, 1'b0, 3'd3, 8'd15));
            fork
                receive_frame_rect_count(40, THR_WIDTH_PIXELS, THR_HEIGHT_LINES,
                                         rd_beats, rd_cycles);
                wait (rd_done);
            join
            assert (!rd_error) else $fatal(1, "VDMA throughput playback failed");
            // MM2S keeps several read bursts in flight; allow randomized
            // slave-ready gaps but catch regressions back to per-line bubbles.
            assert ((rd_beats * 100 / rd_cycles) >= 85)
                else $fatal(1, "VDMA MM2S throughput too low: beats=%0d cycles=%0d",
                            rd_beats, rd_cycles);
            $display("[VDMA THROUGHPUT] MM2S %0d beats in %0d cycles (%0d%%)",
                     rd_beats, rd_cycles, rd_beats * 100 / rd_cycles);
        end

        // Restore the 8x4 frame-store configuration for circular stress.
        axil_m.write(VDMA_WR_STRIDE, STRIDE_BYTES);
        axil_m.write(VDMA_WR_HSIZE, HSIZE_BYTES);
        axil_m.write(VDMA_WR_VSIZE, HEIGHT_LINES);
        axil_m.write(VDMA_FRAME_CTRL,
                     vdma_frame_policy_word(1'b1, 1'b0, 2'd0,
                                            1'b0, 2'd0,
                                            1'b1, 1'b1, 1'b1, 1'b0));

        // CTRL[2] free-runs the writer. Two consecutive source frames must be
        // accepted without software issuing another start, rotating slots at
        // each completed frame boundary.
        axil_m.write(VDMA_WR_CTRL,
                     vdma_ctrl_word(1'b1, 1'b0, 3'd3, 8'd3) | 32'h4);
        fork
            begin
                send_frame_id(4);
                send_frame_id(5);
            end
            begin
                int circular_done;
                circular_done = 0;
                while (circular_done < 2) begin
                    @(posedge clk);
                    if (wr_done) begin
                        circular_done++;
                        if (circular_done == 1)
                            axil_m.write(VDMA_WR_CTRL,
                                         vdma_ctrl_word(1'b0, 1'b0, 3'd3, 8'd3));
                    end
                end
            end
        join
        repeat (2) @(posedge clk);
        @(negedge clk);
        assert (newest_complete_slot == 2'd1 && write_slot == 2'd2)
            else $fatal(1, "VDMA circular rotation mismatch newest=%0d write=%0d",
                        newest_complete_slot, write_slot);
        $display("[VDMA] circular writer auto-restart passed for two frames");

        $finish;
    end

    initial begin
        #20_000 $fatal(1, "VDMA test timeout wr_busy=%0b wr_done=%0b wr_error=%0b wr_axi=%0b marker=%0b config=%0b abort=%0b rd_busy=%0b rd_done=%0b mm2s_state=%0d line=%0d beat=%0d valid=%0b ready=%0b",
                          wr_busy, wr_done, wr_error, wr_axi_error,
                          dut.u_s2mm.marker_error, dut.u_s2mm.config_error,
                          dut.u_s2mm.abort_error,
                          rd_busy, rd_done, dut.u_mm2s.state,
                          dut.u_mm2s.output_line, dut.u_mm2s.output_beat,
                          playback_axis.tvalid, playback_axis.tready);
    end

endmodule : test_vdma

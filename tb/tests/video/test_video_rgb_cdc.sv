`timescale 1ns/1ps

module test_video_rgb_cdc(input logic clk, input logic rst_n);
`ifdef VIDEO_VALIDATE
    localparam int WIDTH = 32;
    localparam int HEIGHT = 16;
`else
    localparam int WIDTH = 8;
    localparam int HEIGHT = 4;
`endif
    localparam int DATA_WIDTH = 64;
    localparam int CDC_FIFO_DEPTH = (WIDTH <= 8) ? 64 : 256;

    logic capture_clk;
    logic axi_clk;
    logic display_clk;
    initial begin
        capture_clk = 1'b0;
        forever #3 capture_clk = ~capture_clk;
    end
    initial begin
        axi_clk = 1'b0;
        forever #2 axi_clk = ~axi_clk;
    end
    initial begin
        display_clk = 1'b0;
        #1;
        forever #3 display_clk = ~display_clk;
    end

    logic capture_rst_n = 1'b0;
    logic axi_rst_n = 1'b0;
    logic display_rst_n = 1'b0;

    logic [23:0] in_data, out_data;
    logic in_user, in_valid, in_ready, in_last;
    logic out_user, out_valid, out_ready, out_last;
    logic [DATA_WIDTH-1:0] packed_data;
    logic [DATA_WIDTH/8-1:0] packed_keep;
    logic packed_user, packed_valid, packed_ready, packed_last;

    function automatic logic [23:0] pixel(input int frame, row, col);
        pixel = {8'(frame), 8'(row), 8'(col)};
    endfunction

    snix_video_capture_cdc #(.DATA_WIDTH(DATA_WIDTH), .FIFO_DEPTH(CDC_FIFO_DEPTH)) u_capture (
        .capture_clk, .capture_rst_n,
        .s_axis_tdata(in_data), .s_axis_tuser(in_user),
        .s_axis_tvalid(in_valid), .s_axis_tready(in_ready), .s_axis_tlast(in_last),
        .axi_clk, .axi_rst_n,
        .m_axis_tdata(packed_data), .m_axis_tkeep(packed_keep),
        .m_axis_tuser(packed_user), .m_axis_tvalid(packed_valid),
        .m_axis_tready(packed_ready), .m_axis_tlast(packed_last)
    );

    snix_video_display_cdc #(.DATA_WIDTH(DATA_WIDTH), .FIFO_DEPTH(CDC_FIFO_DEPTH)) u_display (
        .axi_clk, .axi_rst_n,
        .s_axis_tdata(packed_data), .s_axis_tkeep(packed_keep),
        .s_axis_tuser(packed_user), .s_axis_tvalid(packed_valid),
        .s_axis_tready(packed_ready), .s_axis_tlast(packed_last),
        .display_clk, .display_rst_n,
        .m_axis_tdata(out_data), .m_axis_tuser(out_user),
        .m_axis_tvalid(out_valid), .m_axis_tready(out_ready), .m_axis_tlast(out_last)
    );

    task automatic send_frames;
        for (int frame = 0; frame < 2; frame++) begin
            for (int row = 0; row < HEIGHT; row++) begin
                for (int col = 0; col < WIDTH; col++) begin
                    @(negedge capture_clk);
                    in_data  = pixel(frame, row, col);
                    in_user  = (row == 0) && (col == 0);
                    in_last  = (col == WIDTH - 1);
                    in_valid = 1'b1;
                    @(posedge capture_clk);
                    while (!in_ready)
                        @(posedge capture_clk);
                end
            end
        end
        @(negedge capture_clk);
        in_valid = 1'b0;
        in_user  = 1'b0;
        in_last  = 1'b0;
    endtask

    task automatic receive_frames;
        int count = 0;
        int ready_cycle = 0;
        while (count < 2 * WIDTH * HEIGHT) begin
            @(negedge display_clk);
            out_ready = ((ready_cycle % 7) != 3);
            ready_cycle++;
            @(posedge display_clk);
            if (out_valid && out_ready) begin
                int frame = count / (WIDTH * HEIGHT);
                int frame_offset = count % (WIDTH * HEIGHT);
                int row = frame_offset / WIDTH;
                int col = frame_offset % WIDTH;
                assert (out_data == pixel(frame, row, col))
                    else $fatal(1, "RGB CDC pixel mismatch f=%0d r=%0d c=%0d", frame, row, col);
                assert (out_user == ((row == 0) && (col == 0)))
                    else $fatal(1, "RGB CDC SOF mismatch f=%0d r=%0d c=%0d", frame, row, col);
                assert (out_last == (col == WIDTH - 1))
                    else $fatal(1, "RGB CDC EOL mismatch f=%0d r=%0d c=%0d", frame, row, col);
                count++;
            end
        end
    endtask

    initial begin
        in_data = '0;
        in_user = 1'b0;
        in_valid = 1'b0;
        in_last = 1'b0;
        out_ready = 1'b0;
        repeat (4) @(posedge capture_clk);
        capture_rst_n = 1'b1;
        repeat (4) @(posedge axi_clk);
        axi_rst_n = 1'b1;
        repeat (4) @(posedge display_clk);
        display_rst_n = 1'b1;
        fork
            send_frames();
            receive_frames();
        join
        $display("[VIDEO RGB CDC] two packed %0dx%0d RGB24 frames passed across 3 clocks",
                 WIDTH, HEIGHT);
        $finish;
    end

`ifdef VIDEO_VALIDATE
    initial #500_000 $fatal(1, "video RGB CDC timeout");
`else
    initial #50_000 $fatal(1, "video RGB CDC timeout");
`endif

    logic unused;
    assign unused = clk ^ rst_n;
endmodule : test_video_rgb_cdc

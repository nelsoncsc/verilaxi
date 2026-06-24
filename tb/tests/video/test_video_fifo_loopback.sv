`timescale 1ns/1ps

module test_video_fifo_loopback (
    input logic clk,
    input logic rst_n
);

    localparam snix_video_pkg::video_timing_t TIMING =
        snix_video_pkg::TEST_8x4;
    localparam int H_TOTAL = TIMING.h_active + TIMING.h_front_porch +
                             TIMING.h_sync_pulse + TIMING.h_back_porch;
    localparam int V_TOTAL = TIMING.v_active + TIMING.v_front_porch +
                             TIMING.v_sync_pulse + TIMING.v_back_porch;
    // Large enough for the tiny 8x4 verification frame. Real video datapaths
    // generally use a few lines of elastic storage rather than a frame FIFO.
    localparam int FIFO_DEPTH = 64;

    logic src_hsync, src_vsync, src_de, src_sof, src_eol;
    logic [$clog2(H_TOTAL)-1:0] src_x;
    logic [$clog2(V_TOTAL)-1:0] src_y;
    logic [23:0] src_pixel;

    logic [23:0] in_tdata, out_tdata;
    logic [0:0]  in_tuser, out_tuser;
    logic in_tlast, in_tvalid, in_tready;
    logic out_tlast, out_tvalid, out_tready;
    logic overflow;

    logic display_enable;
    logic display_rst_n;
    logic dst_hsync, dst_vsync, dst_timing_de, dst_timing_sof, dst_timing_eol;
    logic [$clog2(H_TOTAL)-1:0] dst_x;
    logic [$clog2(V_TOTAL)-1:0] dst_y;
    logic dst_de, dst_sof, dst_eol;
    logic [23:0] dst_pixel;
    logic underflow, frame_error;
    int frames_done;

    function automatic logic [23:0] expected_pixel(input int x);
        case ((x * 8) / TIMING.h_active)
            0: return 24'hffffff;
            1: return 24'hffff00;
            2: return 24'h00ffff;
            3: return 24'h00ff00;
            4: return 24'hff00ff;
            5: return 24'hff0000;
            6: return 24'h0000ff;
            default: return 24'h000000;
        endcase
    endfunction

    snix_video_timing_gen #(.TIMING(TIMING)) u_src_timing (
        .clk, .rst_n, .hsync(src_hsync), .vsync(src_vsync),
        .active_video(src_de), .sof(src_sof), .eol(src_eol),
        .pixel_x(src_x), .pixel_y(src_y)
    );

    snix_video_pattern_gen #(.TIMING(TIMING)) u_pattern (
        .active_video(src_de), .pixel_x(src_x), .pixel_y(src_y),
        .pixel_data(src_pixel)
    );

    snix_video_to_axis #(.DATA_WIDTH(24), .USER_WIDTH(1)) u_to_axis (
        .clk, .rst_n,
        .video_de(src_de), .video_sof(src_sof), .video_eol(src_eol),
        .video_data(src_pixel),
        .m_axis_tdata(in_tdata), .m_axis_tuser(in_tuser),
        .m_axis_tlast(in_tlast), .m_axis_tvalid(in_tvalid),
        .m_axis_tready(in_tready), .overflow
    );

    snix_axis_fifo #(
        .DATA_WIDTH(24), .USER_WIDTH(1),
        .FIFO_DEPTH(FIFO_DEPTH), .FRAME_FIFO(1'b0)
    ) u_video_fifo (
        .clk, .rst_n,
        .s_axis_tdata(in_tdata), .s_axis_tuser(in_tuser),
        .s_axis_tvalid(in_tvalid), .s_axis_tlast(in_tlast),
        .s_axis_tready(in_tready),
        .m_axis_tdata(out_tdata), .m_axis_tuser(out_tuser),
        .m_axis_tvalid(out_tvalid), .m_axis_tlast(out_tlast),
        .m_axis_tready(out_tready)
    );

    // Hold the display side off until one tiny active test frame is buffered.
    // This is deliberate downstream backpressure; the FIFO must hide it from
    // the non-stallable native-video source. Production VDMA stores full
    // frames in external memory and sizes this FIFO in lines.
    assign display_rst_n = rst_n && display_enable;

    snix_video_timing_gen #(.TIMING(TIMING)) u_dst_timing (
        .clk, .rst_n(display_rst_n), .hsync(dst_hsync), .vsync(dst_vsync),
        .active_video(dst_timing_de), .sof(dst_timing_sof),
        .eol(dst_timing_eol), .pixel_x(dst_x), .pixel_y(dst_y)
    );

    snix_axis_to_video #(.DATA_WIDTH(24), .USER_WIDTH(1)) u_to_video (
        .clk, .rst_n,
        .timing_de(display_enable && dst_timing_de),
        .timing_sof(display_enable && dst_timing_sof),
        .timing_eol(display_enable && dst_timing_eol),
        .s_axis_tdata(out_tdata), .s_axis_tuser(out_tuser),
        .s_axis_tlast(out_tlast), .s_axis_tvalid(out_tvalid),
        .s_axis_tready(out_tready),
        .video_de(dst_de), .video_sof(dst_sof), .video_eol(dst_eol),
        .video_data(dst_pixel), .underflow, .frame_error
    );

    axis_checker #(.DATA_WIDTH(24), .USER_WIDTH(1), .LABEL("VIDEO_FIFO_IN"))
        u_input_checker (
            .clk, .rst_n, .tdata(in_tdata), .tuser(in_tuser),
            .tvalid(in_tvalid), .tready(in_tready), .tlast(in_tlast)
        );

    axis_checker #(.DATA_WIDTH(24), .USER_WIDTH(1), .LABEL("VIDEO_FIFO_OUT"))
        u_output_checker (
            .clk, .rst_n, .tdata(out_tdata), .tuser(out_tuser),
            .tvalid(out_tvalid), .tready(out_tready), .tlast(out_tlast)
        );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            display_enable <= 1'b0;
            frames_done    <= 0;
        end else begin
            if (!display_enable && src_de && src_eol &&
                (int'(src_y) == TIMING.v_active - 1))
                display_enable <= 1'b1;

            if (src_de)
                assert (in_tready)
                    else $fatal(1, "video FIFO filled while native video was active");

            if (display_enable && dst_timing_de) begin
                assert (dst_de)
                    else $fatal(1, "buffered video underflow at (%0d,%0d)", dst_x, dst_y);
                assert (dst_pixel == expected_pixel(int'(dst_x)))
                    else $fatal(1, "buffered pixel mismatch at (%0d,%0d): exp=%h got=%h",
                                dst_x, dst_y, expected_pixel(int'(dst_x)), dst_pixel);
                assert (dst_sof == dst_timing_sof && dst_eol == dst_timing_eol)
                    else $fatal(1, "buffered frame markers misaligned");

                if (dst_eol && int'(dst_y) == TIMING.v_active - 1) begin
                    frames_done <= frames_done + 1;
                    $display("[VIDEO FIFO] frame %0d passed after buffered backpressure",
                             frames_done + 1);
                end
            end
        end
    end

    initial begin
        wait (rst_n);
        wait (frames_done == 2);
        @(posedge clk);
        assert (!overflow && !underflow && !frame_error)
            else $fatal(1, "buffered adapter flags: overflow=%0b underflow=%0b frame_error=%0b",
                        overflow, underflow, frame_error);
        $finish;
    end

    initial begin
        #10_000 $fatal(1, "video FIFO loopback timeout");
    end

endmodule : test_video_fifo_loopback

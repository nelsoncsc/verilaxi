`timescale 1ns/1ps

module test_video_afifo_loopback (
    input logic clk,    // unused: the test creates independent pixel clocks
    input logic rst_n   // unused
);

    localparam snix_video_pkg::video_timing_t TIMING =
        snix_video_pkg::TEST_8x4;
    localparam int H_TOTAL = TIMING.h_active + TIMING.h_front_porch +
                             TIMING.h_sync_pulse + TIMING.h_back_porch;
    localparam int V_TOTAL = TIMING.v_active + TIMING.v_front_porch +
                             TIMING.v_sync_pulse + TIMING.v_back_porch;
    // Large enough for the tiny 8x4 verification frame. A production VDMA
    // normally buffers only a few lines here; full frames reside in memory.
    localparam int FIFO_DEPTH = 64;

    // Deliberately unrelated clocks: capture is 6 ns, display is 4 ns.
    logic capture_clk;
    logic display_clk;
    initial capture_clk = 1'b0;
    initial display_clk = 1'b0;
    always #3 capture_clk = ~capture_clk;
    always #2 display_clk = ~display_clk;

    logic capture_rst_n, afifo_display_rst_n, display_rst_n;
    logic prefill_done;

    logic src_hsync, src_vsync, src_de, src_sof, src_eol;
    logic [$clog2(H_TOTAL)-1:0] src_x;
    logic [$clog2(V_TOTAL)-1:0] src_y;
    logic [23:0] src_pixel;

    logic [23:0] in_tdata, cdc_tdata, out_tdata;
    logic [24:0] cdc_packed_tdata;
    logic [0:0] in_tuser, cdc_tuser, out_tuser;
    logic in_tlast, in_tvalid, in_tready;
    logic cdc_tlast, cdc_tvalid, cdc_tready;
    logic out_tlast, out_tvalid, out_tready;
    logic overflow;

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

    initial begin
        capture_rst_n     = 1'b0;
        afifo_display_rst_n = 1'b0;
        display_rst_n     = 1'b0;
        repeat (4) @(posedge capture_clk);
        capture_rst_n = 1'b1;

        // Prefill one tiny test frame before enabling the read clock domain.
        // This deterministic startup technique is not a full-frame hardware
        // buffering recommendation for production resolutions.
        wait (prefill_done);
        repeat (2) @(posedge display_clk);
        afifo_display_rst_n = 1'b1;
        // Wait until CDC and local prefetch stages contain the first pixel.
        wait (out_tvalid);
        repeat (2) @(posedge display_clk);
        display_rst_n = 1'b1;
    end

    snix_video_timing_gen #(.TIMING(TIMING)) u_src_timing (
        .clk(capture_clk), .rst_n(capture_rst_n),
        .hsync(src_hsync), .vsync(src_vsync), .active_video(src_de),
        .sof(src_sof), .eol(src_eol), .pixel_x(src_x), .pixel_y(src_y)
    );

    snix_video_pattern_gen #(.TIMING(TIMING)) u_pattern (
        .active_video(src_de), .pixel_x(src_x), .pixel_y(src_y),
        .pixel_data(src_pixel)
    );

    snix_video_to_axis #(.DATA_WIDTH(24), .USER_WIDTH(1)) u_to_axis (
        .clk(capture_clk), .rst_n(capture_rst_n),
        .video_de(src_de), .video_sof(src_sof), .video_eol(src_eol),
        .video_data(src_pixel),
        .m_axis_tdata(in_tdata), .m_axis_tuser(in_tuser),
        .m_axis_tlast(in_tlast), .m_axis_tvalid(in_tvalid),
        .m_axis_tready(in_tready), .overflow
    );

    // The base async AXIS FIFO carries tdata/tlast only. Pack SOF/tuser into
    // the data payload for this video CDC path, then unpack it in the display
    // clock domain before the normal video-aware sync FIFO.
    snix_axis_afifo #(
        .DATA_WIDTH(25),
        .FIFO_DEPTH(FIFO_DEPTH), .FRAME_FIFO(1'b0)
    ) u_video_afifo (
        .s_axis_clk(capture_clk), .s_axis_rst_n(capture_rst_n),
        .s_axis_tdata({in_tuser[0], in_tdata}),
        .s_axis_tvalid(in_tvalid), .s_axis_tlast(in_tlast),
        .s_axis_tready(in_tready),
        .m_axis_clk(display_clk), .m_axis_rst_n(afifo_display_rst_n),
        .m_axis_tdata(cdc_packed_tdata),
        .m_axis_tvalid(cdc_tvalid), .m_axis_tlast(cdc_tlast),
        .m_axis_tready(cdc_tready)
    );

    assign {cdc_tuser[0], cdc_tdata} = cdc_packed_tdata;

    // A read-domain elastic FIFO decouples CDC draining from raster blanking.
    // This mirrors the usual hardware structure: AFIFO for CDC, sync FIFO for
    // local burst/blanking elasticity.
    snix_axis_fifo #(
        .DATA_WIDTH(24), .USER_WIDTH(1),
        .FIFO_DEPTH(FIFO_DEPTH), .FRAME_FIFO(1'b0)
    ) u_display_fifo (
        .clk(display_clk), .rst_n(afifo_display_rst_n),
        .s_axis_tdata(cdc_tdata), .s_axis_tuser(cdc_tuser),
        .s_axis_tvalid(cdc_tvalid), .s_axis_tlast(cdc_tlast),
        .s_axis_tready(cdc_tready),
        .m_axis_tdata(out_tdata), .m_axis_tuser(out_tuser),
        .m_axis_tvalid(out_tvalid), .m_axis_tlast(out_tlast),
        .m_axis_tready(out_tready)
    );

    snix_video_timing_gen #(.TIMING(TIMING)) u_dst_timing (
        .clk(display_clk), .rst_n(display_rst_n),
        .hsync(dst_hsync), .vsync(dst_vsync), .active_video(dst_timing_de),
        .sof(dst_timing_sof), .eol(dst_timing_eol),
        .pixel_x(dst_x), .pixel_y(dst_y)
    );

    snix_axis_to_video #(.DATA_WIDTH(24), .USER_WIDTH(1)) u_to_video (
        .clk(display_clk), .rst_n(display_rst_n),
        .timing_de(display_rst_n && dst_timing_de),
        .timing_sof(display_rst_n && dst_timing_sof),
        .timing_eol(display_rst_n && dst_timing_eol),
        .s_axis_tdata(out_tdata), .s_axis_tuser(out_tuser),
        .s_axis_tlast(out_tlast), .s_axis_tvalid(out_tvalid),
        .s_axis_tready(out_tready),
        .video_de(dst_de), .video_sof(dst_sof), .video_eol(dst_eol),
        .video_data(dst_pixel), .underflow, .frame_error
    );

    axis_checker #(.DATA_WIDTH(24), .USER_WIDTH(1), .LABEL("VIDEO_AFIFO_IN"))
        u_input_checker (
            .clk(capture_clk), .rst_n(capture_rst_n),
            .tdata(in_tdata), .tuser(in_tuser), .tvalid(in_tvalid),
            .tready(in_tready), .tlast(in_tlast)
        );

    axis_checker #(.DATA_WIDTH(24), .USER_WIDTH(1), .LABEL("VIDEO_AFIFO_OUT"))
        u_output_checker (
            .clk(display_clk), .rst_n(afifo_display_rst_n),
            .tdata(cdc_tdata), .tuser(cdc_tuser), .tvalid(cdc_tvalid),
            .tready(cdc_tready), .tlast(cdc_tlast)
        );

    always_ff @(posedge capture_clk or negedge capture_rst_n) begin
        if (!capture_rst_n)
            prefill_done <= 1'b0;
        else begin
            if (!prefill_done && src_de && src_eol &&
                (int'(src_y) == TIMING.v_active - 1))
                prefill_done <= 1'b1;

            if (src_de)
                assert (in_tready)
                    else $fatal(1, "video AFIFO filled while capture video was active");
        end
    end

    always_ff @(posedge display_clk or negedge display_rst_n) begin
        if (!display_rst_n)
            frames_done <= 0;
        else if (dst_timing_de) begin
            assert (dst_de)
                else $fatal(1, "async video underflow at (%0d,%0d)", dst_x, dst_y);
            assert (dst_pixel == expected_pixel(int'(dst_x)))
                else $fatal(1, "async pixel mismatch at (%0d,%0d): exp=%h got=%h",
                            dst_x, dst_y, expected_pixel(int'(dst_x)), dst_pixel);
            assert (dst_sof == dst_timing_sof && dst_eol == dst_timing_eol)
                else $fatal(1, "async video frame markers misaligned");

            if (dst_eol && int'(dst_y) == TIMING.v_active - 1) begin
                frames_done <= frames_done + 1;
                $display("[VIDEO AFIFO] frame %0d passed (capture=6ns display=4ns)",
                         frames_done + 1);
            end
        end
    end

    initial begin
        wait (frames_done == 2);
        @(posedge display_clk);
        assert (!overflow && !underflow && !frame_error)
            else $fatal(1, "async adapter flags: overflow=%0b underflow=%0b frame_error=%0b",
                        overflow, underflow, frame_error);
        $finish;
    end

    initial begin
        #20_000 $fatal(1, "video AFIFO loopback timeout");
    end

endmodule : test_video_afifo_loopback

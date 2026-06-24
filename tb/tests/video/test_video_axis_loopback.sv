`timescale 1ns/1ps

module test_video_axis_loopback (
    input logic clk,
    input logic rst_n
);

    localparam snix_video_pkg::video_timing_t TIMING =
        snix_video_pkg::TEST_8x4;
    localparam int H_TOTAL = TIMING.h_active + TIMING.h_front_porch +
                             TIMING.h_sync_pulse + TIMING.h_back_porch;
    localparam int V_TOTAL = TIMING.v_active + TIMING.v_front_porch +
                             TIMING.v_sync_pulse + TIMING.v_back_porch;

    logic hsync, vsync, active_video, sof, eol;
    logic [$clog2(H_TOTAL)-1:0] pixel_x;
    logic [$clog2(V_TOTAL)-1:0] pixel_y;
    logic [23:0] source_pixel;

    axis_if #(.DATA_WIDTH(24), .USER_WIDTH(1), .KEEP_WIDTH(3))
        video_axis (.ACLK(clk), .ARESETn(rst_n));

    logic recovered_de, recovered_sof, recovered_eol;
    logic [23:0] recovered_pixel;
    logic overflow, underflow, frame_error;
    int frame_pixels;
    int frame_lines;
    int frames_done;
    int print_pixels;

    initial begin
        print_pixels = 0;
        void'($value$plusargs("PRINT_PIXELS=%d", print_pixels));
    end

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

    snix_video_timing_gen #(.TIMING(TIMING)) u_timing (
        .clk, .rst_n, .hsync, .vsync, .active_video, .sof, .eol,
        .pixel_x, .pixel_y
    );

    snix_video_pattern_gen #(.TIMING(TIMING)) u_pattern (
        .active_video, .pixel_x, .pixel_y, .pixel_data(source_pixel)
    );

    snix_video_to_axis #(.DATA_WIDTH(24), .USER_WIDTH(1)) u_to_axis (
        .clk, .rst_n,
        .video_de(active_video), .video_sof(sof), .video_eol(eol),
        .video_data(source_pixel),
        .m_axis_tdata(video_axis.tdata), .m_axis_tuser(video_axis.tuser),
        .m_axis_tlast(video_axis.tlast), .m_axis_tvalid(video_axis.tvalid),
        .m_axis_tready(video_axis.tready), .overflow
    );

    assign video_axis.tkeep = 3'b111;

    snix_axis_to_video #(.DATA_WIDTH(24), .USER_WIDTH(1)) u_to_video (
        .clk, .rst_n,
        .timing_de(active_video), .timing_sof(sof), .timing_eol(eol),
        .s_axis_tdata(video_axis.tdata), .s_axis_tuser(video_axis.tuser),
        .s_axis_tlast(video_axis.tlast), .s_axis_tvalid(video_axis.tvalid),
        .s_axis_tready(video_axis.tready),
        .video_de(recovered_de), .video_sof(recovered_sof),
        .video_eol(recovered_eol), .video_data(recovered_pixel),
        .underflow, .frame_error
    );

    axis_checker #(.DATA_WIDTH(24), .USER_WIDTH(1), .LABEL("VIDEO_AXIS"))
        u_axis_checker (
            .clk, .rst_n,
            .tdata(video_axis.tdata), .tuser(video_axis.tuser),
            .tvalid(video_axis.tvalid), .tready(video_axis.tready),
            .tlast(video_axis.tlast)
        );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            frame_pixels <= 0;
            frame_lines  <= 0;
            frames_done  <= 0;
        end else if (active_video) begin
            if (print_pixels)
                $display("[VIDEO PIXEL] frame=%0d row=%0d col=%0d rgb=%06h sof=%0b eol=%0b",
                         frames_done, pixel_y, pixel_x, recovered_pixel,
                         recovered_sof, recovered_eol);
            assert (recovered_de)
                else $fatal(1, "video underflow at (%0d,%0d)", pixel_x, pixel_y);
            assert (recovered_pixel == source_pixel)
                else $fatal(1, "pixel mismatch at (%0d,%0d): exp=%h got=%h",
                            pixel_x, pixel_y, source_pixel, recovered_pixel);
            assert (source_pixel == expected_pixel(int'(pixel_x)))
                else $fatal(1, "pattern mismatch at (%0d,%0d): model=%h rtl=%h",
                            pixel_x, pixel_y, expected_pixel(int'(pixel_x)),
                            source_pixel);
            assert (video_axis.tuser[0] == sof)
                else $fatal(1, "SOF mismatch at (%0d,%0d)", pixel_x, pixel_y);
            assert (video_axis.tlast == eol)
                else $fatal(1, "EOL mismatch at (%0d,%0d)", pixel_x, pixel_y);
            assert (int'(pixel_x) == frame_pixels % TIMING.h_active)
                else $fatal(1, "x coordinate mismatch");
            assert (int'(pixel_y) == frame_pixels / TIMING.h_active)
                else $fatal(1, "y coordinate mismatch");

            if (sof) begin
                assert (frame_pixels == 0 && frame_lines == 0)
                    else $fatal(1, "SOF arrived before counters reset");
            end

            if (eol && int'(pixel_y) == TIMING.v_active - 1) begin
                assert (frame_pixels + 1 == TIMING.h_active * TIMING.v_active)
                    else $fatal(1, "frame pixel count mismatch: %0d",
                                frame_pixels + 1);
                assert (frame_lines + 1 == TIMING.v_active)
                    else $fatal(1, "frame line count mismatch: %0d",
                                frame_lines + 1);
                frames_done  <= frames_done + 1;
                frame_pixels <= 0;
                frame_lines  <= 0;
                $display("[VIDEO] frame %0d passed (%0dx%0d)",
                         frames_done + 1, TIMING.h_active, TIMING.v_active);
            end else begin
                frame_pixels <= frame_pixels + 1;
                if (eol)
                    frame_lines <= frame_lines + 1;
            end
        end else begin
            assert (!recovered_de && source_pixel == 24'h000000)
                else $fatal(1, "non-blank output outside active video");
        end

        if (rst_n) begin
            assert (hsync == ((int'(pixel_x) >= TIMING.h_active + TIMING.h_front_porch) &&
                              (int'(pixel_x) <  TIMING.h_active + TIMING.h_front_porch +
                                                TIMING.h_sync_pulse)))
                else $fatal(1, "HSYNC timing mismatch at x=%0d", pixel_x);
            assert (vsync == ((int'(pixel_y) >= TIMING.v_active + TIMING.v_front_porch) &&
                              (int'(pixel_y) <  TIMING.v_active + TIMING.v_front_porch +
                                                TIMING.v_sync_pulse)))
                else $fatal(1, "VSYNC timing mismatch at y=%0d", pixel_y);
        end
    end

    initial begin
        wait (rst_n);
        wait (frames_done == 2);
        @(posedge clk);
        assert (!overflow && !underflow && !frame_error)
            else $fatal(1, "adapter flags: overflow=%0b underflow=%0b frame_error=%0b",
                        overflow, underflow, frame_error);
        $finish;
    end

    initial begin
        #5000 $fatal(1, "video loopback timeout");
    end

endmodule : test_video_axis_loopback

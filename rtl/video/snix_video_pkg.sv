`timescale 1ns/1ps

package snix_video_pkg;

    typedef enum logic [3:0] {
        PIXFMT_RGB24   = 4'd0,
        PIXFMT_RGB32   = 4'd1,
        PIXFMT_YUYV422 = 4'd2,
        PIXFMT_UYVY422 = 4'd3,
        PIXFMT_YUV420P = 4'd4
    } pixel_format_t;

    function automatic int unsigned pixel_fmt_bytes(input pixel_format_t fmt);
        case (fmt)
            PIXFMT_RGB24:   pixel_fmt_bytes = 3;
            PIXFMT_RGB32:   pixel_fmt_bytes = 4;
            PIXFMT_YUYV422: pixel_fmt_bytes = 2;
            PIXFMT_UYVY422: pixel_fmt_bytes = 2;
            default:        pixel_fmt_bytes = 4;
        endcase
    endfunction

    typedef struct packed {
        int unsigned h_active;
        int unsigned h_front_porch;
        int unsigned h_sync_pulse;
        int unsigned h_back_porch;
        int unsigned v_active;
        int unsigned v_front_porch;
        int unsigned v_sync_pulse;
        int unsigned v_back_porch;
    } video_timing_t;

    /* verilator lint_off UNUSEDPARAM */
    // Canonical nominal pixel clocks for the timing presets below. Physical
    // hardware must generate these with a PLL/MMCM; these constants describe
    // the target rate and are also consumed by simulation clock generators.
    localparam longint unsigned VGA_640x480_CLK_HZ   = 64'd25_175_000;
    localparam longint unsigned HD_1280x720_CLK_HZ   = 64'd74_250_000;
    localparam longint unsigned FHD_1920x1080_CLK_HZ = 64'd148_500_000;
    localparam longint unsigned UHD_3840x2160_CLK_HZ = 64'd594_000_000;

    // Tiny mode for fast protocol-level simulation.
    localparam video_timing_t TEST_8x4 = {
        32'd8, 32'd1, 32'd2, 32'd1,
        32'd4, 32'd1, 32'd1, 32'd1
    };

    localparam video_timing_t TEST_16x8 = {
        32'd16, 32'd2, 32'd2, 32'd2,
        32'd8,  32'd1, 32'd1, 32'd1
    };

    localparam video_timing_t TEST_32x16 = {
        32'd32, 32'd4, 32'd4, 32'd4,
        32'd16, 32'd2, 32'd2, 32'd2
    };

    localparam video_timing_t TEST_64x32 = {
        32'd64, 32'd8, 32'd8, 32'd8,
        32'd32, 32'd4, 32'd4, 32'd4
    };

    localparam video_timing_t TEST_64x48 = {
        32'd64, 32'd8, 32'd8, 32'd8,
        32'd48, 32'd4, 32'd4, 32'd4
    };

    localparam video_timing_t VGA_640x480 = {
        32'd640, 32'd16, 32'd96, 32'd48,
        32'd480, 32'd10, 32'd2, 32'd33
    };

    localparam video_timing_t HD_1280x720 = {
        32'd1280, 32'd110, 32'd40, 32'd220,
        32'd720,  32'd5,   32'd5,  32'd20
    };

    localparam video_timing_t FHD_1920x1080 = {
        32'd1920, 32'd88, 32'd44, 32'd148,
        32'd1080, 32'd4,  32'd5,  32'd36
    };

    localparam video_timing_t UHD_3840x2160 = {
        32'd3840, 32'd176, 32'd88, 32'd296,
        32'd2160, 32'd8,   32'd10, 32'd72
    };
    /* verilator lint_on UNUSEDPARAM */

endpackage : snix_video_pkg

class video_frame_gen #(
    parameter snix_video_pkg::video_timing_t TIMING =
        snix_video_pkg::VGA_640x480
);

    typedef enum { COLORBARS, RAMP, CHECKERBOARD, RANDOM, CUSTOM } pattern_e;

    pattern_e pattern = COLORBARS;
    logic [23:0] frame[];  // flat pixel array

    function new();
        frame = new[TIMING.h_active * TIMING.v_active];
    endfunction

    function void generate_frame();
        for (int y = 0; y < TIMING.v_active; y++) begin
            for (int x = 0; x < TIMING.h_active; x++) begin
                frame[y * TIMING.h_active + x] = get_pixel(x, y);
            end
        end
    endfunction

    function logic [23:0] get_pixel(int x, int y);
        case (pattern)
            COLORBARS:   return colorbar_pixel(x);
            RAMP:        return ramp_pixel(x, y);
            CHECKERBOARD:return checker_pixel(x, y);
            RANDOM:      return {$urandom()};
            default:     return '0;
        endcase
    endfunction

    function logic [23:0] colorbar_pixel(int x);
        case ((x * 8) / TIMING.h_active)
            0: return 24'hFFFFFF;
            1: return 24'hFFFF00;
            2: return 24'h00FFFF;
            3: return 24'h00FF00;
            4: return 24'hFF00FF;
            5: return 24'hFF0000;
            6: return 24'h0000FF;
            7: return 24'h000000;
            default: return '0;
        endcase
    endfunction

    function logic [23:0] ramp_pixel(int x, int y);
        logic [7:0] r, g, b;
        r = (x * 255) / ((TIMING.h_active > 1) ? TIMING.h_active - 1 : 1);
        g = (y * 255) / ((TIMING.v_active > 1) ? TIMING.v_active - 1 : 1);
        b = 8'h80;
        return {r, g, b};
    endfunction

    function logic [23:0] checker_pixel(int x, int y);
        return ((x[4] ^ y[4])) ? 24'hFFFFFF : 24'h000000;
    endfunction

endclass: video_frame_gen

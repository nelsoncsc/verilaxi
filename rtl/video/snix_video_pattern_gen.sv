module snix_video_pattern_gen #(
    parameter snix_video_pkg::video_timing_t TIMING =
        snix_video_pkg::VGA_640x480
) (
    input  logic active_video,
    input  logic [$clog2(TIMING.h_active + TIMING.h_front_porch +
                         TIMING.h_sync_pulse + TIMING.h_back_porch)-1:0] pixel_x,
    input  logic [$clog2(TIMING.v_active + TIMING.v_front_porch +
                         TIMING.v_sync_pulse + TIMING.v_back_porch)-1:0] pixel_y,
    output logic [23:0] pixel_data
);

    logic [2:0] bar_index;

    always_comb begin
        // Multiplication before division keeps tiny test modes well-defined.
        bar_index = (pixel_x * 8) / TIMING.h_active;
        if (!active_video) begin
            pixel_data = 24'h000000;
        end else begin
            case (bar_index)
                3'd0: pixel_data = 24'hffffff;
                3'd1: pixel_data = 24'hffff00;
                3'd2: pixel_data = 24'h00ffff;
                3'd3: pixel_data = 24'h00ff00;
                3'd4: pixel_data = 24'hff00ff;
                3'd5: pixel_data = 24'hff0000;
                3'd6: pixel_data = 24'h0000ff;
                default: pixel_data = 24'h000000;
            endcase
        end
    end

endmodule : snix_video_pattern_gen

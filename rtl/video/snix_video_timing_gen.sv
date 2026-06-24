module snix_video_timing_gen #(
    parameter snix_video_pkg::video_timing_t TIMING =
        snix_video_pkg::VGA_640x480
) (
    input  logic clk,
    input  logic rst_n,
    output logic hsync,
    output logic vsync,
    output logic active_video,
    output logic sof,
    output logic eol,
    output logic [$clog2(TIMING.h_active + TIMING.h_front_porch +
                         TIMING.h_sync_pulse + TIMING.h_back_porch)-1:0] pixel_x,
    output logic [$clog2(TIMING.v_active + TIMING.v_front_porch +
                         TIMING.v_sync_pulse + TIMING.v_back_porch)-1:0] pixel_y
);

    localparam int H_TOTAL = TIMING.h_active + TIMING.h_front_porch +
                             TIMING.h_sync_pulse + TIMING.h_back_porch;
    localparam int V_TOTAL = TIMING.v_active + TIMING.v_front_porch +
                             TIMING.v_sync_pulse + TIMING.v_back_porch;
    localparam int H_WIDTH = $clog2(H_TOTAL);
    localparam int V_WIDTH = $clog2(V_TOTAL);

    // =====================================================================================================
    // Counters
    // =====================================================================================================
    logic [$clog2(H_TOTAL)-1:0] h_count;
    logic [$clog2(V_TOTAL)-1:0] v_count;

    always_ff @(posedge clk or negedge rst_n) 
        if (!rst_n) begin
            h_count <= '0;
            v_count <= '0;
        end else begin
            if (h_count == H_WIDTH'(H_TOTAL - 1)) begin
                h_count <= '0;
                v_count <= (v_count == V_WIDTH'(V_TOTAL - 1))
                         ? '0 : v_count + 1'b1;
            end
            else begin
                h_count <= h_count + 1'b1;
            end
        end

    
    always_comb begin
        pixel_x      = h_count;
        pixel_y      = v_count;
        active_video = (h_count < H_WIDTH'(TIMING.h_active)) &&
                       (v_count < V_WIDTH'(TIMING.v_active));
        sof           = active_video && (h_count == 0) && (v_count == 0);
        eol           = active_video &&
                        (h_count == H_WIDTH'(TIMING.h_active - 1));
        hsync         = (h_count >= H_WIDTH'(TIMING.h_active +
                                             TIMING.h_front_porch)) &&
                        (h_count < H_WIDTH'(TIMING.h_active +
                                            TIMING.h_front_porch +
                                            TIMING.h_sync_pulse));
        vsync         = (v_count >= V_WIDTH'(TIMING.v_active +
                                             TIMING.v_front_porch)) &&
                        (v_count < V_WIDTH'(TIMING.v_active +
                                            TIMING.v_front_porch +
                                            TIMING.v_sync_pulse));
    end

endmodule : snix_video_timing_gen

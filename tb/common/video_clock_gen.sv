`timescale 1ns/1ps

// Simulation-only pixel clock. FPGA hardware must use a PLL/MMCM or an
// external clock source; fabric logic should not synthesize a clock this way.
module video_clock_gen #(
    parameter longint unsigned CLOCK_HZ = 25_175_000
) (
    output logic clk
);

    localparam realtime HALF_PERIOD_NS = 500_000_000.0 / CLOCK_HZ;

    initial begin
        clk = 1'b0;
        forever #(HALF_PERIOD_NS) clk = ~clk;
    end

endmodule : video_clock_gen

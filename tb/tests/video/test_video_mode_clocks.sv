`timescale 1ns/1ps

module test_video_mode_clocks (
    input logic clk,    // unused: this test creates the mode clocks
    input logic rst_n   // unused
);

    logic vga_clk, hd_clk, fhd_clk, uhd_clk;
    int vga_edges, hd_edges, fhd_edges, uhd_edges;
    realtime vga_first, hd_first, fhd_first, uhd_first;
    realtime vga_last, hd_last, fhd_last, uhd_last;

    video_clock_gen #(.CLOCK_HZ(snix_video_pkg::VGA_640x480_CLK_HZ))
        u_vga_clk (.clk(vga_clk));
    video_clock_gen #(.CLOCK_HZ(snix_video_pkg::HD_1280x720_CLK_HZ))
        u_hd_clk (.clk(hd_clk));
    video_clock_gen #(.CLOCK_HZ(snix_video_pkg::FHD_1920x1080_CLK_HZ))
        u_fhd_clk (.clk(fhd_clk));
    video_clock_gen #(.CLOCK_HZ(snix_video_pkg::UHD_3840x2160_CLK_HZ))
        u_uhd_clk (.clk(uhd_clk));

    // Testbench monitors intentionally use blocking assignments so each edge
    // count and timestamp are captured atomically in the same time slot.
    /* verilator lint_off BLKSEQ */
    always @(posedge vga_clk) begin
        vga_edges++;
        if (vga_edges == 1) vga_first = $realtime;
        if (vga_edges == 6) vga_last  = $realtime;
    end

    always @(posedge hd_clk) begin
        hd_edges++;
        if (hd_edges == 1) hd_first = $realtime;
        if (hd_edges == 6) hd_last  = $realtime;
    end

    always @(posedge fhd_clk) begin
        fhd_edges++;
        if (fhd_edges == 1) fhd_first = $realtime;
        if (fhd_edges == 6) fhd_last  = $realtime;
    end

    always @(posedge uhd_clk) begin
        uhd_edges++;
        if (uhd_edges == 1) uhd_first = $realtime;
        if (uhd_edges == 6) uhd_last  = $realtime;
    end
    /* verilator lint_on BLKSEQ */

    function automatic void check_clock(
        input string name,
        input longint unsigned expected_hz,
        input realtime first_edge,
        input realtime last_edge
    );
        realtime measured_period_ns;
        realtime expected_period_ns;
        realtime error_ns;

        measured_period_ns = (last_edge - first_edge) / 5.0;
        expected_period_ns = 1_000_000_000.0 / expected_hz;
        error_ns = (measured_period_ns > expected_period_ns)
                 ? measured_period_ns - expected_period_ns
                 : expected_period_ns - measured_period_ns;

        assert (error_ns <= 0.0011) // 1 ps clock quantisation tolerance
            else $fatal(1, "%s clock mismatch: expected=%0.6fns measured=%0.6fns",
                        name, expected_period_ns, measured_period_ns);
        $display("[VIDEO CLOCK] %-9s %0.3f MHz, period=%0.3f ns",
                 name, expected_hz / 1_000_000.0, measured_period_ns);
    endfunction

    initial begin
        vga_edges = 0;
        hd_edges  = 0;
        fhd_edges = 0;
        uhd_edges = 0;

        wait (vga_edges >= 6 && hd_edges >= 6 &&
              fhd_edges >= 6 && uhd_edges >= 6);

        check_clock("640x480",   snix_video_pkg::VGA_640x480_CLK_HZ,
                    vga_first, vga_last);
        check_clock("1280x720",  snix_video_pkg::HD_1280x720_CLK_HZ,
                    hd_first, hd_last);
        check_clock("1920x1080", snix_video_pkg::FHD_1920x1080_CLK_HZ,
                    fhd_first, fhd_last);
        check_clock("3840x2160", snix_video_pkg::UHD_3840x2160_CLK_HZ,
                    uhd_first, uhd_last);
        $finish;
    end

    initial begin
        #1_000 $fatal(1, "video mode clock test timeout");
    end

endmodule : test_video_mode_clocks

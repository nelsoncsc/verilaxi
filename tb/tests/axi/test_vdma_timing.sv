`timescale 1ns/1ps
//
// End-to-end VDMA timing integration test.
// Clock domains: pixel_clk (74.25 MHz capture), clk (200 MHz AXI), display_clk (74.25 MHz playback).
// Pipeline: timing_gen → pattern_gen → to_axis → capture_cdc → VDMA S2MM
//           → axi_slave → VDMA MM2S → display_cdc → pixel checker.
// Verifies: clock-domain crossings, correct pixel data round-trip, no overflow/underrun.
//
module test_vdma_timing #(
    parameter int ADDR_WIDTH   = 32,
    parameter int DATA_WIDTH   = 64,
    parameter int ID_WIDTH     = 4,
    parameter int USER_WIDTH   = 1
) (
    input logic clk,
    input logic rst_n
);
    import axi_pkg::*;
    import axi_vdma_pkg::*;

`ifdef VIDEO_PNG
    localparam snix_video_pkg::video_timing_t TIMING = snix_video_pkg::TEST_64x48;
    localparam int FRAMES_TO_RUN = 6;
`elsif VIDEO_VALIDATE
    localparam snix_video_pkg::video_timing_t TIMING = snix_video_pkg::TEST_32x16;
    localparam int FRAMES_TO_RUN = 4;
`else
    localparam snix_video_pkg::video_timing_t TIMING = snix_video_pkg::TEST_8x4;
    localparam int FRAMES_TO_RUN = 4;
`endif

    localparam int H_ACTIVE      = TIMING.h_active;
    localparam int V_ACTIVE      = TIMING.v_active;
    localparam int BYTES_PER_PIX = 3; // RGB24
    localparam int HSIZE_BYTES   = H_ACTIVE * BYTES_PER_PIX;
    localparam int STRIDE_BYTES  = 256;
    localparam int FRAME_BYTES   = STRIDE_BYTES * V_ACTIVE;
    localparam logic [31:0] FRAME_ADDR0 = 32'h0000_1000;
    localparam logic [31:0] FRAME_ADDR1 = FRAME_ADDR0 + FRAME_BYTES;
    localparam logic [31:0] FRAME_ADDR2 = FRAME_ADDR1 + FRAME_BYTES;
    localparam int MEM_DEPTH     = 16384;
    localparam int CDC_FIFO_DEPTH = 64;
    localparam int AXIL_ADDR_WIDTH = 32;
    localparam int AXIL_DATA_WIDTH = 32;

    // -----------------------------------------------------------------
    // Pixel / display clock domains (74.25 MHz, independent phases)
    // -----------------------------------------------------------------
    logic pixel_clk, display_clk;
    logic pixel_rst_n, display_rst_n;
    logic vdma_configured; // pulsed by main task after WR_CTRL is written

    video_clock_gen #(.CLOCK_HZ(snix_video_pkg::HD_1280x720_CLK_HZ)) u_pixel_clk (
        .clk(pixel_clk)
    );
    video_clock_gen #(.CLOCK_HZ(snix_video_pkg::HD_1280x720_CLK_HZ)) u_display_clk (
        .clk(display_clk)
    );

    // Hold pixel/display resets until VDMA is fully configured and S2MM is
    // armed.  This guarantees the first beat from capture_cdc always carries
    // TUSER=1 (SOF), which is what snix_axi_vdma_s2mm expects on beat 0.
    initial begin
        vdma_configured = 1'b0;
        pixel_rst_n     = 1'b0;
        display_rst_n   = 1'b0;
        wait (vdma_configured === 1'b1);
        repeat (2) @(posedge pixel_clk);
        pixel_rst_n = 1'b1;
        repeat (4) @(posedge display_clk);
        display_rst_n = 1'b1;
    end

    // -----------------------------------------------------------------
    // AXI / AXI-Lite interfaces (AXI clock domain = clk)
    // -----------------------------------------------------------------
    axi4_if #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH(ID_WIDTH), .USER_WIDTH(USER_WIDTH)
    ) axi_mem (.ACLK(clk), .ARESETn(rst_n));

    axil_if #(
        .ADDR_WIDTH(AXIL_ADDR_WIDTH), .DATA_WIDTH(AXIL_DATA_WIDTH)
    ) axil (.ACLK(clk), .ARESETn(rst_n));

    // -----------------------------------------------------------------
    // Capture pipeline: timing_gen → pattern_gen → to_axis → capture_cdc
    //                   (pixel_clk domain → axi_clk domain)
    // -----------------------------------------------------------------
    localparam int H_TOTAL = H_ACTIVE + TIMING.h_front_porch +
                             TIMING.h_sync_pulse + TIMING.h_back_porch;
    localparam int V_TOTAL = V_ACTIVE + TIMING.v_front_porch +
                             TIMING.v_sync_pulse + TIMING.v_back_porch;

    logic src_hsync, src_vsync, src_de, src_sof, src_eol;
    logic [$clog2(H_TOTAL)-1:0] src_x;
    logic [$clog2(V_TOTAL)-1:0] src_y;
    logic [23:0] src_pixel;
    logic        cap_overflow;

    // Direct 24-bit output from video_to_axis (not backpressurable)
    logic [23:0] raw_tdata;
    logic [0:0]  raw_tuser;
    logic        raw_tlast, raw_tvalid, raw_tready_unused;

    // PNG source mux — pixel_clk domain counters + combinational DPI override
    logic [23:0] src_pixel_muxed;
    int          png_src_col, png_src_row, png_src_frame;

    always_ff @(posedge pixel_clk or negedge pixel_rst_n) begin
        if (!pixel_rst_n) begin
            png_src_col   <= 0;
            png_src_row   <= 0;
            png_src_frame <= 0;
        end else if (src_de) begin
            if (png_src_col == H_ACTIVE - 1) begin
                png_src_col <= 0;
                if (png_src_row == V_ACTIVE - 1) begin
                    png_src_row   <= 0;
                    png_src_frame <= png_src_frame + 1;
                end else png_src_row <= png_src_row + 1;
            end else png_src_col <= png_src_col + 1;
        end
    end

    always_comb begin
        if (png_src_enabled)
            src_pixel_muxed = 24'(vf_src_get_pixel(
                png_src_frame * H_ACTIVE * V_ACTIVE +
                png_src_row   * H_ACTIVE +
                png_src_col));
        else
            src_pixel_muxed = src_pixel;
    end

    // Buffered 24-bit stream (after sync FIFO that absorbs rr_converter DRAIN stalls)
    logic [23:0] buf_tdata;
    logic [0:0]  buf_tuser;
    logic        buf_tlast, buf_tvalid, buf_tready;

    logic [DATA_WIDTH-1:0]   cap_tdata;
    logic [DATA_WIDTH/8-1:0] cap_tkeep;
    logic [0:0]              cap_tuser;
    logic                    cap_tlast, cap_tvalid, cap_tready;

    snix_video_timing_gen #(.TIMING(TIMING)) u_timing (
        .clk(pixel_clk), .rst_n(pixel_rst_n),
        .hsync(src_hsync), .vsync(src_vsync),
        .active_video(src_de), .sof(src_sof), .eol(src_eol),
        .pixel_x(src_x), .pixel_y(src_y)
    );

    snix_video_pattern_gen #(.TIMING(TIMING)) u_pattern (
        .active_video(src_de), .pixel_x(src_x), .pixel_y(src_y),
        .pixel_data(src_pixel)
    );

    snix_video_to_axis #(.DATA_WIDTH(24), .USER_WIDTH(1)) u_to_axis (
        .clk(pixel_clk), .rst_n(pixel_rst_n),
        .video_de(src_de), .video_sof(src_sof), .video_eol(src_eol),
        .video_data(src_pixel_muxed),
        .m_axis_tdata(raw_tdata), .m_axis_tuser(raw_tuser),
        .m_axis_tlast(raw_tlast), .m_axis_tvalid(raw_tvalid),
        .m_axis_tready(raw_tready_unused), .overflow(cap_overflow)
    );

    // Sync FIFO absorbs 1-cycle backpressure from rgb24_pack during DRAIN.
    // video_to_axis is not backpressurable; without this buffer it drops pixels.
    snix_axis_fifo #(.DATA_WIDTH(24), .USER_WIDTH(1), .FIFO_DEPTH(32)) u_pix_fifo (
        .clk(pixel_clk), .rst_n(pixel_rst_n),
        .s_axis_tdata(raw_tdata), .s_axis_tuser(raw_tuser),
        .s_axis_tlast(raw_tlast), .s_axis_tvalid(raw_tvalid),
        .s_axis_tready(raw_tready_unused),
        .m_axis_tdata(buf_tdata), .m_axis_tuser(buf_tuser),
        .m_axis_tlast(buf_tlast), .m_axis_tvalid(buf_tvalid),
        .m_axis_tready(buf_tready)
    );

    snix_video_capture_cdc #(
        .DATA_WIDTH(DATA_WIDTH), .FIFO_DEPTH(CDC_FIFO_DEPTH)
    ) u_capture_cdc (
        .capture_clk(pixel_clk), .capture_rst_n(pixel_rst_n),
        .s_axis_tdata(buf_tdata), .s_axis_tuser(buf_tuser[0]),
        .s_axis_tvalid(buf_tvalid), .s_axis_tready(buf_tready),
        .s_axis_tlast(buf_tlast),
        .axi_clk(clk), .axi_rst_n(rst_n),
        .m_axis_tdata(cap_tdata), .m_axis_tkeep(cap_tkeep),
        .m_axis_tuser(cap_tuser), .m_axis_tvalid(cap_tvalid),
        .m_axis_tready(cap_tready), .m_axis_tlast(cap_tlast)
    );

    // -----------------------------------------------------------------
    // VDMA DUT
    // -----------------------------------------------------------------
    logic wr_busy, wr_done, wr_error, wr_axi_error;
    logic rd_busy, rd_done, rd_error, rd_axi_error;
    logic irq;
    logic [31:0] vdma_status;
    logic [1:0]  write_slot, read_slot, newest_complete_slot;
    logic [2:0]  valid_slots;

    logic [DATA_WIDTH-1:0]   play_tdata;
    logic [DATA_WIDTH/8-1:0] play_tkeep;
    logic [USER_WIDTH-1:0]   play_tuser;
    logic                    play_tlast, play_tvalid, play_tready;

    snix_axi_vdma #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
        .AXIL_ADDR_WIDTH(AXIL_ADDR_WIDTH), .AXIL_DATA_WIDTH(AXIL_DATA_WIDTH),
        .ID_WIDTH(ID_WIDTH), .USER_WIDTH(USER_WIDTH), .LINE_FIFO_DEPTH(64)
    ) dut (
        .clk, .rst_n,
        .s_axil_awaddr(axil.awaddr), .s_axil_awvalid(axil.awvalid),
        .s_axil_awready(axil.awready),
        .s_axil_wdata(axil.wdata), .s_axil_wstrb(axil.wstrb),
        .s_axil_wvalid(axil.wvalid), .s_axil_wready(axil.wready),
        .s_axil_bresp(axil.bresp), .s_axil_bvalid(axil.bvalid),
        .s_axil_bready(axil.bready),
        .s_axil_araddr(axil.araddr), .s_axil_arvalid(axil.arvalid),
        .s_axil_arready(axil.arready),
        .s_axil_rdata(axil.rdata), .s_axil_rresp(axil.rresp),
        .s_axil_rvalid(axil.rvalid), .s_axil_rready(axil.rready),
        .s_axis_tdata(cap_tdata), .s_axis_tuser(USER_WIDTH'(cap_tuser)),
        .s_axis_tkeep(cap_tkeep),
        .s_axis_tvalid(cap_tvalid), .s_axis_tready(cap_tready),
        .s_axis_tlast(cap_tlast),
        .m_axis_tdata(play_tdata), .m_axis_tuser(play_tuser),
        .m_axis_tkeep(play_tkeep),
        .m_axis_tvalid(play_tvalid), .m_axis_tready(play_tready),
        .m_axis_tlast(play_tlast),
        .wr_busy, .wr_done, .wr_error, .wr_axi_error,
        .rd_busy, .rd_done, .rd_error, .rd_axi_error,
        .vdma_status, .irq,
        .write_slot, .read_slot, .newest_complete_slot, .valid_slots,
        .s2mm_awid(axi_mem.awid), .s2mm_awaddr(axi_mem.awaddr),
        .s2mm_awlen(axi_mem.awlen), .s2mm_awsize(axi_mem.awsize),
        .s2mm_awburst(axi_mem.awburst), .s2mm_awlock(axi_mem.awlock),
        .s2mm_awcache(axi_mem.awcache), .s2mm_awprot(axi_mem.awprot),
        .s2mm_awqos(axi_mem.awqos), .s2mm_awuser(axi_mem.awuser),
        .s2mm_awvalid(axi_mem.awvalid), .s2mm_awready(axi_mem.awready),
        .s2mm_wdata(axi_mem.wdata), .s2mm_wstrb(axi_mem.wstrb),
        .s2mm_wlast(axi_mem.wlast), .s2mm_wuser(axi_mem.wuser),
        .s2mm_wvalid(axi_mem.wvalid), .s2mm_wready(axi_mem.wready),
        .s2mm_bid(axi_mem.bid), .s2mm_bresp(axi_mem.bresp),
        .s2mm_buser(axi_mem.buser), .s2mm_bvalid(axi_mem.bvalid),
        .s2mm_bready(axi_mem.bready),
        .mm2s_arid(axi_mem.arid), .mm2s_araddr(axi_mem.araddr),
        .mm2s_arlen(axi_mem.arlen), .mm2s_arsize(axi_mem.arsize),
        .mm2s_arburst(axi_mem.arburst), .mm2s_arlock(axi_mem.arlock),
        .mm2s_arcache(axi_mem.arcache), .mm2s_arprot(axi_mem.arprot),
        .mm2s_arqos(axi_mem.arqos), .mm2s_aruser(axi_mem.aruser),
        .mm2s_arvalid(axi_mem.arvalid), .mm2s_arready(axi_mem.arready),
        .mm2s_rid(axi_mem.rid), .mm2s_rdata(axi_mem.rdata),
        .mm2s_rresp(axi_mem.rresp), .mm2s_rlast(axi_mem.rlast),
        .mm2s_ruser(axi_mem.ruser), .mm2s_rvalid(axi_mem.rvalid),
        .mm2s_rready(axi_mem.rready)
    );

    // -----------------------------------------------------------------
    // Display pipeline: display_cdc → pixel checker (display_clk domain)
    // -----------------------------------------------------------------
    logic [23:0] disp_tdata;
    logic [0:0]  disp_tuser;
    logic        disp_tlast, disp_tvalid, disp_tready;

    snix_video_display_cdc #(
        .DATA_WIDTH(DATA_WIDTH), .FIFO_DEPTH(CDC_FIFO_DEPTH)
    ) u_display_cdc (
        .axi_clk(clk), .axi_rst_n(rst_n),
        .s_axis_tdata(play_tdata), .s_axis_tkeep(play_tkeep),
        .s_axis_tuser(play_tuser[0]), .s_axis_tvalid(play_tvalid),
        .s_axis_tready(play_tready), .s_axis_tlast(play_tlast),
        .display_clk, .display_rst_n,
        .m_axis_tdata(disp_tdata), .m_axis_tuser(disp_tuser[0]),
        .m_axis_tvalid(disp_tvalid), .m_axis_tready(disp_tready),
        .m_axis_tlast(disp_tlast)
    );

    assign disp_tready = 1'b1;

    // -----------------------------------------------------------------
    // SVA checkers
    // -----------------------------------------------------------------
    axi_mm_checker #(
        .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
        .ID_WIDTH(ID_WIDTH), .ALLOW_ERROR_RESP(1'b1), .LABEL("VDMA_TIMING_MM")
    ) u_mm_checker (
        .clk, .rst_n,
        .awaddr(axi_mem.awaddr), .awlen(axi_mem.awlen),
        .awsize(axi_mem.awsize), .awburst(axi_mem.awburst),
        .awid(axi_mem.awid), .awvalid(axi_mem.awvalid), .awready(axi_mem.awready),
        .wdata(axi_mem.wdata), .wstrb(axi_mem.wstrb),
        .wlast(axi_mem.wlast), .wvalid(axi_mem.wvalid), .wready(axi_mem.wready),
        .bid(axi_mem.bid), .bresp(axi_mem.bresp),
        .bvalid(axi_mem.bvalid), .bready(axi_mem.bready),
        .araddr(axi_mem.araddr), .arlen(axi_mem.arlen),
        .arsize(axi_mem.arsize), .arburst(axi_mem.arburst),
        .arid(axi_mem.arid), .arvalid(axi_mem.arvalid), .arready(axi_mem.arready),
        .rid(axi_mem.rid), .rdata(axi_mem.rdata), .rresp(axi_mem.rresp),
        .rlast(axi_mem.rlast), .rvalid(axi_mem.rvalid), .rready(axi_mem.rready)
    );

    axi_4k_checker #(.ADDR_WIDTH(ADDR_WIDTH), .LABEL("VDMA_TIMING_4K")) u_4k_checker (
        .clk, .rst_n,
        .awaddr(axi_mem.awaddr), .awlen(axi_mem.awlen),
        .awsize(axi_mem.awsize), .awvalid(axi_mem.awvalid),
        .awready(axi_mem.awready),
        .araddr(axi_mem.araddr), .arlen(axi_mem.arlen),
        .arsize(axi_mem.arsize), .arvalid(axi_mem.arvalid),
        .arready(axi_mem.arready)
    );

    axil_checker #(
        .ADDR_WIDTH(AXIL_ADDR_WIDTH), .DATA_WIDTH(AXIL_DATA_WIDTH),
        .LABEL("VDMA_TIMING_AXIL")
    ) u_axil_checker (
        .clk, .rst_n,
        .awaddr(axil.awaddr), .awvalid(axil.awvalid), .awready(axil.awready),
        .wdata(axil.wdata), .wstrb(axil.wstrb),
        .wvalid(axil.wvalid), .wready(axil.wready),
        .bresp(axil.bresp), .bvalid(axil.bvalid), .bready(axil.bready),
        .araddr(axil.araddr), .arvalid(axil.arvalid), .arready(axil.arready),
        .rdata(axil.rdata), .rresp(axil.rresp),
        .rvalid(axil.rvalid), .rready(axil.rready)
    );

    axis_checker #(.DATA_WIDTH(DATA_WIDTH), .USER_WIDTH(USER_WIDTH),
                   .LABEL("VDMA_TIMING_CAP")) u_cap_checker (
        .clk, .rst_n,
        .tdata(cap_tdata), .tuser(USER_WIDTH'(cap_tuser)),
        .tvalid(cap_tvalid), .tready(cap_tready), .tlast(cap_tlast)
    );

    axis_checker #(.DATA_WIDTH(DATA_WIDTH), .USER_WIDTH(USER_WIDTH),
                   .LABEL("VDMA_TIMING_PLAY")) u_play_checker (
        .clk, .rst_n,
        .tdata(play_tdata), .tuser(play_tuser),
        .tvalid(play_tvalid), .tready(play_tready), .tlast(play_tlast)
    );

    // -----------------------------------------------------------------
    // Pixel checker + frame source/sink (display_clk domain)
    // Source: activate with +PNG_SRC_DIR=<dir> (VIDEO_PNG mode only).
    //         Loads frame_00.png .. frame_05.png and drives exp_pix from them.
    // Sink:   activate with +PNG_SINK_PREFIX=<path> — writes one PNG per frame.
    // Both are inlined here (not submodules) for correct Verilator eval order.
    // -----------------------------------------------------------------
    import "DPI-C" function void vf_src_load(input string path);
    import "DPI-C" function void vf_src_load_append(input string path);
    import "DPI-C" function int  vf_src_get_pixel(input int idx);
    import "DPI-C" function int  vf_src_width();
    import "DPI-C" function int  vf_src_height();
    import "DPI-C" function int  vf_src_total_pixels();
    import "DPI-C" function void vf_sink_push(input int rgb24);
    import "DPI-C" function void vf_sink_write(input string path,
                                               input int    width,
                                               input int    height);

    int          display_frames_done;
    int          display_errors;
    int          disp_col;
    int          disp_row;
    string       png_prefix;
    bit          png_enabled;
    bit          png_src_enabled;

    initial begin
        png_enabled = $value$plusargs("PNG_SINK_PREFIX=%s", png_prefix);
        png_src_enabled = 0;
`ifdef VIDEO_PNG
        begin
            string src_dir;
            if ($value$plusargs("PNG_SRC_DIR=%s", src_dir)) begin
                automatic string p;
                $sformat(p, "%s/frame_00.png", src_dir); vf_src_load(p);
                $sformat(p, "%s/frame_01.png", src_dir); vf_src_load_append(p);
                $sformat(p, "%s/frame_02.png", src_dir); vf_src_load_append(p);
                $sformat(p, "%s/frame_03.png", src_dir); vf_src_load_append(p);
                $sformat(p, "%s/frame_04.png", src_dir); vf_src_load_append(p);
                $sformat(p, "%s/frame_05.png", src_dir); vf_src_load_append(p);
                if (vf_src_width() != H_ACTIVE || vf_src_height() != V_ACTIVE ||
                    vf_src_total_pixels() != FRAMES_TO_RUN * H_ACTIVE * V_ACTIVE) begin
                    $fatal(1,
                           "[VDMA_TIMING] PNG source mismatch: got %0dx%0d total=%0d, expected %0dx%0d total=%0d from %s",
                           vf_src_width(), vf_src_height(), vf_src_total_pixels(),
                           H_ACTIVE, V_ACTIVE, FRAMES_TO_RUN * H_ACTIVE * V_ACTIVE, src_dir);
                end
                png_src_enabled = 1;
                $display("[VDMA_TIMING] PNG source: loaded 6 frames from %s", src_dir);
            end
        end
`endif
    end

    function automatic logic [23:0] expected_pixel(input int x);
        logic [2:0] bar;
        bar = (x * 8) / H_ACTIVE;
        case (bar)
            3'd0: return 24'hffffff;
            3'd1: return 24'hffff00;
            3'd2: return 24'h00ffff;
            3'd3: return 24'h00ff00;
            3'd4: return 24'hff00ff;
            3'd5: return 24'hff0000;
            3'd6: return 24'h0000ff;
            default: return 24'h000000;
        endcase
    endfunction

    always_ff @(posedge display_clk) begin
        if (!display_rst_n) begin
            display_frames_done <= 0;
            display_errors      <= 0;
            disp_col            <= 0;
            disp_row            <= 0;
        end else if (disp_tvalid && disp_tready) begin
            logic [23:0] exp_pix;
            logic        exp_sof;
            logic        exp_eol;
            if (png_src_enabled)
                exp_pix = 24'(vf_src_get_pixel(
                    display_frames_done * H_ACTIVE * V_ACTIVE +
                    disp_row * H_ACTIVE + disp_col));
            else
                exp_pix = expected_pixel(disp_col);
            exp_sof = (disp_col == 0) && (disp_row == 0);
            exp_eol = (disp_col == H_ACTIVE - 1);

            if (png_enabled) vf_sink_push(int'(disp_tdata));

            if (disp_tdata !== exp_pix) begin
                if (display_errors < 5)
                    $error("[VDMA_TIMING] pixel mismatch frame=%0d row=%0d col=%0d exp=%06h got=%06h",
                           display_frames_done + 1, disp_row, disp_col, exp_pix, disp_tdata);
                display_errors <= display_errors + 1;
            end
            if (disp_tuser[0] !== exp_sof) begin
                if (display_errors < 5)
                    $error("[VDMA_TIMING] SOF mismatch frame=%0d row=%0d col=%0d exp=%0b got=%0b",
                           display_frames_done + 1, disp_row, disp_col, exp_sof, disp_tuser[0]);
                display_errors <= display_errors + 1;
            end
            if (disp_tlast !== exp_eol) begin
                if (display_errors < 5)
                    $error("[VDMA_TIMING] EOL mismatch frame=%0d row=%0d col=%0d exp=%0b got=%0b",
                           display_frames_done + 1, disp_row, disp_col, exp_eol, disp_tlast);
                display_errors <= display_errors + 1;
            end

            if (exp_eol) begin
                disp_col <= 0;
                if (disp_row == V_ACTIVE - 1) begin
                    disp_row            <= 0;
                    display_frames_done <= display_frames_done + 1;
                    $display("[VDMA_TIMING] frame %0d received %0dx%0d errors_so_far=%0d",
                             display_frames_done + 1, H_ACTIVE, V_ACTIVE, display_errors);
                    if (png_enabled) begin
                        automatic string p;
                        $sformat(p, "%s_%0d.png", png_prefix, display_frames_done + 1);
                        vf_sink_write(p, H_ACTIVE, V_ACTIVE);
                    end
                end else begin
                    disp_row <= disp_row + 1;
                end
            end else begin
                disp_col <= disp_col + 1;
            end
        end
    end

    // -----------------------------------------------------------------
    // BFMs
    // -----------------------------------------------------------------
    axi_slave  #(.ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH),
                 .ID_WIDTH(ID_WIDTH), .MEM_DEPTH(MEM_DEPTH)) mem_slave;
    axil_master #(.ADDR_WIDTH(AXIL_ADDR_WIDTH), .DATA_WIDTH(AXIL_DATA_WIDTH)) axil_m;

    // -----------------------------------------------------------------
    // Main test sequence (AXI clock domain)
    // -----------------------------------------------------------------
    initial begin
        axi_mem.init();
        axil.init();
        axil_m   = new(axil);
        axil_m.reset();
        mem_slave = new(axi_mem, "vdma_timing_mem");
        mem_slave.reset();
        for (int i = 0; i < MEM_DEPTH; i++)
            mem_slave.mem[i] = '0;

        fork mem_slave.run(); join_none

        wait (rst_n === 1'b1);
        repeat (5) @(posedge clk);

        // Program triple-buffer frame addresses
        axil_m.write(VDMA_FRAME_ADDR0, FRAME_ADDR0);
        axil_m.write(VDMA_FRAME_ADDR1, FRAME_ADDR1);
        axil_m.write(VDMA_FRAME_ADDR2, FRAME_ADDR2);

        // Frame geometry (S2MM and MM2S use same resolution)
        axil_m.write(VDMA_WR_HSIZE,  HSIZE_BYTES);
        axil_m.write(VDMA_WR_VSIZE,  V_ACTIVE);
        axil_m.write(VDMA_WR_STRIDE, STRIDE_BYTES);
        axil_m.write(VDMA_RD_HSIZE,  HSIZE_BYTES);
        axil_m.write(VDMA_RD_VSIZE,  V_ACTIVE);
        axil_m.write(VDMA_RD_STRIDE, STRIDE_BYTES);

        // Frame control: frame_store on, genlock on, delay=0, IRQ on wr+rd
        axil_m.write(VDMA_FRAME_CTRL,
                     vdma_frame_policy_word(
                         1'b1,  // enable frame store
                         1'b0,  // no park
                         2'd0,  // park_slot unused
                         1'b1,  // genlock_enable
                         2'd0,  // frame_delay = 0 (newest complete)
                         1'b1,  // wr_irq_enable
                         1'b1,  // rd_irq_enable
                         1'b0,  // error_irq_enable
                         1'b0   // irq_clear
                     ));

        // Pre-configure MM2S transfer parameters (start=0 — genlock will fire first).
        // Must be written BEFORE S2MM starts so beat_size/burst_len are correct if
        // genlock_start fires immediately after wr_done.
        axil_m.write(VDMA_RD_CTRL,
                     vdma_ctrl_word(1'b0, 1'b0, 3'd3, 8'd7));

        // Start S2MM in circular mode: beat_size=3 (8B/beat), burst_len=7 (8-beat)
        // bit[2] = circular (auto-restart after each frame)
        axil_m.write(VDMA_WR_CTRL,
                     vdma_ctrl_word(1'b1, 1'b0, 3'd3, 8'd7) | 32'h4);

        // S2MM is now armed; release pixel/display clock domains.
        // The timing_gen starts fresh so the first capture beat carries SOF.
        vdma_configured = 1'b1;

        // Wait for first captured frame; genlock will auto-start MM2S using the
        // RD_CTRL parameters already programmed above.
        wait (wr_done === 1'b1);
        @(posedge clk);

        assert (!wr_error)
            else $fatal(1, "[VDMA_TIMING] S2MM error on first frame wr_axi_error=%0b", wr_axi_error);

        // Wait for enough complete display frames
        wait (display_frames_done >= FRAMES_TO_RUN);
        repeat (10) @(posedge clk);

        assert (display_errors == 0)
            else $fatal(1, "[VDMA_TIMING] %0d pixel/framing errors — see $error output",
                        display_errors);
        assert (!cap_overflow)
            else $fatal(1, "[VDMA_TIMING] capture CDC overflow");
        assert (!wr_error && !rd_error)
            else $fatal(1, "[VDMA_TIMING] VDMA error wr_error=%0b rd_error=%0b",
                        wr_error, rd_error);

        $display("[VDMA_TIMING] PASS — %0d frames verified %0dx%0d RGB24 at pixel_clk=74.25MHz AXI_clk=200MHz",
                 display_frames_done, H_ACTIVE, V_ACTIVE);
        $finish;
    end


    // Simulation timeout
    initial begin
`ifdef VIDEO_VALIDATE
        #100_000_000 $fatal(1, "[VDMA_TIMING] timeout after 100ms (VIDEO_VALIDATE mode)");
`else
        #20_000_000  $fatal(1, "[VDMA_TIMING] timeout after 20ms");
`endif
    end

endmodule : test_vdma_timing

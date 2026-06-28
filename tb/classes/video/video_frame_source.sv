// video_frame_source — drives a 24-bit AXI-Stream from a PNG file loaded via
// DPI-C.  Sits alongside pattern_gen: instantiate both, mux with a parameter
// or plusarg.  Uses +PNG_SRC=<path> at runtime; if the plusarg is absent the
// module holds tvalid low and the downstream consumer stalls gracefully.
//
// Pixel layout: R in tdata[23:16], G in [15:8], B in [7:0] (RGB24, packed).
// tuser = SOF (first pixel of each frame).
// tlast = EOL (last pixel of each row).
module video_frame_source #(
    parameter int H_ACTIVE    = 8,
    parameter int V_ACTIVE    = 4,
    parameter int FRAME_COUNT = 0   // 0 = repeat forever
) (
    input  logic        clk,
    input  logic        rst_n,
    output logic [23:0] m_axis_tdata,
    output logic        m_axis_tuser,
    output logic        m_axis_tvalid,
    input  logic        m_axis_tready,
    output logic        m_axis_tlast
);
    import "DPI-C" function void vf_src_load(input string path);
    import "DPI-C" function int  vf_src_get_pixel(input int idx);
    import "DPI-C" function int  vf_src_width();
    import "DPI-C" function int  vf_src_height();
    import "DPI-C" function int  vf_src_total_pixels();

    int col, row, frame_num;
    bit loaded;
    string png_path;

    // Load PNG once at simulation start.
    initial begin
        loaded = 0;
        if ($value$plusargs("PNG_SRC=%s", png_path)) begin
            vf_src_load(png_path);
            if (vf_src_total_pixels() == 0)
                $fatal(1, "[VIDEO_FRAME_SOURCE] failed to load PNG_SRC=%s", png_path);
            if (vf_src_width() != H_ACTIVE || vf_src_height() != V_ACTIVE)
                $fatal(1,
                       "[VIDEO_FRAME_SOURCE] PNG_SRC dimension mismatch: got %0dx%0d, expected %0dx%0d (%s)",
                       vf_src_width(), vf_src_height(), H_ACTIVE, V_ACTIVE, png_path);
            loaded = 1;
        end
    end

    // Combinational output — DPI lookup is a pure array read, zero latency.
    always_comb begin
        automatic int idx = frame_num * H_ACTIVE * V_ACTIVE + row * H_ACTIVE + col;
        automatic int pix = vf_src_get_pixel(idx);
        m_axis_tdata  = 24'(pix);
        m_axis_tuser  = (col == 0 && row == 0);
        m_axis_tlast  = (col == H_ACTIVE - 1);
        m_axis_tvalid = loaded &&
                        (FRAME_COUNT == 0 || frame_num < FRAME_COUNT);
    end

    // Advance position on each accepted beat.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            col       <= 0;
            row       <= 0;
            frame_num <= 0;
        end else if (m_axis_tvalid && m_axis_tready) begin
            if (col == H_ACTIVE - 1) begin
                col <= 0;
                if (row == V_ACTIVE - 1) begin
                    row <= 0;
                    if (FRAME_COUNT == 0 || frame_num < FRAME_COUNT - 1)
                        frame_num <= frame_num + 1;
                    else
                        frame_num <= frame_num; // saturate
                end else begin
                    row <= row + 1;
                end
            end else begin
                col <= col + 1;
            end
        end
    end

endmodule : video_frame_source

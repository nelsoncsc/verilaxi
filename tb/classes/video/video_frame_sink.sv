// video_frame_sink — accumulates a 24-bit AXI-Stream and writes one PNG per
// frame via DPI-C.  Instantiate alongside the pixel checker; it has no effect
// on the AXI-Stream (tready is not driven here).
//
// Output filenames: <out_prefix>_frame<N>.png  (N starts at 1).
// The prefix is set via +PNG_SINK_PREFIX=<path> at runtime; if absent the
// module is silent (no files written).
//
// Sampling note: this is a TB-only monitor.  It samples on the FALLING edge
// of clk so that all posedge NBA updates and combinational re-evaluations
// (including any rr_converter tvalid/tdata paths) are fully settled before
// the DPI calls are made.  This avoids Verilator evaluation-order issues that
// arise when a submodule monitor samples posedge signals whose combinational
// drivers are updated by sibling submodule NBA writes in the same time step.
module video_frame_sink #(
    parameter int H_ACTIVE = 8,
    parameter int V_ACTIVE = 4
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [23:0] s_axis_tdata,
    input  logic        s_axis_tuser,
    input  logic        s_axis_tvalid,
    input  logic        s_axis_tready,
    input  logic        s_axis_tlast
);
    import "DPI-C" function void vf_sink_push(input int rgb24);
    import "DPI-C" function void vf_sink_write(input string path,
                                               input int width,
                                               input int height);

    int    col, row, frame_num;
    string prefix;
    bit    enabled;

    initial begin
        col = 0; row = 0; frame_num = 0; enabled = 0;
        if ($value$plusargs("PNG_SINK_PREFIX=%s", prefix))
            enabled = 1;
    end

    // VERILATOR NOTE: Verilator's --timing coroutine scheduler does not
    // reliably invoke this block from a submodule context after sibling
    // submodule NBA updates have propagated through combinational logic
    // (e.g. rr_converter m_axis_tvalid = (state==DRAIN) and m_axis_tdata).
    // When using Verilator, inline the DPI calls directly in the test module
    // alongside the pixel checker always_ff, which is evaluated in the correct
    // post-NBA context.  This module works correctly in VCS/Questa/Xsim.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            col       <= 0;
            row       <= 0;
            frame_num <= 0;
        end else if (enabled && s_axis_tvalid && s_axis_tready) begin
            automatic string path;
            vf_sink_push(int'(s_axis_tdata));
            if (col == H_ACTIVE - 1) begin
                col <= 0;
                if (row == V_ACTIVE - 1) begin
                    row <= 0;
                    frame_num <= frame_num + 1;
                    $sformat(path, "%s_%0d.png", prefix, frame_num + 1);
                    vf_sink_write(path, H_ACTIVE, V_ACTIVE);
                end else begin
                    row <= row + 1;
                end
            end else begin
                col <= col + 1;
            end
        end
    end

endmodule : video_frame_sink

// snix_axis_rr_downsizer.sv
//
// AXI-Stream rational-ratio width downsizer.
//
// Wraps snix_axis_rr_converter and enforces the downsize direction:
// IN_DATA_WIDTH must be strictly greater than OUT_DATA_WIDTH.
//
// Internally the GCD-based fill/drain state machine is used:
//   IN_RATIO  = OUT_DATA_WIDTH / GCD  — input beats per group (>= 2)
//   OUT_RATIO = IN_DATA_WIDTH  / GCD  — output beats per group
//
// For integer ratios (IN_DATA_WIDTH exactly divisible by OUT_DATA_WIDTH)
// prefer snix_axis_downsizer, whose IDLE/BURST structure is equivalent
// (IN_RATIO=1) but makes the integer intent explicit.  Use this module
// for non-integer ratios such as 24→16 (2:3) or 48→32 (2:3).

`default_nettype none

module snix_axis_rr_downsizer #(
    parameter int IN_DATA_WIDTH  = 24,   // wide-side width in bits (multiple of 8)
    parameter int OUT_DATA_WIDTH = 16    // narrow-side width; must be < IN_DATA_WIDTH
) (
    input  wire  clk,
    input  wire  rst_n,

    // Slave — wide (IN_DATA_WIDTH bits)
    input  wire  [IN_DATA_WIDTH-1:0]    s_axis_tdata,
    input  wire  [IN_DATA_WIDTH/8-1:0]  s_axis_tkeep,
    input  wire                         s_axis_tvalid,
    output logic                        s_axis_tready,
    input  wire                         s_axis_tlast,

    // Master — narrow (OUT_DATA_WIDTH bits)
    output logic [OUT_DATA_WIDTH-1:0]   m_axis_tdata,
    output logic [OUT_DATA_WIDTH/8-1:0] m_axis_tkeep,
    output logic                        m_axis_tvalid,
    input  wire                         m_axis_tready,
    output logic                        m_axis_tlast
);

    initial begin
        if (IN_DATA_WIDTH <= OUT_DATA_WIDTH)
            $fatal(1, "%m: IN_DATA_WIDTH (%0d) must be greater than OUT_DATA_WIDTH (%0d)",
                   IN_DATA_WIDTH, OUT_DATA_WIDTH);
    end

    snix_axis_rr_converter #(
        .IN_DATA_WIDTH (IN_DATA_WIDTH),
        .OUT_DATA_WIDTH(OUT_DATA_WIDTH)
    ) u_conv (
        .clk          (clk),
        .rst_n        (rst_n),
        .s_axis_tdata (s_axis_tdata),
        .s_axis_tkeep (s_axis_tkeep),
        .s_axis_tvalid(s_axis_tvalid),
        .s_axis_tready(s_axis_tready),
        .s_axis_tlast (s_axis_tlast),
        .m_axis_tdata (m_axis_tdata),
        .m_axis_tkeep (m_axis_tkeep),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast (m_axis_tlast)
    );

endmodule

`default_nettype wire

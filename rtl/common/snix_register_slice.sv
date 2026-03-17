// ============================================================================
//  snix_register_slice.sv
//
//  Generic ready/valid register slice (skid buffer).
//
//  Same architecture as snix_axis_register but without tuser/tlast —
//  used internally by the DMA and CDMA engines for pipeline decoupling
//  on raw data paths.
// ============================================================================
module snix_register_slice #(
    parameter DATA_WIDTH = 32
) (
    input  logic                  clk,
    input  logic                  rst_n,

    // Input interface
    input  logic [DATA_WIDTH-1:0] s_axis_tdata,
    input  logic                  s_axis_tvalid,
    output logic                  s_axis_tready,

    // Output interface
    output logic [DATA_WIDTH-1:0] m_axis_tdata,
    output logic                  m_axis_tvalid,
    input  logic                  m_axis_tready
);

    // Skid register
    logic                  skid_valid;
    logic [DATA_WIDTH-1:0] skid_data;

    wire s_hsk   = s_axis_tvalid & s_axis_tready;
    wire m_stall = m_axis_tvalid & ~m_axis_tready;

    // -----------------------------------------------------------------
    // Skid valid
    // -----------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n)
            skid_valid <= 1'b0;
        else if (s_hsk & m_stall)
            skid_valid <= 1'b1;
        else if (m_axis_tready)
            skid_valid <= 1'b0;

    // -----------------------------------------------------------------
    // Skid data
    // -----------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n)
            skid_data <= '0;
        else if (s_hsk)
            skid_data <= s_axis_tdata;

    // Ready when skid is empty
    assign s_axis_tready = ~skid_valid;

    // -----------------------------------------------------------------
    // Output valid
    // -----------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n)
            m_axis_tvalid <= 1'b0;
        else if (~m_axis_tvalid | m_axis_tready)
            m_axis_tvalid <= s_axis_tvalid | skid_valid;

    // -----------------------------------------------------------------
    // Output data — skid has priority
    // -----------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n)
            m_axis_tdata <= '0;
        else if (~m_axis_tvalid | m_axis_tready) begin
            if (skid_valid)
                m_axis_tdata <= skid_data;
            else if (s_axis_tvalid)
                m_axis_tdata <= s_axis_tdata;
        end

endmodule : snix_register_slice

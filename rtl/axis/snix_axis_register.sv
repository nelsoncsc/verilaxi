// ============================================================================
//  snix_axis_register.sv
//
//  AXI4-Stream skid buffer (register slice).
//
//  Provides a single stage of pipeline registering on an AXI-Stream bus.
//  A secondary "skid" register absorbs one beat when the downstream stalls,
//  so the upstream never sees tready deassert combinationally from the
//  downstream — breaking timing paths between producer and consumer.
//
//  Reference:
//    https://zipcpu.com/blog/2019/05/22/skidbuffer.html
// ============================================================================
module snix_axis_register #(
    parameter int DATA_WIDTH = 8,
    parameter int USER_WIDTH = 1
) (
    input  logic                  clk,
    input  logic                  rst_n,

    // AXI4-Stream slave (input)
    input  logic [DATA_WIDTH-1:0] s_axis_tdata,
    input  logic [USER_WIDTH-1:0] s_axis_tuser,
    input  logic                  s_axis_tlast,
    input  logic                  s_axis_tvalid,
    output logic                  s_axis_tready,

    // AXI4-Stream master (output)
    output logic [DATA_WIDTH-1:0] m_axis_tdata,
    output logic [USER_WIDTH-1:0] m_axis_tuser,
    output logic                  m_axis_tlast,
    output logic                  m_axis_tvalid,
    input  logic                  m_axis_tready
);

    // Skid register — holds one beat when downstream stalls
    logic                           skid_valid;
    logic [DATA_WIDTH+USER_WIDTH:0] skid_data;  // {tlast, tuser, tdata}

    // Upstream handshake and downstream stall
    wire s_hsk  = s_axis_tvalid & s_axis_tready;
    wire m_stall = m_axis_tvalid & ~m_axis_tready;

    // -----------------------------------------------------------------
    // Skid valid — asserts when upstream delivers a beat but downstream
    // is stalled.  Clears when downstream accepts.
    // -----------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n)
            skid_valid <= 1'b0;
        else if (s_hsk & m_stall)
            skid_valid <= 1'b1;
        else if (m_axis_tready)
            skid_valid <= 1'b0;

    // -----------------------------------------------------------------
    // Skid data — capture input payload on upstream handshake
    // -----------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n)
            skid_data <= '0;
        else if (s_hsk)
            skid_data <= {s_axis_tlast, s_axis_tuser, s_axis_tdata};

    // Ready to upstream when skid register is empty
    assign s_axis_tready = ~skid_valid;

    // -----------------------------------------------------------------
    // Output valid — update only when output can move
    // -----------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n)
            m_axis_tvalid <= 1'b0;
        else if (~m_axis_tvalid | m_axis_tready)
            m_axis_tvalid <= s_axis_tvalid | skid_valid;

    // -----------------------------------------------------------------
    // Output data — skid has priority (older beat), else pass-through
    // -----------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            m_axis_tdata <= '0;
            m_axis_tuser <= '0;
            m_axis_tlast <= 1'b0;
        end
        else if (~m_axis_tvalid | m_axis_tready) begin
            if (skid_valid)
                {m_axis_tlast, m_axis_tuser, m_axis_tdata} <= skid_data;
            else if (s_axis_tvalid)
                {m_axis_tlast, m_axis_tuser, m_axis_tdata} <= {s_axis_tlast, s_axis_tuser, s_axis_tdata};
        end

endmodule : snix_axis_register

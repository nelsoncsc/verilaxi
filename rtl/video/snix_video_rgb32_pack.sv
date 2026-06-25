`timescale 1ns/1ps

module snix_video_rgb32_pack #(
    parameter int OUT_DATA_WIDTH = 64
) (
    input  logic                         clk,
    input  logic                         rst_n,
    input  logic [23:0]                  s_axis_tdata,
    input  logic                         s_axis_tuser,
    input  logic                         s_axis_tvalid,
    output logic                         s_axis_tready,
    input  logic                         s_axis_tlast,
    output logic [OUT_DATA_WIDTH-1:0]    m_axis_tdata,
    output logic [OUT_DATA_WIDTH/8-1:0]  m_axis_tkeep,
    output logic                         m_axis_tuser,
    output logic                         m_axis_tvalid,
    input  logic                         m_axis_tready,
    output logic                         m_axis_tlast
);

    assign s_axis_tready = !m_axis_tvalid || m_axis_tready;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axis_tdata  <= '0;
            m_axis_tkeep  <= '0;
            m_axis_tuser  <= 1'b0;
            m_axis_tvalid <= 1'b0;
            m_axis_tlast  <= 1'b0;
        end else begin
            if (m_axis_tvalid && m_axis_tready)
                m_axis_tvalid <= 1'b0;

            if (s_axis_tvalid && s_axis_tready) begin
                m_axis_tdata  <= '0;
                m_axis_tdata[31:0] <= {8'h00, s_axis_tdata};
                m_axis_tkeep  <= '0;
                m_axis_tkeep[3:0] <= 4'hf;
                m_axis_tuser  <= s_axis_tuser;
                m_axis_tlast  <= s_axis_tlast;
                m_axis_tvalid <= 1'b1;
            end
        end
    end

endmodule : snix_video_rgb32_pack

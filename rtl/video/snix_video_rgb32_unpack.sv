`timescale 1ns/1ps

module snix_video_rgb32_unpack #(
    parameter int IN_DATA_WIDTH = 64
) (
    input  logic                        clk,
    input  logic                        rst_n,
    input  logic [IN_DATA_WIDTH-1:0]    s_axis_tdata,
    input  logic [IN_DATA_WIDTH/8-1:0]  s_axis_tkeep,
    input  logic                        s_axis_tuser,
    input  logic                        s_axis_tvalid,
    output logic                        s_axis_tready,
    input  logic                        s_axis_tlast,
    output logic [23:0]                 m_axis_tdata,
    output logic                        m_axis_tuser,
    output logic                        m_axis_tvalid,
    input  logic                        m_axis_tready,
    output logic                        m_axis_tlast
);

    assign s_axis_tready = !m_axis_tvalid || m_axis_tready;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m_axis_tdata  <= '0;
            m_axis_tuser  <= 1'b0;
            m_axis_tvalid <= 1'b0;
            m_axis_tlast  <= 1'b0;
        end else begin
            if (m_axis_tvalid && m_axis_tready)
                m_axis_tvalid <= 1'b0;

            if (s_axis_tvalid && s_axis_tready) begin
                m_axis_tdata  <= s_axis_tdata[23:0];
                m_axis_tuser  <= s_axis_tuser;
                m_axis_tlast  <= s_axis_tlast;
                m_axis_tvalid <= (s_axis_tkeep[3:0] != 4'h0);
            end
        end
    end

endmodule : snix_video_rgb32_unpack

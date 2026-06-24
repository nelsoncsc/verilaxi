module snix_video_rgb24_pack #(
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

    logic sof_pending;

    snix_axis_rr_converter #(
        .IN_DATA_WIDTH(24), .OUT_DATA_WIDTH(OUT_DATA_WIDTH)
    ) u_pack (
        .clk, .rst_n,
        .s_axis_tdata, .s_axis_tkeep(3'b111), .s_axis_tvalid,
        .s_axis_tready, .s_axis_tlast,
        .m_axis_tdata, .m_axis_tkeep, .m_axis_tvalid,
        .m_axis_tready, .m_axis_tlast
    );

    assign m_axis_tuser = sof_pending && m_axis_tvalid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            sof_pending <= 1'b0;
        else begin
            if (s_axis_tvalid && s_axis_tready && s_axis_tuser)
                sof_pending <= 1'b1;
            if (m_axis_tvalid && m_axis_tready && sof_pending)
                sof_pending <= 1'b0;
        end
    end

endmodule : snix_video_rgb24_pack

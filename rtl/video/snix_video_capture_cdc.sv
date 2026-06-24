module snix_video_capture_cdc #(
    parameter int DATA_WIDTH = 64,
    parameter int FIFO_DEPTH = 64
) (
    input  logic                       capture_clk,
    input  logic                       capture_rst_n,
    input  logic [23:0]                s_axis_tdata,
    input  logic                       s_axis_tuser,
    input  logic                       s_axis_tvalid,
    output logic                       s_axis_tready,
    input  logic                       s_axis_tlast,
    input  logic                       axi_clk,
    input  logic                       axi_rst_n,
    output logic [DATA_WIDTH-1:0]      m_axis_tdata,
    output logic [DATA_WIDTH/8-1:0]    m_axis_tkeep,
    output logic                       m_axis_tuser,
    output logic                       m_axis_tvalid,
    input  logic                       m_axis_tready,
    output logic                       m_axis_tlast
);
    localparam int KEEP_WIDTH = DATA_WIDTH / 8;
    logic [DATA_WIDTH-1:0] packed_data;
    logic [KEEP_WIDTH-1:0] packed_keep;
    logic packed_user, packed_valid, packed_ready, packed_last;
    logic [DATA_WIDTH+KEEP_WIDTH:0] cdc_data;

    snix_video_rgb24_pack #(.OUT_DATA_WIDTH(DATA_WIDTH)) u_pack (
        .clk(capture_clk), .rst_n(capture_rst_n),
        .s_axis_tdata, .s_axis_tuser, .s_axis_tvalid, .s_axis_tready,
        .s_axis_tlast, .m_axis_tdata(packed_data), .m_axis_tkeep(packed_keep),
        .m_axis_tuser(packed_user), .m_axis_tvalid(packed_valid),
        .m_axis_tready(packed_ready), .m_axis_tlast(packed_last)
    );

    snix_axis_afifo #(
        .DATA_WIDTH(DATA_WIDTH + KEEP_WIDTH + 1),
        .FIFO_DEPTH(FIFO_DEPTH), .FRAME_FIFO(0)
    ) u_cdc (
        .s_axis_clk(capture_clk), .s_axis_rst_n(capture_rst_n),
        .s_axis_tdata({packed_user, packed_keep, packed_data}),
        .s_axis_tvalid(packed_valid), .s_axis_tlast(packed_last),
        .s_axis_tready(packed_ready),
        .m_axis_clk(axi_clk), .m_axis_rst_n(axi_rst_n),
        .m_axis_tdata(cdc_data), .m_axis_tvalid,
        .m_axis_tlast, .m_axis_tready
    );

    assign {m_axis_tuser, m_axis_tkeep, m_axis_tdata} = cdc_data;
endmodule : snix_video_capture_cdc

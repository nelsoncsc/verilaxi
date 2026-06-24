module snix_video_display_cdc #(
    parameter int DATA_WIDTH = 64,
    parameter int FIFO_DEPTH = 64
) (
    input  logic                       axi_clk,
    input  logic                       axi_rst_n,
    input  logic [DATA_WIDTH-1:0]      s_axis_tdata,
    input  logic [DATA_WIDTH/8-1:0]    s_axis_tkeep,
    input  logic                       s_axis_tuser,
    input  logic                       s_axis_tvalid,
    output logic                       s_axis_tready,
    input  logic                       s_axis_tlast,
    input  logic                       display_clk,
    input  logic                       display_rst_n,
    output logic [23:0]                m_axis_tdata,
    output logic                       m_axis_tuser,
    output logic                       m_axis_tvalid,
    input  logic                       m_axis_tready,
    output logic                       m_axis_tlast
);
    localparam int KEEP_WIDTH = DATA_WIDTH / 8;
    logic [DATA_WIDTH+KEEP_WIDTH:0] cdc_data;
    logic cdc_user, cdc_valid, cdc_ready, cdc_last;

    snix_axis_afifo #(
        .DATA_WIDTH(DATA_WIDTH + KEEP_WIDTH + 1),
        .FIFO_DEPTH(FIFO_DEPTH), .FRAME_FIFO(0)
    ) u_cdc (
        .s_axis_clk(axi_clk), .s_axis_rst_n(axi_rst_n),
        .s_axis_tdata({s_axis_tuser, s_axis_tkeep, s_axis_tdata}),
        .s_axis_tvalid, .s_axis_tlast, .s_axis_tready,
        .m_axis_clk(display_clk), .m_axis_rst_n(display_rst_n),
        .m_axis_tdata(cdc_data),
        .m_axis_tvalid(cdc_valid), .m_axis_tlast(cdc_last),
        .m_axis_tready(cdc_ready)
    );

    assign cdc_user = cdc_data[DATA_WIDTH + KEEP_WIDTH];

    snix_video_rgb24_unpack #(.IN_DATA_WIDTH(DATA_WIDTH)) u_unpack (
        .clk(display_clk), .rst_n(display_rst_n),
        .s_axis_tdata(cdc_data[DATA_WIDTH-1:0]),
        .s_axis_tkeep(cdc_data[DATA_WIDTH +: KEEP_WIDTH]),
        .s_axis_tuser(cdc_user), .s_axis_tvalid(cdc_valid),
        .s_axis_tready(cdc_ready), .s_axis_tlast(cdc_last),
        .m_axis_tdata, .m_axis_tuser, .m_axis_tvalid,
        .m_axis_tready, .m_axis_tlast
    );
endmodule : snix_video_display_cdc

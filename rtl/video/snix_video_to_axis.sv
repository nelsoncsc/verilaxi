module snix_video_to_axis #(parameter int DATA_WIDTH = 24,
                            parameter int USER_WIDTH = 1) 
                           (input  logic                  clk,
                            input  logic                  rst_n,
                            input  logic                  video_de,
                            input  logic                  video_sof,
                            input  logic                  video_eol,
                            input  logic [DATA_WIDTH-1:0] video_data,
                            output logic [DATA_WIDTH-1:0] m_axis_tdata,
                            output logic [USER_WIDTH-1:0] m_axis_tuser,
                            output logic                  m_axis_tlast,
                            output logic                  m_axis_tvalid,
                            input  logic                  m_axis_tready,
                            output logic                  overflow);

    always_comb begin
        m_axis_tdata    = video_data;
        m_axis_tuser    = '0;
        m_axis_tuser[0] = video_sof;
        m_axis_tlast    = video_eol;
        m_axis_tvalid   = video_de;
    end

    // Native video cannot be backpressured. A production design places an
    // asynchronous FIFO after this adapter; overflow makes any loss explicit.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            overflow <= 1'b0;
        else if (video_de && !m_axis_tready)
            overflow <= 1'b1;
    end

endmodule : snix_video_to_axis

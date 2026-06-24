module snix_axis_to_video #(parameter int DATA_WIDTH = 24,
                            parameter int USER_WIDTH = 1,
                            parameter logic [DATA_WIDTH-1:0] BLANK_DATA = '0) 
                           (input  logic                  clk,
                            input  logic                  rst_n,
                            input  logic                  timing_de,
                            input  logic                  timing_sof,
                            input  logic                  timing_eol,
                            input  logic [DATA_WIDTH-1:0] s_axis_tdata,
                            input  logic [USER_WIDTH-1:0] s_axis_tuser,
                            input  logic                  s_axis_tlast,
                            input  logic                  s_axis_tvalid,
                            output logic                  s_axis_tready,
                            output logic                  video_de,
                            output logic                  video_sof,
                            output logic                  video_eol,
                            output logic [DATA_WIDTH-1:0] video_data,
                            output logic                  underflow,
                            output logic                  frame_error);

    always_comb begin
        s_axis_tready = timing_de;
        video_de      = timing_de && s_axis_tvalid;
        video_sof     = video_de && timing_sof;
        video_eol     = video_de && timing_eol;
        video_data    = video_de ? s_axis_tdata : BLANK_DATA;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            underflow   <= 1'b0;
            frame_error <= 1'b0;
        end else begin
            if (timing_de && !s_axis_tvalid)
                underflow <= 1'b1;

            if (s_axis_tvalid && s_axis_tready &&
                ((s_axis_tuser[0] != timing_sof) ||
                 (s_axis_tlast    != timing_eol)))
                frame_error <= 1'b1;
        end
    end

endmodule : snix_axis_to_video

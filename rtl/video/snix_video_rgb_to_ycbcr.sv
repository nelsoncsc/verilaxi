`timescale 1ns/1ps

module snix_video_rgb_to_ycbcr (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [23:0] s_axis_tdata,
    input  logic        s_axis_tuser,
    input  logic        s_axis_tvalid,
    output logic        s_axis_tready,
    input  logic        s_axis_tlast,
    output logic [23:0] m_axis_tdata,
    output logic        m_axis_tuser,
    output logic        m_axis_tvalid,
    input  logic        m_axis_tready,
    output logic        m_axis_tlast
);

    function automatic logic [7:0] clamp_video_y(input signed [19:0] value);
        if (value < 20'sd16)
            clamp_video_y = 8'd16;
        else if (value > 20'sd235)
            clamp_video_y = 8'd235;
        else
            clamp_video_y = value[7:0];
    endfunction

    function automatic logic [7:0] clamp_video_c(input signed [19:0] value);
        if (value < 20'sd16)
            clamp_video_c = 8'd16;
        else if (value > 20'sd240)
            clamp_video_c = 8'd240;
        else
            clamp_video_c = value[7:0];
    endfunction

    logic signed [19:0] st0_y_sum;
    logic signed [19:0] st0_cb_sum;
    logic signed [19:0] st0_cr_sum;
    logic               st0_user;
    logic               st0_last;
    logic               st0_valid;

    logic [23:0] st1_data;
    logic        st1_user;
    logic        st1_last;
    logic        st1_valid;

    logic allow_st1;
    logic allow_st0;
    logic [7:0] r;
    logic [7:0] g;
    logic [7:0] b;
    logic signed [19:0] y_val;
    logic signed [19:0] cb_val;
    logic signed [19:0] cr_val;

    assign allow_st1 = !st1_valid || m_axis_tready;
    assign allow_st0 = !st0_valid || allow_st1;
    assign s_axis_tready = allow_st0;

    assign m_axis_tdata  = st1_data;
    assign m_axis_tuser  = st1_user;
    assign m_axis_tlast  = st1_last;
    assign m_axis_tvalid = st1_valid;

    always_comb begin
        r = s_axis_tdata[23:16];
        g = s_axis_tdata[15:8];
        b = s_axis_tdata[7:0];
        y_val  = ((st0_y_sum  + 20'sd128) >>> 8) + 20'sd16;
        cb_val = ((st0_cb_sum + 20'sd128) >>> 8) + 20'sd128;
        cr_val = ((st0_cr_sum + 20'sd128) >>> 8) + 20'sd128;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st0_y_sum  <= '0;
            st0_cb_sum <= '0;
            st0_cr_sum <= '0;
            st0_user   <= 1'b0;
            st0_last   <= 1'b0;
            st0_valid  <= 1'b0;
            st1_data   <= '0;
            st1_user   <= 1'b0;
            st1_last   <= 1'b0;
            st1_valid  <= 1'b0;
        end else begin
            if (allow_st1) begin
                st1_valid <= st0_valid;
                st1_user  <= st0_user;
                st1_last  <= st0_last;
                st1_data  <= {clamp_video_y(y_val),
                              clamp_video_c(cb_val),
                              clamp_video_c(cr_val)};
            end

            if (allow_st0) begin
                st0_valid  <= s_axis_tvalid;
                st0_user   <= s_axis_tuser;
                st0_last   <= s_axis_tlast;
                st0_y_sum  <= 20'sd66  * $signed({1'b0, r}) +
                              20'sd129 * $signed({1'b0, g}) +
                              20'sd25  * $signed({1'b0, b});
                st0_cb_sum <= -20'sd38 * $signed({1'b0, r}) -
                              20'sd74  * $signed({1'b0, g}) +
                              20'sd112 * $signed({1'b0, b});
                st0_cr_sum <= 20'sd112 * $signed({1'b0, r}) -
                              20'sd94  * $signed({1'b0, g}) -
                              20'sd18  * $signed({1'b0, b});
            end
        end
    end

endmodule : snix_video_rgb_to_ycbcr

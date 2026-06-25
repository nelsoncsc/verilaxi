`timescale 1ns/1ps

module snix_video_ycbcr_to_rgb (
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

    function automatic logic [7:0] clamp_u8(input signed [20:0] value);
        if (value < 21'sd0)
            clamp_u8 = 8'd0;
        else if (value > 21'sd255)
            clamp_u8 = 8'd255;
        else
            clamp_u8 = value[7:0];
    endfunction

    logic signed [20:0] st0_r_sum;
    logic signed [20:0] st0_g_sum;
    logic signed [20:0] st0_b_sum;
    logic               st0_user;
    logic               st0_last;
    logic               st0_valid;

    logic [23:0] st1_data;
    logic        st1_user;
    logic        st1_last;
    logic        st1_valid;

    logic allow_st1;
    logic allow_st0;
    logic signed [9:0] c;
    logic signed [9:0] d;
    logic signed [9:0] e;
    logic signed [20:0] r_val;
    logic signed [20:0] g_val;
    logic signed [20:0] b_val;

    assign allow_st1 = !st1_valid || m_axis_tready;
    assign allow_st0 = !st0_valid || allow_st1;
    assign s_axis_tready = allow_st0;

    assign m_axis_tdata  = st1_data;
    assign m_axis_tuser  = st1_user;
    assign m_axis_tlast  = st1_last;
    assign m_axis_tvalid = st1_valid;

    always_comb begin
        c = $signed({1'b0, s_axis_tdata[23:16]}) - 10'sd16;
        d = $signed({1'b0, s_axis_tdata[15:8]})  - 10'sd128;
        e = $signed({1'b0, s_axis_tdata[7:0]})   - 10'sd128;
        r_val = (st0_r_sum + 21'sd128) >>> 8;
        g_val = (st0_g_sum + 21'sd128) >>> 8;
        b_val = (st0_b_sum + 21'sd128) >>> 8;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st0_r_sum <= '0;
            st0_g_sum <= '0;
            st0_b_sum <= '0;
            st0_user  <= 1'b0;
            st0_last  <= 1'b0;
            st0_valid <= 1'b0;
            st1_data  <= '0;
            st1_user  <= 1'b0;
            st1_last  <= 1'b0;
            st1_valid <= 1'b0;
        end else begin
            if (allow_st1) begin
                st1_valid <= st0_valid;
                st1_user  <= st0_user;
                st1_last  <= st0_last;
                st1_data  <= {clamp_u8(r_val), clamp_u8(g_val), clamp_u8(b_val)};
            end

            if (allow_st0) begin
                st0_valid <= s_axis_tvalid;
                st0_user  <= s_axis_tuser;
                st0_last  <= s_axis_tlast;
                st0_r_sum <= 21'sd298 * c + 21'sd409 * e;
                st0_g_sum <= 21'sd298 * c - 21'sd100 * d - 21'sd208 * e;
                st0_b_sum <= 21'sd298 * c + 21'sd516 * d;
            end
        end
    end

endmodule : snix_video_ycbcr_to_rgb

`timescale 1ns/1ps

module snix_video_csc_422 #(
    parameter bit YUYV_MODE = 1'b1
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [23:0] s_axis_tdata,
    input  logic        s_axis_tuser,
    input  logic        s_axis_tvalid,
    output logic        s_axis_tready,
    input  logic        s_axis_tlast,
    output logic [31:0] m_axis_tdata,
    output logic        m_axis_tuser,
    output logic        m_axis_tvalid,
    input  logic        m_axis_tready,
    output logic        m_axis_tlast
);

    logic        have_even;
    logic [7:0]  even_y;
    logic [7:0]  even_cb;
    logic [7:0]  even_cr;
    logic        even_user;

    logic [7:0] in_y;
    logic [7:0] in_cb;
    logic [7:0] in_cr;
    logic [7:0] avg_cb;
    logic [7:0] avg_cr;

    assign in_y  = s_axis_tdata[23:16];
    assign in_cb = s_axis_tdata[15:8];
    assign in_cr = s_axis_tdata[7:0];
    assign s_axis_tready = !m_axis_tvalid || m_axis_tready;

    always_comb begin
        avg_cb = (even_cb + in_cb + 8'd1) >> 1;
        avg_cr = (even_cr + in_cr + 8'd1) >> 1;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            have_even    <= 1'b0;
            even_y       <= '0;
            even_cb      <= '0;
            even_cr      <= '0;
            even_user    <= 1'b0;
            m_axis_tdata <= '0;
            m_axis_tuser <= 1'b0;
            m_axis_tlast <= 1'b0;
            m_axis_tvalid <= 1'b0;
        end else begin
            if (m_axis_tvalid && m_axis_tready)
                m_axis_tvalid <= 1'b0;

            if (s_axis_tvalid && s_axis_tready) begin
                if (!have_even) begin
                    if (s_axis_tlast) begin
                        if (YUYV_MODE)
                            m_axis_tdata <= {in_cr, in_y, in_cb, in_y};
                        else
                            m_axis_tdata <= {in_y, in_cr, in_y, in_cb};
                        m_axis_tuser  <= s_axis_tuser;
                        m_axis_tlast  <= 1'b1;
                        m_axis_tvalid <= 1'b1;
                    end else begin
                        even_y    <= in_y;
                        even_cb   <= in_cb;
                        even_cr   <= in_cr;
                        even_user <= s_axis_tuser;
                        have_even <= 1'b1;
                    end
                end else begin
                    if (YUYV_MODE)
                        m_axis_tdata <= {avg_cr, in_y, avg_cb, even_y};
                    else
                        m_axis_tdata <= {in_y, avg_cr, even_y, avg_cb};
                    m_axis_tuser  <= even_user;
                    m_axis_tlast  <= s_axis_tlast;
                    m_axis_tvalid <= 1'b1;
                    have_even     <= 1'b0;
                end
            end
        end
    end

endmodule : snix_video_csc_422

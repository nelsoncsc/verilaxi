`timescale 1ns/1ps

module snix_video_csc_422_expand #(
    parameter bit YUYV_MODE = 1'b1
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [31:0] s_axis_tdata,
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

    typedef enum logic { IDLE = 1'b0, SECOND = 1'b1 } state_t;
    state_t state;

    logic [7:0] y0;
    logic [7:0] y1;
    logic [7:0] cb;
    logic [7:0] cr;
    logic       latched_last;

    assign s_axis_tready = (state == IDLE) && (!m_axis_tvalid || m_axis_tready);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= IDLE;
            y0           <= '0;
            y1           <= '0;
            cb           <= '0;
            cr           <= '0;
            latched_last <= 1'b0;
            m_axis_tdata <= '0;
            m_axis_tuser <= 1'b0;
            m_axis_tlast <= 1'b0;
            m_axis_tvalid <= 1'b0;
        end else begin
            if (m_axis_tvalid && m_axis_tready)
                m_axis_tvalid <= 1'b0;

            case (state)
                IDLE: begin
                    if (s_axis_tvalid && s_axis_tready) begin
                        if (YUYV_MODE) begin
                            y0 <= s_axis_tdata[7:0];
                            cb <= s_axis_tdata[15:8];
                            y1 <= s_axis_tdata[23:16];
                            cr <= s_axis_tdata[31:24];
                            m_axis_tdata <= {s_axis_tdata[7:0],
                                             s_axis_tdata[15:8],
                                             s_axis_tdata[31:24]};
                        end else begin
                            cb <= s_axis_tdata[7:0];
                            y0 <= s_axis_tdata[15:8];
                            cr <= s_axis_tdata[23:16];
                            y1 <= s_axis_tdata[31:24];
                            m_axis_tdata <= {s_axis_tdata[15:8],
                                             s_axis_tdata[7:0],
                                             s_axis_tdata[23:16]};
                        end
                        latched_last  <= s_axis_tlast;
                        m_axis_tuser  <= s_axis_tuser;
                        m_axis_tlast  <= 1'b0;
                        m_axis_tvalid <= 1'b1;
                        state         <= SECOND;
                    end
                end

                SECOND: begin
                    if (!m_axis_tvalid || m_axis_tready) begin
                        m_axis_tdata  <= {y1, cb, cr};
                        m_axis_tuser  <= 1'b0;
                        m_axis_tlast  <= latched_last;
                        m_axis_tvalid <= 1'b1;
                        state         <= IDLE;
                    end
                end
            endcase
        end
    end

endmodule : snix_video_csc_422_expand

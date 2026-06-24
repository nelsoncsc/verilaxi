`timescale 1ns/1ps

module test_video_adapter_errors (
    input logic clk,
    input logic rst_n
);

    logic video_de, video_sof, video_eol;
    logic [23:0] video_data;
    logic [23:0] m_tdata;
    logic [0:0]  m_tuser;
    logic m_tlast, m_tvalid, m_tready;
    logic overflow;

    logic timing_de, timing_sof, timing_eol;
    logic [23:0] s_tdata;
    logic [0:0]  s_tuser;
    logic s_tlast, s_tvalid, s_tready;
    logic out_de, out_sof, out_eol;
    logic [23:0] out_data;
    logic underflow, frame_error;

    snix_video_to_axis u_to_axis (
        .clk, .rst_n,
        .video_de, .video_sof, .video_eol, .video_data,
        .m_axis_tdata(m_tdata), .m_axis_tuser(m_tuser),
        .m_axis_tlast(m_tlast), .m_axis_tvalid(m_tvalid),
        .m_axis_tready(m_tready), .overflow
    );

    snix_axis_to_video u_to_video (
        .clk, .rst_n,
        .timing_de, .timing_sof, .timing_eol,
        .s_axis_tdata(s_tdata), .s_axis_tuser(s_tuser),
        .s_axis_tlast(s_tlast), .s_axis_tvalid(s_tvalid),
        .s_axis_tready(s_tready),
        .video_de(out_de), .video_sof(out_sof), .video_eol(out_eol),
        .video_data(out_data), .underflow, .frame_error
    );

    initial begin
        video_de = 0; video_sof = 0; video_eol = 0; video_data = '0;
        m_tready = 0;
        timing_de = 0; timing_sof = 0; timing_eol = 0;
        s_tdata = '0; s_tuser = '0; s_tlast = 0; s_tvalid = 0;

        @(negedge rst_n);
        @(posedge rst_n);

        // Native video cannot pause: READY low during DE must latch overflow.
        // Simultaneously, an empty AXIS stream during active timing underflows.
        @(negedge clk);
        video_de  = 1;
        video_data = 24'h123456;
        timing_de = 1;
        @(posedge clk);
        @(negedge clk);
        video_de  = 0;
        timing_de = 0;
        @(posedge clk);
        assert (overflow && underflow)
            else $fatal(1, "missing error flags: overflow=%0b underflow=%0b",
                        overflow, underflow);

        // Present a beat whose TUSER/TLAST disagree with the timing position.
        @(negedge clk);
        timing_de  = 1;
        timing_sof = 1;
        s_tvalid   = 1;
        s_tuser    = 0;
        s_tlast    = 1;
        s_tdata    = 24'habcdef;
        @(posedge clk);
        @(negedge clk);
        timing_de  = 0;
        timing_sof = 0;
        s_tvalid   = 0;
        @(posedge clk);
        assert (frame_error)
            else $fatal(1, "framing mismatch did not latch frame_error");

        $display("[VIDEO] overflow, underflow, and framing error checks passed");
        $finish;
    end

    initial begin
        #500 $fatal(1, "video adapter error test timeout");
    end

endmodule : test_video_adapter_errors

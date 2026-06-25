`timescale 1ns/1ps

module test_video_csc_rgb_ycbcr (
    input logic clk,
    input logic rst_n
);

    logic [23:0] s_tdata;
    logic        s_tuser;
    logic        s_tvalid;
    logic        s_tready;
    logic        s_tlast;

    logic [23:0] yuv_tdata;
    logic        yuv_tuser;
    logic        yuv_tvalid;
    logic        yuv_tready;
    logic        yuv_tlast;

    logic [23:0] m_tdata;
    logic        m_tuser;
    logic        m_tvalid;
    logic        m_tready;
    logic        m_tlast;

    logic [23:0] samples [0:7];

    initial begin
        samples[0] = 24'h000000;
        samples[1] = 24'hffffff;
        samples[2] = 24'hff0000;
        samples[3] = 24'h00ff00;
        samples[4] = 24'h0000ff;
        samples[5] = 24'h123456;
        samples[6] = 24'h808080;
        samples[7] = 24'hc86432;
    end

    function automatic logic [7:0] clamp_y(input int value);
        if (value < 16)
            clamp_y = 8'd16;
        else if (value > 235)
            clamp_y = 8'd235;
        else
            clamp_y = value[7:0];
    endfunction

    function automatic logic [7:0] clamp_c(input int value);
        if (value < 16)
            clamp_c = 8'd16;
        else if (value > 240)
            clamp_c = 8'd240;
        else
            clamp_c = value[7:0];
    endfunction

    function automatic logic [23:0] ref_yuv(input logic [23:0] rgb);
        int r;
        int g;
        int b;
        int y;
        int cb;
        int cr;
        begin
            r = int'(rgb[23:16]);
            g = int'(rgb[15:8]);
            b = int'(rgb[7:0]);
            y  = (( 66*r + 129*g +  25*b + 128) >>> 8) + 16;
            cb = ((-38*r -  74*g + 112*b + 128) >>> 8) + 128;
            cr = ((112*r -  94*g -  18*b + 128) >>> 8) + 128;
            ref_yuv = {clamp_y(y), clamp_c(cb), clamp_c(cr)};
        end
    endfunction

    function automatic int abs_diff(input int a, input int b);
        if (a > b)
            abs_diff = a - b;
        else
            abs_diff = b - a;
    endfunction

    snix_video_rgb_to_ycbcr u_fwd (
        .clk, .rst_n,
        .s_axis_tdata(s_tdata), .s_axis_tuser(s_tuser),
        .s_axis_tvalid(s_tvalid), .s_axis_tready(s_tready),
        .s_axis_tlast(s_tlast),
        .m_axis_tdata(yuv_tdata), .m_axis_tuser(yuv_tuser),
        .m_axis_tvalid(yuv_tvalid), .m_axis_tready(yuv_tready),
        .m_axis_tlast(yuv_tlast)
    );

    snix_video_ycbcr_to_rgb u_inv (
        .clk, .rst_n,
        .s_axis_tdata(yuv_tdata), .s_axis_tuser(yuv_tuser),
        .s_axis_tvalid(yuv_tvalid), .s_axis_tready(yuv_tready),
        .s_axis_tlast(yuv_tlast),
        .m_axis_tdata(m_tdata), .m_axis_tuser(m_tuser),
        .m_axis_tvalid(m_tvalid), .m_axis_tready(m_tready),
        .m_axis_tlast(m_tlast)
    );

    axis_checker #(.DATA_WIDTH(24), .USER_WIDTH(1), .LABEL("CSC_RGB_IN"))
        u_in_chk (
            .clk, .rst_n, .tdata(s_tdata), .tuser(s_tuser),
            .tvalid(s_tvalid), .tready(s_tready), .tlast(s_tlast)
        );

    axis_checker #(.DATA_WIDTH(24), .USER_WIDTH(1), .LABEL("CSC_YCBCR"))
        u_mid_chk (
            .clk, .rst_n, .tdata(yuv_tdata), .tuser(yuv_tuser),
            .tvalid(yuv_tvalid), .tready(yuv_tready), .tlast(yuv_tlast)
        );

    axis_checker #(.DATA_WIDTH(24), .USER_WIDTH(1), .LABEL("CSC_RGB_OUT"))
        u_out_chk (
            .clk, .rst_n, .tdata(m_tdata), .tuser(m_tuser),
            .tvalid(m_tvalid), .tready(m_tready), .tlast(m_tlast)
        );

    initial begin
        int sent;
        int yuv_seen;
        int rgb_seen;

        s_tdata   = '0;
        s_tuser   = 1'b0;
        s_tvalid  = 1'b0;
        s_tlast   = 1'b0;
        m_tready  = 1'b1;
        sent      = 0;
        yuv_seen  = 0;
        rgb_seen  = 0;

        @(negedge rst_n);
        @(posedge rst_n);
        fork
            begin
                while (sent < 8) begin
                    @(negedge clk);
                    s_tdata  = samples[sent];
                    s_tuser  = (sent == 0);
                    s_tlast  = (sent == 7);
                    s_tvalid = 1'b1;
                    @(posedge clk);
                    if (s_tready)
                        sent++;
                end
                @(negedge clk);
                s_tvalid = 1'b0;
                s_tuser  = 1'b0;
                s_tlast  = 1'b0;
            end

            begin
                while (yuv_seen < 8) begin
                    @(negedge clk);
                    if (yuv_tvalid && yuv_tready) begin
                        assert (yuv_tdata == ref_yuv(samples[yuv_seen]))
                            else $fatal(1, "YCbCr mismatch idx=%0d exp=%h got=%h",
                                        yuv_seen, ref_yuv(samples[yuv_seen]),
                                        yuv_tdata);
                        yuv_seen++;
                    end
                end
            end

            begin
                while (rgb_seen < 8) begin
                    @(negedge clk);
                    if (m_tvalid && m_tready) begin
                        assert (abs_diff(int'(m_tdata[23:16]), int'(samples[rgb_seen][23:16])) <= 2 &&
                                abs_diff(int'(m_tdata[15:8]),  int'(samples[rgb_seen][15:8]))  <= 2 &&
                                abs_diff(int'(m_tdata[7:0]),   int'(samples[rgb_seen][7:0]))   <= 2)
                            else $fatal(1, "RGB round-trip error idx=%0d exp=%h got=%h",
                                        rgb_seen, samples[rgb_seen], m_tdata);
                        assert (m_tuser == (rgb_seen == 0))
                            else $fatal(1, "CSC TUSER mismatch idx=%0d", rgb_seen);
                        assert (m_tlast == (rgb_seen == 7))
                            else $fatal(1, "CSC TLAST mismatch idx=%0d", rgb_seen);
                        rgb_seen++;
                    end
                end
            end
        join

        $display("[VIDEO] RGB <-> YCbCr CSC checks passed");
        $finish;
    end

    initial begin
        #2_000 $fatal(1, "RGB/YCBCR CSC test timeout");
    end

endmodule : test_video_csc_rgb_ycbcr

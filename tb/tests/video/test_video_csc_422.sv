`timescale 1ns/1ps

module test_video_csc_422 (
    input logic clk,
    input logic rst_n
);

    logic [23:0] s_tdata;
    logic        s_tuser;
    logic        s_tvalid;
    logic        s_tready;
    logic        s_tlast;

    logic [31:0] mid_tdata;
    logic        mid_tuser;
    logic        mid_tvalid;
    logic        mid_tready;
    logic        mid_tlast;

    logic [23:0] m_tdata;
    logic        m_tuser;
    logic        m_tvalid;
    logic        m_tready;
    logic        m_tlast;

    logic [23:0] pixels [0:3];
    logic [7:0]  avg_cb [0:1];
    logic [7:0]  avg_cr [0:1];

    initial begin
        pixels[0] = 24'h102030;
        pixels[1] = 24'h405060;
        pixels[2] = 24'h708090;
        pixels[3] = 24'ha0b0c0;
        avg_cb[0] = (8'h20 + 8'h50 + 8'd1) >> 1;
        avg_cr[0] = (8'h30 + 8'h60 + 8'd1) >> 1;
        avg_cb[1] = (8'h80 + 8'hb0 + 8'd1) >> 1;
        avg_cr[1] = (8'h90 + 8'hc0 + 8'd1) >> 1;
    end

    snix_video_csc_422 #(.YUYV_MODE(1'b1)) u_pack (
        .clk, .rst_n,
        .s_axis_tdata(s_tdata), .s_axis_tuser(s_tuser),
        .s_axis_tvalid(s_tvalid), .s_axis_tready(s_tready),
        .s_axis_tlast(s_tlast),
        .m_axis_tdata(mid_tdata), .m_axis_tuser(mid_tuser),
        .m_axis_tvalid(mid_tvalid), .m_axis_tready(mid_tready),
        .m_axis_tlast(mid_tlast)
    );

    snix_video_csc_422_expand #(.YUYV_MODE(1'b1)) u_expand (
        .clk, .rst_n,
        .s_axis_tdata(mid_tdata), .s_axis_tuser(mid_tuser),
        .s_axis_tvalid(mid_tvalid), .s_axis_tready(mid_tready),
        .s_axis_tlast(mid_tlast),
        .m_axis_tdata(m_tdata), .m_axis_tuser(m_tuser),
        .m_axis_tvalid(m_tvalid), .m_axis_tready(m_tready),
        .m_axis_tlast(m_tlast)
    );

    axis_checker #(.DATA_WIDTH(24), .USER_WIDTH(1), .LABEL("CSC422_IN"))
        u_in_chk (
            .clk, .rst_n, .tdata(s_tdata), .tuser(s_tuser),
            .tvalid(s_tvalid), .tready(s_tready), .tlast(s_tlast)
        );

    axis_checker #(.DATA_WIDTH(32), .USER_WIDTH(1), .LABEL("CSC422_PACKED"))
        u_mid_chk (
            .clk, .rst_n, .tdata(mid_tdata), .tuser(mid_tuser),
            .tvalid(mid_tvalid), .tready(mid_tready), .tlast(mid_tlast)
        );

    axis_checker #(.DATA_WIDTH(24), .USER_WIDTH(1), .LABEL("CSC422_OUT"))
        u_out_chk (
            .clk, .rst_n, .tdata(m_tdata), .tuser(m_tuser),
            .tvalid(m_tvalid), .tready(m_tready), .tlast(m_tlast)
        );

    initial begin
        int sent;
        int received;
        int pair_idx;

        s_tdata  = '0;
        s_tuser  = 1'b0;
        s_tvalid = 1'b0;
        s_tlast  = 1'b0;
        m_tready = 1'b1;
        sent     = 0;
        received = 0;

        @(negedge rst_n);
        @(posedge rst_n);
        fork
            begin
                while (sent < 4) begin
                    @(negedge clk);
                    s_tdata  = pixels[sent];
                    s_tuser  = (sent == 0);
                    s_tlast  = (sent == 3);
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
                while (received < 4) begin
                    @(negedge clk);
                    if (m_tvalid && m_tready) begin
                        pair_idx = received >> 1;
                        assert (m_tdata[23:16] == pixels[received][23:16])
                            else $fatal(1, "CSC422 Y mismatch idx=%0d exp=%h got=%h",
                                        received, pixels[received][23:16],
                                        m_tdata[23:16]);
                        assert (m_tdata[15:8] == avg_cb[pair_idx] &&
                                m_tdata[7:0]  == avg_cr[pair_idx])
                            else $fatal(1, "CSC422 chroma mismatch idx=%0d got=%h",
                                        received, m_tdata);
                        assert (m_tuser == (received == 0))
                            else $fatal(1, "CSC422 TUSER mismatch idx=%0d", received);
                        assert (m_tlast == (received == 3))
                            else $fatal(1, "CSC422 TLAST mismatch idx=%0d", received);
                        received++;
                    end
                end
            end
        join

        $display("[VIDEO] YCbCr 4:2:2 pack/expand checks passed");
        $finish;
    end

    initial begin
        #2_000 $fatal(1, "CSC422 test timeout");
    end

endmodule : test_video_csc_422

`timescale 1ns / 1ps

module testbench;
    
    logic clk;
    logic rst_n;

    // 1ns period clock
    initial clk = 0;
    always #1 clk = ~clk;

    // Select environment via macro TEST_ENV
     // --------------------------------------------------
    // Test environment selection (compile-time)
    // --------------------------------------------------
    `ifdef USE_AXIS_REGISTER
        test_axis_register test_axis_reg_u0(.clk  (clk),
                                            .rst_n (rst_n)
                                           );
    `elsif USE_UART_LITE
        test_uart_lite test_uart_lite_u0 (.clk   (clk),
                                          .rst_n (rst_n)
                                         );
    `elsif USE_AXIS_FIFO
        test_axis_fifo test_axis_fifo_u0 (.clk  (clk),
                                          .rst_n (rst_n)
                                         );
    `elsif USE_AXIL_REGISTER
        test_axil_register test_axil_register_u0 (.clk   (clk),
                                                  .rst_n (rst_n)
                                                 );
    `elsif USE_AXIL_GPIO
        test_axil_gpio test_axil_gpio_u0 (.clk   (clk),
                                          .rst_n (rst_n)
                                         );
    `elsif USE_UART_AXIL_SLAVE
        test_uart_axil_slave test_uart_axil_slave_u0 (.clk   (clk),
                                                      .rst_n (rst_n)
                                                     );
    `elsif USE_UART_AXIL_MASTER
        test_uart_axil_master test_uart_axil_master_u0 (.clk   (clk),
                                                        .rst_n (rst_n)
                                                       );
    `elsif USE_DMA_TEST
       test_dma test_dma_u0 (.clk   (clk),
                             .rst_n (rst_n)
                            );
    `elsif USE_CDMA_TEST
        test_cdma test_cdma_u0 (.clk   (clk),
                                .rst_n (rst_n)
                               );
    `elsif USE_VDMA_TEST
        test_vdma test_vdma_u0 (.clk   (clk),
                                .rst_n (rst_n)
                               );
    `elsif USE_VDMA_TIMING_TEST
        test_vdma_timing test_vdma_timing_u0 (.clk   (clk),
                                              .rst_n (rst_n)
                                             );
    `elsif USE_AXIS_AFIFO
        test_axis_afifo test_axis_afifo_u0 (.clk   (clk),
                                            .rst_n (rst_n)
                                           );
    `elsif USE_AXIS_ARBITER
        test_axis_arbiter test_axis_arbiter_u0 (.clk   (clk),
                                               .rst_n (rst_n)
                                              );
    `elsif USE_AXIS_ARBITER_BEAT
        test_axis_arbiter_beat test_axis_arbiter_beat_u0 (.clk   (clk),
                                                           .rst_n (rst_n)
                                                          );
    `elsif USE_AXIS_ARBITER_WEIGHTED
        test_axis_arbiter_weighted test_axis_arbiter_weighted_u0 (.clk   (clk),
                                                                  .rst_n (rst_n)
                                                                 );
    `elsif USE_AXIS_UPSIZER
        test_axis_upsizer test_axis_upsizer_u0 (.clk   (clk),
                                                .rst_n (rst_n)
                                               );
    `elsif USE_AXIS_DOWNSIZER
        test_axis_downsizer test_axis_downsizer_u0 (.clk   (clk),
                                                    .rst_n (rst_n)
                                                   );
    `elsif USE_AXIS_RR_CONVERTER
        test_axis_rr_converter test_axis_rr_converter_u0 (.clk   (clk),
                                                          .rst_n (rst_n)
                                                         );
    `elsif USE_AXIS_RR_UPSIZER
        test_axis_rr_upsizer test_axis_rr_upsizer_u0 (.clk   (clk),
                                                       .rst_n (rst_n)
                                                      );
    `elsif USE_AXIS_RR_DOWNSIZER
        test_axis_rr_downsizer test_axis_rr_downsizer_u0 (.clk   (clk),
                                                           .rst_n (rst_n)
                                                          );
    `elsif USE_VIDEO_AXIS_LOOPBACK
        test_video_axis_loopback test_video_axis_loopback_u0 (.clk   (clk),
                                                              .rst_n (rst_n)
                                                             );
    `elsif USE_VIDEO_FIFO_LOOPBACK
        test_video_fifo_loopback test_video_fifo_loopback_u0 (.clk   (clk),
                                                              .rst_n (rst_n)
                                                             );
    `elsif USE_VIDEO_AFIFO_LOOPBACK
        test_video_afifo_loopback test_video_afifo_loopback_u0 (.clk   (clk),
                                                                .rst_n (rst_n)
                                                               );
    `elsif USE_VIDEO_ADAPTER_ERRORS
        test_video_adapter_errors test_video_adapter_errors_u0 (.clk   (clk),
                                                                .rst_n (rst_n)
                                                               );
    `elsif USE_VIDEO_MODE_CLOCKS
        test_video_mode_clocks test_video_mode_clocks_u0 (.clk   (clk),
                                                          .rst_n (rst_n)
                                                         );
    `elsif USE_VIDEO_RGB_CDC
        test_video_rgb_cdc test_video_rgb_cdc_u0 (.clk   (clk),
                                                  .rst_n (rst_n)
                                                 );
    `elsif USE_VIDEO_RGB32
        test_video_rgb32 test_video_rgb32_u0 (.clk   (clk),
                                              .rst_n (rst_n)
                                             );
    `elsif USE_VIDEO_CSC_RGB_YCBCR
        test_video_csc_rgb_ycbcr test_video_csc_rgb_ycbcr_u0 (.clk   (clk),
                                                              .rst_n (rst_n)
                                                             );
    `elsif USE_VIDEO_CSC_422
        test_video_csc_422 test_video_csc_422_u0 (.clk   (clk),
                                                  .rst_n (rst_n)
                                                 );
    `else
        initial begin
            $fatal(1, "No test environment selected. Define USE_AXIS_ENV or USE_AXI_ENV.");
        end
    `endif

    initial begin
        rst_n = 1;
        drive_reset();
    end

    task drive_reset();
        @(posedge clk);
        rst_n = 0;
        repeat (2) @(posedge clk);
        rst_n = 1;
        @(posedge clk);
    endtask

endmodule

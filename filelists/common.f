+incdir+tb
+incdir+tb
+incdir+rtl

tb/macros/axi_macros.sv

tb/assertions/axis_checker.sv
tb/assertions/axi_mm_checker.sv
tb/assertions/axi_4k_checker.sv
tb/assertions/axil_checker.sv

tb/interfaces/axis_if.sv
tb/interfaces/axil_if.sv
tb/interfaces/axi_if.sv

tb/packages/axi_pkg.sv
tb/packages/axi_dma_pkg.sv
tb/packages/axi_cdma_pkg.sv
tb/packages/axi_vdma_pkg.sv

rtl/video/snix_video_pkg.sv

tb/common/sample_axi_if.sv
tb/common/sample_axis_if.sv
tb/common/sample_axil_if.sv
tb/common/video_clock_gen.sv
tb/classes/video/video_frame_gen.sv
tb/classes/video/video_frame_source.sv
tb/classes/video/video_frame_sink.sv

rtl/common/snix_register_slice.sv
rtl/common/snix_sync_fifo.sv
rtl/common/snix_async_fifo.sv

rtl/uart/snix_uart_lite.sv

rtl/axis/snix_axis_register.sv
rtl/axis/snix_axis_fifo.sv
rtl/axis/snix_axis_afifo.sv
rtl/axis/snix_axis_arbiter.sv
rtl/axis/snix_axis_upsizer.sv
rtl/axis/snix_axis_downsizer.sv
rtl/axis/snix_axis_rr_converter.sv
rtl/axis/snix_axis_rr_upsizer.sv
rtl/axis/snix_axis_rr_downsizer.sv

rtl/video/snix_video_timing_gen.sv
rtl/video/snix_video_pattern_gen.sv
rtl/video/snix_video_to_axis.sv
rtl/video/snix_axis_to_video.sv
rtl/video/snix_video_rgb24_pack.sv
rtl/video/snix_video_rgb24_unpack.sv
rtl/video/snix_video_rgb32_pack.sv
rtl/video/snix_video_rgb32_unpack.sv
rtl/video/snix_video_rgb_to_ycbcr.sv
rtl/video/snix_video_ycbcr_to_rgb.sv
rtl/video/snix_video_csc_422.sv
rtl/video/snix_video_csc_422_expand.sv
rtl/video/snix_video_capture_cdc.sv
rtl/video/snix_video_display_cdc.sv

rtl/axil/snix_axil_register.sv
rtl/axil/snix_axil_gpio.sv
rtl/axil/snix_uart_axil_master.sv
rtl/axil/snix_uart_axil_slave.sv
rtl/axil/snix_axi_dma_csr.sv
rtl/axil/snix_axi_cdma_csr.sv

rtl/axi/snix_axi_dma.sv
rtl/axi/snix_axi_cdma.sv
rtl/axi/snix_axi_s2mm.sv
rtl/axi/snix_axi_mm2s.sv
rtl/axi/snix_axi_mm2mm.sv
rtl/axi/snix_axi_vdma_frame_store.sv
rtl/axi/snix_axi_vdma_s2mm.sv
rtl/axi/snix_axi_vdma_mm2s.sv
rtl/axi/snix_axi_vdma.sv
rtl/axi/snix_axi_multi_vdma_frame_store.sv
rtl/axi/snix_axi_multi_vdma.sv

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

tb/common/sample_axi_if.sv
tb/common/sample_axis_if.sv
tb/common/sample_axil_if.sv

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

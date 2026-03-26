# ==================================================
# Synthesis (Yosys)
# ==================================================
SYNTH_DIR     := $(WORK_DIR)/synth
VALID_SYNTHS  := axis_register uart_lite axis_arbiter axis_fifo axis_fifo_pkt axis_afifo axis_afifo_pkt axis_upsizer axis_downsizer axis_rr_converter axis_rr_upsizer axis_rr_downsizer axil_register axil_gpio uart_axil_slave uart_axil_master dma cdma
VALID_TARGETS := generic artix7
SYNTH_NAME    ?= axis_fifo
SYNTH_TARGET  ?= generic

# RTL file list (TB-free)
RTL_FILES := $(shell grep '^rtl/' filelists/rtl.f)

# Per-design top module and optional chparam
ifeq ($(SYNTH_NAME),axis_register)
  SYNTH_TOP   := snix_axis_register
  SYNTH_PARAM :=
else ifeq ($(SYNTH_NAME),axis_arbiter)
  SYNTH_TOP   := snix_axis_arbiter
  SYNTH_PARAM :=
else ifeq ($(SYNTH_NAME),axis_fifo)
  SYNTH_TOP   := snix_axis_fifo
  SYNTH_PARAM :=
else ifeq ($(SYNTH_NAME),axis_fifo_pkt)
  SYNTH_TOP   := snix_axis_fifo
  SYNTH_PARAM := -p "chparam -set FRAME_FIFO 1 snix_axis_fifo"
else ifeq ($(SYNTH_NAME),axis_afifo)
  SYNTH_TOP   := snix_axis_afifo
  SYNTH_PARAM :=
else ifeq ($(SYNTH_NAME),axis_afifo_pkt)
  SYNTH_TOP   := snix_axis_afifo
  SYNTH_PARAM := -p "chparam -set FRAME_FIFO 1 snix_axis_afifo"
else ifeq ($(SYNTH_NAME),axil_register)
  SYNTH_TOP   := snix_axil_register
  SYNTH_PARAM :=
else ifeq ($(SYNTH_NAME),axil_gpio)
  SYNTH_TOP   := snix_axil_gpio
  SYNTH_PARAM :=
else ifeq ($(SYNTH_NAME),uart_lite)
  SYNTH_TOP   := snix_uart_lite
  SYNTH_PARAM :=
else ifeq ($(SYNTH_NAME),uart_axil_slave)
  SYNTH_TOP   := snix_uart_axil_slave
  SYNTH_PARAM :=
else ifeq ($(SYNTH_NAME),uart_axil_master)
  SYNTH_TOP   := snix_uart_axil_master
  SYNTH_PARAM :=
else ifeq ($(SYNTH_NAME),dma)
  SYNTH_TOP   := snix_axi_dma
  SYNTH_PARAM :=
else ifeq ($(SYNTH_NAME),cdma)
  SYNTH_TOP   := snix_axi_cdma
  SYNTH_PARAM :=
else ifeq ($(SYNTH_NAME),axis_upsizer)
  SYNTH_TOP   := snix_axis_upsizer
  SYNTH_PARAM :=
else ifeq ($(SYNTH_NAME),axis_downsizer)
  SYNTH_TOP   := snix_axis_downsizer
  SYNTH_PARAM :=
else ifeq ($(SYNTH_NAME),axis_rr_converter)
  SYNTH_TOP   := snix_axis_rr_converter
  SYNTH_PARAM :=
else ifeq ($(SYNTH_NAME),axis_rr_upsizer)
  SYNTH_TOP   := snix_axis_rr_upsizer
  SYNTH_PARAM :=
else ifeq ($(SYNTH_NAME),axis_rr_downsizer)
  SYNTH_TOP   := snix_axis_rr_downsizer
  SYNTH_PARAM :=
endif

# Per-target synthesis command
ifeq ($(SYNTH_TARGET),artix7)
  SYNTH_CMD := synth_xilinx -top $(SYNTH_TOP) -flatten -family xc7 -noiopad
else
  SYNTH_CMD := synth -top $(SYNTH_TOP) -flatten
endif

SYNTH_LOG := $(SYNTH_DIR)/$(SYNTH_NAME)_$(SYNTH_TARGET).log
SYNTH_NET := $(SYNTH_DIR)/$(SYNTH_NAME)_$(SYNTH_TARGET)_netlist.v

.PHONY: synth synth-all

synth:
	@if [ -z "$(SYNTH_TOP)" ]; then \
		echo "Error: unknown SYNTH_NAME '$(SYNTH_NAME)'."; \
		echo "Valid values: $(VALID_SYNTHS)"; \
		exit 1; \
	fi
	@if [ -z "$(filter $(SYNTH_TARGET),$(VALID_TARGETS))" ]; then \
		echo "Error: unknown SYNTH_TARGET '$(SYNTH_TARGET)'."; \
		echo "Valid values: $(VALID_TARGETS)"; \
		exit 1; \
	fi
	@mkdir -p $(SYNTH_DIR)
	@echo "Synthesizing $(SYNTH_NAME) (top: $(SYNTH_TOP), target: $(SYNTH_TARGET))..."
	yosys \
		-p "read_verilog -sv -I rtl $(RTL_FILES)" \
		$(SYNTH_PARAM) \
		-p "$(SYNTH_CMD)" \
		-p "stat" \
		-p "write_verilog -noattr $(SYNTH_NET)" \
		2>&1 | tee $(SYNTH_LOG)

synth-all:
	@for name in $(VALID_SYNTHS); do \
		$(MAKE) synth SYNTH_NAME=$$name SYNTH_TARGET=$(SYNTH_TARGET) || exit 1; \
	done

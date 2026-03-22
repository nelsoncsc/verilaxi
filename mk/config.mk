# ==================================================
# Configuration variables
# ==================================================
TOP_NAME := testbench

RTL_DIR    := rtl
TB_DIR     := tb
TB_CPP_DIR := tb_cpp
WORK_DIR   := work
OBJ_DIR    ?= obj_dir
LOG_DIR    := $(WORK_DIR)/logs
WAVE_DIR   := $(WORK_DIR)/waves

FILELIST_COMMON := filelists/common.f
FILELIST_TB     := filelists/tb_top.f

VALID_TESTS := axis_register axis_fifo axis_afifo axis_arbiter axis_arbiter_beat axis_arbiter_weighted dma axil_register cdma
TESTNAME    ?= axis_register

SRC_BP      ?=
SINK_BP     ?=
TESTTYPE    ?=
READY_PROB  ?=
FRAME_FIFO  ?=

AXIS_SRC_BP_VAL   := $(if $(SRC_BP),$(SRC_BP),0)
AXIS_SINK_BP_VAL  := $(if $(SINK_BP),$(SINK_BP),0)
AXIS_FRAME_VAL    := $(if $(FRAME_FIFO),$(FRAME_FIFO),0)
AFIFO_TESTTYPE_VAL:= $(if $(TESTTYPE),$(TESTTYPE),0)
DMA_TESTTYPE_VAL  := $(if $(TESTTYPE),$(TESTTYPE),4)
CDMA_TESTTYPE_VAL := $(if $(TESTTYPE),$(TESTTYPE),1)
READY_PROB_VAL    := $(if $(READY_PROB),$(READY_PROB),100)

ifeq ($(TESTNAME),axis_register)
  RUN_TAG := $(TESTNAME)_src$(AXIS_SRC_BP_VAL)_sink$(AXIS_SINK_BP_VAL)
else ifeq ($(TESTNAME),axis_arbiter)
  RUN_TAG := $(TESTNAME)_src$(AXIS_SRC_BP_VAL)_sink$(AXIS_SINK_BP_VAL)
else ifeq ($(TESTNAME),axis_arbiter_beat)
  RUN_TAG := $(TESTNAME)_src$(AXIS_SRC_BP_VAL)_sink$(AXIS_SINK_BP_VAL)
else ifeq ($(TESTNAME),axis_arbiter_weighted)
  RUN_TAG := $(TESTNAME)_src$(AXIS_SRC_BP_VAL)_sink$(AXIS_SINK_BP_VAL)
else ifeq ($(TESTNAME),axis_fifo)
  RUN_TAG := $(TESTNAME)_ff$(AXIS_FRAME_VAL)_src$(AXIS_SRC_BP_VAL)_sink$(AXIS_SINK_BP_VAL)
else ifeq ($(TESTNAME),axis_afifo)
  RUN_TAG := $(TESTNAME)_ff$(AXIS_FRAME_VAL)_tt$(AFIFO_TESTTYPE_VAL)_src$(AXIS_SRC_BP_VAL)_sink$(AXIS_SINK_BP_VAL)
else ifeq ($(TESTNAME),dma)
  RUN_TAG := $(TESTNAME)_tt$(DMA_TESTTYPE_VAL)_rp$(READY_PROB_VAL)
else ifeq ($(TESTNAME),cdma)
  RUN_TAG := $(TESTNAME)_tt$(CDMA_TESTTYPE_VAL)_rp$(READY_PROB_VAL)
else
  RUN_TAG := $(TESTNAME)
endif

LOG_FILE   := $(LOG_DIR)/$(RUN_TAG).log
WAVE_FILE  := $(WAVE_DIR)/$(RUN_TAG).fst

SIM_CPP   := $(shell find $(TB_CPP_DIR) -name '*.cpp')

# ENV_FILE per test
ifeq ($(TESTNAME),axis_register)
    ENV_FILE := $(TB_DIR)/tests/axis/test_axis_register.sv
else ifeq ($(TESTNAME),axis_fifo)
    ENV_FILE := $(TB_DIR)/tests/axis/test_axis_fifo.sv
else ifeq ($(TESTNAME),axis_afifo)
    ENV_FILE := $(TB_DIR)/tests/axis/test_axis_afifo.sv
else ifeq ($(TESTNAME),axis_arbiter)
    ENV_FILE := $(TB_DIR)/tests/axis/test_axis_arbiter.sv
else ifeq ($(TESTNAME),axis_arbiter_beat)
    ENV_FILE := $(TB_DIR)/tests/axis/test_axis_arbiter_beat.sv
else ifeq ($(TESTNAME),axis_arbiter_weighted)
    ENV_FILE := $(TB_DIR)/tests/axis/test_axis_arbiter_weighted.sv
else ifeq ($(TESTNAME),dma)
    ENV_FILE := $(TB_DIR)/tests/axi/test_dma.sv
else ifeq ($(TESTNAME),axil_register)
    ENV_FILE := $(TB_DIR)/tests/axil/test_axil_register.sv
else ifeq ($(TESTNAME),cdma)
    ENV_FILE := $(TB_DIR)/tests/axi/test_cdma.sv
endif


SIM_ARGS :=
SIM_ARGS += $(if $(SRC_BP),+SRC_BP=$(SRC_BP))
SIM_ARGS += $(if $(SINK_BP),+SINK_BP=$(SINK_BP))
SIM_ARGS += $(if $(TESTTYPE),+TESTTYPE=$(TESTTYPE))
SIM_ARGS += $(if $(READY_PROB),+READY_PROB=$(READY_PROB))

# ------------------------
# VERILATOR macros per test
# ------------------------
ifeq ($(TESTNAME),axis_register)
  VERILATOR_DEFS := +define+USE_AXIS_REGISTER
else ifeq ($(TESTNAME),axis_fifo)
  VERILATOR_DEFS := +define+USE_AXIS_FIFO
  ifeq ($(FRAME_FIFO),1)
    VERILATOR_DEFS += +define+FRAME_FIFO
  endif
else ifeq ($(TESTNAME),axis_afifo)
  VERILATOR_DEFS := +define+USE_AXIS_AFIFO
  ifeq ($(FRAME_FIFO),1)
    VERILATOR_DEFS += +define+FRAME_FIFO
  endif
else ifeq ($(TESTNAME),axis_arbiter)
  VERILATOR_DEFS := +define+USE_AXIS_ARBITER
else ifeq ($(TESTNAME),axis_arbiter_beat)
  VERILATOR_DEFS := +define+USE_AXIS_ARBITER_BEAT
else ifeq ($(TESTNAME),axis_arbiter_weighted)
  VERILATOR_DEFS := +define+USE_AXIS_ARBITER_WEIGHTED
else ifeq ($(TESTNAME),dma)
  VERILATOR_DEFS := +define+USE_DMA_TEST
else ifeq ($(TESTNAME),axil_register)
  VERILATOR_DEFS := +define+USE_AXIL_REGISTER
else ifeq ($(TESTNAME),cdma)
  VERILATOR_DEFS := +define+USE_CDMA_TEST
endif

VERILATOR_SRCS := \
	-f $(FILELIST_COMMON) \
	-f $(FILELIST_TB) \
	$(ENV_FILE) \
	$(SIM_CPP)

# Validate TESTNAME
ifndef SKIP_VALIDATE
  ifeq ($(filter $(TESTNAME),$(VALID_TESTS)),)
    $(error TESTNAME '$(TESTNAME)' is invalid. Valid values: $(VALID_TESTS))
  endif
endif

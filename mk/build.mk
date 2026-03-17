# ==================================================
# Build & run targets
# ==================================================
.PHONY: run clean cleanall

$(OBJ_DIR)/V$(TOP_NAME): $(SIM_CPP)
	verilator -Wall --assert \
		-Wno-UNUSEDSIGNAL -Wno-EOFNEWLINE -Wno-WIDTHTRUNC -Wno-DECLFILENAME \
		-Wno-SYNCASYNCNET \
		-CFLAGS "-fcoroutines" \
		--cc --sv --exe --build \
		--timing --trace-fst --trace-structs \
		-I$(RTL_DIR) -I$(TB_DIR) \
		--top-module $(TOP_NAME) \
		$(VERILATOR_DEFS) \
		$(VERILATOR_SRCS) \
		--Mdir $(OBJ_DIR) \
		-j $$(nproc 2>/dev/null || sysctl -n hw.logicalcpu)

run: $(OBJ_DIR)/V$(TOP_NAME)
	@mkdir -p $(LOG_DIR) $(WAVE_DIR)
	@echo "Running simulation: $(RUN_TAG)" | tee $(LOG_FILE)
	@./$(OBJ_DIR)/V$(TOP_NAME) $(WAVE_FILE) $(SIM_ARGS) \
		2>&1 | tee -a $(LOG_FILE)
	@echo "Simulation complete. Waveform: $(WAVE_FILE)" \
		| tee -a $(LOG_FILE)

clean:
	rm -rf $(OBJ_DIR)

cleanall: clean
	rm -rf $(WORK_DIR)

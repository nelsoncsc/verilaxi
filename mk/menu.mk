menu:
	@while true; do \
		echo ""; \
		echo "======================================"; \
		echo " Verilator Simulation Menu"; \
		echo "======================================"; \
		echo "Available tests:"; \
		echo "  1) axis_register"; \
		echo "  2) axis_fifo"; \
		echo "  3) axil_register"; \
		echo "  4) dma"; \
		echo "  5) cdma"; \
		echo "  6) axis_afifo (async FIFO CDC)"; \
		echo ""; \
		echo "Commands:"; \
		echo "  s) synth — synthesize a design with Yosys"; \
		echo "  h) help"; \
		echo "  c) clean all"; \
		echo "  q) quit"; \
		echo ""; \
		echo "Select a test [1-6], command, or q to quit:"; \
		read -r choice; \
		case "$$choice" in \
			1) \
				echo "You selected AXIS_REGISTER test."; \
				echo "SRC_BP (source backpressure) = whether the AXIS source can be stalled (0=no, 1=yes)"; \
				echo "SINK_BP (sink backpressure)   = whether the AXIS sink can stall the source (0=no, 1=yes)"; \
				read -p "Enter SRC_BP (0 or 1): " SRC_BP; \
				read -p "Enter SINK_BP (0 or 1): " SINK_BP; \
				$(MAKE) clean run TESTNAME=axis_register SRC_BP=$$SRC_BP SINK_BP=$$SINK_BP; \
				code=$$?; \
				if [ $$code -ne 0 ]; then echo "Simulation failed. Exiting menu."; break; else echo "Simulation successful. Exiting menu."; break; fi ;; \
			2) \
				echo "You selected AXIS_FIFO test."; \
				echo "  FRAME_FIFO=0  streaming / cut-through (default)"; \
				echo "  FRAME_FIFO=1  store-and-forward (holds tvalid until tlast received)"; \
				read -p "Enter FRAME_FIFO (0 or 1, default=0): " FRAME_FIFO; \
				read -p "Enter SRC_BP (0 or 1): " SRC_BP; \
				read -p "Enter SINK_BP (0 or 1): " SINK_BP; \
				$(MAKE) clean run TESTNAME=axis_fifo FRAME_FIFO=$$FRAME_FIFO SRC_BP=$$SRC_BP SINK_BP=$$SINK_BP; \
				code=$$?; \
				if [ $$code -ne 0 ]; then echo "Simulation failed. Exiting menu."; break; else echo "Simulation successful. Exiting menu."; break; fi ;; \
			3) \
				echo "You selected AXIL_REGISTER test."; \
				$(MAKE) clean run TESTNAME=axil_register; \
				code=$$?; \
				if [ $$code -ne 0 ]; then echo "Simulation failed. Exiting menu."; break; else echo "Simulation successful. Exiting menu."; break; fi ;; \
			4) \
				echo "You selected AXI DMA test."; \
				echo "  0) Write abort"; \
				echo "  1) Write DMA + read abort"; \
				echo "  2) Four concurrent write+read frames"; \
				echo "  3) 4KB boundary crossing + partial last beat"; \
				echo "  4) Circular mode (default)"; \
				read -p "Enter TESTTYPE [0-4, default=4]: " TESTTYPE; \
				read -p "Enter READY_PROB 0-100 (AXI slave ready probability, default=100): " READY_PROB; \
				$(MAKE) clean run TESTNAME=dma TESTTYPE=$$TESTTYPE READY_PROB=$$READY_PROB; \
				code=$$?; \
				if [ $$code -ne 0 ]; then echo "Simulation failed. Exiting menu."; break; else echo "Simulation successful. Exiting menu."; break; fi ;; \
			5) \
				echo "You selected AXI CDMA test."; \
				echo "  0) Basic aligned copy (256 B)"; \
				echo "  1) 4KB boundary crossing + partial last beat (default)"; \
				echo "  2) Four consecutive frames (64 B each)"; \
				echo "  3) Abort mid-transfer"; \
				read -p "Enter TESTTYPE [0-3, default=1]: " TESTTYPE; \
				read -p "Enter READY_PROB 0-100 (AXI slave ready probability, default=100): " READY_PROB; \
				$(MAKE) clean run TESTNAME=cdma TESTTYPE=$$TESTTYPE READY_PROB=$$READY_PROB; \
				code=$$?; \
				if [ $$code -ne 0 ]; then echo "Simulation failed. Exiting menu."; break; else echo "Simulation successful. Exiting menu."; break; fi ;; \
			6) \
			echo "You selected AXIS AFIFO (async FIFO CDC) test."; \
			echo "  FRAME_FIFO=0  cut-through / streaming (default)"; \
			echo "  FRAME_FIFO=1  store-and-forward (holds tvalid until tlast received)"; \
			echo "  TESTTYPE 0 = same-rate clocks, 1 = read slow, 2 = read fast"; \
			read -p "Enter FRAME_FIFO (0 or 1, default=0): " FRAME_FIFO; \
			read -p "Enter TESTTYPE (0-2, default=0): " TESTTYPE; \
			read -p "Enter SRC_BP (0 or 1): " SRC_BP; \
			read -p "Enter SINK_BP (0 or 1): " SINK_BP; \
			$(MAKE) clean run TESTNAME=axis_afifo FRAME_FIFO=$$FRAME_FIFO TESTTYPE=$$TESTTYPE SRC_BP=$$SRC_BP SINK_BP=$$SINK_BP; \
			code=$$?; \
			if [ $$code -ne 0 ]; then echo "Simulation failed. Exiting menu."; break; else echo "Simulation successful. Exiting menu."; break; fi ;; \
		s|S) \
				echo "Select design to synthesize:"; \
				echo "  1) axis_register"; \
				echo "  2) axis_fifo (streaming, FRAME_FIFO=0)"; \
				echo "  3) axis_fifo (frame mode, FRAME_FIFO=1)"; \
				echo "  4) axis_afifo (streaming, FRAME_FIFO=0)"; \
				echo "  5) axis_afifo (frame mode, FRAME_FIFO=1)"; \
				echo "  6) axil_register"; \
				echo "  7) dma"; \
				echo "  8) cdma"; \
				echo "  9) all"; \
				read -p "Enter choice [1-9]: " schoice; \
				echo "Synthesis target:"; \
				echo "  g) generic  -- technology-independent (default)"; \
				echo "  a) artix7   -- Xilinx 7-series (LUT6/FDRE/CARRY4 cells)"; \
				read -p "Enter target [g/a, default=g]: " starget; \
				case "$$starget" in \
					a|A|artix7) SYNTH_TARGET=artix7 ;; \
					*)           SYNTH_TARGET=generic ;; \
				esac; \
				case "$$schoice" in \
					1) $(MAKE) synth SYNTH_NAME=axis_register  SYNTH_TARGET=$$SYNTH_TARGET ;; \
					2) $(MAKE) synth SYNTH_NAME=axis_fifo      SYNTH_TARGET=$$SYNTH_TARGET ;; \
					3) $(MAKE) synth SYNTH_NAME=axis_fifo_pkt  SYNTH_TARGET=$$SYNTH_TARGET ;; \
					4) $(MAKE) synth SYNTH_NAME=axis_afifo     SYNTH_TARGET=$$SYNTH_TARGET ;; \
					5) $(MAKE) synth SYNTH_NAME=axis_afifo_pkt SYNTH_TARGET=$$SYNTH_TARGET ;; \
					6) $(MAKE) synth SYNTH_NAME=axil_register  SYNTH_TARGET=$$SYNTH_TARGET ;; \
					7) $(MAKE) synth SYNTH_NAME=dma            SYNTH_TARGET=$$SYNTH_TARGET ;; \
					8) $(MAKE) synth SYNTH_NAME=cdma           SYNTH_TARGET=$$SYNTH_TARGET ;; \
					9) $(MAKE) synth-all                       SYNTH_TARGET=$$SYNTH_TARGET ;; \
					*) echo "Invalid choice." ;; \
				esac ;; \
			h|H) $(MAKE) help ;; \
			c) $(MAKE) cleanall ;; \
			q|Q) echo "Exiting."; break ;; \
			*) echo "Invalid selection."; ;; \
		esac; \
	done

menu:
	@while true; do \
		echo ""; \
		echo "======================================"; \
		echo " Verilaxi Simulator Menu"; \
		echo "======================================"; \
		echo "Available tests:"; \
		echo "  1) axis_register"; \
		echo "  2) axis_arbiter"; \
		echo "  3) axis_arbiter_beat"; \
		echo "  4) axis_arbiter_weighted"; \
		echo "  5) axis_fifo"; \
		echo "  6) axil_register"; \
		echo "  7) axis_afifo (async FIFO CDC)"; \
		echo "  8) dma"; \
		echo "  9) cdma"; \
		echo " 10) axis_upsizer (integer k:1, default IN=8 OUT=32)"; \
		echo " 11) axis_downsizer (integer 1:k, default IN=32 OUT=8)"; \
		echo " 12) axis_rr_converter (rational ratio, default IN=32 OUT=48)"; \
		echo " 13) axis_rr_upsizer (rational up, default IN=16 OUT=24)"; \
		echo " 14) axis_rr_downsizer (rational down, default IN=24 OUT=16)"; \
		echo " 15) uart_lite"; \
		echo " 16) uart_axil_slave"; \
		echo " 17) uart_axil_master"; \
		echo " 18) axil_gpio"; \
		echo " 19) vdma"; \
		echo " 20) video_axis_loopback"; \
		echo " 21) video_fifo_loopback"; \
		echo " 22) video_afifo_loopback"; \
		echo " 23) video_adapter_errors"; \
		echo " 24) video_mode_clocks"; \
		echo " 25) video_rgb_cdc"; \
		echo " 26) video_rgb32"; \
		echo " 27) video_csc_rgb_ycbcr"; \
		echo " 28) video_csc_422"; \
		echo " 29) vdma_timing"; \
		echo " 30) multi_vdma"; \
		echo ""; \
		echo "Commands:"; \
		echo "  s) synth — synthesize a design with Yosys"; \
		echo "  h) help"; \
		echo "  c) clean all"; \
		echo "  q) quit"; \
		echo ""; \
		echo "Select a test [1-30], command, or q to quit:"; \
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
				echo "You selected AXIS_ARBITER test."; \
				echo "SRC_BP (source backpressure) = whether the AXIS sources can be stalled (0=no, 1=yes)"; \
				echo "SINK_BP (sink backpressure)   = whether the AXIS sink can stall the arbiter (0=no, 1=yes)"; \
				read -p "Enter SRC_BP (0 or 1): " SRC_BP; \
				read -p "Enter SINK_BP (0 or 1): " SINK_BP; \
				$(MAKE) clean run TESTNAME=axis_arbiter SRC_BP=$$SRC_BP SINK_BP=$$SINK_BP; \
				code=$$?; \
				if [ $$code -ne 0 ]; then echo "Simulation failed. Exiting menu."; break; else echo "Simulation successful. Exiting menu."; break; fi ;; \
			3) \
				echo "You selected AXIS_ARBITER_BEAT test."; \
				echo "SRC_BP (source backpressure) = whether the AXIS sources can be stalled (0=no, 1=yes)"; \
				echo "SINK_BP (sink backpressure)   = whether the AXIS sink can stall the arbiter (0=no, 1=yes)"; \
				read -p "Enter SRC_BP (0 or 1): " SRC_BP; \
				read -p "Enter SINK_BP (0 or 1): " SINK_BP; \
				$(MAKE) clean run TESTNAME=axis_arbiter_beat SRC_BP=$$SRC_BP SINK_BP=$$SINK_BP; \
				code=$$?; \
				if [ $$code -ne 0 ]; then echo "Simulation failed. Exiting menu."; break; else echo "Simulation successful. Exiting menu."; break; fi ;; \
			4) \
				echo "You selected AXIS_ARBITER_WEIGHTED test."; \
				echo "SRC_BP (source backpressure) = whether the AXIS sources can be stalled (0=no, 1=yes)"; \
				echo "SINK_BP (sink backpressure)   = whether the AXIS sink can stall the arbiter (0=no, 1=yes)"; \
				read -p "Enter SRC_BP (0 or 1): " SRC_BP; \
				read -p "Enter SINK_BP (0 or 1): " SINK_BP; \
				$(MAKE) clean run TESTNAME=axis_arbiter_weighted SRC_BP=$$SRC_BP SINK_BP=$$SINK_BP; \
				code=$$?; \
				if [ $$code -ne 0 ]; then echo "Simulation failed. Exiting menu."; break; else echo "Simulation successful. Exiting menu."; break; fi ;; \
			5) \
				echo "You selected AXIS_FIFO test."; \
				echo "  FRAME_FIFO=0  streaming / cut-through (default)"; \
				echo "  FRAME_FIFO=1  store-and-forward (holds tvalid until tlast received)"; \
				read -p "Enter FRAME_FIFO (0 or 1, default=0): " FRAME_FIFO; \
				read -p "Enter SRC_BP (0 or 1): " SRC_BP; \
				read -p "Enter SINK_BP (0 or 1): " SINK_BP; \
				$(MAKE) clean run TESTNAME=axis_fifo FRAME_FIFO=$$FRAME_FIFO SRC_BP=$$SRC_BP SINK_BP=$$SINK_BP; \
				code=$$?; \
				if [ $$code -ne 0 ]; then echo "Simulation failed. Exiting menu."; break; else echo "Simulation successful. Exiting menu."; break; fi ;; \
			6) \
				echo "You selected AXIL_REGISTER test."; \
				$(MAKE) clean run TESTNAME=axil_register; \
				code=$$?; \
				if [ $$code -ne 0 ]; then echo "Simulation failed. Exiting menu."; break; else echo "Simulation successful. Exiting menu."; break; fi ;; \
			7) \
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
			8) \
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
			9) \
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
		10) \
			echo "You selected AXIS_UPSIZER test (integer k:1, IN=8 OUT=32)."; \
			echo "SRC_BP (source backpressure) = whether the AXIS source can be stalled (0=no, 1=yes)"; \
			echo "SINK_BP (sink backpressure)   = whether the AXIS sink can stall the DUT (0=no, 1=yes)"; \
			read -p "Enter SRC_BP (0 or 1): " SRC_BP; \
			read -p "Enter SINK_BP (0 or 1): " SINK_BP; \
			$(MAKE) clean run TESTNAME=axis_upsizer SRC_BP=$$SRC_BP SINK_BP=$$SINK_BP; \
			code=$$?; \
			if [ $$code -ne 0 ]; then echo "Simulation failed. Exiting menu."; break; else echo "Simulation successful. Exiting menu."; break; fi ;; \
		11) \
			echo "You selected AXIS_DOWNSIZER test (integer 1:k, IN=32 OUT=8)."; \
			echo "SRC_BP (source backpressure) = whether the AXIS source can be stalled (0=no, 1=yes)"; \
			echo "SINK_BP (sink backpressure)   = whether the AXIS sink can stall the DUT (0=no, 1=yes)"; \
			read -p "Enter SRC_BP (0 or 1): " SRC_BP; \
			read -p "Enter SINK_BP (0 or 1): " SINK_BP; \
			$(MAKE) clean run TESTNAME=axis_downsizer SRC_BP=$$SRC_BP SINK_BP=$$SINK_BP; \
			code=$$?; \
			if [ $$code -ne 0 ]; then echo "Simulation failed. Exiting menu."; break; else echo "Simulation successful. Exiting menu."; break; fi ;; \
		12) \
			echo "You selected AXIS_RR_CONVERTER test (rational ratio, IN=32 OUT=48)."; \
			echo "SRC_BP (source backpressure) = whether the AXIS source can be stalled (0=no, 1=yes)"; \
			echo "SINK_BP (sink backpressure)   = whether the AXIS sink can stall the DUT (0=no, 1=yes)"; \
			read -p "Enter SRC_BP (0 or 1): " SRC_BP; \
			read -p "Enter SINK_BP (0 or 1): " SINK_BP; \
			$(MAKE) clean run TESTNAME=axis_rr_converter SRC_BP=$$SRC_BP SINK_BP=$$SINK_BP; \
			code=$$?; \
			if [ $$code -ne 0 ]; then echo "Simulation failed. Exiting menu."; break; else echo "Simulation successful. Exiting menu."; break; fi ;; \
		13) \
			echo "You selected AXIS_RR_UPSIZER test (rational up, IN=16 OUT=24)."; \
			echo "SRC_BP (source backpressure) = whether the AXIS source can be stalled (0=no, 1=yes)"; \
			echo "SINK_BP (sink backpressure)   = whether the AXIS sink can stall the DUT (0=no, 1=yes)"; \
			read -p "Enter SRC_BP (0 or 1): " SRC_BP; \
			read -p "Enter SINK_BP (0 or 1): " SINK_BP; \
			$(MAKE) clean run TESTNAME=axis_rr_upsizer SRC_BP=$$SRC_BP SINK_BP=$$SINK_BP; \
			code=$$?; \
			if [ $$code -ne 0 ]; then echo "Simulation failed. Exiting menu."; break; else echo "Simulation successful. Exiting menu."; break; fi ;; \
		14) \
			echo "You selected AXIS_RR_DOWNSIZER test (rational down, IN=24 OUT=16)."; \
			echo "SRC_BP (source backpressure) = whether the AXIS source can be stalled (0=no, 1=yes)"; \
			echo "SINK_BP (sink backpressure)   = whether the AXIS sink can stall the DUT (0=no, 1=yes)"; \
			read -p "Enter SRC_BP (0 or 1): " SRC_BP; \
			read -p "Enter SINK_BP (0 or 1): " SINK_BP; \
			$(MAKE) clean run TESTNAME=axis_rr_downsizer SRC_BP=$$SRC_BP SINK_BP=$$SINK_BP; \
			code=$$?; \
			if [ $$code -ne 0 ]; then echo "Simulation failed. Exiting menu."; break; else echo "Simulation successful. Exiting menu."; break; fi ;; \
		15) \
			echo "You selected UART_LITE test."; \
			$(MAKE) clean run TESTNAME=uart_lite; \
			code=$$?; \
			if [ $$code -ne 0 ]; then echo "Simulation failed. Exiting menu."; break; else echo "Simulation successful. Exiting menu."; break; fi ;; \
		16) \
			echo "You selected UART_AXIL_SLAVE test."; \
			$(MAKE) clean run TESTNAME=uart_axil_slave; \
			code=$$?; \
			if [ $$code -ne 0 ]; then echo "Simulation failed. Exiting menu."; break; else echo "Simulation successful. Exiting menu."; break; fi ;; \
		17) \
			echo "You selected UART_AXIL_MASTER test."; \
			$(MAKE) clean run TESTNAME=uart_axil_master; \
			code=$$?; \
			if [ $$code -ne 0 ]; then echo "Simulation failed. Exiting menu."; break; else echo "Simulation successful. Exiting menu."; break; fi ;; \
		18) \
			echo "You selected AXIL_GPIO test."; \
			$(MAKE) clean run TESTNAME=axil_gpio; \
			code=$$?; \
			if [ $$code -ne 0 ]; then echo "Simulation failed. Exiting menu."; break; else echo "Simulation successful. Exiting menu."; break; fi ;; \
		19) \
			echo "You selected AXI VDMA test."; \
			read -p "Enter READY_PROB 0-100 (AXI slave ready probability, default=100): " READY_PROB; \
			$(MAKE) clean run TESTNAME=vdma READY_PROB=$$READY_PROB; \
			code=$$?; \
			if [ $$code -ne 0 ]; then echo "Simulation failed. Exiting menu."; break; else echo "Simulation successful. Exiting menu."; break; fi ;; \
		20) \
			echo "You selected VIDEO_AXIS_LOOPBACK test."; \
			$(MAKE) clean run TESTNAME=video_axis_loopback; \
			code=$$?; \
			if [ $$code -ne 0 ]; then echo "Simulation failed. Exiting menu."; break; else echo "Simulation successful. Exiting menu."; break; fi ;; \
		21) \
			echo "You selected VIDEO_FIFO_LOOPBACK test."; \
			$(MAKE) clean run TESTNAME=video_fifo_loopback; \
			code=$$?; \
			if [ $$code -ne 0 ]; then echo "Simulation failed. Exiting menu."; break; else echo "Simulation successful. Exiting menu."; break; fi ;; \
		22) \
			echo "You selected VIDEO_AFIFO_LOOPBACK test."; \
			$(MAKE) clean run TESTNAME=video_afifo_loopback; \
			code=$$?; \
			if [ $$code -ne 0 ]; then echo "Simulation failed. Exiting menu."; break; else echo "Simulation successful. Exiting menu."; break; fi ;; \
		23) \
			echo "You selected VIDEO_ADAPTER_ERRORS test."; \
			$(MAKE) clean run TESTNAME=video_adapter_errors; \
			code=$$?; \
			if [ $$code -ne 0 ]; then echo "Simulation failed. Exiting menu."; break; else echo "Simulation successful. Exiting menu."; break; fi ;; \
		24) \
			echo "You selected VIDEO_MODE_CLOCKS test."; \
			$(MAKE) clean run TESTNAME=video_mode_clocks; \
			code=$$?; \
			if [ $$code -ne 0 ]; then echo "Simulation failed. Exiting menu."; break; else echo "Simulation successful. Exiting menu."; break; fi ;; \
		25) \
			echo "You selected VIDEO_RGB_CDC test."; \
			$(MAKE) clean run TESTNAME=video_rgb_cdc; \
			code=$$?; \
			if [ $$code -ne 0 ]; then echo "Simulation failed. Exiting menu."; break; else echo "Simulation successful. Exiting menu."; break; fi ;; \
		26) \
			echo "You selected VIDEO_RGB32 test."; \
			$(MAKE) clean run TESTNAME=video_rgb32; \
			code=$$?; \
			if [ $$code -ne 0 ]; then echo "Simulation failed. Exiting menu."; break; else echo "Simulation successful. Exiting menu."; break; fi ;; \
		27) \
			echo "You selected VIDEO_CSC_RGB_YCBCR test."; \
			$(MAKE) clean run TESTNAME=video_csc_rgb_ycbcr; \
			code=$$?; \
			if [ $$code -ne 0 ]; then echo "Simulation failed. Exiting menu."; break; else echo "Simulation successful. Exiting menu."; break; fi ;; \
		28) \
			echo "You selected VIDEO_CSC_422 test."; \
			$(MAKE) clean run TESTNAME=video_csc_422; \
			code=$$?; \
			if [ $$code -ne 0 ]; then echo "Simulation failed. Exiting menu."; break; else echo "Simulation successful. Exiting menu."; break; fi ;; \
		29) \
			echo "You selected VDMA_TIMING test."; \
			echo "  VIDEO_VALIDATE=0  small 8x4 smoke profile (default)"; \
			echo "  VIDEO_VALIDATE=1  larger 32x16 timing-aware profile"; \
			read -p "Enter VIDEO_VALIDATE (0 or 1, default=0): " VIDEO_VALIDATE; \
			$(MAKE) clean run TESTNAME=vdma_timing VIDEO_VALIDATE=$$VIDEO_VALIDATE; \
			code=$$?; \
			if [ $$code -ne 0 ]; then echo "Simulation failed. Exiting menu."; break; else echo "Simulation successful. Exiting menu."; break; fi ;; \
		30) \
			echo "You selected MULTI_VDMA test."; \
			echo "  MULTI_VDMA_TAPS selects temporal read taps (1-3 in directed tests; default=2)"; \
			read -p "Enter MULTI_VDMA_TAPS (1-3, default=2): " MULTI_VDMA_TAPS; \
			$(MAKE) clean run TESTNAME=multi_vdma MULTI_VDMA_TAPS=$$MULTI_VDMA_TAPS; \
			code=$$?; \
			if [ $$code -ne 0 ]; then echo "Simulation failed. Exiting menu."; break; else echo "Simulation successful. Exiting menu."; break; fi ;; \
		s|S) \
				echo "Select design to synthesize:"; \
				echo "  1) axis_register"; \
				echo "  2) uart_lite"; \
				echo "  3) axis_arbiter"; \
				echo "  4) axis_fifo (streaming, FRAME_FIFO=0)"; \
				echo "  5) axis_fifo (frame mode, FRAME_FIFO=1)"; \
				echo "  6) axis_afifo (streaming, FRAME_FIFO=0)"; \
				echo "  7) axis_afifo (frame mode, FRAME_FIFO=1)"; \
				echo "  8) axil_register"; \
				echo "  9) axil_gpio"; \
				echo " 10) uart_axil_slave"; \
				echo " 11) uart_axil_master"; \
				echo " 12) dma"; \
				echo " 13) cdma"; \
				echo " 14) axis_upsizer (integer k:1, IN=8 OUT=32)"; \
				echo " 15) axis_downsizer (integer 1:k, IN=32 OUT=8)"; \
				echo " 16) axis_rr_converter (rational ratio, IN=32 OUT=48)"; \
				echo " 17) axis_rr_upsizer (rational up, IN=16 OUT=24)"; \
				echo " 18) axis_rr_downsizer (rational down, IN=24 OUT=16)"; \
				echo " 19) vdma"; \
				echo " 20) multi_vdma"; \
				echo " 21) video_rgb32_pack"; \
				echo " 22) video_rgb32_unpack"; \
				echo " 23) video_rgb_to_ycbcr"; \
				echo " 24) video_ycbcr_to_rgb"; \
				echo " 25) video_csc_422"; \
				echo " 26) video_csc_422_expand"; \
				echo " 27) all"; \
				read -p "Enter choice [1-27]: " schoice; \
				echo "Synthesis target:"; \
				echo "  g) generic  -- technology-independent (default)"; \
				echo "  a) artix7   -- Xilinx 7-series (LUT6/FDRE/CARRY4 cells)"; \
				read -p "Enter target [g/a, default=g]: " starget; \
				case "$$starget" in \
					a|A|artix7) SYNTH_TARGET=artix7 ;; \
					*)           SYNTH_TARGET=generic ;; \
				esac; \
				case "$$schoice" in \
					1)  $(MAKE) synth SYNTH_NAME=axis_register      SYNTH_TARGET=$$SYNTH_TARGET ;; \
					2)  $(MAKE) synth SYNTH_NAME=uart_lite          SYNTH_TARGET=$$SYNTH_TARGET ;; \
					3)  $(MAKE) synth SYNTH_NAME=axis_arbiter       SYNTH_TARGET=$$SYNTH_TARGET ;; \
					4)  $(MAKE) synth SYNTH_NAME=axis_fifo          SYNTH_TARGET=$$SYNTH_TARGET ;; \
					5)  $(MAKE) synth SYNTH_NAME=axis_fifo_pkt      SYNTH_TARGET=$$SYNTH_TARGET ;; \
					6)  $(MAKE) synth SYNTH_NAME=axis_afifo         SYNTH_TARGET=$$SYNTH_TARGET ;; \
					7)  $(MAKE) synth SYNTH_NAME=axis_afifo_pkt     SYNTH_TARGET=$$SYNTH_TARGET ;; \
					8)  $(MAKE) synth SYNTH_NAME=axil_register      SYNTH_TARGET=$$SYNTH_TARGET ;; \
					9)  $(MAKE) synth SYNTH_NAME=axil_gpio          SYNTH_TARGET=$$SYNTH_TARGET ;; \
					10) $(MAKE) synth SYNTH_NAME=uart_axil_slave    SYNTH_TARGET=$$SYNTH_TARGET ;; \
					11) $(MAKE) synth SYNTH_NAME=uart_axil_master   SYNTH_TARGET=$$SYNTH_TARGET ;; \
					12) $(MAKE) synth SYNTH_NAME=dma                SYNTH_TARGET=$$SYNTH_TARGET ;; \
					13) $(MAKE) synth SYNTH_NAME=cdma               SYNTH_TARGET=$$SYNTH_TARGET ;; \
					14) $(MAKE) synth SYNTH_NAME=axis_upsizer       SYNTH_TARGET=$$SYNTH_TARGET ;; \
					15) $(MAKE) synth SYNTH_NAME=axis_downsizer     SYNTH_TARGET=$$SYNTH_TARGET ;; \
					16) $(MAKE) synth SYNTH_NAME=axis_rr_converter  SYNTH_TARGET=$$SYNTH_TARGET ;; \
					17) $(MAKE) synth SYNTH_NAME=axis_rr_upsizer    SYNTH_TARGET=$$SYNTH_TARGET ;; \
					18) $(MAKE) synth SYNTH_NAME=axis_rr_downsizer  SYNTH_TARGET=$$SYNTH_TARGET ;; \
					19) $(MAKE) synth SYNTH_NAME=vdma               SYNTH_TARGET=$$SYNTH_TARGET ;; \
					20) $(MAKE) synth SYNTH_NAME=multi_vdma         SYNTH_TARGET=$$SYNTH_TARGET ;; \
					21) $(MAKE) synth SYNTH_NAME=video_rgb32_pack   SYNTH_TARGET=$$SYNTH_TARGET ;; \
					22) $(MAKE) synth SYNTH_NAME=video_rgb32_unpack SYNTH_TARGET=$$SYNTH_TARGET ;; \
					23) $(MAKE) synth SYNTH_NAME=video_rgb_to_ycbcr SYNTH_TARGET=$$SYNTH_TARGET ;; \
					24) $(MAKE) synth SYNTH_NAME=video_ycbcr_to_rgb SYNTH_TARGET=$$SYNTH_TARGET ;; \
					25) $(MAKE) synth SYNTH_NAME=video_csc_422      SYNTH_TARGET=$$SYNTH_TARGET ;; \
					26) $(MAKE) synth SYNTH_NAME=video_csc_422_expand SYNTH_TARGET=$$SYNTH_TARGET ;; \
					27) $(MAKE) synth-all                           SYNTH_TARGET=$$SYNTH_TARGET ;; \
					*) echo "Invalid choice." ;; \
				esac ;; \
			h|H) $(MAKE) help ;; \
			c) $(MAKE) cleanall ;; \
			q|Q) echo "Exiting."; break ;; \
			*) echo "Invalid selection."; ;; \
		esac; \
	done

// snix_axis_downsizer.sv
//
// AXI-Stream width downsizer: splits one wide input beat into RATIO
// consecutive narrow output beats.  Beat[0] (LSBs) is output first;
// Beat[RATIO-1] (MSBs) is output last.
//
// Parameters
//   IN_DATA_WIDTH  — wide-side bus width in bits (multiple of 8)
//   OUT_DATA_WIDTH — narrow-side width; must divide IN_DATA_WIDTH evenly
//                    and the ratio must be >= 2
//
// TLAST / TKEEP
//   For non-TLAST input beats, all RATIO output beats are emitted and
//   each carries its corresponding TKEEP slice.
//   For a TLAST input beat, the module emits output beats up to the
//   highest byte lane with non-zero TKEEP; TLAST is asserted on that
//   beat.  Empty (all-zero TKEEP) trailing lanes are skipped.
//
// Flow control
//   s_axis_tready is asserted only in IDLE state.  While in BURST the
//   module cannot accept a new input beat until the current one is
//   fully transmitted downstream.

`default_nettype none

module snix_axis_downsizer #(
    parameter int IN_DATA_WIDTH  = 32,  // wide-side width in bits (multiple of 8)
    parameter int OUT_DATA_WIDTH = 8    // narrow-side width; must divide IN_DATA_WIDTH
) (
    input  wire  clk,
    input  wire  rst_n,

    // Slave — wide (IN_DATA_WIDTH bits)
    input  wire  [IN_DATA_WIDTH-1:0]    s_axis_tdata,
    input  wire  [IN_DATA_WIDTH/8-1:0]  s_axis_tkeep,
    input  wire                         s_axis_tvalid,
    output logic                        s_axis_tready,
    input  wire                         s_axis_tlast,

    // Master — narrow (OUT_DATA_WIDTH bits)
    output logic [OUT_DATA_WIDTH-1:0]   m_axis_tdata,
    output logic [OUT_DATA_WIDTH/8-1:0] m_axis_tkeep,
    output logic                        m_axis_tvalid,
    input  wire                         m_axis_tready,
    output logic                        m_axis_tlast
);

    localparam int RATIO      = IN_DATA_WIDTH  / OUT_DATA_WIDTH;
    localparam int IN_KEEP_W  = IN_DATA_WIDTH  / 8;
    localparam int OUT_KEEP_W = OUT_DATA_WIDTH / 8;
    localparam int PHASE_W    = (RATIO < 2) ? 1 : $clog2(RATIO);

    // ------------------------------------------------------------------ //
    //  FSM states                                                         //
    // ------------------------------------------------------------------ //
    typedef enum logic { IDLE = 1'b0, BURST = 1'b1 } state_t;
    state_t state;

    // ------------------------------------------------------------------ //
    //  Latched input beat                                                 //
    // ------------------------------------------------------------------ //
    logic [IN_DATA_WIDTH-1:0]  latch_data;
    logic [IN_KEEP_W-1:0]      latch_keep;
    logic                      latch_last;

    // Current output-beat index and the last valid index for this word.
    logic [PHASE_W-1:0] phase;
    logic [PHASE_W-1:0] last_phase;

    // ------------------------------------------------------------------ //
    //  Combinational output — driven directly from latched state         //
    // ------------------------------------------------------------------ //
    assign s_axis_tready = (state == IDLE);
    assign m_axis_tvalid = (state == BURST);
    assign m_axis_tdata  = latch_data[int'(phase)*OUT_DATA_WIDTH +: OUT_DATA_WIDTH];
    assign m_axis_tkeep  = latch_keep[int'(phase)*OUT_KEEP_W     +: OUT_KEEP_W    ];
    assign m_axis_tlast  = latch_last && (phase == last_phase);

    // ------------------------------------------------------------------ //
    //  Sequential logic                                                   //
    // ------------------------------------------------------------------ //
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= IDLE;
            phase      <= '0;
            last_phase <= PHASE_W'(RATIO - 1);
            latch_data <= '0;
            latch_keep <= '0;
            latch_last <= 1'b0;
        end else begin
            case (state)

                IDLE: begin
                    if (s_axis_tvalid) begin
                        latch_data <= s_axis_tdata;
                        latch_keep <= s_axis_tkeep;
                        latch_last <= s_axis_tlast;
                        phase      <= '0;

                        // Determine the last valid output beat.
                        // For non-TLAST beats all RATIO lanes are valid.
                        // For TLAST, scan to find the highest non-zero TKEEP lane.
                        if (s_axis_tlast) begin
                            last_phase <= PHASE_W'(0);
                            for (int i = 0; i < RATIO; i++) begin
                                if (s_axis_tkeep[i*OUT_KEEP_W +: OUT_KEEP_W] != '0)
                                    last_phase <= PHASE_W'(i);
                            end
                        end else begin
                            last_phase <= PHASE_W'(RATIO - 1);
                        end

                        state <= BURST;
                    end
                end

                BURST: begin
                    if (m_axis_tready) begin
                        if (phase == last_phase) begin
                            // All output beats for this word have been sent.
                            state <= IDLE;
                            phase <= '0;
                        end else begin
                            phase <= PHASE_W'(int'(phase) + 1);
                        end
                    end
                end

            endcase
        end
    end

endmodule

`default_nettype wire

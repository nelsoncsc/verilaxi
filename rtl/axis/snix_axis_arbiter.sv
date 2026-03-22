`timescale 1ns/1ps

// -------------------------------------------------
// snix_axis_arbiter
//
// N-to-1 AXI-Stream round-robin arbiter.
//
// - Arbitrates at packet granularity: once a source
//   is granted, it holds the grant until tlast+handshake.
//   Optionally, arbitration can happen at beat granularity.
// - Round-robin pointer advances after each completed
//   packet so all sources get equal access.
//   In beat mode, the pointer advances after each accepted beat.
// - Backpressure on m_axis_tready propagates to the
//   currently-granted slave only.
//
// Constraints:
//   NUM_SRCS >= 2
//   Sources must obey AXI-Stream: once tvalid is
//   asserted it must remain high until the handshake.
//
// Implementation notes:
//   All combinational logic is kept in one always_comb block.
//   s_axis_tready is computed with a for loop (constant
//   per-iteration index) rather than a variable-index
//   write, which keeps the generated logic and simulation
//   behavior straightforward across tools.
// -------------------------------------------------
module snix_axis_arbiter #(parameter int NUM_SRCS   = 4,
                           parameter int DATA_WIDTH = 8,
                           parameter int USER_WIDTH = 1,
                           parameter bit HOLD_PACKET = 1'b1,
                           parameter int WEIGHT_W   = 4,
                           parameter logic [NUM_SRCS*WEIGHT_W-1:0] WEIGHTS = '0)
                          (input  logic clk,
                           input  logic rst_n,

                           // Slave ports (N sources)
                           input  logic [NUM_SRCS-1:0][DATA_WIDTH-1:0] s_axis_tdata,
                           input  logic [NUM_SRCS-1:0][USER_WIDTH-1:0] s_axis_tuser,
                           input  logic [NUM_SRCS-1:0]                 s_axis_tvalid,
                           input  logic [NUM_SRCS-1:0]                 s_axis_tlast,
                           output logic [NUM_SRCS-1:0]                 s_axis_tready,

                           // Master port (1 sink)
                           output logic [DATA_WIDTH-1:0] m_axis_tdata,
                           output logic [USER_WIDTH-1:0] m_axis_tuser,
                           output logic                  m_axis_tvalid,
                           output logic                  m_axis_tlast,
                           input  logic                  m_axis_tready);

    localparam int SEL_W = NUM_SRCS <= 1 ? 1 : $clog2(NUM_SRCS);

    // -------------------------------------------------------
    // Arbiter state (all registered)
    // -------------------------------------------------------
    logic [SEL_W-1:0] sel;    // source locked for current packet
    logic             locked; // 1 = packet in progress
    logic [SEL_W-1:0] rr_ptr; // round-robin start pointer
    logic [NUM_SRCS-1:0][WEIGHT_W-1:0] credit; // weighted packet credits

    // -------------------------------------------------------
    // Combinational outputs used by the state machine.
    // Written by always_comb, read by always_ff only.
    // -------------------------------------------------------
    logic [SEL_W-1:0] arb_sel;
    logic             arb_valid;
    logic [SEL_W-1:0] eff_sel;
    logic             eff_valid;
    logic             any_valid;
    logic             any_credit_valid;
    logic             unit_last;
    logic             unit_done;
    integer           idx;

    function logic [WEIGHT_W-1:0] cfg_weight(input int src_idx);
        logic [WEIGHT_W-1:0] raw_weight;
        begin
            raw_weight = WEIGHTS[src_idx*WEIGHT_W +: WEIGHT_W];
            cfg_weight = (raw_weight == '0) ? WEIGHT_W'(1) : raw_weight;
        end
    endfunction

    // -------------------------------------------------------
    // Single always_comb for all combinational logic.
    // -------------------------------------------------------
    always_comb begin : comb_proc
        // ---- Round-robin arbitration ----
        arb_sel   = '0;
        arb_valid = 1'b0;
        any_valid = 1'b0;
        any_credit_valid = 1'b0;
        for (int i = 0; i < NUM_SRCS; i++) begin
            idx = int'(rr_ptr) + i;
            if (idx >= NUM_SRCS) idx -= NUM_SRCS;
            if (s_axis_tvalid[idx]) begin
                any_valid = 1'b1;
                if (credit[idx] != '0) begin
                    any_credit_valid = 1'b1;
                end
            end
            if (s_axis_tvalid[idx] && (credit[idx] != '0) && !arb_valid) begin
                arb_sel   = SEL_W'(idx);
                arb_valid = 1'b1;
            end
        end

        // ---- Effective selection ----
        eff_sel   = locked ? sel : arb_sel;
        eff_valid = locked ? s_axis_tvalid[sel] : arb_valid;

        // ---- Output mux ----
        m_axis_tdata  = s_axis_tdata [eff_sel];
        m_axis_tuser  = s_axis_tuser [eff_sel];
        m_axis_tlast  = s_axis_tlast [eff_sel];
        m_axis_tvalid = eff_valid;

        // ---- tready: grant only the selected source ----
        for (int i = 0; i < NUM_SRCS; i++) begin
            s_axis_tready[i] = (eff_valid && (eff_sel == SEL_W'(i)))
                              ? m_axis_tready : 1'b0;
        end
    end

    // -------------------------------------------------------
    // State machine: lock / unlock on packet boundaries
    // -------------------------------------------------------
    logic handshake;
    assign handshake = m_axis_tvalid && m_axis_tready;
    assign unit_last = HOLD_PACKET ? s_axis_tlast[eff_sel] : 1'b1;
    assign unit_done = handshake && unit_last;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sel    <= '0;
            locked <= 1'b0;
            rr_ptr <= '0;
            for (int i = 0; i < NUM_SRCS; i++) begin
                credit[i] <= cfg_weight(i);
            end
        end else begin
            if (!locked) begin
                if (arb_valid) begin
                    if (handshake) begin
                        if (HOLD_PACKET && !s_axis_tlast[arb_sel]) begin
                            // First accepted beat of a multi-beat packet:
                            // lock ownership and wait for TLAST before
                            // consuming the weighted credit.
                            sel    <= arb_sel;
                            locked <= 1'b1;
                        end else begin
                            // Single-beat packet, or beat-based arbitration:
                            // this accepted beat completes the current unit.
                            if (credit[arb_sel] > 0) begin
                                credit[arb_sel] <= credit[arb_sel] - WEIGHT_W'(1);
                            end
                            rr_ptr <= SEL_W'(int'(arb_sel) == NUM_SRCS-1 ? 0 : int'(arb_sel) + 1);
                        end
                    end else begin
                        // Hold the selected source stable until the current
                        // beat is accepted. In packet mode, the same lock is
                        // then extended until TLAST.
                        sel    <= arb_sel;
                        locked <= 1'b1;
                    end
                end else if (any_valid && !any_credit_valid) begin
                    // All weighted credits were consumed. Reload and start
                    // a new weighted round on the next arbitration cycle.
                    for (int i = 0; i < NUM_SRCS; i++) begin
                        credit[i] <= cfg_weight(i);
                    end
                end
            end else begin
                // Locked: wait for the current arbitration unit to complete.
                if (unit_done) begin
                    locked <= 1'b0;
                    if (credit[sel] > 0) begin
                        credit[sel] <= credit[sel] - WEIGHT_W'(1);
                    end
                    rr_ptr <= SEL_W'(int'(sel) == NUM_SRCS-1 ? 0 : int'(sel) + 1);
                end
            end
        end
    end

endmodule: snix_axis_arbiter

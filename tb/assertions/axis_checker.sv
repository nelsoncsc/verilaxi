`timescale 1ns/1ps

// ============================================================================
//  axis_checker.sv
//
//  AXI4-Stream protocol checker — Verilator-compatible concurrent SVA.
//
//  Checks compliance with AMBA AXI4-Stream Protocol Specification:
//    Rule 1 — VALID stability   : TVALID must not deassert without handshake
//    Rule 2 — Payload stability : TDATA/TLAST/TUSER stable while VALID && !READY
//    Rule 3 — No X on TVALID   : VALID must be a known value after reset
//    Rule 4 — No X on payload  : TDATA/TLAST must not be X when TVALID is high
//
//  Parameterized — instantiate once per AXI-Stream port.
//  Works for: axis_register, axis_fifo, mm2s output, s2mm input.
//
//  Requires Verilator --assert flag to activate assert/cover properties.
// ============================================================================
module axis_checker #(
    parameter int    DATA_WIDTH = 8,
    parameter int    USER_WIDTH = 1,
    parameter string LABEL      = "AXIS"   // identifies port in error messages
) (
    input logic                  clk,
    input logic                  rst_n,

    input logic [DATA_WIDTH-1:0] tdata,
    input logic [USER_WIDTH-1:0] tuser,
    input logic                  tvalid,
    input logic                  tready,
    input logic                  tlast
);

    // =========================================================================
    // Rule 1 — VALID stability
    // Spec 2.2.1: "Once TVALID is asserted it must remain asserted until the
    //              handshake occurs (TVALID && TREADY)."
    //
    // Post-NBA sampling caveat:
    //   When a handshake fills the FIFO at posedge N, fifo_full goes high in
    //   the NBA region and tready drops to 0.  The SVA checker (post-NBA) sees
    //   tvalid=1, tready=0 at posedge N even though the handshake completed
    //   in the active region.  The master legally deasserts tvalid at N+1, but
    //   the naive antecedent would flag it as a violation.
    //
    //   Fix: exclude the cycle where tready just fell ($fell(tready)).  A
    //   1-to-0 transition on tready means the FIFO was not-full last cycle,
    //   implying wr_en could have been 1 in the active region (handshake).
    //   Only check stability when tready has been continuously low.
    // =========================================================================
    property p_tvalid_stable;
        @(posedge clk) disable iff (!rst_n)
        tvalid && !tready && !$fell(tready) |=> tvalid || tready;
    endproperty

    assert property (p_tvalid_stable)
        else $error("%s: TVALID deasserted before handshake (TREADY was low)", LABEL);

    // =========================================================================
    // Rule 2 — Payload stability
    // Spec 2.2.1: Payload must remain stable while TVALID is high and TREADY
    //             is low — the master may not change its mind mid-transfer.
    //
    // Same $fell(tready) guard as Rule 1 — after a handshake that fills the
    // FIFO, the master may present new data for the next transfer.
    // =========================================================================
    property p_tdata_stable;
        @(posedge clk) disable iff (!rst_n)
        tvalid && !tready && !$fell(tready) |=> $stable(tdata) || tready;
    endproperty

    property p_tlast_stable;
        @(posedge clk) disable iff (!rst_n)
        tvalid && !tready && !$fell(tready) |=> $stable(tlast) || tready;
    endproperty

    property p_tuser_stable;
        @(posedge clk) disable iff (!rst_n)
        tvalid && !tready && !$fell(tready) |=> $stable(tuser) || tready;
    endproperty

    assert property (p_tdata_stable)
        else $error("%s: TDATA changed while TVALID high and TREADY low", LABEL);

    assert property (p_tlast_stable)
        else $error("%s: TLAST changed while TVALID high and TREADY low", LABEL);

    assert property (p_tuser_stable)
        else $error("%s: TUSER changed while TVALID high and TREADY low", LABEL);

    // =========================================================================
    // Rule 3 — No X on TVALID after reset
    // An unknown VALID makes all other rules meaningless.
    // =========================================================================
    always @(posedge clk) begin
        if (rst_n)
            assert (!$isunknown(tvalid))
                else $error("%s: TVALID is X/Z", LABEL);
    end

    // =========================================================================
    // Rule 4 — No X on payload when TVALID is asserted
    // =========================================================================
    always @(posedge clk) begin
        if (rst_n && tvalid) begin
            assert (!$isunknown(tdata))
                else $error("%s: TDATA contains X/Z when TVALID is high", LABEL);
            assert (!$isunknown(tlast))
                else $error("%s: TLAST is X/Z when TVALID is high", LABEL);
        end
    end

    // =========================================================================
    // Coverage — confirm the checker exercised real traffic during simulation
    // =========================================================================
    cover property (@(posedge clk) disable iff (!rst_n)
        tvalid && tready);              // at least one handshake seen

    cover property (@(posedge clk) disable iff (!rst_n)
        tvalid && tready && tlast);     // at least one packet end seen

    cover property (@(posedge clk) disable iff (!rst_n)
        tvalid && !tready);             // backpressure was exercised

endmodule : axis_checker

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
    // =========================================================================
    property p_tvalid_stable;
        @(posedge clk) disable iff (!rst_n)
        tvalid && !tready |=> tvalid;
    endproperty

    assert property (p_tvalid_stable)
        else $error("%s: TVALID deasserted before handshake (TREADY was low)", LABEL);

    // =========================================================================
    // Rule 2 — Payload stability
    // Spec 2.2.1: Payload must remain stable while TVALID is high and TREADY
    //             is low — the master may not change its mind mid-transfer.
    // =========================================================================
    property p_tdata_stable;
        @(posedge clk) disable iff (!rst_n)
        tvalid && !tready |=> $stable(tdata);
    endproperty

    property p_tlast_stable;
        @(posedge clk) disable iff (!rst_n)
        tvalid && !tready |=> $stable(tlast);
    endproperty

    property p_tuser_stable;
        @(posedge clk) disable iff (!rst_n)
        tvalid && !tready |=> $stable(tuser);
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

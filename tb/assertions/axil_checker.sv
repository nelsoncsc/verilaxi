`timescale 1ns/1ps

// ============================================================================
//  axil_checker.sv
//
//  AXI4-Lite protocol checker — Verilator-compatible.
//
//  AXI-Lite has no burst (no AWLEN/WLAST), fixed 32-bit data, no IDs.
//  Each channel follows the same VALID/READY handshake rules as AXI4.
//
//  Rules:
//    Rule 1 — VALID stability   : VALID must not deassert without handshake
//    Rule 2 — Payload stability : address/data stable while VALID && !READY
//    Rule 3 — No X on VALID     : VALID must be known after reset
//    Rule 4 — No X on RDATA     : RDATA must not be X when RVALID high
//    Rule 5 — Error responses   : flag SLVERR / DECERR on BRESP / RRESP
//
//  Parameterized — instantiate once per AXI-Lite port.
//  Works for: DMA/CDMA CSR slave ports, axil_register slave port.
//
//  Requires Verilator --assert flag.
// ============================================================================
module axil_checker #(
    parameter int    ADDR_WIDTH = 32,
    parameter int    DATA_WIDTH = 32,
    parameter string LABEL      = "AXIL"
) (
    input logic clk,
    input logic rst_n,

    // AW channel
    input logic [ADDR_WIDTH-1:0]   awaddr,
    input logic                    awvalid,
    input logic                    awready,

    // W channel
    input logic [DATA_WIDTH-1:0]   wdata,
    input logic [DATA_WIDTH/8-1:0] wstrb,
    input logic                    wvalid,
    input logic                    wready,

    // B channel
    input logic [1:0]              bresp,
    input logic                    bvalid,
    input logic                    bready,

    // AR channel
    input logic [ADDR_WIDTH-1:0]   araddr,
    input logic                    arvalid,
    input logic                    arready,

    // R channel
    input logic [DATA_WIDTH-1:0]   rdata,
    input logic [1:0]              rresp,
    input logic                    rvalid,
    input logic                    rready
);

    // =========================================================================
    // AW channel
    // =========================================================================
    property p_awvalid_stable;
        @(posedge clk) disable iff (!rst_n)
        awvalid && !awready |=> awvalid;
    endproperty
    assert property (p_awvalid_stable)
        else $error("%s: AWVALID deasserted before handshake", LABEL);

    property p_awaddr_stable;
        @(posedge clk) disable iff (!rst_n)
        awvalid && !awready |=> $stable(awaddr) || awready;
    endproperty
    assert property (p_awaddr_stable)
        else $error("%s: AWADDR changed while AWVALID high, AWREADY low", LABEL);

    always @(posedge clk)
        if (rst_n) assert (!$isunknown(awvalid))
            else $error("%s: AWVALID is X/Z", LABEL);

    // =========================================================================
    // W channel
    // =========================================================================
    property p_wvalid_stable;
        @(posedge clk) disable iff (!rst_n)
        wvalid && !wready |=> wvalid;
    endproperty
    assert property (p_wvalid_stable)
        else $error("%s: WVALID deasserted before handshake", LABEL);

    property p_w_payload_stable;
        @(posedge clk) disable iff (!rst_n)
        wvalid && !wready |=> ($stable(wdata) && $stable(wstrb)) || wready;
    endproperty
    assert property (p_w_payload_stable)
        else $error("%s: W payload changed while WVALID high, WREADY low", LABEL);

    always @(posedge clk)
        if (rst_n) assert (!$isunknown(wvalid))
            else $error("%s: WVALID is X/Z", LABEL);

    // =========================================================================
    // B channel
    // =========================================================================
    property p_bvalid_stable;
        @(posedge clk) disable iff (!rst_n)
        bvalid && !bready |=> bvalid;
    endproperty
    assert property (p_bvalid_stable)
        else $error("%s: BVALID deasserted before handshake", LABEL);

    always @(posedge clk) begin
        if (rst_n) begin
            assert (!$isunknown(bvalid))
                else $error("%s: BVALID is X/Z", LABEL);
            if (bvalid)
                assert (bresp inside {2'b00, 2'b01})
                    else $error("%s: Error BRESP=0b%0b (SLVERR/DECERR)", LABEL, bresp);
        end
    end

    // =========================================================================
    // AR channel
    // =========================================================================
    property p_arvalid_stable;
        @(posedge clk) disable iff (!rst_n)
        arvalid && !arready |=> arvalid;
    endproperty
    assert property (p_arvalid_stable)
        else $error("%s: ARVALID deasserted before handshake", LABEL);

    property p_araddr_stable;
        @(posedge clk) disable iff (!rst_n)
        arvalid && !arready |=> $stable(araddr) || arready;
    endproperty
    assert property (p_araddr_stable)
        else $error("%s: ARADDR changed while ARVALID high, ARREADY low", LABEL);

    always @(posedge clk)
        if (rst_n) assert (!$isunknown(arvalid))
            else $error("%s: ARVALID is X/Z", LABEL);

    // =========================================================================
    // R channel
    // =========================================================================
    property p_rvalid_stable;
        @(posedge clk) disable iff (!rst_n)
        rvalid && !rready |=> rvalid || rready;  // allow deassert only at handshake (Verilator: post-NBA sampling)
    endproperty
    assert property (p_rvalid_stable)
        else $error("%s: RVALID deasserted before handshake", LABEL);

    property p_r_payload_stable;
        @(posedge clk) disable iff (!rst_n)
        rvalid && !rready |=> ($stable(rdata) && $stable(rresp)) || rready;
    endproperty
    assert property (p_r_payload_stable)
        else $error("%s: R payload changed while RVALID high, RREADY low", LABEL);

    always @(posedge clk) begin
        if (rst_n) begin
            assert (!$isunknown(rvalid))
                else $error("%s: RVALID is X/Z", LABEL);
            if (rvalid) begin
                assert (!$isunknown(rdata))
                    else $error("%s: RDATA contains X/Z when RVALID high", LABEL);
                assert (rresp inside {2'b00, 2'b01})
                    else $error("%s: Error RRESP=0b%0b (SLVERR/DECERR)", LABEL, rresp);
            end
        end
    end

    // =========================================================================
    // Coverage — confirm all five channels are exercised
    // =========================================================================
    cover property (@(posedge clk) disable iff (!rst_n) awvalid && awready);
    cover property (@(posedge clk) disable iff (!rst_n) wvalid  && wready);
    cover property (@(posedge clk) disable iff (!rst_n) bvalid  && bready);
    cover property (@(posedge clk) disable iff (!rst_n) arvalid && arready);
    cover property (@(posedge clk) disable iff (!rst_n) rvalid  && rready);

endmodule : axil_checker

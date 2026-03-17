`timescale 1ns/1ps

// ============================================================================
//  axi_mm_checker.sv
//
//  AXI4 Memory-Mapped protocol checker — Verilator-compatible.
//
//  Per-channel rules (AW / W / B / AR / R):
//    Rule 1  — VALID stability   : VALID must not deassert without handshake
//    Rule 2  — Payload stability : address/data stable while VALID && !READY
//    Rule 3  — No X on VALID     : VALID must be a known value after reset
//    Rule 4  — No X on data      : RDATA/WDATA must not be X when VALID high
//    Rule 5  — Error responses   : flag SLVERR / DECERR on BRESP / RRESP
//
//  Cross-channel rules:
//    Rule 6  — WLAST alignment   : W burst must have exactly AWLEN+1 beats
//    Rule 7  — RLAST alignment   : R burst must have exactly ARLEN+1 beats
//
//  Parameterized — instantiate once per AXI4 master port.
//  Works for: mm2s AR/R port, s2mm AW/W/B port, mm2mm (both write + read).
//
//  Requires Verilator --assert flag.
// ============================================================================
module axi_mm_checker #(
    parameter int    ADDR_WIDTH = 32,
    parameter int    DATA_WIDTH = 64,
    parameter int    ID_WIDTH   = 4,
    parameter string LABEL      = "AXI_MM"
) (
    input logic clk,
    input logic rst_n,

    // AW channel
    input logic [ADDR_WIDTH-1:0]   awaddr,
    input logic [7:0]              awlen,
    input logic [2:0]              awsize,
    input logic [1:0]              awburst,
    input logic [ID_WIDTH-1:0]     awid,
    input logic                    awvalid,
    input logic                    awready,

    // W channel
    input logic [DATA_WIDTH-1:0]   wdata,
    input logic [DATA_WIDTH/8-1:0] wstrb,
    input logic                    wlast,
    input logic                    wvalid,
    input logic                    wready,

    // B channel
    input logic [ID_WIDTH-1:0]     bid,
    input logic [1:0]              bresp,
    input logic                    bvalid,
    input logic                    bready,

    // AR channel
    input logic [ADDR_WIDTH-1:0]   araddr,
    input logic [7:0]              arlen,
    input logic [2:0]              arsize,
    input logic [1:0]              arburst,
    input logic [ID_WIDTH-1:0]     arid,
    input logic                    arvalid,
    input logic                    arready,

    // R channel
    input logic [ID_WIDTH-1:0]     rid,
    input logic [DATA_WIDTH-1:0]   rdata,
    input logic [1:0]              rresp,
    input logic                    rlast,
    input logic                    rvalid,
    input logic                    rready
);

    // =========================================================================
    // AW channel
    // =========================================================================
    property p_awvalid_stable;
        @(posedge clk) disable iff (!rst_n)
        awvalid && !awready |=> awvalid || awready;
    endproperty
    assert property (p_awvalid_stable)
        else $error("%s: AWVALID deasserted before handshake", LABEL);

    property p_aw_payload_stable;
        @(posedge clk) disable iff (!rst_n)
        awvalid && !awready |=>
            ($stable(awaddr) && $stable(awlen) && $stable(awsize) &&
             $stable(awburst) && $stable(awid)) || awready;
    endproperty
    assert property (p_aw_payload_stable)
        else $error("%s: AW payload changed while AWVALID high, AWREADY low", LABEL);

    always @(posedge clk)
        if (rst_n) assert (!$isunknown(awvalid))
            else $error("%s: AWVALID is X/Z", LABEL);

    // =========================================================================
    // W channel
    // =========================================================================
    property p_wvalid_stable;
        @(posedge clk) disable iff (!rst_n)
        wvalid && !wready |=> wvalid || wready;
    endproperty
    assert property (p_wvalid_stable)
        else $error("%s: WVALID deasserted before handshake", LABEL);

    property p_w_payload_stable;
        @(posedge clk) disable iff (!rst_n)
        wvalid && !wready |=>
            ($stable(wdata) && $stable(wstrb) && $stable(wlast)) || wready;
    endproperty
    assert property (p_w_payload_stable)
        else $error("%s: W payload changed while WVALID high, WREADY low", LABEL);

    always @(posedge clk) begin
        if (rst_n) begin
            assert (!$isunknown(wvalid))
                else $error("%s: WVALID is X/Z", LABEL);
            if (wvalid)
                assert (!$isunknown(wdata))
                    else $error("%s: WDATA contains X/Z when WVALID high", LABEL);
        end
    end

    // =========================================================================
    // B channel
    // =========================================================================
    property p_bvalid_stable;
        @(posedge clk) disable iff (!rst_n)
        bvalid && !bready |=> bvalid || bready;
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
        arvalid && !arready |=> arvalid || arready;
    endproperty
    assert property (p_arvalid_stable)
        else $error("%s: ARVALID deasserted before handshake", LABEL);

    property p_ar_payload_stable;
        @(posedge clk) disable iff (!rst_n)
        arvalid && !arready |=>
            ($stable(araddr) && $stable(arlen) && $stable(arsize) &&
             $stable(arburst) && $stable(arid)) || arready;
    endproperty
    assert property (p_ar_payload_stable)
        else $error("%s: AR payload changed while ARVALID high, ARREADY low", LABEL);

    always @(posedge clk)
        if (rst_n) assert (!$isunknown(arvalid))
            else $error("%s: ARVALID is X/Z", LABEL);

    // =========================================================================
    // R channel
    // =========================================================================
    property p_rvalid_stable;
        @(posedge clk) disable iff (!rst_n)
        rvalid && !rready |=> rvalid || rready;
    endproperty
    assert property (p_rvalid_stable)
        else $error("%s: RVALID deasserted before handshake", LABEL);

    property p_r_payload_stable;
        @(posedge clk) disable iff (!rst_n)
        rvalid && !rready |=>
            ($stable(rdata) && $stable(rresp) && $stable(rlast) && $stable(rid)) || rready;
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
    // Rule 6 — WLAST alignment with AWLEN
    //   W burst must contain exactly AWLEN+1 beats.
    //   Uses combinatorial effective_awlen to handle the corner case where
    //   AW and WLAST handshake simultaneously (1-beat burst).
    // =========================================================================
    logic [7:0] w_beat_cnt;
    logic [7:0] aw_len_cap;
    logic       aw_w_pending;

    logic [7:0] eff_awlen;
    assign eff_awlen = (awvalid && awready) ? awlen : aw_len_cap;

    always @(posedge clk) begin
        if (!rst_n) begin
            w_beat_cnt   <= '0;
            aw_len_cap   <= '0;
            aw_w_pending <= 1'b0;
        end else begin
            if (awvalid && awready) begin
                aw_len_cap <= awlen;
                if (!(wvalid && wready && wlast))   // set pending unless WLAST same cycle
                    aw_w_pending <= 1'b1;
            end
            if (wvalid && wready) begin
                if (wlast) begin
                    if (aw_w_pending || (awvalid && awready))
                        assert (w_beat_cnt == eff_awlen)
                            else $error("%s: WLAST at beat %0d, AWLEN=%0d (expected %0d beats)",
                                        LABEL, w_beat_cnt, eff_awlen, eff_awlen + 8'd1);
                    w_beat_cnt   <= '0;
                    aw_w_pending <= 1'b0;
                end else begin
                    w_beat_cnt <= w_beat_cnt + 8'd1;
                end
            end
        end
    end

    // =========================================================================
    // Rule 7 — RLAST alignment with ARLEN
    //   R burst must contain exactly ARLEN+1 beats.
    // =========================================================================
    logic [7:0] r_beat_cnt;
    logic [7:0] ar_len_cap;

    always @(posedge clk) begin
        if (!rst_n) begin
            r_beat_cnt <= '0;
            ar_len_cap <= '0;
        end else begin
            if (arvalid && arready)
                ar_len_cap <= arlen;
            if (rvalid && rready) begin
                if (rlast) begin
                    assert (r_beat_cnt == ar_len_cap)
                        else $error("%s: RLAST at beat %0d, ARLEN=%0d (expected %0d beats)",
                                    LABEL, r_beat_cnt, ar_len_cap, ar_len_cap + 8'd1);
                    r_beat_cnt <= '0;
                end else begin
                    r_beat_cnt <= r_beat_cnt + 8'd1;
                end
            end
        end
    end

    // =========================================================================
    // Coverage
    // =========================================================================
    cover property (@(posedge clk) disable iff (!rst_n) awvalid && awready);
    cover property (@(posedge clk) disable iff (!rst_n) wvalid  && wready && wlast);
    cover property (@(posedge clk) disable iff (!rst_n) bvalid  && bready);
    cover property (@(posedge clk) disable iff (!rst_n) arvalid && arready);
    cover property (@(posedge clk) disable iff (!rst_n) rvalid  && rready && rlast);

endmodule : axi_mm_checker

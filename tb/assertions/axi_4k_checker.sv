`timescale 1ns/1ps

// ============================================================================
//  axi_4k_checker.sv
//
//  Checks that issued AXI4 INCR bursts do not cross a 4KB boundary.
//  Intended to complement axi_mm_checker with a focused address-window rule.
// ============================================================================
module axi_4k_checker #(
    parameter int    ADDR_WIDTH = 32,
    parameter string LABEL      = "AXI_4K"
) (
    input logic clk,
    input logic rst_n,

    input logic [ADDR_WIDTH-1:0] awaddr,
    input logic [7:0]            awlen,
    input logic [2:0]            awsize,
    input logic                  awvalid,
    input logic                  awready,

    input logic [ADDR_WIDTH-1:0] araddr,
    input logic [7:0]            arlen,
    input logic [2:0]            arsize,
    input logic                  arvalid,
    input logic                  arready
);

    function automatic [15:0] burst_bytes(
        input logic [7:0] len,
        input logic [2:0] size
    );
        burst_bytes = ({8'b0, len} + 16'd1) << size;
    endfunction

    property p_aw_no_4k_cross;
        @(posedge clk) disable iff (!rst_n)
        awvalid && awready |->
            ({4'b0, awaddr[11:0]} + burst_bytes(awlen, awsize)) <= 16'd4096;
    endproperty
    assert property (p_aw_no_4k_cross)
        else $error("%s: AW burst crosses 4KB boundary addr=0x%0h len=%0d size=%0d bytes=%0d",
                    LABEL, awaddr, awlen, awsize, burst_bytes(awlen, awsize));

    property p_ar_no_4k_cross;
        @(posedge clk) disable iff (!rst_n)
        arvalid && arready |->
            ({4'b0, araddr[11:0]} + burst_bytes(arlen, arsize)) <= 16'd4096;
    endproperty
    assert property (p_ar_no_4k_cross)
        else $error("%s: AR burst crosses 4KB boundary addr=0x%0h len=%0d size=%0d bytes=%0d",
                    LABEL, araddr, arlen, arsize, burst_bytes(arlen, arsize));

endmodule : axi_4k_checker

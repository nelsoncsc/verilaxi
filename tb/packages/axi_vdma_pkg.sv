`timescale 1ns/1ps

package axi_vdma_pkg;

    /* verilator lint_off UNUSEDPARAM */
    localparam int VDMA_WR_CTRL   = 32'h00;
    localparam int VDMA_WR_ADDR   = 32'h04;
    localparam int VDMA_WR_STRIDE = 32'h08;
    localparam int VDMA_RD_CTRL   = 32'h0c;
    localparam int VDMA_RD_ADDR   = 32'h10;
    localparam int VDMA_RD_STRIDE = 32'h14;
    localparam int VDMA_STATUS    = 32'h18;
    localparam int VDMA_WR_HSIZE  = 32'h1c;
    localparam int VDMA_WR_VSIZE  = 32'h20;
    localparam int VDMA_RD_HSIZE  = 32'h24;
    localparam int VDMA_RD_VSIZE  = 32'h28;
    localparam int VDMA_FRAME_ADDR0 = 32'h2c;
    localparam int VDMA_FRAME_ADDR1 = 32'h30;
    localparam int VDMA_FRAME_ADDR2 = 32'h34;
    localparam int VDMA_FRAME_CTRL  = 32'h38;
    localparam int VDMA_IRQ_ACK     = 32'h3c;
    /* verilator lint_on UNUSEDPARAM */

    function automatic logic [31:0] vdma_ctrl_word(
        input logic       start,
        input logic       stop,
        input logic [2:0] beat_size,
        input logic [7:0] burst_len
    );
        logic [31:0] value;
        value       = '0;
        value[0]    = start;
        value[1]    = stop;
        value[5:3]  = beat_size;
        value[13:6] = burst_len;
        return value;
    endfunction

    function automatic logic [31:0] vdma_frame_ctrl_word(
        input logic       enable,
        input logic       park_mode,
        input logic [1:0] park_slot,
        input logic       wr_irq_enable,
        input logic       rd_irq_enable,
        input logic       error_irq_enable,
        input logic       irq_clear
    );
        logic [31:0] value;
        value       = '0;
        value[0]    = enable;
        value[1]    = park_mode;
        value[3:2]  = park_slot;
        value[8]    = wr_irq_enable;
        value[9]    = rd_irq_enable;
        value[10]   = error_irq_enable;
        value[16]   = irq_clear;
        return value;
    endfunction

    function automatic logic [31:0] vdma_frame_policy_word(
        input logic       enable,
        input logic       park_mode,
        input logic [1:0] park_slot,
        input logic       genlock_enable,
        input logic [1:0] frame_delay,
        input logic       wr_irq_enable,
        input logic       rd_irq_enable,
        input logic       error_irq_enable,
        input logic       irq_clear
    );
        logic [31:0] value;
        value = vdma_frame_ctrl_word(enable, park_mode, park_slot,
                                     wr_irq_enable, rd_irq_enable,
                                     error_irq_enable, irq_clear);
        value[4]   = genlock_enable;
        value[6:5] = frame_delay;
        return value;
    endfunction

    function automatic logic [31:0] vdma_irq_ack_word(
        input logic clear_irq,
        input logic clear_faults,
        input logic clear_telemetry
    );
        logic [31:0] value;
        value    = '0;
        value[0] = clear_irq;
        value[1] = clear_faults;
        value[2] = clear_telemetry;
        return value;
    endfunction

endpackage : axi_vdma_pkg

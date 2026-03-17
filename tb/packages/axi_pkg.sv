`timescale 1ns / 1ps
package axi_pkg;
    `include "macros/axi_macros.sv"

    `include "classes/axi/axi_master.sv"
    `include "classes/axi/axi_slave.sv"
    `include "classes/axi/axi_driver.sv"

    `include "classes/axil/axil_master.sv"
    `include "classes/axil/axil_slave.sv"
    `include "classes/axil/axil_driver.sv"
    
    `include "classes/axis/axis_source.sv"
    `include "classes/axis/axis_sink.sv"
    `include "classes/axis/axis_connect.sv"
    `include "classes/axis/axis_driver.sv"

endpackage: axi_pkg
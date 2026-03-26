`timescale 1ns / 1ps

module test_uart_axil_slave #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
) (
    input logic clk,
    input logic rst_n
);
    import axi_pkg::*;

    axil_if #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) axil_if_t (
        .ACLK   (clk),
        .ARESETn(rst_n)
    ),
    axil_if_s (
        .ACLK   (clk),
        .ARESETn(rst_n)
    );

    logic uart_rx;
    logic uart_tx;
    logic [31:0] rd_data;
    int timeout_ctr;

    assign uart_rx = uart_tx;

    snix_uart_axil_slave #(
        .DATA_WIDTH (DATA_WIDTH),
        .ADDR_WIDTH (4),
        .CLK_FREQ_HZ(10_000_000),
        .BAUD_RATE  (1_000_000),
        .FIFO_DEPTH (8)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .uart_rx      (uart_rx),
        .uart_tx      (uart_tx),
        .s_axil_awaddr(axil_if_t.awaddr[3:0]),
        .s_axil_awvalid(axil_if_t.awvalid),
        .s_axil_awready(axil_if_t.awready),
        .s_axil_wdata (axil_if_t.wdata),
        .s_axil_wstrb (axil_if_t.wstrb),
        .s_axil_wvalid(axil_if_t.wvalid),
        .s_axil_wready(axil_if_t.wready),
        .s_axil_bresp (axil_if_t.bresp),
        .s_axil_bvalid(axil_if_t.bvalid),
        .s_axil_bready(axil_if_t.bready),
        .s_axil_araddr(axil_if_t.araddr[3:0]),
        .s_axil_arvalid(axil_if_t.arvalid),
        .s_axil_arready(axil_if_t.arready),
        .s_axil_rdata (axil_if_t.rdata),
        .s_axil_rresp (axil_if_t.rresp),
        .s_axil_rvalid(axil_if_t.rvalid),
        .s_axil_rready(axil_if_t.rready)
    );

    sample_axil_if #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) sample_axil_if_u0 (
        .axil_if_t(axil_if_t),
        .axil_if_s(axil_if_s)
    );

    axil_checker #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .LABEL("UART_AXIL_SLV")
    ) u_axil_chk (
        .clk    (clk),
        .rst_n  (rst_n),
        .awaddr (axil_if_t.awaddr),
        .awvalid(axil_if_t.awvalid),
        .awready(axil_if_t.awready),
        .wdata  (axil_if_t.wdata),
        .wstrb  (axil_if_t.wstrb),
        .wvalid (axil_if_t.wvalid),
        .wready (axil_if_t.wready),
        .bresp  (axil_if_t.bresp),
        .bvalid (axil_if_t.bvalid),
        .bready (axil_if_t.bready),
        .araddr (axil_if_t.araddr),
        .arvalid(axil_if_t.arvalid),
        .arready(axil_if_t.arready),
        .rdata  (axil_if_t.rdata),
        .rresp  (axil_if_t.rresp),
        .rvalid (axil_if_t.rvalid),
        .rready (axil_if_t.rready)
    );

    axil_master #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) m;

    initial begin
        axil_if_t.init();
        m = new(axil_if_t);
        m.reset();

        wait (rst_n == 1'b1);
        repeat (4) @(posedge clk);

        m.write(32'h0, 32'h00000055);
        m.write(32'h0, 32'h000000A3);

        timeout_ctr = 0;
        while (timeout_ctr < 2000) begin
            m.read(32'h4, rd_data);
            if (rd_data[1]) begin
                break;
            end
            timeout_ctr += 1;
            @(posedge clk);
        end

        if (!rd_data[1]) begin
            $fatal(1, "test_uart_axil_slave: timeout waiting for RX valid");
        end

        m.read(32'h0, rd_data);
        if (rd_data[7:0] !== 8'h55) begin
            $fatal(1, "test_uart_axil_slave: expected first byte 0x55 got 0x%02x", rd_data[7:0]);
        end
        $display("[UART-AXIL][RD ] data=0x%02x", rd_data[7:0]);

        timeout_ctr = 0;
        do begin
            m.read(32'h4, rd_data);
            timeout_ctr += 1;
            if (timeout_ctr > 2000) begin
                $fatal(1, "test_uart_axil_slave: timeout waiting for second RX byte");
            end
            @(posedge clk);
        end while (!rd_data[1]);

        m.read(32'h0, rd_data);
        if (rd_data[7:0] !== 8'hA3) begin
            $fatal(1, "test_uart_axil_slave: expected second byte 0xA3 got 0x%02x", rd_data[7:0]);
        end
        $display("[UART-AXIL][RD ] data=0x%02x", rd_data[7:0]);

        m.read(32'h4, rd_data);
        if (rd_data[1] !== 1'b0) begin
            $fatal(1, "test_uart_axil_slave: expected RX FIFO empty after reads");
        end

        $display("test_uart_axil_slave: PASS");
        #20 $finish;
    end

    initial begin
        #1000000 $fatal("test_uart_axil_slave: Simulation timed out");
    end

endmodule : test_uart_axil_slave

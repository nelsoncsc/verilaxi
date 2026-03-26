`timescale 1ns / 1ps

module test_uart_axil_master #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
) (
    input logic clk,
    input logic rst_n
);
    import axi_pkg::*;

    logic host_to_dut;
    logic dut_to_host;

    logic [7:0] host_tx_data;
    logic       host_tx_valid;
    logic       host_tx_ready;
    logic [7:0] host_rx_data;
    logic       host_rx_valid;
    logic       host_rx_ready;
    logic       host_tx_busy;
    logic       host_rx_busy;
    byte        host_rx_q[$];

    axil_if #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) axil_if_t (
        .ACLK   (clk),
        .ARESETn(rst_n)
    );

    axil_slave #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .MEM_DEPTH (1024)
    ) s;

    snix_uart_lite #(
        .CLK_FREQ_HZ(10_000_000),
        .BAUD_RATE  (1_000_000),
        .FIFO_DEPTH (8)
    ) host_uart_u0 (
        .clk     (clk),
        .rst_n   (rst_n),
        .uart_rx (dut_to_host),
        .uart_tx (host_to_dut),
        .tx_data (host_tx_data),
        .tx_valid(host_tx_valid),
        .tx_ready(host_tx_ready),
        .rx_data (host_rx_data),
        .rx_valid(host_rx_valid),
        .rx_ready(host_rx_ready),
        .tx_busy (host_tx_busy),
        .rx_busy (host_rx_busy)
    );

    snix_uart_axil_master #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .CLK_FREQ_HZ(10_000_000),
        .BAUD_RATE  (1_000_000),
        .FIFO_DEPTH (8)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),
        .uart_rx      (host_to_dut),
        .uart_tx      (dut_to_host),
        .m_axil_awaddr(axil_if_t.awaddr),
        .m_axil_awvalid(axil_if_t.awvalid),
        .m_axil_awready(axil_if_t.awready),
        .m_axil_wdata (axil_if_t.wdata),
        .m_axil_wstrb (axil_if_t.wstrb),
        .m_axil_wvalid(axil_if_t.wvalid),
        .m_axil_wready(axil_if_t.wready),
        .m_axil_bresp (axil_if_t.bresp),
        .m_axil_bvalid(axil_if_t.bvalid),
        .m_axil_bready(axil_if_t.bready),
        .m_axil_araddr(axil_if_t.araddr),
        .m_axil_arvalid(axil_if_t.arvalid),
        .m_axil_arready(axil_if_t.arready),
        .m_axil_rdata (axil_if_t.rdata),
        .m_axil_rresp (axil_if_t.rresp),
        .m_axil_rvalid(axil_if_t.rvalid),
        .m_axil_rready(axil_if_t.rready)
    );

    task automatic host_send_byte(input byte value);
        begin
            @(posedge clk);
            while (!host_tx_ready) @(posedge clk);
            host_tx_data  = value;
            host_tx_valid = 1'b1;
            @(posedge clk);
            host_tx_valid = 1'b0;
        end
    endtask

    task automatic host_send_string(input string text);
        int i;
        begin
            for (i = 0; i < text.len(); i++) begin
                host_send_byte(text[i]);
            end
        end
    endtask

    task automatic host_expect_string(input string text);
        int i;
        begin
            for (i = 0; i < text.len(); i++) begin
                while (host_rx_q.size() == 0) @(posedge clk);
                if (host_rx_q[0] !== text[i]) begin
                    $fatal(1, "test_uart_axil_master: response mismatch at index %0d expected='%s' got=0x%02x",
                           i, text[i], host_rx_q[0]);
                end
                $display("[UART-AXIL-M][RX ] idx=%0d char=0x%02x", i, host_rx_q[0]);
                host_rx_q.pop_front();
            end
        end
    endtask

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            host_rx_ready <= 1'b1;
        end else begin
            host_rx_ready <= 1'b1;
            if (host_rx_valid && host_rx_ready) begin
                host_rx_q.push_back(host_rx_data);
            end
        end
    end

    initial begin
        axil_if_t.init();
        s = new(axil_if_t);
        s.reset();

        host_tx_data  = '0;
        host_tx_valid = 1'b0;
        host_rx_ready = 1'b1;

        fork
            s.run();
        join_none

        wait (rst_n == 1'b1);
        repeat (4) @(posedge clk);

        host_send_string("W 00000010 DEADBEEF\n");
        host_expect_string("OK\n");

        host_send_string("R 00000010\n");
        host_expect_string("D 00000010 DEADBEEF\n");

        host_send_string("X 00000000\n");
        host_expect_string("ERR\n");

        $display("test_uart_axil_master: PASS");
        #20 $finish;
    end

    initial begin
        #2000000 $fatal("test_uart_axil_master: Simulation timed out");
    end

endmodule : test_uart_axil_master

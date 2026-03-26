`timescale 1ns / 1ps

module test_uart_lite (
    input logic clk,
    input logic rst_n
);

    localparam int CLK_FREQ_HZ = 10_000_000;
    localparam int BAUD_RATE   = 1_000_000;
    localparam int FIFO_DEPTH  = 8;
    localparam int CLKS_PER_BIT = CLK_FREQ_HZ / BAUD_RATE;

    logic       uart_rx;
    logic       uart_tx;
    logic [7:0] tx_data;
    logic       tx_valid;
    logic       tx_ready;
    logic [7:0] rx_data;
    logic       rx_valid;
    logic       rx_ready;
    logic       tx_busy;
    logic       rx_busy;

    byte expected_q[$];
    int  tx_count;
    int  rx_count;

    assign uart_rx = uart_tx;

    snix_uart_lite #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE  (BAUD_RATE),
        .FIFO_DEPTH (FIFO_DEPTH)
    ) dut (
        .clk    (clk),
        .rst_n  (rst_n),
        .uart_rx(uart_rx),
        .uart_tx(uart_tx),
        .tx_data(tx_data),
        .tx_valid(tx_valid),
        .tx_ready(tx_ready),
        .rx_data(rx_data),
        .rx_valid(rx_valid),
        .rx_ready(rx_ready),
        .tx_busy(tx_busy),
        .rx_busy(rx_busy)
    );

    task automatic send_byte(input byte value);
        begin
            expected_q.push_back(value);
            @(posedge clk);
            while (!tx_ready) @(posedge clk);
            tx_data  = value;
            tx_valid = 1'b1;
            $display("[UART][TX ] byte %0d data=0x%02x", tx_count, value);
            tx_count = tx_count + 1;
            @(posedge clk);
            tx_valid = 1'b0;
        end
    endtask

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_ready <= 1'b1;
            tx_count <= 0;
            rx_count <= 0;
        end else begin
            rx_ready <= 1'b1;
            if (rx_valid && rx_ready) begin
                if (expected_q.size() == 0) begin
                    $fatal(1, "test_uart_lite: unexpected RX byte 0x%02x", rx_data);
                end

                if (rx_data !== expected_q[0]) begin
                    $fatal(1, "test_uart_lite: RX mismatch. expected=0x%02x got=0x%02x", expected_q[0], rx_data);
                end

                $display("[UART][RX ] byte %0d data=0x%02x", rx_count, rx_data);
                expected_q.pop_front();
                rx_count <= rx_count + 1;
            end
        end
    end

    initial begin
        tx_data  = '0;
        tx_valid = 1'b0;
        rx_ready = 1'b1;

        wait (rst_n == 1'b1);
        repeat (4) @(posedge clk);

        send_byte(8'h55);
        send_byte(8'hA3);
        send_byte(8'h00);
        send_byte(8'hFF);

        wait (expected_q.size() == 0);
        repeat ((12 * CLKS_PER_BIT) + 10) @(posedge clk);

        if (tx_busy || rx_busy) begin
            $fatal(1, "test_uart_lite: UART remained busy after traffic drained");
        end

        $display("test_uart_lite: PASS (%0d bytes looped back)", rx_count);
        #20 $finish;
    end

    initial begin
        #1000000 $fatal("test_uart_lite: Simulation timed out");
    end

endmodule : test_uart_lite

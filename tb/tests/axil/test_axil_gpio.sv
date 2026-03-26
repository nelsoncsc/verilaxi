`timescale 1ns / 1ps

module test_axil_gpio #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
) (
    input logic clk,
    input logic rst_n
);
    import axi_pkg::*;

    localparam logic [ADDR_WIDTH-1:0] GPIO_OUT_ADDR = 32'h0;
    localparam logic [ADDR_WIDTH-1:0] GPIO_IN_ADDR  = 32'h4;
    localparam logic [ADDR_WIDTH-1:0] BTN_EDGE_ADDR = 32'h8;
    localparam logic [ADDR_WIDTH-1:0] RGB0_ADDR     = 32'hC;
    localparam logic [ADDR_WIDTH-1:0] RGB1_ADDR     = 32'h10;

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

    logic [3:0]  gpio_sw;
    logic [1:0]  gpio_btn;
    logic [3:0]  gpio_led;
    logic [5:0]  gpio_rgb;
    logic [31:0] rd_data;

    axil_master #(
        .ADDR_WIDTH(ADDR_WIDTH),
        .DATA_WIDTH(DATA_WIDTH)
    ) m;

    snix_axil_gpio #(
        .DATA_WIDTH      (DATA_WIDTH),
        .ADDR_WIDTH      (ADDR_WIDTH),
        .NUM_LEDS        (4),
        .NUM_RGB_LEDS    (2),
        .NUM_SWITCHES    (4),
        .NUM_BUTTONS     (2),
        .DEBOUNCE_CYCLES (4)
    ) dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .s_axil_awaddr (axil_if_t.awaddr),
        .s_axil_awvalid(axil_if_t.awvalid),
        .s_axil_awready(axil_if_t.awready),
        .s_axil_wdata  (axil_if_t.wdata),
        .s_axil_wstrb  (axil_if_t.wstrb),
        .s_axil_wvalid (axil_if_t.wvalid),
        .s_axil_wready (axil_if_t.wready),
        .s_axil_bresp  (axil_if_t.bresp),
        .s_axil_bvalid (axil_if_t.bvalid),
        .s_axil_bready (axil_if_t.bready),
        .s_axil_araddr (axil_if_t.araddr),
        .s_axil_arvalid(axil_if_t.arvalid),
        .s_axil_arready(axil_if_t.arready),
        .s_axil_rdata  (axil_if_t.rdata),
        .s_axil_rresp  (axil_if_t.rresp),
        .s_axil_rvalid (axil_if_t.rvalid),
        .s_axil_rready (axil_if_t.rready),
        .gpio_sw       (gpio_sw),
        .gpio_btn      (gpio_btn),
        .gpio_led      (gpio_led),
        .gpio_rgb      (gpio_rgb)
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
        .LABEL("AXIL_GPIO")
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

    task automatic wait_cycles(input int count);
        begin
            repeat (count) @(posedge clk);
        end
    endtask

    initial begin
        axil_if_t.init();
        m = new(axil_if_t);
        m.reset();

        gpio_sw  = '0;
        gpio_btn = '0;

        wait (rst_n == 1'b1);
        wait_cycles(4);

        m.write(GPIO_OUT_ADDR, 32'h0000_000A);
        wait_cycles(1);
        if (gpio_led !== 4'b1010) begin
            $fatal(1, "test_axil_gpio: expected LED state 0xA got 0x%0h", gpio_led);
        end
        $display("[AXIL-GPIO][LED ] gpio_led=0x%0h", gpio_led);

        m.write(RGB0_ADDR, 32'h0000_0005);
        m.write(RGB1_ADDR, 32'h0000_0003);
        wait_cycles(1);
        if (gpio_rgb[2:0] !== 3'b101) begin
            $fatal(1, "test_axil_gpio: expected RGB0 state 0x5 got 0x%0h", gpio_rgb[2:0]);
        end
        if (gpio_rgb[5:3] !== 3'b011) begin
            $fatal(1, "test_axil_gpio: expected RGB1 state 0x3 got 0x%0h", gpio_rgb[5:3]);
        end
        $display("[AXIL-GPIO][RGB ] rgb0=0x%0h rgb1=0x%0h", gpio_rgb[2:0], gpio_rgb[5:3]);

        m.read(RGB0_ADDR, rd_data);
        if (rd_data[2:0] !== 3'b101) begin
            $fatal(1, "test_axil_gpio: expected RGB0 readback 0x5 got 0x%0h", rd_data[2:0]);
        end
        m.read(RGB1_ADDR, rd_data);
        if (rd_data[2:0] !== 3'b011) begin
            $fatal(1, "test_axil_gpio: expected RGB1 readback 0x3 got 0x%0h", rd_data[2:0]);
        end

        gpio_sw = 4'b0101;
        wait_cycles(3);
        m.read(GPIO_IN_ADDR, rd_data);
        if (rd_data[3:0] !== 4'b0101) begin
            $fatal(1, "test_axil_gpio: expected switches 0x5 got 0x%0h", rd_data[3:0]);
        end
        if (rd_data[5:4] !== 2'b00) begin
            $fatal(1, "test_axil_gpio: expected buttons low got 0x%0h", rd_data[5:4]);
        end
        $display("[AXIL-GPIO][IN  ] gpio_in=0x%08x", rd_data);

        gpio_btn[0] = 1'b1;
        wait_cycles(1);
        gpio_btn[0] = 1'b0;
        wait_cycles(1);
        gpio_btn[0] = 1'b1;
        wait_cycles(8);

        m.read(GPIO_IN_ADDR, rd_data);
        if (rd_data[4] !== 1'b1) begin
            $fatal(1, "test_axil_gpio: debounced button 0 did not assert");
        end

        m.read(BTN_EDGE_ADDR, rd_data);
        if (rd_data[1:0] !== 2'b01) begin
            $fatal(1, "test_axil_gpio: expected sticky button edge 0x1 got 0x%0h", rd_data[1:0]);
        end
        $display("[AXIL-GPIO][EDGE] btn_edge=0x%0h", rd_data[1:0]);

        m.write(BTN_EDGE_ADDR, 32'h0000_0001);
        wait_cycles(1);
        m.read(BTN_EDGE_ADDR, rd_data);
        if (rd_data[1:0] !== 2'b00) begin
            $fatal(1, "test_axil_gpio: expected edge clear got 0x%0h", rd_data[1:0]);
        end

        $display("test_axil_gpio: PASS");
        #20 $finish;
    end

    initial begin
        #1000000 $fatal("test_axil_gpio: Simulation timed out");
    end

endmodule : test_axil_gpio

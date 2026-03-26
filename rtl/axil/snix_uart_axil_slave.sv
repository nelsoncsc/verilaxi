// ============================================================================
//  snix_uart_axil_slave.sv
//
//  AXI-Lite UART peripheral backed by snix_uart_lite.
//
//  Register map:
//    0x00 DATA    W: enqueue TX byte in [7:0]
//                 R: dequeue RX byte from [7:0] when available
//    0x04 STATUS  [0] tx_ready
//                 [1] rx_valid
//                 [2] tx_busy
//                 [3] rx_busy
// ============================================================================
module snix_uart_axil_slave #(
    parameter int DATA_WIDTH  = 32,
    parameter int ADDR_WIDTH  = 4,
    parameter int CLK_FREQ_HZ = 100_000_000,
    parameter int BAUD_RATE   = 115_200,
    parameter int FIFO_DEPTH  = 8
) (
    input  logic                    clk,
    input  logic                    rst_n,

    input  logic                    uart_rx,
    output logic                    uart_tx,

    input  logic [ADDR_WIDTH-1:0]   s_axil_awaddr,
    input  logic                    s_axil_awvalid,
    output logic                    s_axil_awready,

    input  logic [DATA_WIDTH-1:0]   s_axil_wdata,
    input  logic [DATA_WIDTH/8-1:0] s_axil_wstrb,
    input  logic                    s_axil_wvalid,
    output logic                    s_axil_wready,

    output logic [1:0]              s_axil_bresp,
    output logic                    s_axil_bvalid,
    input  logic                    s_axil_bready,

    input  logic [ADDR_WIDTH-1:0]   s_axil_araddr,
    input  logic                    s_axil_arvalid,
    output logic                    s_axil_arready,

    output logic [DATA_WIDTH-1:0]   s_axil_rdata,
    output logic [1:0]              s_axil_rresp,
    output logic                    s_axil_rvalid,
    input  logic                    s_axil_rready
);

    localparam int ADDRLSB = $clog2(DATA_WIDTH/8);
    localparam int REG_INDEX_WIDTH = (ADDR_WIDTH > ADDRLSB) ? (ADDR_WIDTH - ADDRLSB) : 1;
    localparam logic [REG_INDEX_WIDTH-1:0] DATA_REG_IDX   = '0;
    localparam logic [REG_INDEX_WIDTH-1:0] STATUS_REG_IDX = 'd1;

    logic [ADDR_WIDTH-ADDRLSB-1:0] awaddr_reg;
    logic                          awvalid_reg;
    logic [DATA_WIDTH-1:0]         wdata_reg;
    logic [DATA_WIDTH/8-1:0]       wstrb_reg;
    logic                          wvalid_reg;
    logic [ADDR_WIDTH-ADDRLSB-1:0] araddr_reg;
    logic                          arvalid_reg;

    logic [7:0]                    uart_tx_data;
    logic                          uart_tx_valid;
    logic                          uart_tx_ready;
    logic [7:0]                    uart_rx_data;
    logic                          uart_rx_valid;
    logic                          uart_rx_ready;
    logic                          uart_tx_busy;
    logic                          uart_rx_busy;

    logic                          write_ready;
    logic                          read_ready;
    logic                          write_is_data;
    logic                          read_is_data;

    assign write_is_data = (awaddr_reg[REG_INDEX_WIDTH-1:0] == DATA_REG_IDX);
    assign read_is_data  = (araddr_reg[REG_INDEX_WIDTH-1:0] == DATA_REG_IDX);

    assign write_ready   = awvalid_reg & wvalid_reg & (~s_axil_bvalid | s_axil_bready) &
                           (~write_is_data | uart_tx_ready);
    assign read_ready    = arvalid_reg & (~s_axil_rvalid | s_axil_rready);

    assign uart_tx_data  = wdata_reg[7:0];
    assign uart_tx_valid = write_ready & write_is_data & wstrb_reg[0];
    assign uart_rx_ready = read_ready & read_is_data & uart_rx_valid;

    snix_register_slice #(
        .DATA_WIDTH(ADDR_WIDTH-ADDRLSB)
    ) aw_slice_u0 (
        .clk         (clk),
        .rst_n       (rst_n),
        .s_axis_tdata(s_axil_awaddr[ADDR_WIDTH-1:ADDRLSB]),
        .s_axis_tvalid(s_axil_awvalid),
        .s_axis_tready(s_axil_awready),
        .m_axis_tdata(awaddr_reg),
        .m_axis_tvalid(awvalid_reg),
        .m_axis_tready(write_ready)
    );

    snix_register_slice #(
        .DATA_WIDTH(DATA_WIDTH + DATA_WIDTH/8)
    ) w_slice_u0 (
        .clk         (clk),
        .rst_n       (rst_n),
        .s_axis_tdata({s_axil_wdata, s_axil_wstrb}),
        .s_axis_tvalid(s_axil_wvalid),
        .s_axis_tready(s_axil_wready),
        .m_axis_tdata({wdata_reg, wstrb_reg}),
        .m_axis_tvalid(wvalid_reg),
        .m_axis_tready(write_ready)
    );

    snix_register_slice #(
        .DATA_WIDTH(ADDR_WIDTH-ADDRLSB)
    ) ar_slice_u0 (
        .clk         (clk),
        .rst_n       (rst_n),
        .s_axis_tdata(s_axil_araddr[ADDR_WIDTH-1:ADDRLSB]),
        .s_axis_tvalid(s_axil_arvalid),
        .s_axis_tready(s_axil_arready),
        .m_axis_tdata(araddr_reg),
        .m_axis_tvalid(arvalid_reg),
        .m_axis_tready(read_ready)
    );

    snix_uart_lite #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .BAUD_RATE  (BAUD_RATE),
        .FIFO_DEPTH (FIFO_DEPTH)
    ) uart_lite_u0 (
        .clk     (clk),
        .rst_n   (rst_n),
        .uart_rx (uart_rx),
        .uart_tx (uart_tx),
        .tx_data (uart_tx_data),
        .tx_valid(uart_tx_valid),
        .tx_ready(uart_tx_ready),
        .rx_data (uart_rx_data),
        .rx_valid(uart_rx_valid),
        .rx_ready(uart_rx_ready),
        .tx_busy (uart_tx_busy),
        .rx_busy (uart_rx_busy)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axil_bvalid <= 1'b0;
        end else if (write_ready) begin
            s_axil_bvalid <= 1'b1;
        end else if (s_axil_bready) begin
            s_axil_bvalid <= 1'b0;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axil_rvalid <= 1'b0;
        end else if (read_ready) begin
            s_axil_rvalid <= 1'b1;
        end else if (s_axil_rready) begin
            s_axil_rvalid <= 1'b0;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axil_rdata <= '0;
        end else if (read_ready) begin
            s_axil_rdata <= '0;
            if (read_is_data) begin
                s_axil_rdata[7:0] <= uart_rx_valid ? uart_rx_data : 8'h00;
            end else if (araddr_reg[REG_INDEX_WIDTH-1:0] == STATUS_REG_IDX) begin
                s_axil_rdata[0] <= uart_tx_ready;
                s_axil_rdata[1] <= uart_rx_valid;
                s_axil_rdata[2] <= uart_tx_busy;
                s_axil_rdata[3] <= uart_rx_busy;
            end
        end
    end

    assign s_axil_bresp = 2'b00;
    assign s_axil_rresp = 2'b00;

endmodule : snix_uart_axil_slave

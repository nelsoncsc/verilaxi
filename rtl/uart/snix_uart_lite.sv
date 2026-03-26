// ============================================================================
//  snix_uart_lite.sv
//
//  Simple UART core with byte-stream interfaces on both TX and RX.
//
//  Features:
//    - 8N1 framing
//    - Parameterized baud divider
//    - Independent shallow TX/RX byte FIFOs
//    - Ready/valid byte interfaces for easy composition with control blocks
// ============================================================================
module snix_uart_lite #(
    parameter int CLK_FREQ_HZ = 100_000_000,
    parameter int BAUD_RATE   = 115_200,
    parameter int FIFO_DEPTH  = 8
) (
    input  logic       clk,
    input  logic       rst_n,

    input  logic       uart_rx,
    output logic       uart_tx,

    input  logic [7:0] tx_data,
    input  logic       tx_valid,
    output logic       tx_ready,

    output logic [7:0] rx_data,
    output logic       rx_valid,
    input  logic       rx_ready,

    output logic       tx_busy,
    output logic       rx_busy
);

    localparam int CLKS_PER_BIT = CLK_FREQ_HZ / BAUD_RATE;
    localparam int HALF_BIT_CLKS = (CLKS_PER_BIT > 1) ? (CLKS_PER_BIT / 2) : 1;
    localparam int BAUD_CNT_W = (CLKS_PER_BIT > 1) ? $clog2(CLKS_PER_BIT) : 1;
    localparam int FIFO_AW = (FIFO_DEPTH > 1) ? $clog2(FIFO_DEPTH) : 1;
    localparam logic [FIFO_AW-1:0] FIFO_LAST_PTR = FIFO_DEPTH - 1;
    localparam logic [FIFO_AW:0]   FIFO_DEPTH_COUNT = FIFO_DEPTH;

    typedef enum logic [1:0] {
        TX_IDLE,
        TX_START,
        TX_DATA,
        TX_STOP
    } tx_state_t;

    typedef enum logic [1:0] {
        RX_IDLE,
        RX_START,
        RX_DATA,
        RX_STOP
    } rx_state_t;

    tx_state_t tx_state;
    rx_state_t rx_state;

    logic [BAUD_CNT_W-1:0] tx_baud_cnt;
    logic [BAUD_CNT_W-1:0] rx_baud_cnt;
    logic [2:0]            tx_bit_idx;
    logic [2:0]            rx_bit_idx;
    logic [7:0]            tx_shift_reg;
    logic [7:0]            rx_shift_reg;

    logic [7:0] tx_fifo_data;
    logic [7:0] rx_fifo_data;
    logic       tx_fifo_wr_en;
    logic       tx_fifo_rd_en;
    logic       rx_fifo_wr_en;
    logic       rx_fifo_rd_en;
    logic       tx_fifo_full;
    logic       tx_fifo_empty;
    logic       rx_fifo_full;
    logic       rx_fifo_empty;
    logic [FIFO_AW:0] tx_fill_cnt;
    logic [FIFO_AW:0] rx_fill_cnt;
    logic [FIFO_AW-1:0] tx_wr_ptr, tx_rd_ptr;
    logic [FIFO_AW-1:0] rx_wr_ptr, rx_rd_ptr;
    logic [7:0] tx_mem [0:FIFO_DEPTH-1];
    logic [7:0] rx_mem [0:FIFO_DEPTH-1];

    initial begin
        if (CLK_FREQ_HZ < BAUD_RATE) begin
            $error("snix_uart_lite: CLK_FREQ_HZ must be >= BAUD_RATE");
        end
        if (FIFO_DEPTH < 2) begin
            $error("snix_uart_lite: FIFO_DEPTH must be >= 2");
        end
    end

    assign tx_fifo_wr_en = tx_valid & tx_ready;
    assign tx_ready      = ~tx_fifo_full;

    assign rx_fifo_rd_en = rx_valid & rx_ready;
    assign rx_valid      = ~rx_fifo_empty;
    assign rx_data       = rx_fifo_data;

    function automatic [FIFO_AW-1:0] fifo_next_ptr(input [FIFO_AW-1:0] ptr);
        if (ptr == FIFO_LAST_PTR) begin
            fifo_next_ptr = '0;
        end else begin
            fifo_next_ptr = ptr + 1'b1;
        end
    endfunction

    assign tx_fifo_data  = tx_mem[tx_rd_ptr];
    assign rx_fifo_data  = rx_mem[rx_rd_ptr];
    assign tx_fifo_empty = (tx_fill_cnt == 0);
    assign rx_fifo_empty = (rx_fill_cnt == 0);
    assign tx_fifo_full  = (tx_fill_cnt == FIFO_DEPTH_COUNT);
    assign rx_fifo_full  = (rx_fill_cnt == FIFO_DEPTH_COUNT);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_wr_ptr  <= '0;
            tx_rd_ptr  <= '0;
            tx_fill_cnt <= '0;
        end else begin
            if (tx_fifo_wr_en) begin
                tx_mem[tx_wr_ptr] <= tx_data;
                tx_wr_ptr <= fifo_next_ptr(tx_wr_ptr);
            end

            if (tx_fifo_rd_en) begin
                tx_rd_ptr <= fifo_next_ptr(tx_rd_ptr);
            end

            case ({tx_fifo_wr_en, tx_fifo_rd_en})
                2'b10: tx_fill_cnt <= tx_fill_cnt + 1'b1;
                2'b01: tx_fill_cnt <= tx_fill_cnt - 1'b1;
                default: ;
            endcase
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_wr_ptr   <= '0;
            rx_rd_ptr   <= '0;
            rx_fill_cnt <= '0;
        end else begin
            if (rx_fifo_wr_en) begin
                rx_mem[rx_wr_ptr] <= rx_shift_reg;
                rx_wr_ptr <= fifo_next_ptr(rx_wr_ptr);
            end

            if (rx_fifo_rd_en) begin
                rx_rd_ptr <= fifo_next_ptr(rx_rd_ptr);
            end

            case ({rx_fifo_wr_en, rx_fifo_rd_en})
                2'b10: rx_fill_cnt <= rx_fill_cnt + 1'b1;
                2'b01: rx_fill_cnt <= rx_fill_cnt - 1'b1;
                default: ;
            endcase
        end
    end

    // -----------------------------------------------------------------
    // UART transmitter
    // -----------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            uart_tx      <= 1'b1;
            tx_busy      <= 1'b0;
            tx_state     <= TX_IDLE;
            tx_baud_cnt  <= '0;
            tx_bit_idx   <= '0;
            tx_shift_reg <= '0;
            tx_fifo_rd_en <= 1'b0;
        end else begin
            tx_fifo_rd_en <= 1'b0;

            case (tx_state)
                TX_IDLE: begin
                    uart_tx <= 1'b1;
                    tx_busy <= 1'b0;
                    if (!tx_fifo_empty) begin
                        tx_fifo_rd_en <= 1'b1;
                        tx_shift_reg  <= tx_fifo_data;
                        tx_baud_cnt   <= CLKS_PER_BIT - 1;
                        tx_bit_idx    <= '0;
                        tx_busy       <= 1'b1;
                        tx_state      <= TX_START;
                        uart_tx       <= 1'b0;
                    end
                end

                TX_START: begin
                    if (tx_baud_cnt == 0) begin
                        tx_baud_cnt <= CLKS_PER_BIT - 1;
                        tx_state    <= TX_DATA;
                        uart_tx     <= tx_shift_reg[0];
                    end else begin
                        tx_baud_cnt <= tx_baud_cnt - 1'b1;
                    end
                end

                TX_DATA: begin
                    if (tx_baud_cnt == 0) begin
                        tx_baud_cnt <= CLKS_PER_BIT - 1;
                        if (tx_bit_idx == 3'd7) begin
                            tx_state <= TX_STOP;
                            uart_tx  <= 1'b1;
                        end else begin
                            tx_bit_idx <= tx_bit_idx + 1'b1;
                            uart_tx    <= tx_shift_reg[tx_bit_idx + 1'b1];
                        end
                    end else begin
                        tx_baud_cnt <= tx_baud_cnt - 1'b1;
                    end
                end

                TX_STOP: begin
                    if (tx_baud_cnt == 0) begin
                        tx_state <= TX_IDLE;
                    end else begin
                        tx_baud_cnt <= tx_baud_cnt - 1'b1;
                    end
                end

                default: tx_state <= TX_IDLE;
            endcase
        end
    end

    // -----------------------------------------------------------------
    // UART receiver
    // -----------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_busy       <= 1'b0;
            rx_state      <= RX_IDLE;
            rx_baud_cnt   <= '0;
            rx_bit_idx    <= '0;
            rx_shift_reg  <= '0;
            rx_fifo_wr_en <= 1'b0;
        end else begin
            rx_fifo_wr_en <= 1'b0;

            case (rx_state)
                RX_IDLE: begin
                    rx_busy <= 1'b0;
                    if (!uart_rx) begin
                        rx_busy     <= 1'b1;
                        rx_state    <= RX_START;
                        rx_baud_cnt <= HALF_BIT_CLKS - 1;
                        rx_bit_idx  <= '0;
                    end
                end

                RX_START: begin
                    if (rx_baud_cnt == 0) begin
                        if (!uart_rx) begin
                            rx_state    <= RX_DATA;
                            rx_baud_cnt <= CLKS_PER_BIT - 1;
                        end else begin
                            rx_state <= RX_IDLE;
                        end
                    end else begin
                        rx_baud_cnt <= rx_baud_cnt - 1'b1;
                    end
                end

                RX_DATA: begin
                    if (rx_baud_cnt == 0) begin
                        rx_shift_reg[rx_bit_idx] <= uart_rx;
                        rx_baud_cnt <= CLKS_PER_BIT - 1;
                        if (rx_bit_idx == 3'd7) begin
                            rx_state <= RX_STOP;
                        end else begin
                            rx_bit_idx <= rx_bit_idx + 1'b1;
                        end
                    end else begin
                        rx_baud_cnt <= rx_baud_cnt - 1'b1;
                    end
                end

                RX_STOP: begin
                    if (rx_baud_cnt == 0) begin
                        if (uart_rx && !rx_fifo_full) begin
                            rx_fifo_wr_en <= 1'b1;
                        end
                        rx_state <= RX_IDLE;
                    end else begin
                        rx_baud_cnt <= rx_baud_cnt - 1'b1;
                    end
                end

                default: rx_state <= RX_IDLE;
            endcase
        end
    end

endmodule : snix_uart_lite

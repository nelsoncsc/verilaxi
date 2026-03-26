// ============================================================================
//  snix_uart_axil_master.sv
//
//  UART-to-AXI-Lite bridge. Commands are ASCII and newline terminated:
//
//    W <addr32hex> <data32hex>\n
//    R <addr32hex>\n
//
//  Responses:
//    OK\n
//    ERR\n
//    D <addr32hex> <data32hex>\n
// ============================================================================
module snix_uart_axil_master #(
    parameter int ADDR_WIDTH  = 32,
    parameter int DATA_WIDTH  = 32,
    parameter int CLK_FREQ_HZ = 100_000_000,
    parameter int BAUD_RATE   = 115_200,
    parameter int FIFO_DEPTH  = 8
) (
    input  logic                    clk,
    input  logic                    rst_n,

    input  logic                    uart_rx,
    output logic                    uart_tx,

    output logic [ADDR_WIDTH-1:0]   m_axil_awaddr,
    output logic                    m_axil_awvalid,
    input  logic                    m_axil_awready,

    output logic [DATA_WIDTH-1:0]   m_axil_wdata,
    output logic [DATA_WIDTH/8-1:0] m_axil_wstrb,
    output logic                    m_axil_wvalid,
    input  logic                    m_axil_wready,

    input  logic [1:0]              m_axil_bresp,
    input  logic                    m_axil_bvalid,
    output logic                    m_axil_bready,

    output logic [ADDR_WIDTH-1:0]   m_axil_araddr,
    output logic                    m_axil_arvalid,
    input  logic                    m_axil_arready,

    input  logic [DATA_WIDTH-1:0]   m_axil_rdata,
    input  logic [1:0]              m_axil_rresp,
    input  logic                    m_axil_rvalid,
    output logic                    m_axil_rready
);

    localparam logic [1:0] RESP_NONE = 2'd0;
    localparam logic [1:0] RESP_OK   = 2'd1;
    localparam logic [1:0] RESP_ERR  = 2'd2;
    localparam logic [1:0] RESP_READ = 2'd3;

    typedef enum logic [2:0] {
        PARSE_IDLE,
        PARSE_ADDR,
        PARSE_DATA,
        PARSE_EOL
    } parse_state_t;

    typedef enum logic [2:0] {
        AXIL_IDLE,
        AXIL_WRITE_AW,
        AXIL_WRITE_W,
        AXIL_WRITE_B,
        AXIL_READ_AR,
        AXIL_READ_R
    } axil_state_t;

    logic [7:0] uart_tx_data;
    logic       uart_tx_valid;
    logic       uart_tx_ready;
    logic [7:0] uart_rx_data;
    logic       uart_rx_valid;
    logic       uart_rx_ready;
    logic       uart_core_tx_busy;
    logic       uart_core_rx_busy;

    parse_state_t parse_state;
    axil_state_t  axil_state;

    logic         cmd_is_write;
    logic [3:0]   nibble_count;
    logic [31:0]  cmd_addr;
    logic [31:0]  cmd_data;
    logic [31:0]  read_data_latched;

    logic [1:0]   resp_kind;
    logic [4:0]   resp_len;
    logic [4:0]   resp_idx;
    logic         resp_active;
    logic         resp_done;
    logic [7:0]   resp_byte;

    function automatic logic is_hex(input logic [7:0] c);
        is_hex = ((c >= "0") && (c <= "9")) ||
                 ((c >= "a") && (c <= "f")) ||
                 ((c >= "A") && (c <= "F"));
    endfunction

    function automatic logic [3:0] hex_value(input logic [7:0] c);
        if ((c >= "0") && (c <= "9")) begin
            hex_value = c - "0";
        end else if ((c >= "a") && (c <= "f")) begin
            hex_value = (c - "a") + 8'd10;
        end else begin
            hex_value = (c - "A") + 8'd10;
        end
    endfunction

    function automatic logic [7:0] hex_ascii(input logic [3:0] nibble);
        if (nibble < 10) begin
            hex_ascii = "0" + {4'b0, nibble};
        end else begin
            hex_ascii = "A" + {4'b0, (nibble - 4'd10)};
        end
    endfunction

    always_comb begin
        resp_len  = '0;
        resp_byte = 8'h00;

        unique case (resp_kind)
            RESP_OK: begin
                resp_len = 5'd3;
                unique case (resp_idx)
                    5'd0: resp_byte = "O";
                    5'd1: resp_byte = "K";
                    5'd2: resp_byte = "\n";
                    default: resp_byte = 8'h00;
                endcase
            end

            RESP_ERR: begin
                resp_len = 5'd4;
                unique case (resp_idx)
                    5'd0: resp_byte = "E";
                    5'd1: resp_byte = "R";
                    5'd2: resp_byte = "R";
                    5'd3: resp_byte = "\n";
                    default: resp_byte = 8'h00;
                endcase
            end

            RESP_READ: begin
                resp_len = 5'd20;
                unique case (resp_idx)
                    5'd0:  resp_byte = "D";
                    5'd1:  resp_byte = " ";
                    5'd2:  resp_byte = hex_ascii(cmd_addr[31:28]);
                    5'd3:  resp_byte = hex_ascii(cmd_addr[27:24]);
                    5'd4:  resp_byte = hex_ascii(cmd_addr[23:20]);
                    5'd5:  resp_byte = hex_ascii(cmd_addr[19:16]);
                    5'd6:  resp_byte = hex_ascii(cmd_addr[15:12]);
                    5'd7:  resp_byte = hex_ascii(cmd_addr[11:8]);
                    5'd8:  resp_byte = hex_ascii(cmd_addr[7:4]);
                    5'd9:  resp_byte = hex_ascii(cmd_addr[3:0]);
                    5'd10: resp_byte = " ";
                    5'd11: resp_byte = hex_ascii(read_data_latched[31:28]);
                    5'd12: resp_byte = hex_ascii(read_data_latched[27:24]);
                    5'd13: resp_byte = hex_ascii(read_data_latched[23:20]);
                    5'd14: resp_byte = hex_ascii(read_data_latched[19:16]);
                    5'd15: resp_byte = hex_ascii(read_data_latched[15:12]);
                    5'd16: resp_byte = hex_ascii(read_data_latched[11:8]);
                    5'd17: resp_byte = hex_ascii(read_data_latched[7:4]);
                    5'd18: resp_byte = hex_ascii(read_data_latched[3:0]);
                    5'd19: resp_byte = "\n";
                    default: resp_byte = 8'h00;
                endcase
            end

            default: begin
                resp_len  = '0;
                resp_byte = 8'h00;
            end
        endcase
    end

    assign uart_tx_data  = resp_byte;
    assign uart_tx_valid = resp_active;
    assign resp_done     = resp_active & uart_tx_valid & uart_tx_ready & (resp_idx == resp_len - 1'b1);

    assign uart_rx_ready = (axil_state == AXIL_IDLE) & ~resp_active;

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
        .tx_busy (uart_core_tx_busy),
        .rx_busy (uart_core_rx_busy)
    );

    // -----------------------------------------------------------------
    // Command parser
    // -----------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            resp_kind   <= RESP_NONE;
            resp_idx    <= '0;
            resp_active <= 1'b0;

            parse_state   <= PARSE_IDLE;
            cmd_is_write  <= 1'b0;
            nibble_count  <= '0;
            cmd_addr      <= '0;
            cmd_data      <= '0;
            read_data_latched <= '0;

            m_axil_awaddr <= '0;
            m_axil_awvalid <= 1'b0;
            m_axil_wdata  <= '0;
            m_axil_wstrb  <= {DATA_WIDTH/8{1'b1}};
            m_axil_wvalid <= 1'b0;
            m_axil_bready <= 1'b0;
            m_axil_araddr <= '0;
            m_axil_arvalid <= 1'b0;
            m_axil_rready <= 1'b0;
            axil_state    <= AXIL_IDLE;
        end else begin
            if (resp_active && uart_tx_valid && uart_tx_ready) begin
                if (resp_done) begin
                    resp_kind   <= RESP_NONE;
                    resp_active <= 1'b0;
                    resp_idx    <= '0;
                end else begin
                    resp_idx <= resp_idx + 1'b1;
                end
            end

            if (uart_rx_valid && uart_rx_ready) begin
                unique case (parse_state)
                    PARSE_IDLE: begin
                        if ((uart_rx_data == "W") || (uart_rx_data == "w")) begin
                            cmd_is_write <= 1'b1;
                            parse_state  <= PARSE_ADDR;
                            nibble_count <= '0;
                            cmd_addr     <= '0;
                            cmd_data     <= '0;
                        end else if ((uart_rx_data == "R") || (uart_rx_data == "r")) begin
                            cmd_is_write <= 1'b0;
                            parse_state  <= PARSE_ADDR;
                            nibble_count <= '0;
                            cmd_addr     <= '0;
                        end else if ((uart_rx_data == " ") || (uart_rx_data == "\n") || (uart_rx_data == "\r")) begin
                            parse_state <= PARSE_IDLE;
                        end else begin
                            resp_kind   <= RESP_ERR;
                            resp_idx    <= '0;
                            resp_active <= 1'b1;
                            parse_state <= PARSE_IDLE;
                        end
                    end

                    PARSE_ADDR: begin
                        if ((uart_rx_data == " ") && (nibble_count == 0)) begin
                            parse_state <= PARSE_ADDR;
                        end else if (is_hex(uart_rx_data) && (nibble_count < 8)) begin
                            cmd_addr <= {cmd_addr[27:0], hex_value(uart_rx_data)};
                            nibble_count <= nibble_count + 1'b1;
                            if (nibble_count == 4'd7) begin
                                nibble_count <= '0;
                                parse_state  <= cmd_is_write ? PARSE_DATA : PARSE_EOL;
                            end
                        end else begin
                            resp_kind   <= RESP_ERR;
                            resp_idx    <= '0;
                            resp_active <= 1'b1;
                            parse_state <= PARSE_IDLE;
                        end
                    end

                    PARSE_DATA: begin
                        if ((uart_rx_data == " ") && (nibble_count == 0)) begin
                            parse_state <= PARSE_DATA;
                        end else if (is_hex(uart_rx_data) && (nibble_count < 8)) begin
                            cmd_data <= {cmd_data[27:0], hex_value(uart_rx_data)};
                            nibble_count <= nibble_count + 1'b1;
                            if (nibble_count == 4'd7) begin
                                nibble_count <= '0;
                                parse_state  <= PARSE_EOL;
                            end
                        end else begin
                            resp_kind   <= RESP_ERR;
                            resp_idx    <= '0;
                            resp_active <= 1'b1;
                            parse_state <= PARSE_IDLE;
                        end
                    end

                    PARSE_EOL: begin
                        if (uart_rx_data == "\r") begin
                            parse_state <= PARSE_EOL;
                        end else if (uart_rx_data == "\n") begin
                            if (cmd_is_write) begin
                                m_axil_awaddr  <= cmd_addr[ADDR_WIDTH-1:0];
                                m_axil_wdata   <= cmd_data[DATA_WIDTH-1:0];
                                m_axil_awvalid <= 1'b1;
                                axil_state     <= AXIL_WRITE_AW;
                            end else begin
                                m_axil_araddr  <= cmd_addr[ADDR_WIDTH-1:0];
                                m_axil_arvalid <= 1'b1;
                                axil_state     <= AXIL_READ_AR;
                            end
                            parse_state <= PARSE_IDLE;
                        end else if (uart_rx_data == " ") begin
                            parse_state <= PARSE_EOL;
                        end else begin
                            resp_kind   <= RESP_ERR;
                            resp_idx    <= '0;
                            resp_active <= 1'b1;
                            parse_state <= PARSE_IDLE;
                        end
                    end

                    default: parse_state <= PARSE_IDLE;
                endcase
            end

            unique case (axil_state)
                AXIL_IDLE: begin
                    m_axil_bready <= 1'b0;
                    m_axil_rready <= 1'b0;
                    if (!m_axil_awvalid)
                        m_axil_wvalid <= 1'b0;
                end

                AXIL_WRITE_AW: begin
                    if (m_axil_awvalid && m_axil_awready) begin
                        m_axil_awvalid <= 1'b0;
                        m_axil_wvalid  <= 1'b1;
                        axil_state      <= AXIL_WRITE_W;
                    end
                end

                AXIL_WRITE_W: begin
                    if (m_axil_wvalid && m_axil_wready) begin
                        m_axil_wvalid <= 1'b0;
                        m_axil_bready <= 1'b1;
                        axil_state    <= AXIL_WRITE_B;
                    end
                end

                AXIL_WRITE_B: begin
                    if (m_axil_bvalid && m_axil_bready) begin
                        m_axil_bready <= 1'b0;
                        resp_kind   <= RESP_OK;
                        resp_idx    <= '0;
                        resp_active <= 1'b1;
                        axil_state <= AXIL_IDLE;
                    end
                end

                AXIL_READ_AR: begin
                    if (m_axil_arvalid && m_axil_arready) begin
                        m_axil_arvalid <= 1'b0;
                        m_axil_rready  <= 1'b1;
                        axil_state      <= AXIL_READ_R;
                    end
                end

                AXIL_READ_R: begin
                    if (m_axil_rvalid && m_axil_rready) begin
                        read_data_latched <= m_axil_rdata;
                        m_axil_rready     <= 1'b0;
                        resp_kind         <= RESP_READ;
                        resp_idx          <= '0;
                        resp_active       <= 1'b1;
                        axil_state <= AXIL_IDLE;
                    end
                end

                default: axil_state <= AXIL_IDLE;
            endcase
        end
    end

endmodule : snix_uart_axil_master

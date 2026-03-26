// ============================================================================
//  snix_axil_gpio.sv
//
//  AXI-Lite GPIO peripheral with synchronized switch inputs, debounced button
//  inputs, user LED outputs, RGB LED outputs, and sticky rising-edge capture
//  for buttons.
// ============================================================================
module snix_axil_gpio #(
    parameter int DATA_WIDTH       = 32,
    parameter int ADDR_WIDTH       = 32,
    parameter int NUM_LEDS         = 4,
    parameter int NUM_RGB_LEDS     = 2,
    parameter int NUM_SWITCHES     = 4,
    parameter int NUM_BUTTONS      = 4,
    parameter int DEBOUNCE_CYCLES  = 16
) (
    input  logic                        clk,
    input  logic                        rst_n,

    input  logic [ADDR_WIDTH-1:0]       s_axil_awaddr,
    input  logic                        s_axil_awvalid,
    output logic                        s_axil_awready,

    input  logic [DATA_WIDTH-1:0]       s_axil_wdata,
    input  logic [DATA_WIDTH/8-1:0]     s_axil_wstrb,
    input  logic                        s_axil_wvalid,
    output logic                        s_axil_wready,

    output logic [1:0]                  s_axil_bresp,
    output logic                        s_axil_bvalid,
    input  logic                        s_axil_bready,

    input  logic [ADDR_WIDTH-1:0]       s_axil_araddr,
    input  logic                        s_axil_arvalid,
    output logic                        s_axil_arready,

    output logic [DATA_WIDTH-1:0]       s_axil_rdata,
    output logic [1:0]                  s_axil_rresp,
    output logic                        s_axil_rvalid,
    input  logic                        s_axil_rready,

    input  logic [NUM_SWITCHES-1:0]     gpio_sw,
    input  logic [NUM_BUTTONS-1:0]      gpio_btn,
    output logic [NUM_LEDS-1:0]         gpio_led,
    output logic [NUM_RGB_LEDS*3-1:0]   gpio_rgb
);

    localparam int ADDRLSB        = $clog2(DATA_WIDTH/8);
    localparam int REG_INDEX_W    = (ADDR_WIDTH > ADDRLSB) ? (ADDR_WIDTH - ADDRLSB) : 1;
    localparam int BTN_CNT_W      = (DEBOUNCE_CYCLES <= 1) ? 1 : $clog2(DEBOUNCE_CYCLES);

    localparam logic [REG_INDEX_W-1:0] GPIO_OUT_ADDR  = 'd0;
    localparam logic [REG_INDEX_W-1:0] GPIO_IN_ADDR   = 'd1;
    localparam logic [REG_INDEX_W-1:0] BTN_EDGE_ADDR  = 'd2;
    localparam logic [REG_INDEX_W-1:0] RGB0_ADDR      = 'd3;
    localparam logic [REG_INDEX_W-1:0] RGB1_ADDR      = 'd4;

    logic                          awvalid_reg;
    logic [REG_INDEX_W-1:0]        awaddr_reg;
    logic                          arvalid_reg;
    logic [REG_INDEX_W-1:0]        araddr_reg;

    logic                          wvalid_reg;
    logic [DATA_WIDTH-1:0]         wdata_reg;
    logic [DATA_WIDTH/8-1:0]       wstrb_reg;

    logic                          write_ready;
    logic                          read_ready;
    logic [DATA_WIDTH-1:0]         write_mask;
    logic [DATA_WIDTH-1:0]         clr_mask;

    logic [NUM_LEDS-1:0]           gpio_led_reg;
    logic [NUM_RGB_LEDS*3-1:0]     gpio_rgb_reg;
    logic [NUM_SWITCHES-1:0]       sw_sync1, sw_sync2;
    logic [NUM_BUTTONS-1:0]        btn_sync1, btn_sync2;
    logic [NUM_BUTTONS-1:0]        btn_db;
    logic [NUM_BUTTONS-1:0]        btn_db_d;
    logic [NUM_BUTTONS-1:0]        btn_edge;
    logic [BTN_CNT_W-1:0]          btn_cnt [0:NUM_BUTTONS-1];

    logic [DATA_WIDTH-1:0]         gpio_in_reg;
    logic [DATA_WIDTH-1:0]         btn_edge_reg;
    logic [DATA_WIDTH-1:0]         read_data_next;
    logic [NUM_BUTTONS-1:0]        btn_rise;
    logic [NUM_BUTTONS-1:0]        btn_edge_next;

    assign write_ready = awvalid_reg & wvalid_reg & (~s_axil_bvalid | s_axil_bready);
    assign read_ready  = arvalid_reg & (~s_axil_rvalid | s_axil_rready);

    assign gpio_led    = gpio_led_reg;
    assign gpio_rgb    = gpio_rgb_reg;
    assign btn_rise    = btn_db & ~btn_db_d;

    always_comb begin
        write_mask = '0;
        for (int i = 0; i < DATA_WIDTH/8; i++) begin
            write_mask[i*8 +: 8] = {8{wstrb_reg[i]}};
        end
    end

    always_comb begin
        gpio_in_reg = '0;
        btn_edge_reg = '0;

        gpio_in_reg[NUM_SWITCHES-1:0] = sw_sync2;
        gpio_in_reg[NUM_SWITCHES +: NUM_BUTTONS] = btn_db;
        btn_edge_reg[NUM_BUTTONS-1:0] = btn_edge;
    end

    always_comb begin
        clr_mask      = '0;
        read_data_next = '0;

        if (awaddr_reg == BTN_EDGE_ADDR) begin
            clr_mask[NUM_BUTTONS-1:0] = wdata_reg[NUM_BUTTONS-1:0] & write_mask[NUM_BUTTONS-1:0];
        end

        unique case (araddr_reg)
            GPIO_OUT_ADDR: begin
                read_data_next[NUM_LEDS-1:0] = gpio_led_reg;
            end
            RGB0_ADDR: begin
                if (NUM_RGB_LEDS > 0) begin
                    read_data_next[2:0] = gpio_rgb_reg[2:0];
                end
            end
            RGB1_ADDR: begin
                if (NUM_RGB_LEDS > 1) begin
                    read_data_next[2:0] = gpio_rgb_reg[5:3];
                end
            end
            GPIO_IN_ADDR: begin
                read_data_next = gpio_in_reg;
            end
            BTN_EDGE_ADDR: begin
                read_data_next = btn_edge_reg;
            end
            default: begin
                read_data_next = '0;
            end
        endcase
    end

    snix_register_slice #(
        .DATA_WIDTH(REG_INDEX_W)
    ) aw_slice_u0 (
        .clk          (clk),
        .rst_n        (rst_n),
        .s_axis_tdata (s_axil_awaddr[ADDR_WIDTH-1:ADDRLSB]),
        .s_axis_tvalid(s_axil_awvalid),
        .s_axis_tready(s_axil_awready),
        .m_axis_tdata (awaddr_reg),
        .m_axis_tvalid(awvalid_reg),
        .m_axis_tready(write_ready)
    );

    snix_register_slice #(
        .DATA_WIDTH(DATA_WIDTH + DATA_WIDTH/8)
    ) w_slice_u0 (
        .clk          (clk),
        .rst_n        (rst_n),
        .s_axis_tdata ({s_axil_wdata, s_axil_wstrb}),
        .s_axis_tvalid(s_axil_wvalid),
        .s_axis_tready(s_axil_wready),
        .m_axis_tdata ({wdata_reg, wstrb_reg}),
        .m_axis_tvalid(wvalid_reg),
        .m_axis_tready(write_ready)
    );

    snix_register_slice #(
        .DATA_WIDTH(REG_INDEX_W)
    ) ar_slice_u0 (
        .clk          (clk),
        .rst_n        (rst_n),
        .s_axis_tdata (s_axil_araddr[ADDR_WIDTH-1:ADDRLSB]),
        .s_axis_tvalid(s_axil_arvalid),
        .s_axis_tready(s_axil_arready),
        .m_axis_tdata (araddr_reg),
        .m_axis_tvalid(arvalid_reg),
        .m_axis_tready(read_ready)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axil_bvalid <= 1'b0;
        end else if (write_ready) begin
            s_axil_bvalid <= 1'b1;
        end else if (s_axil_bvalid && s_axil_bready) begin
            s_axil_bvalid <= 1'b0;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s_axil_rvalid <= 1'b0;
            s_axil_rdata  <= '0;
        end else begin
            if (read_ready) begin
                s_axil_rvalid <= 1'b1;
                s_axil_rdata  <= read_data_next;
            end else if (s_axil_rvalid && s_axil_rready) begin
                s_axil_rvalid <= 1'b0;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gpio_led_reg <= '0;
        end else if (write_ready && (awaddr_reg == GPIO_OUT_ADDR)) begin
            for (int i = 0; i < NUM_LEDS; i++) begin
                if (write_mask[i]) begin
                    gpio_led_reg[i] <= wdata_reg[i];
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gpio_rgb_reg <= '0;
        end else if (write_ready) begin
            if ((awaddr_reg == RGB0_ADDR) && (NUM_RGB_LEDS > 0)) begin
                for (int i = 0; i < 3; i++) begin
                    if (write_mask[i]) begin
                        gpio_rgb_reg[i] <= wdata_reg[i];
                    end
                end
            end
            if ((awaddr_reg == RGB1_ADDR) && (NUM_RGB_LEDS > 1)) begin
                for (int i = 0; i < 3; i++) begin
                    if (write_mask[i]) begin
                        gpio_rgb_reg[3+i] <= wdata_reg[i];
                    end
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sw_sync1  <= '0;
            sw_sync2  <= '0;
            btn_sync1 <= '0;
            btn_sync2 <= '0;
        end else begin
            sw_sync1  <= gpio_sw;
            sw_sync2  <= sw_sync1;
            btn_sync1 <= gpio_btn;
            btn_sync2 <= btn_sync1;
        end
    end

    generate
        if (DEBOUNCE_CYCLES <= 1) begin : GEN_BTN_NODEBOUNCE
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    btn_db <= '0;
                end else begin
                    btn_db <= btn_sync2;
                end
            end
        end else begin : GEN_BTN_DEBOUNCE
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    btn_db <= '0;
                    for (int i = 0; i < NUM_BUTTONS; i++) begin
                        btn_cnt[i] <= '0;
                    end
                end else begin
                    for (int i = 0; i < NUM_BUTTONS; i++) begin
                        if (btn_sync2[i] == btn_db[i]) begin
                            btn_cnt[i] <= '0;
                        end else if (btn_cnt[i] == BTN_CNT_W'(DEBOUNCE_CYCLES-1)) begin
                            btn_db[i]  <= btn_sync2[i];
                            btn_cnt[i] <= '0;
                        end else begin
                            btn_cnt[i] <= btn_cnt[i] + BTN_CNT_W'(1);
                        end
                    end
                end
            end
        end
    endgenerate

    always_comb begin
        btn_edge_next = btn_edge;
        btn_edge_next = (btn_edge_next & ~clr_mask[NUM_BUTTONS-1:0]) | btn_rise;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            btn_db_d <= '0;
            btn_edge <= '0;
        end else begin
            btn_db_d <= btn_db;
            btn_edge <= btn_edge_next;
        end
    end

    assign s_axil_bresp = 2'b00;
    assign s_axil_rresp = 2'b00;

endmodule : snix_axil_gpio

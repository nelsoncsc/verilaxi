// ============================================================================
//  snix_axil_register.sv
//
//  SystemVerilog implementation of an AXI-Lite register slave.
//
//  Largely based on ZipCPU's implementation and tutorial:
//    https://zipcpu.com/blog/2020/03/08/easyaxil.html
// ============================================================================
module snix_axil_register #(parameter DATA_WIDTH = 32,
                            parameter ADDR_WIDTH = 4,
                            parameter NUM_REGS   = 16)
                           (input  logic                                clk,
                            input  logic                                rst_n,
                                
                            // AXI Lite Interface with prefix s_axil
                            input  logic [ADDR_WIDTH-1:0]               s_axil_awaddr,
                            input  logic                                s_axil_awvalid,
                            output logic                                s_axil_awready,

                            input  logic [DATA_WIDTH-1:0]               s_axil_wdata,
                            input  logic [DATA_WIDTH/8-1:0]             s_axil_wstrb,
                            input  logic                                s_axil_wvalid,
                            output logic                                s_axil_wready,

                            output logic [1:0]                          s_axil_bresp,
                            output logic                                s_axil_bvalid,
                            input  logic                                s_axil_bready,

                            input  logic [ADDR_WIDTH-1:0]               s_axil_araddr,
                            input  logic                                s_axil_arvalid,
                            output logic                                s_axil_arready,

                            output logic [DATA_WIDTH-1:0]               s_axil_rdata,
                            output logic [1:0]                          s_axil_rresp,
                            output logic                                s_axil_rvalid,
                            input  logic                                s_axil_rready,
                            output logic [NUM_REGS-1:0][DATA_WIDTH-1:0] config_status_reg);


    localparam AXIL_DATA_WIDTH = DATA_WIDTH;
    localparam AXIL_ADDR_WIDTH = ADDR_WIDTH;
    localparam ADDRLSB = $clog2(AXIL_DATA_WIDTH/8);
    localparam REG_INDEX_WIDTH = $clog2(NUM_REGS);


    logic                               s_axil_awvalid_reg, s_axil_awready_reg;
    logic [AXIL_ADDR_WIDTH-ADDRLSB-1:0] s_axil_awaddr_reg;

    logic                               s_axil_arvalid_reg, s_axil_arready_reg;
    logic [AXIL_ADDR_WIDTH-ADDRLSB-1:0] s_axil_araddr_reg;


    logic                               s_axil_wvalid_reg, s_axil_wready_reg;
    logic [AXIL_DATA_WIDTH-1:0]         s_axil_wdata_reg;
    logic [AXIL_DATA_WIDTH/8-1:0]       s_axil_wstrb_reg;

    logic                               s_axil_write_ready, s_axil_read_ready;
    logic [31:0]                        awaddr_index,       araddr_index;
    

    assign s_axil_write_ready = s_axil_awvalid_reg & s_axil_wvalid_reg & (!s_axil_bvalid | s_axil_bready);
    assign s_axil_read_ready  = s_axil_arvalid_reg & (!s_axil_rvalid | s_axil_rready);
    assign awaddr_index = {{(32-REG_INDEX_WIDTH){1'b0}}, s_axil_awaddr_reg[REG_INDEX_WIDTH-1:0]};
    assign araddr_index = {{(32-REG_INDEX_WIDTH){1'b0}}, s_axil_araddr_reg[REG_INDEX_WIDTH-1:0]};

    snix_register_slice #(.DATA_WIDTH(AXIL_ADDR_WIDTH-ADDRLSB))
             reg_slice_u0(.clk(clk),
                         .rst_n(rst_n),
                         .s_axis_tdata(s_axil_awaddr[AXIL_ADDR_WIDTH-1:ADDRLSB]),
                         .s_axis_tvalid(s_axil_awvalid),
                         .s_axis_tready(s_axil_awready),

                         .m_axis_tdata(s_axil_awaddr_reg),
                         .m_axis_tvalid(s_axil_awvalid_reg),
                         .m_axis_tready(s_axil_write_ready));

    
    snix_register_slice #(.DATA_WIDTH(AXIL_DATA_WIDTH+AXIL_DATA_WIDTH/8))
             reg_slice_u1(.clk(clk),
                         .rst_n(rst_n),
                         .s_axis_tdata({s_axil_wdata, s_axil_wstrb}),
                         .s_axis_tvalid(s_axil_wvalid),
                         .s_axis_tready(s_axil_wready),

                         .m_axis_tdata({s_axil_wdata_reg, s_axil_wstrb_reg}),
                         .m_axis_tvalid(s_axil_wvalid_reg),
                         .m_axis_tready(s_axil_write_ready));


    snix_register_slice #(.DATA_WIDTH(AXIL_ADDR_WIDTH-ADDRLSB))
             reg_slice_u2(.clk(clk),
                         .rst_n(rst_n),
                         .s_axis_tdata(s_axil_araddr[AXIL_ADDR_WIDTH-1:ADDRLSB]),
                         .s_axis_tvalid(s_axil_arvalid),
                         .s_axis_tready(s_axil_arready),

                         .m_axis_tdata(s_axil_araddr_reg),
                         .m_axis_tvalid(s_axil_arvalid_reg),
                         .m_axis_tready(s_axil_read_ready));


    always_ff @(posedge clk or negedge rst_n)
        if(!rst_n) begin
            s_axil_bvalid <= 1'b0;
        end
        else if(s_axil_write_ready) begin
            s_axil_bvalid <= 1'b1;
        end
        else if(s_axil_bready) begin
            s_axil_bvalid <= 1'b0;
        end


    always_ff @(posedge clk or negedge rst_n)
        if(!rst_n) begin
            s_axil_rvalid <= 1'b0;
        end
        else if(s_axil_read_ready) begin
            s_axil_rvalid <= 1'b1;
        end
        else if(s_axil_rready) begin
            s_axil_rvalid <= 1'b0;
        end

    always_ff @(posedge clk or negedge rst_n)
        if(!rst_n) begin
            config_status_reg <= '0;
        end
        else if(s_axil_write_ready && awaddr_index < NUM_REGS) begin
            for(int i = 0; i < (AXIL_DATA_WIDTH/8); i++) begin
                config_status_reg[awaddr_index][8*i +: 8] <= s_axil_wstrb_reg[i] ? s_axil_wdata_reg[8*i +: 8] : config_status_reg[awaddr_index][8*i +: 8];
            end
        end

    always_ff @(posedge clk or negedge rst_n)
        if(!rst_n) begin
            s_axil_rdata <= '0;
        end
        else if(s_axil_read_ready && araddr_index < NUM_REGS) begin
           s_axil_rdata  <= config_status_reg[araddr_index]; 
        end


    assign s_axil_bresp = 2'b00;
    assign s_axil_rresp = 2'b00;

endmodule: snix_axil_register

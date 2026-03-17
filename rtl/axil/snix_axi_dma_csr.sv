module snix_axi_dma_csr   #(parameter DATA_WIDTH = 32,
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
                            input  logic [DATA_WIDTH-1:0]               read_status_reg,
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

    // AXI DMA REGISTER MAP
    /*

     Address              Register                  Description
     0x00                 WR_CTRL                   wr_start/wr_stop/wr_circular/wr_size/wr_len
     0x04                 WR_NUM_BYTES              number of bytes to write
     0x08                 WR_ADDR                   write base address
     
     0x0C                 RD_CTRL                   rd_start/rd_stop/rd_circular/rd_size/rd_len
     0x10                 RD_NUM_BYTES              number of bytes to read
     0x14                 RD_ADDR                   read base address
     
     0x18                 STATUS                    wr_busy/rd_busy/wr_done/rd_done


             0x00  ---- WR_CTRL
    Bits                          Field
    [0]                           ctrl_wr_start
    [1]                           ctrl_wr_stop
    [2]                           ctrl_wr_circular
    [5:3]                         ctrl_wr_size
    [13:6]                        ctrl_wr_len
    [31:14]                       Reserved

             0x04  ---- WR_NUM_BYTES
    Bits                          Field
    [31:0]                        ctrl_wr_transfer_len
    [31:16]                       Reserved

            0x08  ---- WR_ADDR
    Bits                          Field
    [31:0]                        ctrl_wr_addr

            0x0C  ---- RD_CTRL
    Bits                          Field
    [0]                           ctrl_rd_start
    [1]                           ctrl_rd_stop
    [2]                           ctrl_rd_circular
    [5:3]                         ctrl_rd_size
    [13:6]                        ctrl_rd_len
    [31:14]                       Reserved
     
             0x10  ---- RD_NUM_BYTES
    Bits                          Field
    [31:0]                        ctrl_rd_transfer_len
    [31:16]                       Reserved

             0x14  ---- RD_ADDR
    Bits                          Field
    [31:0]                        ctrl_rd_addr

             0x18  ---- STATUS
    Bits                          Field
    [0]                           ctrl_wr_done
    [1]                           ctrl_rd_done
    [31:2]                        Reserved
   */

    localparam int WR_CTRL_IDX   = 0;    // 0x00
    //localparam int WR_NUM_BYTES_IDX  = 1;  // 0x04
    //localparam int WR_ADDR_IDX   = 2;  // 0x08

    localparam int RD_CTRL_IDX   = 3;    // 0x0C
    //localparam int RD_NUM_BYTES_IDX  = 4;  // 0x10
    //localparam int RD_ADDR_IDX   = 5;  // 0x14

    localparam int STATUS_IDX    = 6;    // 0x18

    // control signals to start/stop read/write DMAS
    logic ctrl_wr_start;
    logic ctrl_wr_stop;
    logic ctrl_rd_start;
    logic ctrl_rd_stop; 

    logic ctrl_wr_done;
    logic ctrl_rd_done;

    
    assign ctrl_wr_start = config_status_reg[WR_CTRL_IDX][0];
    assign ctrl_wr_stop  = config_status_reg[WR_CTRL_IDX][1];
    assign ctrl_rd_start = config_status_reg[RD_CTRL_IDX][0];
    assign ctrl_rd_stop  = config_status_reg[RD_CTRL_IDX][1];

    assign ctrl_wr_done  = read_status_reg[0];
    assign ctrl_rd_done  = read_status_reg[1];

    always_ff @(posedge clk or negedge rst_n)
        if(!rst_n) begin
            config_status_reg <= '0;
        end
        else if(s_axil_write_ready && awaddr_index < NUM_REGS) begin
            for(int i = 0; i < (AXIL_DATA_WIDTH/8); i++) begin
                config_status_reg[awaddr_index][8*i +: 8] <= s_axil_wstrb_reg[i] ? s_axil_wdata_reg[8*i +: 8] : config_status_reg[awaddr_index][8*i +: 8];
            end
        end
        else begin
            config_status_reg <= config_status_reg;
            // clear pulses as soon as they are set by software
            if(ctrl_wr_start) begin
                config_status_reg[WR_CTRL_IDX][0] <= 1'b0;
            end
            if(ctrl_wr_stop) begin
                config_status_reg[WR_CTRL_IDX][1] <= 1'b0;
            end
            if(ctrl_rd_start) begin
                config_status_reg[RD_CTRL_IDX][0] <= 1'b0;
            end
            if(ctrl_rd_stop) begin
                config_status_reg[RD_CTRL_IDX][1] <= 1'b0;
            end

            // set read-only registers to DMA status signals
            // Latch DONE bits (sticky)
            if (ctrl_wr_done)
                config_status_reg[STATUS_IDX][0] <= 1'b1;

            if (ctrl_rd_done)
                config_status_reg[STATUS_IDX][1] <= 1'b1;          
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

endmodule: snix_axi_dma_csr
module snix_axi_dma #(parameter int ADDR_WIDTH = 32,
                      parameter int DATA_WIDTH = 64,
                      parameter int AXIL_ADDR_WIDTH = 32,
                      parameter int AXIL_DATA_WIDTH = 32,
                      parameter int ID_WIDTH   = 4,
                      parameter int USER_WIDTH = 1)
                     (// Global signals
                      input logic                                 clk,
                      input logic                                 rst_n,

                      // AXI Lite Interface with prefix s_axil
                      input  logic [AXIL_ADDR_WIDTH-1:0]          s_axil_awaddr,
                      input  logic                                s_axil_awvalid,
                      output logic                                s_axil_awready,

                      input  logic [AXIL_DATA_WIDTH-1:0]          s_axil_wdata,
                      input  logic [AXIL_DATA_WIDTH/8-1:0]        s_axil_wstrb,
                      input  logic                                s_axil_wvalid,
                      output logic                                s_axil_wready,

                      output logic [1:0]                          s_axil_bresp, 
                      output logic                                s_axil_bvalid,
                      input  logic                                s_axil_bready,

                      input  logic [AXIL_ADDR_WIDTH-1:0]          s_axil_araddr,
                      input  logic                                s_axil_arvalid,
                      output logic                                s_axil_arready,

                      output logic [AXIL_DATA_WIDTH-1:0]          s_axil_rdata,
                      output logic [1:0]                          s_axil_rresp,
                      output logic                                s_axil_rvalid,
                      input  logic                                s_axil_rready,

                      // AXI-Stream input
                      input  logic [DATA_WIDTH-1:0]               s_axis_tdata,
                      input  logic                                s_axis_tvalid,
                      output logic                                s_axis_tready,
                      input  logic                                s_axis_tlast,

                      // AXI-Stream output
                      output logic [DATA_WIDTH-1:0]               m_axis_tdata,
                      output logic                                m_axis_tvalid,
                      input  logic                                m_axis_tready,
                      output  logic                               m_axis_tlast,

                      // AW Channel
                      output logic [ID_WIDTH-1:0]                 s2mm_awid,
                      output logic [ADDR_WIDTH-1:0]               s2mm_awaddr,
                      output logic [7:0]                          s2mm_awlen,
                      output logic [2:0]                          s2mm_awsize,
                      output logic [1:0]                          s2mm_awburst,
                      output logic                                s2mm_awlock,
                      output logic [3:0]                          s2mm_awcache,
                      output logic [2:0]                          s2mm_awprot,
                      output logic [3:0]                          s2mm_awqos,
                      output logic [USER_WIDTH-1:0]               s2mm_awuser,
                      output logic                                s2mm_awvalid,
                      input  logic                                s2mm_awready,

                      // W Channel
                      output logic [DATA_WIDTH-1:0]               s2mm_wdata,
                      output logic [DATA_WIDTH/8-1:0]             s2mm_wstrb,
                      output logic                                s2mm_wlast,
                      output logic [USER_WIDTH-1:0]               s2mm_wuser,
                      output logic                                s2mm_wvalid,
                      input  logic                                s2mm_wready,

                      // B Channel
                      input  logic [ID_WIDTH-1:0]                 s2mm_bid,
                      input  logic [1:0]                          s2mm_bresp,
                      input  logic [USER_WIDTH-1:0]               s2mm_buser,
                      input  logic                                s2mm_bvalid,
                      output logic                                s2mm_bready,

                      // AR Channel
                      output logic [ID_WIDTH-1:0]                 mm2s_arid,
                      output logic [ADDR_WIDTH-1:0]               mm2s_araddr,
                      output logic [7:0]                          mm2s_arlen,
                      output logic [2:0]                          mm2s_arsize,
                      output logic [1:0]                          mm2s_arburst,
                      output logic                                mm2s_arlock,
                      output logic [3:0]                          mm2s_arcache,
                      output logic [2:0]                          mm2s_arprot,
                      output logic [3:0]                          mm2s_arqos,
                      output logic [USER_WIDTH-1:0]               mm2s_aruser,
                      output logic                                mm2s_arvalid,
                      input  logic                                mm2s_arready,
                    
                      // R Channel
                      input  logic [ID_WIDTH-1:0]                 mm2s_rid,
                      input  logic [DATA_WIDTH-1:0]               mm2s_rdata,
                      input  logic [1:0]                          mm2s_rresp,
                      input  logic                                mm2s_rlast,
                      input  logic [USER_WIDTH-1:0]               mm2s_ruser,
                      input  logic                                mm2s_rvalid,
                      output logic                                mm2s_rready
                     );

    localparam NUM_REGS = 16;
    logic [NUM_REGS-1:0][AXIL_DATA_WIDTH-1:0] config_status_reg;
    logic [AXIL_DATA_WIDTH-1:0]               read_status_reg;
    

    // ---------------- WR side ----------------
    logic                  ctrl_wr_done;
    logic                  ctrl_wr_start;  
    logic                  ctrl_wr_stop;
    logic                  ctrl_wr_circular_mode;
    logic [2:0]            ctrl_wr_size;
    logic [7:0]            ctrl_wr_len;
    logic [31:0]           ctrl_wr_transfer_len;
    logic [ADDR_WIDTH-1:0] ctrl_wr_addr;

    // ---------------- RD side ----------------
    logic                  ctrl_rd_done;
    logic                  ctrl_rd_start; 
    logic                  ctrl_rd_stop;
    logic                  ctrl_rd_circular_mode;
    logic [2:0]            ctrl_rd_size;
    logic [7:0]            ctrl_rd_len;
    logic [31:0]           ctrl_rd_transfer_len;
    logic [ADDR_WIDTH-1:0] ctrl_rd_addr;

    localparam int WR_CTRL_IDX      = 0;  // 0x00
    localparam int WR_NUM_BYTES_IDX = 1;  // 0x04
    localparam int WR_ADDR_IDX      = 2;  // 0x08
    localparam int RD_CTRL_IDX      = 3;  // 0x0C
    localparam int RD_NUM_BYTES_IDX = 4;  // 0x10
    localparam int RD_ADDR_IDX      = 5;  // 0x14

    //localparam int STATUS_IDX    = 6;  // 0x18

    // WR_CTRL (reg[0])
    assign ctrl_wr_start         = config_status_reg[WR_CTRL_IDX][0];
    assign ctrl_wr_stop          = config_status_reg[WR_CTRL_IDX][1];
    assign ctrl_wr_circular_mode = config_status_reg[WR_CTRL_IDX][2];
    assign ctrl_wr_size          = config_status_reg[WR_CTRL_IDX][5:3];
    assign ctrl_wr_len           = config_status_reg[WR_CTRL_IDX][13:6];

    // WR_NUM_BYTES (reg[1])
    assign ctrl_wr_transfer_len  = config_status_reg[WR_NUM_BYTES_IDX]; // 'd4

    // WR_ADDR (reg[2])
    assign ctrl_wr_addr          = config_status_reg[WR_ADDR_IDX][ADDR_WIDTH-1:0];

    // RD_CTRL (reg[3])
    assign ctrl_rd_start         = config_status_reg[RD_CTRL_IDX][0];
    assign ctrl_rd_stop          = config_status_reg[RD_CTRL_IDX][1];
    assign ctrl_rd_circular_mode = config_status_reg[RD_CTRL_IDX][2];
    assign ctrl_rd_size          = config_status_reg[RD_CTRL_IDX][5:3];
    assign ctrl_rd_len           = config_status_reg[RD_CTRL_IDX][13:6];

    // RD_NUM_BYTES (reg[4])
    assign ctrl_rd_transfer_len  = config_status_reg[RD_NUM_BYTES_IDX];

    // RD_ADDR (reg[5])
    assign ctrl_rd_addr          = config_status_reg[RD_ADDR_IDX][ADDR_WIDTH-1:0];

    // STATUS (reg[6])
    assign read_status_reg       = {30'b0, ctrl_rd_done, ctrl_wr_done};

    snix_axi_dma_csr #(.DATA_WIDTH(AXIL_DATA_WIDTH),
                       .ADDR_WIDTH(AXIL_ADDR_WIDTH),
                       .NUM_REGS(NUM_REGS)) 
                    dma_csr    (.clk(clk),
                                .rst_n(rst_n),

                                .s_axil_awaddr(s_axil_awaddr),
                                .s_axil_awvalid(s_axil_awvalid),
                                .s_axil_awready(s_axil_awready),

                                .s_axil_wdata(s_axil_wdata),
                                .s_axil_wstrb(s_axil_wstrb),
                                .s_axil_wvalid(s_axil_wvalid),
                                .s_axil_wready(s_axil_wready),

                                .s_axil_bresp(s_axil_bresp),
                                .s_axil_bvalid(s_axil_bvalid),
                                .s_axil_bready(s_axil_bready),

                                .s_axil_araddr(s_axil_araddr),
                                .s_axil_arvalid(s_axil_arvalid),
                                .s_axil_arready(s_axil_arready),

                                .s_axil_rdata(s_axil_rdata),
                                .s_axil_rresp(s_axil_rresp),
                                .s_axil_rvalid(s_axil_rvalid),
                                .s_axil_rready(s_axil_rready),

                                .read_status_reg(read_status_reg),
                                .config_status_reg(config_status_reg)
                               );


    localparam int FIFO_DEPTH_S2MM = 16;
    localparam int FIFO_DEPTH_MM2S = 16;
    
   
    snix_axi_s2mm #(.ADDR_WIDTH(ADDR_WIDTH),
                    .DATA_WIDTH(DATA_WIDTH),
                    .ID_WIDTH(ID_WIDTH),
                    .USER_WIDTH(USER_WIDTH),
                    .FIFO_DEPTH(FIFO_DEPTH_S2MM))

               axi_s2mm(.clk(clk),
                        .rst_n(rst_n),
                        
                        .ctrl_wr_start(ctrl_wr_start),
                        .ctrl_wr_stop(ctrl_wr_stop),
                        .ctrl_wr_addr(ctrl_wr_addr),
                        .ctrl_wr_len(ctrl_wr_len),
                        .ctrl_wr_size(ctrl_wr_size),
                        .ctrl_wr_transfer_len(ctrl_wr_transfer_len),
                        .ctrl_wr_circular_mode(ctrl_wr_circular_mode),
                        .ctrl_wr_done(ctrl_wr_done),

                        .s_axis_tdata(s_axis_tdata),
                        .s_axis_tvalid(s_axis_tvalid),
                        .s_axis_tready(s_axis_tready),
                        .s_axis_tlast(s_axis_tlast),

                        
                        .s2mm_awid(s2mm_awid), 
                        .s2mm_awaddr(s2mm_awaddr), 
                        .s2mm_awlen(s2mm_awlen), 
                        .s2mm_awsize(s2mm_awsize), 
                        .s2mm_awburst(s2mm_awburst),
                        .s2mm_awlock(s2mm_awlock), 
                        .s2mm_awcache(s2mm_awcache), 
                        .s2mm_awprot(s2mm_awprot), 
                        .s2mm_awqos(s2mm_awqos), 
                        .s2mm_awuser(s2mm_awuser),
                        .s2mm_awvalid(s2mm_awvalid),
                        .s2mm_awready(s2mm_awready),

                        .s2mm_wdata(s2mm_wdata),
                        .s2mm_wstrb(s2mm_wstrb),
                        .s2mm_wlast(s2mm_wlast), 
                        .s2mm_wuser(s2mm_wuser), 
                        .s2mm_wvalid(s2mm_wvalid),
                        .s2mm_wready(s2mm_wready),

                        .s2mm_bid(s2mm_bid), 
                        .s2mm_bresp(s2mm_bresp), 
                        .s2mm_buser(s2mm_buser), 
                        .s2mm_bvalid(s2mm_bvalid),
                        .s2mm_bready(s2mm_bready)
                        );

    snix_axi_mm2s #(.ADDR_WIDTH(ADDR_WIDTH),
                    .DATA_WIDTH(DATA_WIDTH),
                    .ID_WIDTH(ID_WIDTH),
                    .USER_WIDTH(USER_WIDTH),
                    .FIFO_DEPTH(FIFO_DEPTH_MM2S))

               axi_mm2s(.clk(clk),
                        .rst_n(rst_n),
                        
                        .ctrl_rd_start(ctrl_rd_start),
                        .ctrl_rd_stop(ctrl_rd_stop),
                        .ctrl_rd_addr(ctrl_rd_addr),
                        .ctrl_rd_len(ctrl_rd_len),
                        .ctrl_rd_size(ctrl_rd_size),
                        .ctrl_rd_transfer_len(ctrl_rd_transfer_len),
                        .ctrl_rd_circular_mode(ctrl_rd_circular_mode),
                        .ctrl_rd_done(ctrl_rd_done),

                        .m_axis_tdata(m_axis_tdata),
                        .m_axis_tvalid(m_axis_tvalid),
                        .m_axis_tready(m_axis_tready),
                        .m_axis_tlast(m_axis_tlast),

                        
                        .mm2s_arid(mm2s_arid), 
                        .mm2s_araddr(mm2s_araddr), 
                        .mm2s_arlen(mm2s_arlen), 
                        .mm2s_arsize(mm2s_arsize), 
                        .mm2s_arburst(mm2s_arburst),
                        .mm2s_arlock(mm2s_arlock), 
                        .mm2s_arcache(mm2s_arcache), 
                        .mm2s_arprot(mm2s_arprot), 
                        .mm2s_arqos(mm2s_arqos), 
                        .mm2s_aruser(mm2s_aruser),
                        .mm2s_arvalid(mm2s_arvalid),
                        .mm2s_arready(mm2s_arready),

                        .mm2s_rid(mm2s_rid),
                        .mm2s_rdata(mm2s_rdata),
                        .mm2s_rresp(mm2s_rresp),
                        .mm2s_rlast(mm2s_rlast), 
                        .mm2s_ruser(mm2s_ruser), 
                        .mm2s_rvalid(mm2s_rvalid),
                        .mm2s_rready(mm2s_rready)
                        );




endmodule: snix_axi_dma

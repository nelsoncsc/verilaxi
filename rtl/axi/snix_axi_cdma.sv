// ============================================================================
//  snix_axi_cdma.sv
//  Central DMA — memory-to-memory transfers via snix_axi_mm2mm
//
//  Instantiates:
//    snix_axi_cdma_csr  — AXI-Lite register interface
//    snix_axi_mm2mm     — read-then-write AXI4 engine
//
//  Software register map (see snix_axi_cdma_csr.sv for full detail):
//    0x00  CDMA_CTRL      [0]=start [1]=stop [5:3]=size [13:6]=len
//    0x04  CDMA_NUM_BYTES [31:0]=transfer_len
//    0x08  CDMA_SRC_ADDR  [31:0]=source base address
//    0x0C  CDMA_DST_ADDR  [31:0]=destination base address
//    0x10  STATUS         [0]=done (sticky, read-only)
// ============================================================================
module snix_axi_cdma #(
    parameter int ADDR_WIDTH      = 32,
    parameter int DATA_WIDTH      = 64,
    parameter int AXIL_ADDR_WIDTH = 32,
    parameter int AXIL_DATA_WIDTH = 32,
    parameter int ID_WIDTH        = 4,
    parameter int USER_WIDTH      = 1)
   (// Global signals
    input  logic                             clk,
    input  logic                             rst_n,
    // AXI-Lite CSR interface
    input  logic [AXIL_ADDR_WIDTH-1:0]       s_axil_awaddr,
    input  logic                             s_axil_awvalid,
    output logic                             s_axil_awready,
    input  logic [AXIL_DATA_WIDTH-1:0]       s_axil_wdata,
    input  logic [AXIL_DATA_WIDTH/8-1:0]     s_axil_wstrb,
    input  logic                             s_axil_wvalid,
    output logic                             s_axil_wready,
    output logic [1:0]                       s_axil_bresp,
    output logic                             s_axil_bvalid,
    input  logic                             s_axil_bready,
    input  logic [AXIL_ADDR_WIDTH-1:0]       s_axil_araddr,
    input  logic                             s_axil_arvalid,
    output logic                             s_axil_arready,
    output logic [AXIL_DATA_WIDTH-1:0]       s_axil_rdata,
    output logic [1:0]                       s_axil_rresp,
    output logic                             s_axil_rvalid,
    input  logic                             s_axil_rready,
    // AXI4 memory port — AW channel
    output logic [ID_WIDTH-1:0]              mm2mm_awid,
    output logic [ADDR_WIDTH-1:0]            mm2mm_awaddr,
    output logic [7:0]                       mm2mm_awlen,
    output logic [2:0]                       mm2mm_awsize,
    output logic [1:0]                       mm2mm_awburst,
    output logic                             mm2mm_awlock,
    output logic [3:0]                       mm2mm_awcache,
    output logic [2:0]                       mm2mm_awprot,
    output logic [3:0]                       mm2mm_awqos,
    output logic [USER_WIDTH-1:0]            mm2mm_awuser,
    output logic                             mm2mm_awvalid,
    input  logic                             mm2mm_awready,
    // W channel
    output logic [DATA_WIDTH-1:0]            mm2mm_wdata,
    output logic [DATA_WIDTH/8-1:0]          mm2mm_wstrb,
    output logic                             mm2mm_wlast,
    output logic [USER_WIDTH-1:0]            mm2mm_wuser,
    output logic                             mm2mm_wvalid,
    input  logic                             mm2mm_wready,
    // B channel
    input  logic [ID_WIDTH-1:0]              mm2mm_bid,
    input  logic [1:0]                       mm2mm_bresp,
    input  logic [USER_WIDTH-1:0]            mm2mm_buser,
    input  logic                             mm2mm_bvalid,
    output logic                             mm2mm_bready,
    // AR channel
    output logic [ID_WIDTH-1:0]              mm2mm_arid,
    output logic [ADDR_WIDTH-1:0]            mm2mm_araddr,
    output logic [7:0]                       mm2mm_arlen,
    output logic [2:0]                       mm2mm_arsize,
    output logic [1:0]                       mm2mm_arburst,
    output logic                             mm2mm_arlock,
    output logic [3:0]                       mm2mm_arcache,
    output logic [2:0]                       mm2mm_arprot,
    output logic [3:0]                       mm2mm_arqos,
    output logic [USER_WIDTH-1:0]            mm2mm_aruser,
    output logic                             mm2mm_arvalid,
    input  logic                             mm2mm_arready,
    // R channel
    input  logic [ID_WIDTH-1:0]              mm2mm_rid,
    input  logic [DATA_WIDTH-1:0]            mm2mm_rdata,
    input  logic [1:0]                       mm2mm_rresp,
    input  logic                             mm2mm_rlast,
    input  logic [USER_WIDTH-1:0]            mm2mm_ruser,
    input  logic                             mm2mm_rvalid,
    output logic                             mm2mm_rready);

localparam int NUM_REGS   = 8;
localparam int FIFO_DEPTH = 16;

localparam int CDMA_CTRL_IDX      = 0;
localparam int CDMA_NUM_BYTES_IDX = 1;
localparam int CDMA_SRC_ADDR_IDX  = 2;
localparam int CDMA_DST_ADDR_IDX  = 3;
// Index 4 = STATUS — write-protected inside snix_axi_cdma_csr

    logic [NUM_REGS-1:0][AXIL_DATA_WIDTH-1:0] config_status_reg;
    logic [AXIL_DATA_WIDTH-1:0]               read_status_reg;

// -------------------------------------------------------------------------
// Decode control registers
// -------------------------------------------------------------------------
    logic                  ctrl_start, ctrl_stop;
    logic [2:0]            ctrl_size;
    logic [7:0]            ctrl_len;
    logic [31:0]           ctrl_transfer_len;
    logic [ADDR_WIDTH-1:0] ctrl_src_addr, ctrl_dst_addr;
    logic                  ctrl_done;

assign ctrl_start        = config_status_reg[CDMA_CTRL_IDX][0];
assign ctrl_stop         = config_status_reg[CDMA_CTRL_IDX][1];
assign ctrl_size         = config_status_reg[CDMA_CTRL_IDX][5:3];
assign ctrl_len          = config_status_reg[CDMA_CTRL_IDX][13:6];
assign ctrl_transfer_len = config_status_reg[CDMA_NUM_BYTES_IDX];
assign ctrl_src_addr     = config_status_reg[CDMA_SRC_ADDR_IDX][ADDR_WIDTH-1:0];
assign ctrl_dst_addr     = config_status_reg[CDMA_DST_ADDR_IDX][ADDR_WIDTH-1:0];

assign read_status_reg   = {{(AXIL_DATA_WIDTH-1){1'b0}}, ctrl_done};

// -------------------------------------------------------------------------
// CSR
// -------------------------------------------------------------------------
snix_axi_cdma_csr #(
    .DATA_WIDTH(AXIL_DATA_WIDTH),
    .ADDR_WIDTH(AXIL_ADDR_WIDTH),
    .NUM_REGS  (NUM_REGS))
cdma_csr (
    .clk               (clk),
    .rst_n             (rst_n),
    .s_axil_awaddr     (s_axil_awaddr),
    .s_axil_awvalid    (s_axil_awvalid),
    .s_axil_awready    (s_axil_awready),
    .s_axil_wdata      (s_axil_wdata),
    .s_axil_wstrb      (s_axil_wstrb),
    .s_axil_wvalid     (s_axil_wvalid),
    .s_axil_wready     (s_axil_wready),
    .s_axil_bresp      (s_axil_bresp),
    .s_axil_bvalid     (s_axil_bvalid),
    .s_axil_bready     (s_axil_bready),
    .s_axil_araddr     (s_axil_araddr),
    .s_axil_arvalid    (s_axil_arvalid),
    .s_axil_arready    (s_axil_arready),
    .s_axil_rdata      (s_axil_rdata),
    .s_axil_rresp      (s_axil_rresp),
    .s_axil_rvalid     (s_axil_rvalid),
    .s_axil_rready     (s_axil_rready),
    .read_status_reg   (read_status_reg),
    .config_status_reg (config_status_reg));

// -------------------------------------------------------------------------
// MM2MM engine
// -------------------------------------------------------------------------
snix_axi_mm2mm #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .DATA_WIDTH(DATA_WIDTH),
    .ID_WIDTH  (ID_WIDTH),
    .USER_WIDTH(USER_WIDTH),
    .FIFO_DEPTH(FIFO_DEPTH))
axi_mm2mm (
    .clk              (clk),
    .rst_n            (rst_n),
    .ctrl_start       (ctrl_start),
    .ctrl_stop        (ctrl_stop),
    .ctrl_src_addr    (ctrl_src_addr),
    .ctrl_dst_addr    (ctrl_dst_addr),
    .ctrl_len         (ctrl_len),
    .ctrl_size        (ctrl_size),
    .ctrl_transfer_len(ctrl_transfer_len),
    .ctrl_done        (ctrl_done),
    .mm2mm_awid       (mm2mm_awid),
    .mm2mm_awaddr     (mm2mm_awaddr),
    .mm2mm_awlen      (mm2mm_awlen),
    .mm2mm_awsize     (mm2mm_awsize),
    .mm2mm_awburst    (mm2mm_awburst),
    .mm2mm_awlock     (mm2mm_awlock),
    .mm2mm_awcache    (mm2mm_awcache),
    .mm2mm_awprot     (mm2mm_awprot),
    .mm2mm_awqos      (mm2mm_awqos),
    .mm2mm_awuser     (mm2mm_awuser),
    .mm2mm_awvalid    (mm2mm_awvalid),
    .mm2mm_awready    (mm2mm_awready),
    .mm2mm_wdata      (mm2mm_wdata),
    .mm2mm_wstrb      (mm2mm_wstrb),
    .mm2mm_wlast      (mm2mm_wlast),
    .mm2mm_wuser      (mm2mm_wuser),
    .mm2mm_wvalid     (mm2mm_wvalid),
    .mm2mm_wready     (mm2mm_wready),
    .mm2mm_bid        (mm2mm_bid),
    .mm2mm_bresp      (mm2mm_bresp),
    .mm2mm_buser      (mm2mm_buser),
    .mm2mm_bvalid     (mm2mm_bvalid),
    .mm2mm_bready     (mm2mm_bready),
    .mm2mm_arid       (mm2mm_arid),
    .mm2mm_araddr     (mm2mm_araddr),
    .mm2mm_arlen      (mm2mm_arlen),
    .mm2mm_arsize     (mm2mm_arsize),
    .mm2mm_arburst    (mm2mm_arburst),
    .mm2mm_arlock     (mm2mm_arlock),
    .mm2mm_arcache    (mm2mm_arcache),
    .mm2mm_arprot     (mm2mm_arprot),
    .mm2mm_arqos      (mm2mm_arqos),
    .mm2mm_aruser     (mm2mm_aruser),
    .mm2mm_arvalid    (mm2mm_arvalid),
    .mm2mm_arready    (mm2mm_arready),
    .mm2mm_rid        (mm2mm_rid),
    .mm2mm_rdata      (mm2mm_rdata),
    .mm2mm_rresp      (mm2mm_rresp),
    .mm2mm_rlast      (mm2mm_rlast),
    .mm2mm_ruser      (mm2mm_ruser),
    .mm2mm_rvalid     (mm2mm_rvalid),
    .mm2mm_rready     (mm2mm_rready));

endmodule : snix_axi_cdma

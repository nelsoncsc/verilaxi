// ============================================================================
//  snix_axi_cdma_csr.sv
//  AXI-Lite CSR for snix_axi_cdma (memory-to-memory central DMA)
//
//  Register Map (word-addressed, 32-bit registers):
//
//   Offset  Index  Name               Bits
//   0x00    0      CDMA_CTRL          [0]     = start (write-1 pulse)
//                                     [1]     = stop  (write-1 pulse)
//                                     [5:3]   = size  (AXI AxSIZE)
//                                     [13:6]  = len   (AXI AxLEN)
//                                     [31:14] = reserved
//   0x04    1      CDMA_NUM_BYTES     [31:0]  = transfer_len (byte count)
//   0x08    2      CDMA_SRC_ADDR      [31:0]  = source base address
//   0x0C    3      CDMA_DST_ADDR      [31:0]  = destination base address
//   0x10    4      STATUS (read-only) [0]     = done (sticky; cleared on start)
//                                     [31:1]  = reserved
//   0x14–   5–7    Reserved
//
//  Differences from snix_axi_dma_csr:
//   - Single CTRL register (no separate WR/RD paths)
//   - Separate SRC_ADDR and DST_ADDR registers
//   - STATUS[0] is write-protected; hardware sets it, start clears it
// ============================================================================
module snix_axi_cdma_csr #(
    parameter int DATA_WIDTH = 32,
    parameter int ADDR_WIDTH = 4,
    parameter int NUM_REGS   = 8)
   (input  logic                                clk,
    input  logic                                rst_n,
    // AXI-Lite interface
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
    // Status from mm2mm engine: [0] = ctrl_done (single-cycle pulse)
    input  logic [DATA_WIDTH-1:0]               read_status_reg,
    // Register file
    output logic [NUM_REGS-1:0][DATA_WIDTH-1:0] config_status_reg);

localparam int AXIL_DATA_WIDTH = DATA_WIDTH;
localparam int AXIL_ADDR_WIDTH = ADDR_WIDTH;
localparam int ADDRLSB         = $clog2(AXIL_DATA_WIDTH / 8);
localparam int REG_INDEX_WIDTH = $clog2(NUM_REGS);

localparam int CDMA_CTRL_IDX      = 0;  // 0x00  used: pulse-clear start/stop bits
//localparam int CDMA_NUM_BYTES_IDX = 1;  // 0x04  decoded in snix_axi_cdma top
//localparam int CDMA_SRC_ADDR_IDX  = 2;  // 0x08  decoded in snix_axi_cdma top
//localparam int CDMA_DST_ADDR_IDX  = 3;  // 0x0C  decoded in snix_axi_cdma top
localparam int STATUS_IDX         = 4;  // 0x10  used: write-protect + done latch

// -------------------------------------------------------------------------
// AXI-Lite skid-buffer register slices (same topology as snix_axi_dma_csr)
// -------------------------------------------------------------------------
    logic                               s_axil_awvalid_reg;
    logic [AXIL_ADDR_WIDTH-ADDRLSB-1:0] s_axil_awaddr_reg;
    logic                               s_axil_arvalid_reg;
    logic [AXIL_ADDR_WIDTH-ADDRLSB-1:0] s_axil_araddr_reg;
    logic                               s_axil_wvalid_reg;
    logic [AXIL_DATA_WIDTH-1:0]         s_axil_wdata_reg;
    logic [AXIL_DATA_WIDTH/8-1:0]       s_axil_wstrb_reg;

    logic        s_axil_write_ready, s_axil_read_ready;
    logic [31:0] awaddr_index, araddr_index;

assign s_axil_write_ready = s_axil_awvalid_reg & s_axil_wvalid_reg &
                            (!s_axil_bvalid | s_axil_bready);
assign s_axil_read_ready  = s_axil_arvalid_reg & (!s_axil_rvalid | s_axil_rready);

assign awaddr_index = {{(32-REG_INDEX_WIDTH){1'b0}}, s_axil_awaddr_reg[REG_INDEX_WIDTH-1:0]};
assign araddr_index = {{(32-REG_INDEX_WIDTH){1'b0}}, s_axil_araddr_reg[REG_INDEX_WIDTH-1:0]};

snix_register_slice #(.DATA_WIDTH(AXIL_ADDR_WIDTH - ADDRLSB)) reg_slice_u0 (
    .clk          (clk),
    .rst_n        (rst_n),
    .s_axis_tdata (s_axil_awaddr[AXIL_ADDR_WIDTH-1:ADDRLSB]),
    .s_axis_tvalid(s_axil_awvalid),
    .s_axis_tready(s_axil_awready),
    .m_axis_tdata (s_axil_awaddr_reg),
    .m_axis_tvalid(s_axil_awvalid_reg),
    .m_axis_tready(s_axil_write_ready));

snix_register_slice #(.DATA_WIDTH(AXIL_DATA_WIDTH + AXIL_DATA_WIDTH/8)) reg_slice_u1 (
    .clk          (clk),
    .rst_n        (rst_n),
    .s_axis_tdata ({s_axil_wdata, s_axil_wstrb}),
    .s_axis_tvalid(s_axil_wvalid),
    .s_axis_tready(s_axil_wready),
    .m_axis_tdata ({s_axil_wdata_reg, s_axil_wstrb_reg}),
    .m_axis_tvalid(s_axil_wvalid_reg),
    .m_axis_tready(s_axil_write_ready));

snix_register_slice #(.DATA_WIDTH(AXIL_ADDR_WIDTH - ADDRLSB)) reg_slice_u2 (
    .clk          (clk),
    .rst_n        (rst_n),
    .s_axis_tdata (s_axil_araddr[AXIL_ADDR_WIDTH-1:ADDRLSB]),
    .s_axis_tvalid(s_axil_arvalid),
    .s_axis_tready(s_axil_arready),
    .m_axis_tdata (s_axil_araddr_reg),
    .m_axis_tvalid(s_axil_arvalid_reg),
    .m_axis_tready(s_axil_read_ready));

// -------------------------------------------------------------------------
// B channel
// -------------------------------------------------------------------------
always_ff @(posedge clk or negedge rst_n)
    if (!rst_n)                  s_axil_bvalid <= 1'b0;
    else if (s_axil_write_ready) s_axil_bvalid <= 1'b1;
    else if (s_axil_bready)      s_axil_bvalid <= 1'b0;

// -------------------------------------------------------------------------
// R channel
// -------------------------------------------------------------------------
always_ff @(posedge clk or negedge rst_n)
    if (!rst_n)                 s_axil_rvalid <= 1'b0;
    else if (s_axil_read_ready) s_axil_rvalid <= 1'b1;
    else if (s_axil_rready)     s_axil_rvalid <= 1'b0;

// -------------------------------------------------------------------------
// Control / status signal aliases (combinatorial from register file)
// -------------------------------------------------------------------------
    logic ctrl_start, ctrl_stop, ctrl_done;

assign ctrl_start = config_status_reg[CDMA_CTRL_IDX][0];
assign ctrl_stop  = config_status_reg[CDMA_CTRL_IDX][1];
assign ctrl_done  = read_status_reg[0];

// -------------------------------------------------------------------------
// Register file
//
// Write priority (highest to lowest within an always_ff block):
//   1. AXI-Lite write (byte-enable; STATUS_IDX is write-protected)
//   2. Pulse-clear: start[0] and stop[1] are single-cycle strobes
//   3. STATUS latch: done bit set by hardware, cleared when start fires
//
// Note on NBA priority: later assignments in program order win, so
// "config_status_reg <= config_status_reg" is safely overridden by
// the per-bit assignments that follow in the else branch.
// -------------------------------------------------------------------------
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        config_status_reg <= '0;

    end else if (s_axil_write_ready &&
                 awaddr_index < NUM_REGS &&
                 awaddr_index != STATUS_IDX) begin   // STATUS is read-only
        for (int i = 0; i < AXIL_DATA_WIDTH/8; i++) begin
            config_status_reg[awaddr_index][8*i +: 8] <=
                s_axil_wstrb_reg[i] ? s_axil_wdata_reg[8*i +: 8]
                                    : config_status_reg[awaddr_index][8*i +: 8];
        end

    end else begin
        config_status_reg <= config_status_reg;

        // Pulse-clear: start and stop are one-cycle strobes
        if (ctrl_start) config_status_reg[CDMA_CTRL_IDX][0] <= 1'b0;
        if (ctrl_stop)  config_status_reg[CDMA_CTRL_IDX][1] <= 1'b0;

        // STATUS[0]: cleared when a new transfer starts; set sticky on done
        if (ctrl_start) config_status_reg[STATUS_IDX][0] <= 1'b0;
        if (ctrl_done)  config_status_reg[STATUS_IDX][0] <= 1'b1;
    end
end

// -------------------------------------------------------------------------
// Read data mux
// -------------------------------------------------------------------------
always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        s_axil_rdata <= '0;
    else if (s_axil_read_ready && araddr_index < NUM_REGS)
        s_axil_rdata <= config_status_reg[araddr_index];
end

assign s_axil_bresp = 2'b00;
assign s_axil_rresp = 2'b00;

endmodule : snix_axi_cdma_csr

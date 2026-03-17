// =============================================================================
// snix_axi_mm2mm.sv
//
// Memory-to-Memory DMA Engine
// - Reads from source address, writes to destination address
// - Handles 4K boundary crossing on both read and write sides
// - Supports partial last beat with correct wstrb
// - Decoupled read/write with internal FIFO
//
// Architecture:
//   AR FSM → R Data → FIFO → W Data → AW FSM
//                              ↓
//                         B Response
// =============================================================================

module snix_axi_mm2mm #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 64,
    parameter int ID_WIDTH   = 4,
    parameter int USER_WIDTH = 1,
    parameter int FIFO_DEPTH = 16
)(
    // Global signals
    input  logic                     clk,
    input  logic                     rst_n,
    
    // Control interface (from CSR)
    input  logic                     ctrl_start,
    input  logic                     ctrl_stop,
    input  logic [ADDR_WIDTH-1:0]    ctrl_src_addr,
    input  logic [ADDR_WIDTH-1:0]    ctrl_dst_addr,
    input  logic [7:0]               ctrl_len,
    input  logic [2:0]               ctrl_size,
    input  logic [31:0]              ctrl_transfer_len,
    output logic                     ctrl_done,
    output logic                     ctrl_error,
    
    // AXI Read Channel (to RD Arbiter)
    output logic [ID_WIDTH-1:0]      mm2mm_arid,
    output logic [ADDR_WIDTH-1:0]    mm2mm_araddr,
    output logic [7:0]               mm2mm_arlen,
    output logic [2:0]               mm2mm_arsize,
    output logic [1:0]               mm2mm_arburst,
    output logic                     mm2mm_arlock,
    output logic [3:0]               mm2mm_arcache,
    output logic [2:0]               mm2mm_arprot,
    output logic [3:0]               mm2mm_arqos,
    output logic [USER_WIDTH-1:0]    mm2mm_aruser,
    output logic                     mm2mm_arvalid,
    input  logic                     mm2mm_arready,
    
    input  logic [ID_WIDTH-1:0]      mm2mm_rid,
    input  logic [DATA_WIDTH-1:0]    mm2mm_rdata,
    input  logic [1:0]               mm2mm_rresp,
    input  logic                     mm2mm_rlast,
    input  logic [USER_WIDTH-1:0]    mm2mm_ruser,
    input  logic                     mm2mm_rvalid,
    output logic                     mm2mm_rready,
    
    // AXI Write Channel (to WR Arbiter)
    output logic [ID_WIDTH-1:0]      mm2mm_awid,
    output logic [ADDR_WIDTH-1:0]    mm2mm_awaddr,
    output logic [7:0]               mm2mm_awlen,
    output logic [2:0]               mm2mm_awsize,
    output logic [1:0]               mm2mm_awburst,
    output logic                     mm2mm_awlock,
    output logic [3:0]               mm2mm_awcache,
    output logic [2:0]               mm2mm_awprot,
    output logic [3:0]               mm2mm_awqos,
    output logic [USER_WIDTH-1:0]    mm2mm_awuser,
    output logic                     mm2mm_awvalid,
    input  logic                     mm2mm_awready,
    
    output logic [DATA_WIDTH-1:0]    mm2mm_wdata,
    output logic [DATA_WIDTH/8-1:0]  mm2mm_wstrb,
    output logic                     mm2mm_wlast,
    output logic [USER_WIDTH-1:0]    mm2mm_wuser,
    output logic                     mm2mm_wvalid,
    input  logic                     mm2mm_wready,
    
    input  logic [ID_WIDTH-1:0]      mm2mm_bid,
    input  logic [1:0]               mm2mm_bresp,
    input  logic [USER_WIDTH-1:0]    mm2mm_buser,
    input  logic                     mm2mm_bvalid,
    output logic                     mm2mm_bready
);

    // =========================================================================
    // Local parameters
    // =========================================================================
    localparam int STRB_WIDTH = DATA_WIDTH / 8;

    // =========================================================================
    // Start/Stop edge detection
    // =========================================================================
    logic ctrl_start_r, start_edge;
    logic ctrl_stop_r, stop_edge;
    
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            ctrl_start_r <= 1'b0;
            ctrl_stop_r  <= 1'b0;
        end else begin
            ctrl_start_r <= ctrl_start;
            ctrl_stop_r  <= ctrl_stop;
        end
    
    assign start_edge = ctrl_start & ~ctrl_start_r;
    assign stop_edge  = ctrl_stop & ~ctrl_stop_r;

    // =========================================================================
    // Abort latch
    // =========================================================================
    logic abort;
    
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n)           abort <= 1'b0;
        else if (stop_edge)   abort <= 1'b1;
        else if (start_edge)  abort <= 1'b0;

    // =========================================================================
    // Read FSM
    // =========================================================================
    typedef enum logic [2:0] {
        RD_IDLE,
        RD_PREP1,
        RD_PREP2,
        RD_AR,
        RD_READ,
        RD_DONE
    } rd_state_t;
    
    rd_state_t rd_state, rd_next_state;
    
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) rd_state <= RD_IDLE;
        else        rd_state <= rd_next_state;

    // Read state machine logic
    // TODO: Implement similar to MM2S
    // - Track rd_pending_bytes
    // - Compute burst lengths with 4K boundary
    // - Issue AR, receive R data
    // - Push data to internal FIFO

    // =========================================================================
    // Write FSM
    // =========================================================================
    typedef enum logic [2:0] {
        WR_IDLE,
        WR_WAIT,    // Wait for FIFO data
        WR_PREP1,
        WR_PREP2,
        WR_AW,
        WR_WRITE,
        WR_BRESP
    } wr_state_t;
    
    wr_state_t wr_state, wr_next_state;
    
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) wr_state <= WR_IDLE;
        else        wr_state <= wr_next_state;

    // Write state machine logic
    // TODO: Implement similar to S2MM
    // - Track wr_pending_bytes
    // - Compute burst lengths with 4K boundary
    // - Generate correct wstrb for partial last beat
    // - Pop data from FIFO, issue AW/W

    // =========================================================================
    // Internal FIFO (Read data → Write data)
    // =========================================================================
    logic [DATA_WIDTH-1:0] fifo_wdata;
    logic                  fifo_wvalid;
    logic                  fifo_wready;
    logic [DATA_WIDTH-1:0] fifo_rdata;
    logic                  fifo_rvalid;
    logic                  fifo_rready;
    logic                  fifo_rlast;
    
    // Instantiate FIFO
    snix_axis_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) data_fifo (
        .clk           (clk),
        .rst_n         (rst_n),
        .s_axis_tdata  (mm2mm_rdata),
        .s_axis_tlast  (mm2mm_rlast),
        .s_axis_tuser  (1'b0),
        .s_axis_tvalid (mm2mm_rvalid && (rd_state == RD_READ)),
        .s_axis_tready (fifo_wready),
        .m_axis_tdata  (fifo_rdata),
        .m_axis_tlast  (fifo_rlast),
        .m_axis_tuser  (),
        .m_axis_tvalid (fifo_rvalid),
        .m_axis_tready (fifo_rready)
    );

    // =========================================================================
    // Transfer tracking
    // =========================================================================
    logic [31:0] rd_bytes_done;
    logic [31:0] wr_bytes_done;
    logic [31:0] transfer_len_reg;
    
    logic rd_complete;
    logic wr_complete;
    
    assign rd_complete = (rd_bytes_done == transfer_len_reg) && (rd_bytes_done != '0);
    assign wr_complete = (wr_bytes_done == transfer_len_reg) && (wr_bytes_done != '0);

    // =========================================================================
    // Done/Error outputs
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            ctrl_done  <= 1'b0;
            ctrl_error <= 1'b0;
        end else begin
            // Done: single-cycle pulse when write completes
            ctrl_done <= (wr_state != WR_IDLE) && (wr_next_state == WR_IDLE) && !abort;
            
            // Error: latch on bad response
            if (start_edge)
                ctrl_error <= 1'b0;
            else if (mm2mm_rvalid && mm2mm_rready && (mm2mm_rresp != 2'b00))
                ctrl_error <= 1'b1;
            else if (mm2mm_bvalid && mm2mm_bready && (mm2mm_bresp != 2'b00))
                ctrl_error <= 1'b1;
        end

    // =========================================================================
    // AXI signal defaults
    // =========================================================================
    assign mm2mm_arburst = 2'b01;  // INCR
    assign mm2mm_arlock  = 1'b0;
    assign mm2mm_arcache = 4'b0011; // Bufferable
    assign mm2mm_arprot  = 3'b0;
    assign mm2mm_arqos   = 4'b0;
    assign mm2mm_arid    = '0;
    assign mm2mm_aruser  = '0;
    
    assign mm2mm_awburst = 2'b01;  // INCR
    assign mm2mm_awlock  = 1'b0;
    assign mm2mm_awcache = 4'b0011; // Bufferable
    assign mm2mm_awprot  = 3'b0;
    assign mm2mm_awqos   = 4'b0;
    assign mm2mm_awid    = '0;
    assign mm2mm_awuser  = '0;
    assign mm2mm_wuser   = '0;

    // =========================================================================
    // TODO: Complete implementation
    //
    // The following needs to be implemented:
    //
    // 1. Read FSM (rd_next_state logic):
    //    - RD_IDLE: Wait for start_edge
    //    - RD_PREP1: Stage 1 of burst calculation (4K boundary)
    //    - RD_PREP2: Stage 2 of burst calculation
    //    - RD_AR: Issue AR, wait for arready
    //    - RD_READ: Receive R data, push to FIFO
    //    - Loop back to RD_PREP1 until rd_complete
    //
    // 2. Write FSM (wr_next_state logic):
    //    - WR_IDLE: Wait for start_edge
    //    - WR_WAIT: Wait for FIFO to have enough data
    //    - WR_PREP1: Stage 1 of burst calculation
    //    - WR_PREP2: Stage 2 of burst calculation
    //    - WR_AW: Issue AW, wait for awready
    //    - WR_WRITE: Send W data from FIFO
    //    - WR_BRESP: Wait for B response
    //    - Loop back to WR_WAIT until wr_complete
    //
    // 3. Burst calculation (same as S2MM/MM2S):
    //    - compute_num_bytes()
    //    - compute_next_len()
    //    - 4K boundary handling
    //
    // 4. WSTRB generation (same as S2MM):
    //    - Track bytes_in_burst
    //    - Generate partial mask on last beat
    //
    // 5. Address tracking:
    //    - rd_next_addr: increments by burst_actual_bytes
    //    - wr_next_addr: increments by burst_actual_bytes
    //
    // 6. Coordination:
    //    - Write cannot start until FIFO has data
    //    - Read can run ahead of write (up to FIFO depth)
    //    - Both must handle abort cleanly
    //
    // =========================================================================

    // Placeholder assignments (remove when implementing)
    assign rd_next_state = RD_IDLE;
    assign wr_next_state = WR_IDLE;
    
    assign mm2mm_araddr  = '0;
    assign mm2mm_arlen   = '0;
    assign mm2mm_arsize  = '0;
    assign mm2mm_arvalid = 1'b0;
    assign mm2mm_rready  = 1'b0;
    
    assign mm2mm_awaddr  = '0;
    assign mm2mm_awlen   = '0;
    assign mm2mm_awsize  = '0;
    assign mm2mm_awvalid = 1'b0;
    assign mm2mm_wdata   = '0;
    assign mm2mm_wstrb   = '0;
    assign mm2mm_wlast   = 1'b0;
    assign mm2mm_wvalid  = 1'b0;
    assign mm2mm_bready  = 1'b0;
    
    assign fifo_rready   = 1'b0;
    
    assign rd_bytes_done    = '0;
    assign wr_bytes_done    = '0;
    assign transfer_len_reg = '0;

endmodule : snix_axi_mm2mm

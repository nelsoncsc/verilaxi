// =============================================================================
// snix_axi_wr_arbiter.sv
//
// Write channel arbiter for S2MM and MM2MM engines
// - Round-robin AW arbitration
// - W channel routing based on AW grant
// - B response routing by BID
//
// Features:
// - Zero bubble arbitration (next grant computed while current active)
// - Supports up to 2 outstanding transactions per engine
// - Uses AXI ID[0] to distinguish engines: 0=S2MM, 1=MM2MM
// =============================================================================

module snix_axi_wr_arbiter #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 64,
    parameter int ID_WIDTH   = 4,
    parameter int USER_WIDTH = 1,
    parameter int MAX_OUTSTANDING = 2  // Per engine
)(
    input  logic clk,
    input  logic rst_n,

    // =========================================================================
    // S2MM Engine Interface (Engine 0)
    // =========================================================================
    // AW Channel
    input  logic [ID_WIDTH-1:0]      s2mm_awid,
    input  logic [ADDR_WIDTH-1:0]    s2mm_awaddr,
    input  logic [7:0]               s2mm_awlen,
    input  logic [2:0]               s2mm_awsize,
    input  logic [1:0]               s2mm_awburst,
    input  logic                     s2mm_awlock,
    input  logic [3:0]               s2mm_awcache,
    input  logic [2:0]               s2mm_awprot,
    input  logic [3:0]               s2mm_awqos,
    input  logic [USER_WIDTH-1:0]    s2mm_awuser,
    input  logic                     s2mm_awvalid,
    output logic                     s2mm_awready,
    // W Channel
    input  logic [DATA_WIDTH-1:0]    s2mm_wdata,
    input  logic [DATA_WIDTH/8-1:0]  s2mm_wstrb,
    input  logic                     s2mm_wlast,
    input  logic [USER_WIDTH-1:0]    s2mm_wuser,
    input  logic                     s2mm_wvalid,
    output logic                     s2mm_wready,
    // B Channel
    output logic [ID_WIDTH-1:0]      s2mm_bid,
    output logic [1:0]               s2mm_bresp,
    output logic [USER_WIDTH-1:0]    s2mm_buser,
    output logic                     s2mm_bvalid,
    input  logic                     s2mm_bready,

    // =========================================================================
    // MM2MM Engine Interface (Engine 1)
    // =========================================================================
    // AW Channel
    input  logic [ID_WIDTH-1:0]      mm2mm_awid,
    input  logic [ADDR_WIDTH-1:0]    mm2mm_awaddr,
    input  logic [7:0]               mm2mm_awlen,
    input  logic [2:0]               mm2mm_awsize,
    input  logic [1:0]               mm2mm_awburst,
    input  logic                     mm2mm_awlock,
    input  logic [3:0]               mm2mm_awcache,
    input  logic [2:0]               mm2mm_awprot,
    input  logic [3:0]               mm2mm_awqos,
    input  logic [USER_WIDTH-1:0]    mm2mm_awuser,
    input  logic                     mm2mm_awvalid,
    output logic                     mm2mm_awready,
    // W Channel
    input  logic [DATA_WIDTH-1:0]    mm2mm_wdata,
    input  logic [DATA_WIDTH/8-1:0]  mm2mm_wstrb,
    input  logic                     mm2mm_wlast,
    input  logic [USER_WIDTH-1:0]    mm2mm_wuser,
    input  logic                     mm2mm_wvalid,
    output logic                     mm2mm_wready,
    // B Channel
    output logic [ID_WIDTH-1:0]      mm2mm_bid,
    output logic [1:0]               mm2mm_bresp,
    output logic [USER_WIDTH-1:0]    mm2mm_buser,
    output logic                     mm2mm_bvalid,
    input  logic                     mm2mm_bready,

    // =========================================================================
    // Shared AXI Write Port (to interconnect)
    // =========================================================================
    // AW Channel
    output logic [ID_WIDTH-1:0]      m_awid,
    output logic [ADDR_WIDTH-1:0]    m_awaddr,
    output logic [7:0]               m_awlen,
    output logic [2:0]               m_awsize,
    output logic [1:0]               m_awburst,
    output logic                     m_awlock,
    output logic [3:0]               m_awcache,
    output logic [2:0]               m_awprot,
    output logic [3:0]               m_awqos,
    output logic [USER_WIDTH-1:0]    m_awuser,
    output logic                     m_awvalid,
    input  logic                     m_awready,
    // W Channel
    output logic [DATA_WIDTH-1:0]    m_wdata,
    output logic [DATA_WIDTH/8-1:0]  m_wstrb,
    output logic                     m_wlast,
    output logic [USER_WIDTH-1:0]    m_wuser,
    output logic                     m_wvalid,
    input  logic                     m_wready,
    // B Channel
    input  logic [ID_WIDTH-1:0]      m_bid,
    input  logic [1:0]               m_bresp,
    input  logic [USER_WIDTH-1:0]    m_buser,
    input  logic                     m_bvalid,
    output logic                     m_bready
);

    // =========================================================================
    // Local parameters
    // =========================================================================
    localparam int STRB_WIDTH = DATA_WIDTH / 8;
    
    // Engine IDs (use lower bits of AXI ID)
    localparam logic [ID_WIDTH-1:0] S2MM_ID_TAG  = '0;        // ID[0] = 0
    localparam logic [ID_WIDTH-1:0] MM2MM_ID_TAG = {{(ID_WIDTH-1){1'b0}}, 1'b1}; // ID[0] = 1

    // =========================================================================
    // Outstanding transaction tracking
    //
    // We track how many W bursts are pending for each engine.
    // AW can issue ahead of W, but W must follow in order per engine.
    // =========================================================================
    logic [$clog2(MAX_OUTSTANDING+1)-1:0] s2mm_aw_pending;
    logic [$clog2(MAX_OUTSTANDING+1)-1:0] mm2mm_aw_pending;
    
    // FIFO to track W channel ownership order
    // Each entry indicates which engine owns the next W burst
    // 0 = S2MM, 1 = MM2MM
    localparam int W_FIFO_DEPTH = 2 * MAX_OUTSTANDING;
    logic [W_FIFO_DEPTH-1:0] w_owner_fifo;
    logic [$clog2(W_FIFO_DEPTH)-1:0] w_fifo_wr_ptr;
    logic [$clog2(W_FIFO_DEPTH)-1:0] w_fifo_rd_ptr;
    logic [$clog2(W_FIFO_DEPTH+1)-1:0] w_fifo_count;
    
    logic w_fifo_empty;
    logic w_fifo_full;
    logic current_w_owner;  // 0 = S2MM, 1 = MM2MM
    
    assign w_fifo_empty = (w_fifo_count == 0);
    assign w_fifo_full  = (w_fifo_count == W_FIFO_DEPTH);
    assign current_w_owner = w_owner_fifo[w_fifo_rd_ptr];

    // =========================================================================
    // AW Channel Arbitration (Round-Robin)
    // =========================================================================
    logic aw_grant;      // 0 = S2MM, 1 = MM2MM
    logic last_grant;    // For round-robin fairness
    logic aw_handshake;
    
    assign aw_handshake = m_awvalid && m_awready;
    
    // Determine which engines are requesting and eligible
    logic s2mm_aw_req, mm2mm_aw_req;
    assign s2mm_aw_req  = s2mm_awvalid  && (s2mm_aw_pending < MAX_OUTSTANDING) && !w_fifo_full;
    assign mm2mm_aw_req = mm2mm_awvalid && (mm2mm_aw_pending < MAX_OUTSTANDING) && !w_fifo_full;
    
    // Round-robin arbitration
    always_comb begin
        if (s2mm_aw_req && mm2mm_aw_req) begin
            // Both requesting - alternate based on last grant
            aw_grant = ~last_grant;
        end else if (s2mm_aw_req) begin
            aw_grant = 1'b0;  // S2MM
        end else if (mm2mm_aw_req) begin
            aw_grant = 1'b1;  // MM2MM
        end else begin
            aw_grant = 1'b0;  // Default (no request)
        end
    end
    
    // Track last grant for round-robin
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n)
            last_grant <= 1'b0;
        else if (aw_handshake)
            last_grant <= aw_grant;

    // =========================================================================
    // AW Channel Mux
    // =========================================================================
    always_comb begin
        if (aw_grant == 1'b0) begin
            // S2MM selected
            m_awid    = {s2mm_awid[ID_WIDTH-1:1], 1'b0};  // Force ID[0] = 0
            m_awaddr  = s2mm_awaddr;
            m_awlen   = s2mm_awlen;
            m_awsize  = s2mm_awsize;
            m_awburst = s2mm_awburst;
            m_awlock  = s2mm_awlock;
            m_awcache = s2mm_awcache;
            m_awprot  = s2mm_awprot;
            m_awqos   = s2mm_awqos;
            m_awuser  = s2mm_awuser;
            m_awvalid = s2mm_aw_req;
        end else begin
            // MM2MM selected
            m_awid    = {mm2mm_awid[ID_WIDTH-1:1], 1'b1}; // Force ID[0] = 1
            m_awaddr  = mm2mm_awaddr;
            m_awlen   = mm2mm_awlen;
            m_awsize  = mm2mm_awsize;
            m_awburst = mm2mm_awburst;
            m_awlock  = mm2mm_awlock;
            m_awcache = mm2mm_awcache;
            m_awprot  = mm2mm_awprot;
            m_awqos   = mm2mm_awqos;
            m_awuser  = mm2mm_awuser;
            m_awvalid = mm2mm_aw_req;
        end
    end
    
    // AW ready signals back to engines
    assign s2mm_awready  = (aw_grant == 1'b0) && m_awready && s2mm_aw_req;
    assign mm2mm_awready = (aw_grant == 1'b1) && m_awready && mm2mm_aw_req;

    // =========================================================================
    // W Owner FIFO Management
    // =========================================================================
    logic w_burst_complete;
    assign w_burst_complete = m_wvalid && m_wready && m_wlast;
    
    // Write to FIFO on AW handshake
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            w_fifo_wr_ptr <= '0;
            w_owner_fifo  <= '0;
        end else if (aw_handshake) begin
            w_owner_fifo[w_fifo_wr_ptr] <= aw_grant;
            w_fifo_wr_ptr <= w_fifo_wr_ptr + 1'b1;
        end
    
    // Read from FIFO on W burst complete
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n)
            w_fifo_rd_ptr <= '0;
        else if (w_burst_complete)
            w_fifo_rd_ptr <= w_fifo_rd_ptr + 1'b1;
    
    // FIFO count
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n)
            w_fifo_count <= '0;
        else begin
            case ({aw_handshake, w_burst_complete})
                2'b10:   w_fifo_count <= w_fifo_count + 1'b1;
                2'b01:   w_fifo_count <= w_fifo_count - 1'b1;
                default: w_fifo_count <= w_fifo_count;
            endcase
        end

    // =========================================================================
    // Outstanding Transaction Counters
    // =========================================================================
    logic s2mm_b_handshake, mm2mm_b_handshake;
    assign s2mm_b_handshake  = s2mm_bvalid  && s2mm_bready;
    assign mm2mm_b_handshake = mm2mm_bvalid && mm2mm_bready;
    
    // S2MM outstanding counter
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n)
            s2mm_aw_pending <= '0;
        else begin
            case ({s2mm_awready && s2mm_awvalid, s2mm_b_handshake})
                2'b10:   s2mm_aw_pending <= s2mm_aw_pending + 1'b1;
                2'b01:   s2mm_aw_pending <= s2mm_aw_pending - 1'b1;
                default: s2mm_aw_pending <= s2mm_aw_pending;
            endcase
        end
    
    // MM2MM outstanding counter
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n)
            mm2mm_aw_pending <= '0;
        else begin
            case ({mm2mm_awready && mm2mm_awvalid, mm2mm_b_handshake})
                2'b10:   mm2mm_aw_pending <= mm2mm_aw_pending + 1'b1;
                2'b01:   mm2mm_aw_pending <= mm2mm_aw_pending - 1'b1;
                default: mm2mm_aw_pending <= mm2mm_aw_pending;
            endcase
        end

    // =========================================================================
    // W Channel Mux (based on FIFO head)
    // =========================================================================
    always_comb begin
        if (w_fifo_empty) begin
            // No pending W bursts - shouldn't happen in normal operation
            m_wdata  = '0;
            m_wstrb  = '0;
            m_wlast  = 1'b0;
            m_wuser  = '0;
            m_wvalid = 1'b0;
        end else if (current_w_owner == 1'b0) begin
            // S2MM owns current W burst
            m_wdata  = s2mm_wdata;
            m_wstrb  = s2mm_wstrb;
            m_wlast  = s2mm_wlast;
            m_wuser  = s2mm_wuser;
            m_wvalid = s2mm_wvalid;
        end else begin
            // MM2MM owns current W burst
            m_wdata  = mm2mm_wdata;
            m_wstrb  = mm2mm_wstrb;
            m_wlast  = mm2mm_wlast;
            m_wuser  = mm2mm_wuser;
            m_wvalid = mm2mm_wvalid;
        end
    end
    
    // W ready signals back to engines
    assign s2mm_wready  = !w_fifo_empty && (current_w_owner == 1'b0) && m_wready;
    assign mm2mm_wready = !w_fifo_empty && (current_w_owner == 1'b1) && m_wready;

    // =========================================================================
    // B Channel Demux (based on BID[0])
    // =========================================================================
    logic b_route_to_mm2mm;
    assign b_route_to_mm2mm = m_bid[0];
    
    // S2MM B channel
    assign s2mm_bid    = m_bid;
    assign s2mm_bresp  = m_bresp;
    assign s2mm_buser  = m_buser;
    assign s2mm_bvalid = m_bvalid && !b_route_to_mm2mm;
    
    // MM2MM B channel
    assign mm2mm_bid    = m_bid;
    assign mm2mm_bresp  = m_bresp;
    assign mm2mm_buser  = m_buser;
    assign mm2mm_bvalid = m_bvalid && b_route_to_mm2mm;
    
    // B ready to interconnect
    assign m_bready = b_route_to_mm2mm ? mm2mm_bready : s2mm_bready;

endmodule : snix_axi_wr_arbiter

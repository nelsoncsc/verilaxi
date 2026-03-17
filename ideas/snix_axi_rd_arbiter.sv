// =============================================================================
// snix_axi_rd_arbiter.sv
//
// Read channel arbiter for MM2S and MM2MM engines
// - Round-robin AR arbitration
// - R data routing based on RID
//
// Features:
// - Zero bubble arbitration
// - Supports up to 2 outstanding transactions per engine
// - Uses AXI ID[0] to distinguish engines: 0=MM2S, 1=MM2MM
// =============================================================================

module snix_axi_rd_arbiter #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 64,
    parameter int ID_WIDTH   = 4,
    parameter int USER_WIDTH = 1,
    parameter int MAX_OUTSTANDING = 2  // Per engine
)(
    input  logic clk,
    input  logic rst_n,

    // =========================================================================
    // MM2S Engine Interface (Engine 0)
    // =========================================================================
    // AR Channel
    input  logic [ID_WIDTH-1:0]      mm2s_arid,
    input  logic [ADDR_WIDTH-1:0]    mm2s_araddr,
    input  logic [7:0]               mm2s_arlen,
    input  logic [2:0]               mm2s_arsize,
    input  logic [1:0]               mm2s_arburst,
    input  logic                     mm2s_arlock,
    input  logic [3:0]               mm2s_arcache,
    input  logic [2:0]               mm2s_arprot,
    input  logic [3:0]               mm2s_arqos,
    input  logic [USER_WIDTH-1:0]    mm2s_aruser,
    input  logic                     mm2s_arvalid,
    output logic                     mm2s_arready,
    // R Channel
    output logic [ID_WIDTH-1:0]      mm2s_rid,
    output logic [DATA_WIDTH-1:0]    mm2s_rdata,
    output logic [1:0]               mm2s_rresp,
    output logic                     mm2s_rlast,
    output logic [USER_WIDTH-1:0]    mm2s_ruser,
    output logic                     mm2s_rvalid,
    input  logic                     mm2s_rready,

    // =========================================================================
    // MM2MM Engine Interface (Engine 1)
    // =========================================================================
    // AR Channel
    input  logic [ID_WIDTH-1:0]      mm2mm_arid,
    input  logic [ADDR_WIDTH-1:0]    mm2mm_araddr,
    input  logic [7:0]               mm2mm_arlen,
    input  logic [2:0]               mm2mm_arsize,
    input  logic [1:0]               mm2mm_arburst,
    input  logic                     mm2mm_arlock,
    input  logic [3:0]               mm2mm_arcache,
    input  logic [2:0]               mm2mm_arprot,
    input  logic [3:0]               mm2mm_arqos,
    input  logic [USER_WIDTH-1:0]    mm2mm_aruser,
    input  logic                     mm2mm_arvalid,
    output logic                     mm2mm_arready,
    // R Channel
    output logic [ID_WIDTH-1:0]      mm2mm_rid,
    output logic [DATA_WIDTH-1:0]    mm2mm_rdata,
    output logic [1:0]               mm2mm_rresp,
    output logic                     mm2mm_rlast,
    output logic [USER_WIDTH-1:0]    mm2mm_ruser,
    output logic                     mm2mm_rvalid,
    input  logic                     mm2mm_rready,

    // =========================================================================
    // Shared AXI Read Port (to interconnect)
    // =========================================================================
    // AR Channel
    output logic [ID_WIDTH-1:0]      m_arid,
    output logic [ADDR_WIDTH-1:0]    m_araddr,
    output logic [7:0]               m_arlen,
    output logic [2:0]               m_arsize,
    output logic [1:0]               m_arburst,
    output logic                     m_arlock,
    output logic [3:0]               m_arcache,
    output logic [2:0]               m_arprot,
    output logic [3:0]               m_arqos,
    output logic [USER_WIDTH-1:0]    m_aruser,
    output logic                     m_arvalid,
    input  logic                     m_arready,
    // R Channel
    input  logic [ID_WIDTH-1:0]      m_rid,
    input  logic [DATA_WIDTH-1:0]    m_rdata,
    input  logic [1:0]               m_rresp,
    input  logic                     m_rlast,
    input  logic [USER_WIDTH-1:0]    m_ruser,
    input  logic                     m_rvalid,
    output logic                     m_rready
);

    // =========================================================================
    // Outstanding transaction tracking
    // =========================================================================
    logic [$clog2(MAX_OUTSTANDING+1)-1:0] mm2s_ar_pending;
    logic [$clog2(MAX_OUTSTANDING+1)-1:0] mm2mm_ar_pending;

    // =========================================================================
    // AR Channel Arbitration (Round-Robin)
    // =========================================================================
    logic ar_grant;      // 0 = MM2S, 1 = MM2MM
    logic last_grant;    // For round-robin fairness
    logic ar_handshake;
    
    assign ar_handshake = m_arvalid && m_arready;
    
    // Determine which engines are requesting and eligible
    logic mm2s_ar_req, mm2mm_ar_req;
    assign mm2s_ar_req  = mm2s_arvalid  && (mm2s_ar_pending < MAX_OUTSTANDING);
    assign mm2mm_ar_req = mm2mm_arvalid && (mm2mm_ar_pending < MAX_OUTSTANDING);
    
    // Round-robin arbitration
    always_comb begin
        if (mm2s_ar_req && mm2mm_ar_req) begin
            // Both requesting - alternate based on last grant
            ar_grant = ~last_grant;
        end else if (mm2s_ar_req) begin
            ar_grant = 1'b0;  // MM2S
        end else if (mm2mm_ar_req) begin
            ar_grant = 1'b1;  // MM2MM
        end else begin
            ar_grant = 1'b0;  // Default (no request)
        end
    end
    
    // Track last grant for round-robin
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n)
            last_grant <= 1'b0;
        else if (ar_handshake)
            last_grant <= ar_grant;

    // =========================================================================
    // AR Channel Mux
    // =========================================================================
    always_comb begin
        if (ar_grant == 1'b0) begin
            // MM2S selected
            m_arid    = {mm2s_arid[ID_WIDTH-1:1], 1'b0};  // Force ID[0] = 0
            m_araddr  = mm2s_araddr;
            m_arlen   = mm2s_arlen;
            m_arsize  = mm2s_arsize;
            m_arburst = mm2s_arburst;
            m_arlock  = mm2s_arlock;
            m_arcache = mm2s_arcache;
            m_arprot  = mm2s_arprot;
            m_arqos   = mm2s_arqos;
            m_aruser  = mm2s_aruser;
            m_arvalid = mm2s_ar_req;
        end else begin
            // MM2MM selected
            m_arid    = {mm2mm_arid[ID_WIDTH-1:1], 1'b1}; // Force ID[0] = 1
            m_araddr  = mm2mm_araddr;
            m_arlen   = mm2mm_arlen;
            m_arsize  = mm2mm_arsize;
            m_arburst = mm2mm_arburst;
            m_arlock  = mm2mm_arlock;
            m_arcache = mm2mm_arcache;
            m_arprot  = mm2mm_arprot;
            m_arqos   = mm2mm_arqos;
            m_aruser  = mm2mm_aruser;
            m_arvalid = mm2mm_ar_req;
        end
    end
    
    // AR ready signals back to engines
    assign mm2s_arready  = (ar_grant == 1'b0) && m_arready && mm2s_ar_req;
    assign mm2mm_arready = (ar_grant == 1'b1) && m_arready && mm2mm_ar_req;

    // =========================================================================
    // Outstanding Transaction Counters
    // =========================================================================
    logic mm2s_r_done, mm2mm_r_done;
    assign mm2s_r_done  = mm2s_rvalid  && mm2s_rready  && mm2s_rlast;
    assign mm2mm_r_done = mm2mm_rvalid && mm2mm_rready && mm2mm_rlast;
    
    // MM2S outstanding counter
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n)
            mm2s_ar_pending <= '0;
        else begin
            case ({mm2s_arready && mm2s_arvalid, mm2s_r_done})
                2'b10:   mm2s_ar_pending <= mm2s_ar_pending + 1'b1;
                2'b01:   mm2s_ar_pending <= mm2s_ar_pending - 1'b1;
                default: mm2s_ar_pending <= mm2s_ar_pending;
            endcase
        end
    
    // MM2MM outstanding counter
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n)
            mm2mm_ar_pending <= '0;
        else begin
            case ({mm2mm_arready && mm2mm_arvalid, mm2mm_r_done})
                2'b10:   mm2mm_ar_pending <= mm2mm_ar_pending + 1'b1;
                2'b01:   mm2mm_ar_pending <= mm2mm_ar_pending - 1'b1;
                default: mm2mm_ar_pending <= mm2mm_ar_pending;
            endcase
        end

    // =========================================================================
    // R Channel Demux (based on RID[0])
    //
    // Unlike W channel, R data can come back out-of-order between different IDs.
    // We route based on RID[0]: 0=MM2S, 1=MM2MM
    // =========================================================================
    logic r_route_to_mm2mm;
    assign r_route_to_mm2mm = m_rid[0];
    
    // MM2S R channel
    assign mm2s_rid    = m_rid;
    assign mm2s_rdata  = m_rdata;
    assign mm2s_rresp  = m_rresp;
    assign mm2s_rlast  = m_rlast;
    assign mm2s_ruser  = m_ruser;
    assign mm2s_rvalid = m_rvalid && !r_route_to_mm2mm;
    
    // MM2MM R channel
    assign mm2mm_rid    = m_rid;
    assign mm2mm_rdata  = m_rdata;
    assign mm2mm_rresp  = m_rresp;
    assign mm2mm_rlast  = m_rlast;
    assign mm2mm_ruser  = m_ruser;
    assign mm2mm_rvalid = m_rvalid && r_route_to_mm2mm;
    
    // R ready to interconnect
    assign m_rready = r_route_to_mm2mm ? mm2mm_rready : mm2s_rready;

endmodule : snix_axi_rd_arbiter

interface axi4_if #(parameter int ADDR_WIDTH = 32,
                    parameter int DATA_WIDTH = 64,
                    parameter int ID_WIDTH   = 4,
                    parameter int USER_WIDTH = 1)
                   (input logic ACLK,
                    input logic ARESETn);

    // -----------------------------
    // Write Address Channel (AW)
    // -----------------------------
    logic [ID_WIDTH-1:0]     awid;
    logic [ADDR_WIDTH-1:0]   awaddr;
    logic [7:0]              awlen;
    logic [2:0]              awsize;
    logic [1:0]              awburst;
    logic                    awlock;
    logic [3:0]              awcache;
    logic [2:0]              awprot;
    logic [3:0]              awqos;
    logic [USER_WIDTH-1:0]   awuser;
    logic                    awvalid;
    logic                    awready;

    // -----------------------------
    // Write Data Channel (W)
    // -----------------------------
    logic [DATA_WIDTH-1:0]   wdata;
    logic [DATA_WIDTH/8-1:0] wstrb;
    logic                    wlast;
    logic [USER_WIDTH-1:0]   wuser;
    logic                    wvalid;
    logic                    wready;

    // -----------------------------
    // Write Response Channel (B)
    // -----------------------------
    logic [ID_WIDTH-1:0]     bid;
    logic [1:0]              bresp;
    logic [USER_WIDTH-1:0]   buser;
    logic                    bvalid;
    logic                    bready;

    // -----------------------------
    // Read Address Channel (AR)
    // -----------------------------
    logic [ID_WIDTH-1:0]     arid;
    logic [ADDR_WIDTH-1:0]   araddr;
    logic [7:0]              arlen;
    logic [2:0]              arsize;
    logic [1:0]              arburst;
    logic                    arlock;
    logic [3:0]              arcache;
    logic [2:0]              arprot;
    logic [3:0]              arqos;
    logic [USER_WIDTH-1:0]   aruser;
    logic                    arvalid;
    logic                    arready;

    // -----------------------------
    // Read Data Channel (R)
    // -----------------------------
    logic [ID_WIDTH-1:0]     rid;
    logic [DATA_WIDTH-1:0]   rdata;
    logic [1:0]              rresp;
    logic                    rlast;
    logic [USER_WIDTH-1:0]   ruser;
    logic                    rvalid;
    logic                    rready;

    // =========================================================
    // Master Modport
    // =========================================================
    modport master (
        // Global
        input  ACLK, ARESETn,

        // AW
        output awid, awaddr, awlen, awsize, awburst,
               awlock, awcache, awprot, awqos, awuser, awvalid,
        input  awready,

        // W
        output wdata, wstrb, wlast, wuser, wvalid,
        input  wready,

        // B
        input  bid, bresp, buser, bvalid,
        output bready,

        // AR
        output arid, araddr, arlen, arsize, arburst,
               arlock, arcache, arprot, arqos, aruser, arvalid,
        input  arready,

        // R
        input  rid, rdata, rresp, rlast, ruser, rvalid,
        output rready
    );

    // =========================================================
    // Slave Modport
    // =========================================================
    modport slave (
        // Global
        input  ACLK, ARESETn,

        // AW
        input  awid, awaddr, awlen, awsize, awburst,
               awlock, awcache, awprot, awqos, awuser, awvalid,
        output awready,

        // W
        input  wdata, wstrb, wlast, wuser, wvalid,
        output wready,

        // B
        output bid, bresp, buser, bvalid,
        input  bready,

        // AR
        input  arid, araddr, arlen, arsize, arburst,
               arlock, arcache, arprot, arqos, aruser, arvalid,
        output arready,

        // R
        output rid, rdata, rresp, rlast, ruser, rvalid,
        input  rready
    );

    task automatic init();
        awid    = 0;
        awaddr  = 0;
        awlen   = 0;
        awsize  = 0;
        awburst = 0;
        awlock  = 0;
        awcache = 0;
        awprot  = 0; 
        awqos   = 0;
        awuser  = 0; 
        awvalid = 0; 
        awready = 0;

        wdata   = 0;
        wstrb   = 0; 
        wlast   = 0; 
        wuser   = 0; 
        wvalid  = 0;
        wready  = 0;
        
        bid     = 0; 
        bresp   = 0;
        buser   = 0; 
        bvalid  = 0; 
        bready  = 0;
 
        arid    = 0;
        araddr  = 0;
        arlen   = 0;
        arsize  = 0;
        arburst = 0;
        arlock  = 0;
        arcache = 0;
        arprot  = 0; 
        arqos   = 0;
        aruser  = 0; 
        arvalid = 0; 
        arready = 0;

        rid     = 0; 
        rdata   = 0;
        rresp   = 0; 
        rlast   = 0;
        ruser   = 0;
        rvalid  = 0;
        rready  = 0;
    endtask: init

endinterface: axi4_if

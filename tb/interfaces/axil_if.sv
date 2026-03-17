interface axil_if #(parameter int ADDR_WIDTH = 32,
                    parameter int DATA_WIDTH = 32)
                    (input logic ACLK,
                     input logic ARESETn);

    // -----------------------------
    // Write Address Channel (AW)
    // -----------------------------
    logic [ADDR_WIDTH-1:0]   awaddr;
    logic                    awvalid;
    logic                    awready;

    // -----------------------------
    // Write Data Channel (W)
    // -----------------------------
    logic [DATA_WIDTH-1:0]   wdata;
    logic [DATA_WIDTH/8-1:0] wstrb;
    logic                    wvalid;
    logic                    wready;

    // -----------------------------
    // Write Response Channel (B)
    // -----------------------------
    logic [1:0]              bresp;
    logic                    bvalid;
    logic                    bready;

    // -----------------------------
    // Read Address Channel (AR)
    // -----------------------------
    logic [ADDR_WIDTH-1:0]  araddr;
    logic                   arvalid;
    logic                   arready;

    // -----------------------------
    // Read Data Channel (R)
    // -----------------------------
    logic [DATA_WIDTH-1:0]   rdata;
    logic [1:0]              rresp;
    logic                    rvalid;
    logic                    rready;

    // =========================================================
    // Master Modport
    // =========================================================
    modport master (
        // Global
        input  ACLK, ARESETn,

        // AW
        output awaddr, awvalid,
        input  awready,

        // W
        output wdata, wstrb, wvalid,
        input  wready,

        // B
        input  bresp, bvalid,
        output bready,

        // AR
        output araddr, arvalid,
        input  arready,

        // R
        input  rdata, rresp, rvalid,
        output rready
    );

    // =========================================================
    // Slave Modport
    // =========================================================
    modport slave (
        // Global
        input  ACLK, ARESETn,

        // AW
        input  awaddr, awvalid,
        output awready,

        // W
        input  wdata, wstrb, wvalid,
        output wready,

        // B
        output bresp, bvalid,
        input  bready,

        // AR
        input  araddr, arvalid,
        output arready,

        // R
        output rdata, rresp, rvalid,
        input  rready
    );

    // =========================================================
    // Task to reset all signals
    // =========================================================
    task automatic init();
        awaddr  = 0; awvalid = 0; awready = 0;
        wdata   = 0; wstrb = 0;   wvalid  = 0; wready  = 0;
        bresp   = 0; bvalid  = 0; bready  = 0;
        araddr  = 0; arvalid = 0; arready = 0;
        rdata   = 0; rresp   = 0; rvalid  = 0; rready = 0;
    endtask: init

endinterface: axil_if

`define AXI_DATA_T(ADDR_W, DATA_W, ID_W, USER_W) \
    typedef struct packed { \
        logic [ID_W-1:0]     awid; \
        logic [ADDR_W-1:0]   awaddr; \
        logic [7:0]          awlen; \
        logic [2:0]          awsize; \
        logic [1:0]          awburst; \
        logic                awlock; \
        logic [3:0]          awcache; \
        logic [2:0]          awprot; \
        logic [3:0]          awqos; \
        logic [USER_W-1:0]   awuser; \
        logic                awvalid; \
        logic                awready; \
    \
        logic [DATA_W-1:0]   wdata; \
        logic [DATA_W/8-1:0] wstrb; \
        logic                wlast; \
        logic [USER_W-1:0]   wuser; \
        logic                wvalid; \
        logic                wready; \
    \
        logic [ID_W-1:0]     bid; \
        logic [1:0]          bresp; \
        logic [USER_W-1:0]   buser; \
        logic                bvalid; \
        logic                bready; \
    \
        logic [ID_W-1:0]     arid; \
        logic [ADDR_W-1:0]   araddr; \
        logic [7:0]           arlen; \
        logic [2:0]           arsize; \
        logic [1:0]           arburst; \
        logic                 arlock; \
        logic [3:0]           arcache; \
        logic [2:0]           arprot; \
        logic [3:0]           arqos; \
        logic [USER_W-1:0]    aruser; \
        logic                 arvalid; \
        logic                 arready; \
    \
        logic [ID_W-1:0]      rid; \
        logic [DATA_W-1:0]    rdata; \
        logic [1:0]           rresp; \
        logic                 rlast; \
        logic [USER_W-1:0]    ruser; \
        logic                 rvalid; \
        logic                 rready; \
    } axi_data_t;

    /*
    // macro usage:
     `AXI_DATA_T(ADDR_WIDTH, DATA_WIDTH, ID_WIDTH, USER_WIDTH)
     axi_data_t tdata;
    */

interface axis_if #(parameter int DATA_WIDTH = 8,
                    parameter int USER_WIDTH = 1,
                    parameter int KEEP_WIDTH = ((DATA_WIDTH + 7) / 8))
                   (input logic ACLK,
                    input logic ARESETn);

    logic [DATA_WIDTH-1:0] tdata; 
    logic [KEEP_WIDTH-1:0] tkeep;
    logic [USER_WIDTH-1:0] tuser;
    logic                  tvalid;
    logic                  tlast;
    logic                  tready; 

    modport src(input  ACLK,
                input  ARESETn,
                output tdata,
                output tkeep,
                output tuser,
                output tvalid,
                output tlast,
                input  tready
                );

    modport sink(input  ACLK,
                 input  ARESETn,
                 input  tdata,
                 input  tkeep,
                 input  tuser,
                 input  tvalid,
                 input  tlast,
                 output tready
                 );
    
    task automatic init();
        tvalid = 0;
        tready = 0;
        tdata  = 0;
        tkeep  = 0;
        tuser  = 0;
        tlast  = 0;
    endtask: init
    

endinterface: axis_if

// ============================================================================
//  snix_async_fifo.sv
//
//  SystemVerilog implementation of an async FIFO. If targeting FPGAs, this
//  implementation is intended to infer BRAM.
//
//  Largely based on ZipCPU's async FIFO work:
//    https://zipcpu.com/blog/2018/07/06/afifo.html
// ============================================================================
module snix_async_fifo #(parameter DATA_WIDTH = 8,
		                 parameter FIFO_DEPTH = 4)
                        (input  logic                  wclk,
                        input  logic                  wrst_n,
                        input  logic                  wr_en,
                        input  logic [DATA_WIDTH-1:0] wdata,
                        output logic                  wfull,
                        
                        input  logic                  rclk,
                        input  logic                  rrst_n,
                        input  logic                  rd_en,
                        output logic [DATA_WIDTH-1:0] rdata,
                        output logic [$clog2(FIFO_DEPTH):0] rd_n_items,
                        output logic                        rempty);

    localparam ADDR_W = $clog2(FIFO_DEPTH);
    localparam NFF    = 2;

    logic [ADDR_W:0] rd_addr,     next_rd_addr;
    logic [ADDR_W:0] wr_addr,     next_wr_addr;
    logic [ADDR_W:0] rgray,       wgray;
    logic [ADDR_W:0] rd_wgray,    wr_rgray,    rd_wbin;// rd_n_items;  

    (* ASYNC_REG =  "TRUE" *) logic [(ADDR_W+1)*(NFF-1)-1:0] rgray_cross, wgray_cross;    
    (* ram_style = "block" *) logic [DATA_WIDTH-1:0] mem [0:FIFO_DEPTH-1];

    logic [DATA_WIDTH-1:0] lcl_rd_data;
    logic                  lcl_read, lcl_rd_empty;

    assign next_wr_addr = wr_addr + 1'b1;
    always_ff @(posedge wclk or negedge wrst_n)
        if(!wrst_n) begin
            wr_addr <= (ADDR_W+1)'(0);
            wgray <= (ADDR_W+1)'(0);
        end
        else if(wr_en && !wfull) begin
            wr_addr <= next_wr_addr;
            wgray   <= next_wr_addr ^ (next_wr_addr>>1);
        end

    always_ff @(posedge wclk)
        if (wr_en && !wfull)
            mem[wr_addr[ADDR_W-1:0]] <= wdata;


    assign next_rd_addr = rd_addr + 1'b1;
    assign lcl_rd_data  = mem[rd_addr[ADDR_W-1:0]];

    always_ff @(posedge wclk or negedge wrst_n)
        if(!wrst_n) begin
            wr_rgray    <= (ADDR_W+1)'(0);
            rgray_cross <= (ADDR_W+1)'(0);
        end
        else begin
            {wr_rgray, rgray_cross} <= {rgray_cross, rgray};
        end

    always_ff @(posedge rclk or negedge rrst_n)
        if(!rrst_n) begin
            rd_wgray    <= (ADDR_W+1)'(0);
            wgray_cross <= (ADDR_W+1)'(0);
            rd_n_items  <= (ADDR_W+1)'(0);
        end
        else begin
            {rd_wgray, wgray_cross} <= {wgray_cross, wgray};
            rd_n_items <= (rd_wbin - rd_addr)  & ((1 << (ADDR_W + 1)) - 1);
        end

    always_comb begin
        rd_wbin[ADDR_W] = rd_wgray[ADDR_W];
        for (int i = ADDR_W-1; i >= 0; i--) begin
            rd_wbin[i] = rd_wbin[i+1] ^ rd_wgray[i];
        end
    end

    assign wfull        = wr_rgray == {~wgray[ADDR_W:ADDR_W-1], wgray[ADDR_W-2:0]};
    assign lcl_rd_empty = rd_wgray == rgray;
    assign lcl_read     = rempty || rd_en;

    // Single block: all rclk state sampled simultaneously so Verilator reads
    // lcl_rd_empty (depends on rgray) before any NBA update of rgray is applied.
    always_ff @(posedge rclk or negedge rrst_n)
        if(!rrst_n) begin
            rd_addr <= (ADDR_W+1)'(0);
            rgray   <= (ADDR_W+1)'(0);
            rempty  <= 1'b1;
        end
        else if(lcl_read) begin
            if(!lcl_rd_empty) begin
                rd_addr <= next_rd_addr;
                rgray   <= next_rd_addr ^ (next_rd_addr>>1);
            end
            rempty <= lcl_rd_empty;
            rdata  <= lcl_rd_data;
        end


`ifdef AFIFO_DEBUG
    always_ff @(posedge rclk) begin
        if (DATA_WIDTH == 74 && lcl_read && !lcl_rd_empty)
            $display("[AFIFO74_R] t=%0t rd_addr=%0d->%0d rd_en=%0b rempty=%0b data=%016h",
                     $time, rd_addr, next_rd_addr, rd_en, rempty, lcl_rd_data[64:1]);
    end
    always_ff @(posedge wclk) begin
        if (DATA_WIDTH == 74 && wr_en && !wfull)
            $display("[AFIFO74_W] t=%0t wr_addr=%0d data=%016h",
                     $time, wr_addr, wdata[64:1]);
    end
`endif

endmodule: snix_async_fifo

// ============================================================================
//  snix_sync_fifo.sv
//
//  Synchronous FIFO with first-word-fall-through (FWFT) bypass.
//
//  Architecture:
//    - Dual-pointer circular buffer with MSB wrap-bit for full detection
//    - Write-through bypass path: when the FIFO is empty and a write arrives,
//      data is forwarded directly to the output without a one-cycle read delay
//    - Block-RAM inference hint for FPGA targets
// ============================================================================
module snix_sync_fifo #(
    parameter int DATA_WIDTH = 32,
    parameter int FIFO_DEPTH = 16
) (
    input  logic                         clk,
    input  logic                         rst_n,

    // Write port
    input  logic [DATA_WIDTH-1:0]        data_i,
    input  logic                         wr_en,

    // Read port
    input  logic                         rd_en,
    output logic [DATA_WIDTH-1:0]        data_o,

    // Status
    output logic [$clog2(FIFO_DEPTH):0]  fill_cnt,
    output logic                         fifo_full,
    output logic                         fifo_empty
);

    localparam int AWIDTH = $clog2(FIFO_DEPTH);

    // Storage
    (* ram_style="block" *)
    logic [DATA_WIDTH-1:0] mem [0:FIFO_DEPTH-1];

    // Pointers — extra MSB for wrap-around detection
    logic [AWIDTH:0] wptr, rptr;

    // Bypass (FWFT) path
    logic [DATA_WIDTH-1:0] fwd_data;
    logic                  fwd_valid;

    // Qualified strobes
    wire do_wr = wr_en & ~fifo_full;
    wire do_rd = rd_en & ~fifo_empty;

    // -----------------------------------------------------------------
    // Write pointer
    // -----------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n)
            wptr <= '0;
        else if (do_wr)
            wptr <= wptr + 1'b1;

    // -----------------------------------------------------------------
    // Read pointer
    // -----------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n)
            rptr <= '0;
        else if (do_rd)
            rptr <= rptr + 1'b1;

    // -----------------------------------------------------------------
    // Memory write
    // -----------------------------------------------------------------
    always_ff @(posedge clk)
        if (do_wr)
            mem[wptr[AWIDTH-1:0]] <= data_i;

    // -----------------------------------------------------------------
    // Memory read — pre-fetch next location for FWFT
    // -----------------------------------------------------------------
    logic [DATA_WIDTH-1:0] mem_rd;

    always_ff @(posedge clk)
        if (do_rd)
            mem_rd <= mem[rptr[AWIDTH-1:0] + 1'b1];

    // -----------------------------------------------------------------
    // Fill counter and empty flag
    // -----------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n) begin
            fifo_empty <= 1'b1;
            fill_cnt   <= '0;
        end else begin
            case ({do_wr, do_rd})
                2'b10: begin
                    fill_cnt   <= fill_cnt + 1'b1;
                    fifo_empty <= 1'b0;
                end
                2'b01: begin
                    fill_cnt   <= fill_cnt - 1'b1;
                    fifo_empty <= (fill_cnt <= 1);
                end
                default: ;
            endcase
        end

    // Full flag — MSB of fill counter
    assign fifo_full = fill_cnt[AWIDTH];

    // -----------------------------------------------------------------
    // FWFT bypass — forward write data directly when FIFO is empty
    // -----------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n)
        if (!rst_n)
            fwd_valid <= 1'b0;
        else if (fifo_empty || rd_en) begin
            if (!wr_en)
                fwd_valid <= 1'b0;
            else if (fifo_empty || (rd_en && fill_cnt == 1))
                fwd_valid <= 1'b1;
            else
                fwd_valid <= 1'b0;
        end

    always_ff @(posedge clk)
        if (fifo_empty || rd_en)
            fwd_data <= data_i;

    // Output mux — bypass path has priority
    assign data_o = fwd_valid ? fwd_data : mem_rd;

endmodule : snix_sync_fifo

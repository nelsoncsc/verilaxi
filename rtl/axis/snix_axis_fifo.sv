// ============================================================================
//  snix_axis_fifo.sv
//
//  AXI4-Stream FIFO with two operating modes selected by FRAME_FIFO:
//
//    FRAME_FIFO = 0 (default) — streaming / cut-through
//      Output valid asserts as soon as any data enters the FIFO.
//      Downstream can begin reading before the full packet arrives.
//
//    FRAME_FIFO = 1 — store-and-forward
//      Output valid is suppressed until the complete packet (through tlast)
//      has been written into the FIFO.  Guarantees the downstream never
//      sees a stalled mid-packet transfer.
// ============================================================================
module snix_axis_fifo #(
    parameter int DATA_WIDTH  = 32,
    parameter int USER_WIDTH  = 1,
    parameter int FIFO_DEPTH  = 16,
    parameter bit FRAME_FIFO  = 0       // 0 = streaming, 1 = store-and-forward
) (
    input  logic                  clk,
    input  logic                  rst_n,

    // AXI4-Stream slave (input)
    input  logic [DATA_WIDTH-1:0] s_axis_tdata,
    input  logic [USER_WIDTH-1:0] s_axis_tuser,
    input  logic                  s_axis_tvalid,
    input  logic                  s_axis_tlast,
    output logic                  s_axis_tready,

    // AXI4-Stream master (output)
    output logic [DATA_WIDTH-1:0] m_axis_tdata,
    output logic [USER_WIDTH-1:0] m_axis_tuser,
    output logic                  m_axis_tvalid,
    output logic                  m_axis_tlast,
    input  logic                  m_axis_tready
);

    localparam int AWIDTH = $clog2(FIFO_DEPTH);

    // Internal FIFO signals
    logic [DATA_WIDTH-1:0] fifo_tdata;
    logic [USER_WIDTH-1:0] fifo_tuser;
    logic                  fifo_tlast;
    logic                  wr_en, rd_en;
    logic                  fifo_full, fifo_empty;
    logic [AWIDTH:0]       fill_cnt;

    // Handshake strobes
    assign s_axis_tready = ~fifo_full;
    assign wr_en         = s_axis_tvalid & s_axis_tready;
    assign rd_en         = m_axis_tvalid & m_axis_tready;

    // Output mapping
    assign m_axis_tdata  = fifo_tdata;
    assign m_axis_tuser  = fifo_tuser;
    assign m_axis_tlast  = fifo_tlast;

    // -------------------------------------------------------------------------
    // Output valid generation
    //
    //   FRAME_FIFO = 1 : store-and-forward FSM
    //     IDLE   -> STREAM  when tlast is written into the FIFO
    //     STREAM -> IDLE    when tlast is read out of the FIFO
    //
    //   FRAME_FIFO = 0 : cut-through, valid tracks fifo_empty directly
    // -------------------------------------------------------------------------
    generate
        if (FRAME_FIFO) begin : gen_frame_mode

            typedef enum logic { IDLE, STREAM } state_t;
            state_t state, nxt;

            always_ff @(posedge clk or negedge rst_n)
                if (!rst_n) state <= IDLE;
                else        state <= nxt;

            always_comb begin
                nxt = state;
                case (state)
                    IDLE:   if (wr_en && s_axis_tlast)  nxt = STREAM;
                    STREAM: if (rd_en && fifo_tlast)    nxt = IDLE;
                endcase
            end

            assign m_axis_tvalid = ~fifo_empty & (state == STREAM);

        end else begin : gen_stream_mode

            assign m_axis_tvalid = ~fifo_empty;

        end
    endgenerate

    // -------------------------------------------------------------------------
    // Sync FIFO instance — packs {tdata, tuser, tlast} into one word
    // -------------------------------------------------------------------------
    snix_sync_fifo #(
        .DATA_WIDTH (DATA_WIDTH + USER_WIDTH + 1),
        .FIFO_DEPTH (FIFO_DEPTH)
    ) u_fifo (
        .clk        (clk),
        .rst_n      (rst_n),
        .data_i     ({s_axis_tdata, s_axis_tuser, s_axis_tlast}),
        .wr_en      (wr_en),
        .rd_en      (rd_en),
        .data_o     ({fifo_tdata,   fifo_tuser,   fifo_tlast}),
        .fifo_full  (fifo_full),
        .fifo_empty (fifo_empty),
        .fill_cnt   (fill_cnt)
    );

endmodule : snix_axis_fifo

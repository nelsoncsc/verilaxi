// snix_axis_rr_converter.sv
//
// AXI-Stream rational-ratio width converter with byte-accurate TKEEP support.
//
// Converts between any two byte-aligned widths IN_DATA_WIDTH and
// OUT_DATA_WIDTH. Instead of assuming every input beat is fully valid, the
// converter appends only the bytes selected by s_axis_tkeep into a byte
// reservoir. Output beats are emitted from the oldest bytes in the reservoir.
//
// This means the converter preserves arbitrary input TKEEP patterns:
//   - sparse input beats are compacted into a continuous output byte stream
//   - full output beats use all-ones TKEEP
//   - the final beat of a packet uses a partial TKEEP when fewer than
//     OUT_BYTES remain in the reservoir
//
// Flow control
//   s_axis_tready is high only in FILL state.
//   m_axis_tvalid is high only in DRAIN state.
//   The design does not accept and emit in the same cycle; once the reservoir
//   has enough bytes for one output beat, or the packet ends, the converter
//   drains the buffered bytes before returning to FILL.

`default_nettype none

module snix_axis_rr_converter #(
    parameter int IN_DATA_WIDTH  = 32,
    parameter int OUT_DATA_WIDTH = 48
) (
    input  wire  clk,
    input  wire  rst_n,

    input  wire  [IN_DATA_WIDTH-1:0]    s_axis_tdata,
    input  wire  [IN_DATA_WIDTH/8-1:0]  s_axis_tkeep,
    input  wire                         s_axis_tvalid,
    output logic                        s_axis_tready,
    input  wire                         s_axis_tlast,

    output logic [OUT_DATA_WIDTH-1:0]   m_axis_tdata,
    output logic [OUT_DATA_WIDTH/8-1:0] m_axis_tkeep,
    output logic                        m_axis_tvalid,
    input  wire                         m_axis_tready,
    output logic                        m_axis_tlast
);

    localparam int IN_BYTES  = IN_DATA_WIDTH  / 8;
    localparam int OUT_BYTES = OUT_DATA_WIDTH / 8;
    localparam int BUF_BYTES = OUT_BYTES + IN_BYTES;
    localparam int CNT_W     = $clog2(BUF_BYTES + 1);

    typedef enum logic { FILL = 1'b0, DRAIN = 1'b1 } state_t;
    state_t state;

    logic [BUF_BYTES*8-1:0] buf_data;
    logic [CNT_W-1:0]       buf_count;
    logic                   packet_end_pending;

    logic [OUT_DATA_WIDTH-1:0]   out_tdata;
    logic [OUT_BYTES-1:0]        out_tkeep;
    logic                        out_tlast;
    logic [CNT_W-1:0]            out_valid_bytes;

    function automatic logic [OUT_BYTES-1:0] keep_mask(input int valid_bytes);
        logic [OUT_BYTES-1:0] mask;
        mask = '0;
        for (int i = 0; i < OUT_BYTES; i++) begin
            if (i < valid_bytes)
                mask[i] = 1'b1;
        end
        keep_mask = mask;
    endfunction

    always_comb begin
        out_tdata       = '0;
        out_tkeep       = '0;
        out_tlast       = 1'b0;
        out_valid_bytes = '0;

        if (state == DRAIN) begin
            if (packet_end_pending && (buf_count < CNT_W'(OUT_BYTES)))
                out_valid_bytes = buf_count;
            else
                out_valid_bytes = CNT_W'(OUT_BYTES);

            out_tkeep = keep_mask(int'(out_valid_bytes));
            out_tlast = packet_end_pending && (buf_count <= CNT_W'(OUT_BYTES));

            for (int i = 0; i < OUT_BYTES; i++) begin
                if (i < int'(out_valid_bytes))
                    out_tdata[i*8 +: 8] = buf_data[i*8 +: 8];
            end
        end
    end

    assign s_axis_tready = (state == FILL);
    assign m_axis_tvalid = (state == DRAIN);
    assign m_axis_tdata  = out_tdata;
    assign m_axis_tkeep  = out_tkeep;
    assign m_axis_tlast  = out_tlast;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state              <= FILL;
            buf_data           <= '0;
            buf_count          <= '0;
            packet_end_pending <= 1'b0;
        end else begin
            case (state)
                FILL: begin
                    if (s_axis_tvalid) begin
                        logic [BUF_BYTES*8-1:0] next_buf_data;
                        logic [CNT_W-1:0]       next_buf_count;
                        int                     add_count;

                        next_buf_data  = buf_data;
                        next_buf_count = buf_count;
                        add_count      = 0;

                        for (int lane = 0; lane < IN_BYTES; lane++) begin
                            if (s_axis_tkeep[lane]) begin
                                next_buf_data[(int'(buf_count) + add_count)*8 +: 8] =
                                    s_axis_tdata[lane*8 +: 8];
                                add_count++;
                            end
                        end

                        next_buf_count = buf_count + CNT_W'(add_count);
                        buf_data       <= next_buf_data;
                        buf_count      <= next_buf_count;

                        if (s_axis_tlast) begin
                            packet_end_pending <= 1'b1;
                            state              <= DRAIN;
                        end else if (next_buf_count >= CNT_W'(OUT_BYTES)) begin
                            state <= DRAIN;
                        end
                    end
                end

                DRAIN: begin
                    if (m_axis_tready) begin
                        logic [BUF_BYTES*8-1:0] next_buf_data;
                        logic [CNT_W-1:0]       emitted_bytes;
                        logic [CNT_W-1:0]       next_buf_count;

                        emitted_bytes = out_valid_bytes;
                        next_buf_count = buf_count - emitted_bytes;
                        next_buf_data  = '0;

                        for (int i = 0; i < BUF_BYTES; i++) begin
                            if ((i + int'(emitted_bytes)) < int'(buf_count))
                                next_buf_data[i*8 +: 8] =
                                    buf_data[(i + int'(emitted_bytes))*8 +: 8];
                        end

                        buf_data  <= next_buf_data;
                        buf_count <= next_buf_count;

                        if (packet_end_pending) begin
                            if (buf_count <= CNT_W'(OUT_BYTES)) begin
                                packet_end_pending <= 1'b0;
                                state              <= FILL;
                            end else begin
                                state <= DRAIN;
                            end
                        end else if (next_buf_count >= CNT_W'(OUT_BYTES)) begin
                            state <= DRAIN;
                        end else begin
                            state <= FILL;
                        end
                    end
                end
            endcase
        end
    end

endmodule

`default_nettype wire

module snix_axi_vdma_mm2s #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32,
    parameter int ID_WIDTH   = 4,
    parameter int USER_WIDTH = 1,
    parameter int FIFO_DEPTH = 64
) (
    input  logic                     clk,
    input  logic                     rst_n,

    input  logic                     frame_start,
    input  logic                     frame_stop,
    input  logic [ADDR_WIDTH-1:0]    frame_addr,
    input  logic [31:0]              frame_stride,
    input  logic [31:0]              frame_hsize_bytes,
    input  logic [31:0]              frame_vsize_lines,
    input  logic [7:0]               burst_len,
    input  logic [2:0]               beat_size,
    output logic                     frame_busy,
    output logic                     frame_done,
    output logic                     frame_error,
    output logic                     axi_error,

    output logic [DATA_WIDTH-1:0]    m_axis_tdata,
    output logic [USER_WIDTH-1:0]    m_axis_tuser,
    output logic [DATA_WIDTH/8-1:0]  m_axis_tkeep,
    output logic                     m_axis_tvalid,
    input  logic                     m_axis_tready,
    output logic                     m_axis_tlast,

    output logic [ID_WIDTH-1:0]      mm2s_arid,
    output logic [ADDR_WIDTH-1:0]    mm2s_araddr,
    output logic [7:0]               mm2s_arlen,
    output logic [2:0]               mm2s_arsize,
    output logic [1:0]               mm2s_arburst,
    output logic                     mm2s_arlock,
    output logic [3:0]               mm2s_arcache,
    output logic [2:0]               mm2s_arprot,
    output logic [3:0]               mm2s_arqos,
    output logic [USER_WIDTH-1:0]    mm2s_aruser,
    output logic                     mm2s_arvalid,
    input  logic                     mm2s_arready,

    input  logic [ID_WIDTH-1:0]      mm2s_rid,
    input  logic [DATA_WIDTH-1:0]    mm2s_rdata,
    input  logic [1:0]               mm2s_rresp,
    input  logic                     mm2s_rlast,
    input  logic [USER_WIDTH-1:0]    mm2s_ruser,
    input  logic                     mm2s_rvalid,
    output logic                     mm2s_rready
);

    localparam int BYTES_PER_BEAT = DATA_WIDTH / 8;
    localparam int MAX_OUTSTANDING = 4;
    localparam logic [15:0] MAX_OUTSTANDING_BURSTS = MAX_OUTSTANDING[15:0];
    localparam logic [16:0] FIFO_RESERVE_LIMIT = (FIFO_DEPTH - 1);

    typedef enum logic [1:0] {IDLE, ACTIVE, WAIT_OUTPUT, ABORT} state_t;
    state_t state;

    logic [31:0]           output_line;
    logic [31:0]           output_beat;
    logic                  output_complete;

    logic [31:0]           read_line;
    logic [ADDR_WIDTH-1:0] line_addr;
    logic [ADDR_WIDTH-1:0] next_read_addr;
    logic [31:0]           line_bytes_remaining;
    logic [31:0]           aligned_line_bytes;
    logic [31:0]           beats_per_line;
    logic                  schedule_complete;

    logic [14:0]           max_burst_bytes;
    logic [14:0]           bytes_to_4k;
    logic [14:0]           burst_bytes;
    logic [15:0]           burst_beats;
    logic [7:0]            burst_arlen;
    logic [31:0]           remaining_after_burst;
    logic                  can_issue_ar;
    logic                  ar_gap;
    logic                  ar_fire;
    logic                  r_fire;
    logic                  output_fire;
    logic [15:0]           reserved_beats;
    logic [15:0]           outstanding_bursts;
    logic [15:0]           reserved_beats_next;
    logic [15:0]           outstanding_bursts_next;
    logic [16:0]           reserved_plus_burst;
    logic                  schedule_last_fire;
    logic                  schedule_done_next;

    logic [DATA_WIDTH-1:0] fifo_tdata;
    logic [USER_WIDTH-1:0] fifo_tuser_unused;
    logic                  fifo_tvalid;
    logic                  fifo_tlast_unused;
    logic                  fifo_s_tready;

    assign beats_per_line = (frame_hsize_bytes + BYTES_PER_BEAT - 1) /
                            BYTES_PER_BEAT;

    always_comb begin
        case (beat_size)
            3'b000: aligned_line_bytes = frame_hsize_bytes;
            3'b001: aligned_line_bytes = (frame_hsize_bytes + 32'd1) & ~32'd1;
            3'b010: aligned_line_bytes = (frame_hsize_bytes + 32'd3) & ~32'd3;
            3'b011: aligned_line_bytes = (frame_hsize_bytes + 32'd7) & ~32'd7;
            3'b100: aligned_line_bytes = (frame_hsize_bytes + 32'd15) & ~32'd15;
            3'b101: aligned_line_bytes = (frame_hsize_bytes + 32'd31) & ~32'd31;
            3'b110: aligned_line_bytes = (frame_hsize_bytes + 32'd63) & ~32'd63;
            3'b111: aligned_line_bytes = (frame_hsize_bytes + 32'd127) & ~32'd127;
        endcase
    end

    assign max_burst_bytes = compute_num_bytes(burst_len, beat_size);
    assign bytes_to_4k = ({1'b0, max_burst_bytes} +
                          {4'b0, next_read_addr[11:0]} >= 16'd4096)
                         ? (15'd4096 - {3'b0, next_read_addr[11:0]})
                         : max_burst_bytes;

    always_comb begin
        burst_bytes = max_burst_bytes;
        if (bytes_to_4k < burst_bytes)
            burst_bytes = bytes_to_4k;
        if (line_bytes_remaining[14:0] < burst_bytes)
            burst_bytes = line_bytes_remaining[14:0];
        burst_arlen = compute_next_len(burst_bytes, beat_size);
    end

    assign burst_beats = {8'b0, burst_arlen} + 16'd1;
    assign remaining_after_burst = line_bytes_remaining -
                                   {17'b0, burst_bytes};
    assign reserved_plus_burst = {1'b0, reserved_beats} +
                                 {1'b0, burst_beats};
    assign can_issue_ar = frame_busy && !schedule_complete &&
                          !ar_gap &&
                          (line_bytes_remaining != 0) &&
                          (outstanding_bursts < MAX_OUTSTANDING_BURSTS) &&
                          (reserved_plus_burst <= FIFO_RESERVE_LIMIT);
    assign ar_fire     = mm2s_arvalid && mm2s_arready;
    assign r_fire      = mm2s_rvalid && mm2s_rready;
    assign output_fire = m_axis_tvalid && m_axis_tready && frame_busy;

    assign reserved_beats_next = reserved_beats +
                                 (ar_fire ? burst_beats : 16'd0) -
                                 (output_fire ? 16'd1 : 16'd0);
    assign outstanding_bursts_next = outstanding_bursts +
                                     (ar_fire ? 16'd1 : 16'd0) -
                                     ((r_fire && mm2s_rlast) ?
                                      16'd1 : 16'd0);
    assign schedule_last_fire = ar_fire && (remaining_after_burst == 0) &&
                                (read_line + 1 >= frame_vsize_lines);
    assign schedule_done_next = schedule_complete || schedule_last_fire;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state                <= IDLE;
            frame_busy           <= 1'b0;
            frame_done           <= 1'b0;
            frame_error          <= 1'b0;
            axi_error            <= 1'b0;
            read_line            <= '0;
            line_addr            <= '0;
            next_read_addr       <= '0;
            line_bytes_remaining <= '0;
            schedule_complete    <= 1'b0;
            reserved_beats       <= '0;
            outstanding_bursts   <= '0;
            ar_gap               <= 1'b0;
        end else begin
            frame_done <= 1'b0;
            ar_gap     <= 1'b0;

            case (state)
                IDLE: begin
                    if (frame_start) begin
                        frame_busy           <= 1'b1;
                        frame_error          <= (frame_hsize_bytes == 0) ||
                                                (frame_vsize_lines == 0);
                        axi_error            <= 1'b0;
                        read_line            <= '0;
                        line_addr            <= frame_addr;
                        next_read_addr       <= frame_addr;
                        line_bytes_remaining <= aligned_line_bytes;
                        schedule_complete    <= 1'b0;
                        reserved_beats       <= '0;
                        outstanding_bursts   <= '0;
                        ar_gap               <= 1'b0;
                        state                <= ((frame_hsize_bytes == 0) ||
                                                 (frame_vsize_lines == 0)) ?
                                                WAIT_OUTPUT : ACTIVE;
                    end
                end

                ACTIVE: begin
                    if (r_fire && (mm2s_rresp != 2'b00)) begin
                        axi_error   <= 1'b1;
                        frame_error <= 1'b1;
                    end

                    if (frame_stop) begin
                        frame_error <= 1'b1;
                        state       <= ABORT;
                    end else begin
                        if (ar_fire) begin
                            ar_gap <= 1'b1;
                            next_read_addr <= next_read_addr +
                                              {{(ADDR_WIDTH-15){1'b0}},
                                               burst_bytes};
                            if (remaining_after_burst == 0) begin
                                line_bytes_remaining <= aligned_line_bytes;
                                if (read_line + 1 >= frame_vsize_lines) begin
                                    schedule_complete <= 1'b1;
                                end else begin
                                    read_line      <= read_line + 1'b1;
                                    line_addr      <= line_addr +
                                                      ADDR_WIDTH'(frame_stride);
                                    next_read_addr <= line_addr +
                                                      ADDR_WIDTH'(frame_stride);
                                end
                            end else begin
                                line_bytes_remaining <= remaining_after_burst;
                            end
                        end

                        reserved_beats     <= reserved_beats_next;
                        outstanding_bursts <= outstanding_bursts_next;

                        if (schedule_done_next &&
                            (outstanding_bursts_next == 0)) begin
                            state <= WAIT_OUTPUT;
                        end
                    end
                end

                WAIT_OUTPUT: begin
                    if (frame_stop) begin
                        frame_error <= 1'b1;
                        frame_busy  <= 1'b0;
                        frame_done  <= 1'b1;
                        state       <= IDLE;
                    end else if (output_complete) begin
                        frame_busy <= 1'b0;
                        frame_done <= 1'b1;
                        state      <= IDLE;
                    end
                end

                ABORT: begin
                    frame_error <= 1'b1;
                    if (r_fire && (mm2s_rresp != 2'b00))
                        axi_error <= 1'b1;
                    if (output_fire && (reserved_beats != 0))
                        reserved_beats <= reserved_beats - 16'd1;
                    if (r_fire && mm2s_rlast) begin
                        if (outstanding_bursts > 1) begin
                            outstanding_bursts <= outstanding_bursts - 16'd1;
                        end else begin
                            outstanding_bursts <= '0;
                            frame_busy <= 1'b0;
                            frame_done <= 1'b1;
                            state      <= IDLE;
                        end
                    end else if (outstanding_bursts == 0) begin
                        frame_busy <= 1'b0;
                        frame_done <= 1'b1;
                        state      <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            output_line     <= '0;
            output_beat     <= '0;
            output_complete <= 1'b0;
        end else if (frame_start) begin
            output_line     <= '0;
            output_beat     <= '0;
            output_complete <= 1'b0;
        end else if (output_fire) begin
            if (m_axis_tlast && (output_line + 1 >= frame_vsize_lines))
                output_complete <= 1'b1;

            if (output_beat + 1 >= beats_per_line) begin
                output_beat <= '0;
                output_line <= output_line + 1'b1;
            end else begin
                output_beat <= output_beat + 1'b1;
            end
        end
    end

    assign mm2s_arvalid = (state == ACTIVE) && can_issue_ar;
    assign mm2s_araddr  = next_read_addr;
    assign mm2s_arlen   = burst_arlen;
    assign mm2s_arsize  = beat_size;
    assign mm2s_arburst = 2'b01;
    assign mm2s_arlock  = 1'b0;
    assign mm2s_arcache = 4'b0;
    assign mm2s_arprot  = 3'b0;
    assign mm2s_arqos   = 4'b0;
    assign mm2s_arid    = '0;
    assign mm2s_aruser  = '0;

    assign mm2s_rready = fifo_s_tready && ((state == ACTIVE) || (state == ABORT));

    snix_axis_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .USER_WIDTH(USER_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) u_fifo (
        .clk,
        .rst_n,
        .s_axis_tdata  (mm2s_rdata),
        .s_axis_tuser  ('0),
        .s_axis_tvalid (mm2s_rvalid && ((state == ACTIVE) || (state == ABORT))),
        .s_axis_tlast  (mm2s_rlast),
        .s_axis_tready (fifo_s_tready),
        .m_axis_tdata  (fifo_tdata),
        .m_axis_tuser  (fifo_tuser_unused),
        .m_axis_tvalid (fifo_tvalid),
        .m_axis_tlast  (fifo_tlast_unused),
        .m_axis_tready (m_axis_tready && frame_busy)
    );

    assign m_axis_tdata  = fifo_tdata;
    assign m_axis_tvalid = fifo_tvalid && frame_busy;
    assign m_axis_tlast  = (output_beat + 1 >= beats_per_line) &&
                           m_axis_tvalid;

    always_comb begin
        int valid_bytes;
        valid_bytes = int'(frame_hsize_bytes % BYTES_PER_BEAT);
        m_axis_tkeep = '1;
        if ((output_beat + 1 >= beats_per_line) && (valid_bytes != 0)) begin
            m_axis_tkeep = '0;
            for (int lane = 0; lane < BYTES_PER_BEAT; lane++)
                if (lane < valid_bytes)
                    m_axis_tkeep[lane] = 1'b1;
        end
    end

    always_comb begin
        m_axis_tuser    = '0;
        m_axis_tuser[0] = (output_line == 0) && (output_beat == 0) &&
                          m_axis_tvalid;
    end

    function automatic [14:0] compute_num_bytes(
        input logic [7:0] len,
        input logic [2:0] size
    );
        case (size)
            3'b000: compute_num_bytes = {7'b0, len + 1'b1};
            3'b001: compute_num_bytes = {6'b0, len + 1'b1, 1'b0};
            3'b010: compute_num_bytes = {5'b0, len + 1'b1, 2'b0};
            3'b011: compute_num_bytes = {4'b0, len + 1'b1, 3'b0};
            3'b100: compute_num_bytes = {3'b0, len + 1'b1, 4'b0};
            3'b101: compute_num_bytes = {2'b0, len + 1'b1, 5'b0};
            3'b110: compute_num_bytes = {1'b0, len + 1'b1, 6'b0};
            3'b111: compute_num_bytes = {      len + 1'b1, 7'b0};
        endcase
    endfunction

    function automatic [7:0] compute_next_len(
        input logic [14:0] bytes_i,
        input logic [2:0]  size
    );
        logic [14:0] num_beats;

        case(size)
            3'b000: num_beats = bytes_i;
            3'b001: num_beats = (bytes_i + 15'd1) >> 1;
            3'b010: num_beats = (bytes_i + 15'd3) >> 2;
            3'b011: num_beats = (bytes_i + 15'd7) >> 3;
            3'b100: num_beats = (bytes_i + 15'd15) >> 4;
            3'b101: num_beats = (bytes_i + 15'd31) >> 5;
            3'b110: num_beats = (bytes_i + 15'd63) >> 6;
            3'b111: num_beats = (bytes_i + 15'd127) >> 7;
        endcase

        if (num_beats == 15'd0)
            compute_next_len = 8'd0;
        else
            compute_next_len = num_beats[7:0] - 8'd1;
    endfunction

endmodule : snix_axi_vdma_mm2s

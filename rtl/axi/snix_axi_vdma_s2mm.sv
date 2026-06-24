module snix_axi_vdma_s2mm #(
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

    input  logic [DATA_WIDTH-1:0]    s_axis_tdata,
    input  logic [USER_WIDTH-1:0]    s_axis_tuser,
    input  logic [DATA_WIDTH/8-1:0]  s_axis_tkeep,
    input  logic                     s_axis_tvalid,
    output logic                     s_axis_tready,
    input  logic                     s_axis_tlast,

    output logic [ID_WIDTH-1:0]      s2mm_awid,
    output logic [ADDR_WIDTH-1:0]    s2mm_awaddr,
    output logic [7:0]               s2mm_awlen,
    output logic [2:0]               s2mm_awsize,
    output logic [1:0]               s2mm_awburst,
    output logic                     s2mm_awlock,
    output logic [3:0]               s2mm_awcache,
    output logic [2:0]               s2mm_awprot,
    output logic [3:0]               s2mm_awqos,
    output logic [USER_WIDTH-1:0]    s2mm_awuser,
    output logic                     s2mm_awvalid,
    input  logic                     s2mm_awready,

    output logic [DATA_WIDTH-1:0]    s2mm_wdata,
    output logic [DATA_WIDTH/8-1:0]  s2mm_wstrb,
    output logic                     s2mm_wlast,
    output logic [USER_WIDTH-1:0]    s2mm_wuser,
    output logic                     s2mm_wvalid,
    input  logic                     s2mm_wready,

    input  logic [ID_WIDTH-1:0]      s2mm_bid,
    input  logic [1:0]               s2mm_bresp,
    input  logic [USER_WIDTH-1:0]    s2mm_buser,
    input  logic                     s2mm_bvalid,
    output logic                     s2mm_bready
);

    localparam int BYTES_PER_BEAT = DATA_WIDTH / 8;
    localparam int STRB_WIDTH     = DATA_WIDTH / 8;
    localparam int STRB_IDX_WIDTH = $clog2(STRB_WIDTH) + 1;
    localparam int MAX_OUTSTANDING = 4;
    localparam int DESC_PTR_WIDTH = $clog2(MAX_OUTSTANDING);
    localparam logic [15:0] MAX_OUTSTANDING_BURSTS = MAX_OUTSTANDING[15:0];

    typedef enum logic [1:0] {IDLE, ACTIVE, ABORT} state_t;
    state_t state;

    logic [31:0]           input_line;
    logic [31:0]           input_beat;
    logic [31:0]           beats_per_line;
    logic                  marker_error;
    logic                  config_error;
    logic                  abort_error;
    logic                  input_complete;

    logic [31:0]           write_line;
    logic [ADDR_WIDTH-1:0] line_addr;
    logic [ADDR_WIDTH-1:0] next_write_addr;
    logic [31:0]           line_bytes_remaining;
    logic                  schedule_complete;

    logic [14:0]           max_burst_bytes;
    logic [14:0]           bytes_to_4k;
    logic [14:0]           burst_bytes;
    logic [15:0]           burst_beats;
    logic [7:0]            burst_awlen;
    logic [31:0]           remaining_after_burst;
    logic                  can_issue_aw;
    logic                  aw_gap;
    logic                  aw_fire;
    logic                  w_fire;
    logic                  b_fire;
    logic                  w_active;
    logic                  w_active_next;
    logic [15:0]           w_beats_remaining;
    logic [14:0]           bytes_in_burst;
    logic [15:0]           outstanding_bursts;
    logic [15:0]           outstanding_bursts_next;
    logic                  schedule_last_fire;
    logic                  schedule_done_next;

    logic [DATA_WIDTH-1:0] fifo_tdata;
    logic                  fifo_tvalid;
    logic                  fifo_tlast_unused;
    logic                  fifo_tuser_unused;
    logic                  fifo_s_tready;

    logic [STRB_WIDTH-1:0]    wstrb_mask;
    logic [STRB_WIDTH-1:0]    partial_strb_mask;
    logic [STRB_IDX_WIDTH-1:0] valid_bytes;

    logic [7:0]                     desc_awlen_q [MAX_OUTSTANDING];
    logic [14:0]                    desc_bytes_q [MAX_OUTSTANDING];
    logic [DESC_PTR_WIDTH-1:0]      desc_wr_ptr;
    logic [DESC_PTR_WIDTH-1:0]      desc_rd_ptr;
    logic [15:0]                    desc_count;
    logic [15:0]                    desc_count_next;
    logic                           desc_full;
    logic                           desc_pop;
    logic [15:0]                    desc_pop_beats;
    logic [14:0]                    desc_pop_bytes;

    assign beats_per_line = (frame_hsize_bytes + BYTES_PER_BEAT - 1) /
                            BYTES_PER_BEAT;
    assign frame_error = marker_error || config_error || abort_error ||
                         axi_error;

    assign max_burst_bytes = compute_num_bytes(burst_len, beat_size);
    assign bytes_to_4k = ({1'b0, max_burst_bytes} +
                          {4'b0, next_write_addr[11:0]} >= 16'd4096)
                         ? (15'd4096 - {3'b0, next_write_addr[11:0]})
                         : max_burst_bytes;

    always_comb begin
        burst_bytes = max_burst_bytes;
        if (bytes_to_4k < burst_bytes)
            burst_bytes = bytes_to_4k;
        if (line_bytes_remaining[14:0] < burst_bytes)
            burst_bytes = line_bytes_remaining[14:0];
        burst_awlen = compute_next_len(burst_bytes, beat_size);
    end

    assign burst_beats = {8'b0, burst_awlen} + 16'd1;
    assign remaining_after_burst = line_bytes_remaining -
                                   {17'b0, burst_bytes};

    assign aw_fire = s2mm_awvalid && s2mm_awready;
    assign w_fire  = s2mm_wvalid && s2mm_wready;
    assign b_fire  = s2mm_bvalid && s2mm_bready;

    assign desc_full = (desc_count >= MAX_OUTSTANDING_BURSTS);
    assign desc_pop = !w_active && (desc_count != 0) &&
                      ((state == ACTIVE) || (state == ABORT));
    assign desc_pop_beats = {8'b0, desc_awlen_q[desc_rd_ptr]} + 16'd1;
    assign desc_pop_bytes = desc_bytes_q[desc_rd_ptr];
    assign desc_count_next = desc_count +
                             (aw_fire ? 16'd1 : 16'd0) -
                             (desc_pop ? 16'd1 : 16'd0);
    assign w_active_next = desc_pop ? 1'b1 :
                           (w_fire && (w_beats_remaining <= 16'd1)) ?
                           1'b0 : w_active;

    assign can_issue_aw = (state == ACTIVE) && frame_busy &&
                          !schedule_complete && !aw_gap &&
                          !desc_full &&
                          (line_bytes_remaining != 0) &&
                          (outstanding_bursts < MAX_OUTSTANDING_BURSTS);

    assign outstanding_bursts_next = outstanding_bursts +
                                     (aw_fire ? 16'd1 : 16'd0) -
                                     (b_fire ? 16'd1 : 16'd0);
    assign schedule_last_fire = aw_fire && (remaining_after_burst == 0) &&
                                (write_line + 1 >= frame_vsize_lines);
    assign schedule_done_next = schedule_complete || schedule_last_fire;

    // Stop accepting stream data once the configured frame geometry has been
    // consumed. The writer may remain busy until the final BRESP drains.
    assign s_axis_tready = fifo_s_tready && frame_busy &&
                           (state == ACTIVE) &&
                           (input_line < frame_vsize_lines);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state                <= IDLE;
            frame_busy           <= 1'b0;
            frame_done           <= 1'b0;
            config_error         <= 1'b0;
            abort_error          <= 1'b0;
            axi_error            <= 1'b0;
            write_line           <= '0;
            line_addr            <= '0;
            next_write_addr      <= '0;
            line_bytes_remaining <= '0;
            schedule_complete    <= 1'b0;
            outstanding_bursts   <= '0;
            desc_wr_ptr          <= '0;
            desc_rd_ptr          <= '0;
            desc_count           <= '0;
            aw_gap               <= 1'b0;
            w_active             <= 1'b0;
            w_beats_remaining    <= '0;
            bytes_in_burst       <= '0;
        end else begin
            frame_done <= 1'b0;
            aw_gap     <= 1'b0;

            if (b_fire && (s2mm_bresp != 2'b00)) begin
                axi_error <= 1'b1;
            end

            case (state)
                IDLE: begin
                    if (frame_start) begin
                        frame_busy           <= 1'b1;
                        config_error         <= (frame_hsize_bytes == 0) ||
                                                (frame_vsize_lines == 0);
                        abort_error          <= 1'b0;
                        axi_error            <= 1'b0;
                        write_line           <= '0;
                        line_addr            <= frame_addr;
                        next_write_addr      <= frame_addr;
                        line_bytes_remaining <= frame_hsize_bytes;
                        schedule_complete    <= 1'b0;
                        outstanding_bursts   <= '0;
                        desc_wr_ptr          <= '0;
                        desc_rd_ptr          <= '0;
                        desc_count           <= '0;
                        aw_gap               <= 1'b0;
                        w_active             <= 1'b0;
                        w_beats_remaining    <= '0;
                        bytes_in_burst       <= '0;
                        state                <= ((frame_hsize_bytes == 0) ||
                                                 (frame_vsize_lines == 0)) ?
                                                ABORT : ACTIVE;
                    end
                end

                ACTIVE: begin
                    if (frame_stop) begin
                        abort_error <= 1'b1;
                        state       <= ABORT;
                    end

                    if (aw_fire) begin
                        aw_gap <= 1'b1;
                        desc_awlen_q[desc_wr_ptr] <= burst_awlen;
                        desc_bytes_q[desc_wr_ptr] <= burst_bytes;
                        desc_wr_ptr <= desc_wr_ptr + 1'b1;
                        next_write_addr   <= next_write_addr +
                                             {{(ADDR_WIDTH-15){1'b0}},
                                              burst_bytes};

                        if (remaining_after_burst == 0) begin
                            line_bytes_remaining <= frame_hsize_bytes;
                            if (write_line + 1 >= frame_vsize_lines) begin
                                schedule_complete <= 1'b1;
                            end else begin
                                write_line      <= write_line + 1'b1;
                                line_addr       <= line_addr +
                                                   ADDR_WIDTH'(frame_stride);
                                next_write_addr <= line_addr +
                                                   ADDR_WIDTH'(frame_stride);
                            end
                        end else begin
                            line_bytes_remaining <= remaining_after_burst;
                        end
                    end

                    if (desc_pop) begin
                        desc_rd_ptr       <= desc_rd_ptr + 1'b1;
                        w_active          <= 1'b1;
                        w_beats_remaining <= desc_pop_beats;
                        bytes_in_burst    <= desc_pop_bytes;
                    end else if (w_fire) begin
                        if (w_beats_remaining > 1) begin
                            w_beats_remaining <= w_beats_remaining - 16'd1;
                            bytes_in_burst    <= (bytes_in_burst >
                                                  STRB_WIDTH[14:0])
                                                 ? (bytes_in_burst -
                                                    STRB_WIDTH[14:0])
                                                 : 15'd0;
                        end else begin
                            w_beats_remaining <= '0;
                            bytes_in_burst    <= '0;
                            w_active          <= 1'b0;
                        end
                    end

                    outstanding_bursts <= outstanding_bursts_next;
                    desc_count         <= desc_count_next;

                    if (schedule_done_next &&
                        (outstanding_bursts_next == 0) &&
                        (desc_count_next == 0) &&
                        !w_active_next) begin
                        frame_busy <= 1'b0;
                        frame_done <= 1'b1;
                        state      <= IDLE;
                    end
                end

                ABORT: begin
                    if (desc_pop) begin
                        desc_rd_ptr       <= desc_rd_ptr + 1'b1;
                        w_active          <= 1'b1;
                        w_beats_remaining <= desc_pop_beats;
                        bytes_in_burst    <= desc_pop_bytes;
                    end else if (w_fire) begin
                        if (w_beats_remaining > 1) begin
                            w_beats_remaining <= w_beats_remaining - 16'd1;
                            bytes_in_burst    <= (bytes_in_burst >
                                                  STRB_WIDTH[14:0])
                                                 ? (bytes_in_burst -
                                                    STRB_WIDTH[14:0])
                                                 : 15'd0;
                        end else begin
                            w_beats_remaining <= '0;
                            bytes_in_burst    <= '0;
                            w_active          <= 1'b0;
                        end
                    end

                    outstanding_bursts <= outstanding_bursts_next;
                    desc_count         <= desc_count_next;

                    if ((outstanding_bursts_next == 0) &&
                        (desc_count_next == 0) &&
                        !w_active_next) begin
                        frame_busy <= 1'b0;
                        frame_done <= 1'b1;
                        state      <= IDLE;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

    // Validate AXI4-Stream video markers independently of the memory writer.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            input_line     <= '0;
            input_beat     <= '0;
            input_complete <= 1'b0;
            marker_error   <= 1'b0;
        end else if (frame_start) begin
            input_line     <= '0;
            input_beat     <= '0;
            input_complete <= 1'b0;
            marker_error   <= 1'b0;
        end else if (s_axis_tvalid && s_axis_tready && frame_busy) begin
            logic [BYTES_PER_BEAT-1:0] expected_keep;
            int video_valid_bytes;
            video_valid_bytes = int'(frame_hsize_bytes % BYTES_PER_BEAT);
            expected_keep = '1;
            if ((input_beat + 1 >= beats_per_line) &&
                (video_valid_bytes != 0)) begin
                expected_keep = '0;
                for (int lane = 0; lane < BYTES_PER_BEAT; lane++)
                    if (lane < video_valid_bytes)
                        expected_keep[lane] = 1'b1;
            end

            if ((s_axis_tuser[0] != ((input_line == 0) && (input_beat == 0))) ||
                (s_axis_tlast != (input_beat + 1 >= beats_per_line)) ||
                (s_axis_tkeep != expected_keep))
                marker_error <= 1'b1;

            if (input_beat + 1 >= beats_per_line) begin
                input_beat <= '0;
                if (input_line + 1 >= frame_vsize_lines) begin
                    input_complete <= 1'b1;
                    input_line     <= input_line + 1'b1;
                end else begin
                    input_line <= input_line + 1'b1;
                end
            end else begin
                input_beat <= input_beat + 1'b1;
            end
        end
    end

    snix_axis_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .FIFO_DEPTH(FIFO_DEPTH)
    ) u_fifo (
        .clk,
        .rst_n,
        .s_axis_tdata  (s_axis_tdata),
        .s_axis_tlast  (s_axis_tlast),
        .s_axis_tuser  ('0),
        .s_axis_tvalid (s_axis_tvalid && frame_busy &&
                        (state == ACTIVE) &&
                        (input_line < frame_vsize_lines)),
        .s_axis_tready (fifo_s_tready),
        .m_axis_tdata  (fifo_tdata),
        .m_axis_tlast  (fifo_tlast_unused),
        .m_axis_tuser  (fifo_tuser_unused),
        .m_axis_tvalid (fifo_tvalid),
        .m_axis_tready (w_active && s2mm_wready)
    );

    assign valid_bytes = (bytes_in_burst <= STRB_WIDTH[14:0])
                         ? bytes_in_burst[STRB_IDX_WIDTH-1:0]
                         : STRB_WIDTH[STRB_IDX_WIDTH-1:0];

    always_comb begin
        partial_strb_mask = '0;
        for (int lane = 0; lane < STRB_WIDTH; lane++)
            if (lane < valid_bytes)
                partial_strb_mask[lane] = 1'b1;
    end

    always_comb begin
        if (s2mm_wlast && (bytes_in_burst < STRB_WIDTH[14:0]) &&
            (bytes_in_burst != '0))
            wstrb_mask = partial_strb_mask;
        else if (bytes_in_burst == '0)
            wstrb_mask = '0;
        else
            wstrb_mask = '1;
    end

    assign s2mm_awvalid = can_issue_aw;
    assign s2mm_awaddr  = next_write_addr;
    assign s2mm_awlen   = burst_awlen;
    assign s2mm_awsize  = beat_size;
    assign s2mm_awburst = 2'b01;
    assign s2mm_awid    = '0;
    assign s2mm_awlock  = 1'b0;
    assign s2mm_awcache = 4'b0;
    assign s2mm_awprot  = 3'b0;
    assign s2mm_awqos   = 4'b0;
    assign s2mm_awuser  = '0;

    generate
        for (genvar i = 0; i < STRB_WIDTH; i++) begin : gen_wdata_mask
            assign s2mm_wdata[i*8 +: 8] = wstrb_mask[i] ?
                                           fifo_tdata[i*8 +: 8] : 8'h00;
        end
    endgenerate

    assign s2mm_wvalid = w_active && fifo_tvalid;
    assign s2mm_wlast  = w_active && (w_beats_remaining == 16'd1) &&
                         s2mm_wvalid;
    assign s2mm_wstrb  = wstrb_mask;
    assign s2mm_wuser  = '0;
    assign s2mm_bready = (state == ACTIVE) || (state == ABORT);

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

endmodule : snix_axi_vdma_s2mm

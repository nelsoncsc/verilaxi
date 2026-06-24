module snix_axi_vdma_frame_store #(
    parameter int ADDR_WIDTH = 32
) (
    input  logic                  clk,
    input  logic                  rst_n,
    input  logic                  enable,
    input  logic                  park_mode,
    input  logic [1:0]            park_slot,
    input  logic [1:0]            frame_delay,
    input  logic [ADDR_WIDTH-1:0] frame_addr0,
    input  logic [ADDR_WIDTH-1:0] frame_addr1,
    input  logic [ADDR_WIDTH-1:0] frame_addr2,
    input  logic                  wr_frame_start,
    input  logic                  wr_frame_done,
    input  logic                  rd_frame_start,
    input  logic                  rd_frame_busy,
    output logic [ADDR_WIDTH-1:0] wr_frame_addr,
    output logic [ADDR_WIDTH-1:0] rd_frame_addr,
    output logic [1:0]            write_slot,
    output logic [1:0]            read_slot,
    output logic [1:0]            newest_complete_slot,
    output logic [2:0]            valid_slots,
    output logic                  rd_frame_available,
    output logic                  overwrite_event
);

    logic [1:0] rd_candidate;
    logic [1:0] delayed_candidate;

    function automatic logic [ADDR_WIDTH-1:0] slot_addr(input logic [1:0] slot);
        case (slot)
            2'd1: slot_addr = frame_addr1;
            2'd2: slot_addr = frame_addr2;
            default: slot_addr = frame_addr0;
        endcase
    endfunction

    function automatic logic [1:0] delayed_slot(
        input logic [1:0] newest,
        input logic [1:0] delay
    );
        case (delay)
            2'd0: delayed_slot = newest;
            2'd1: delayed_slot = (newest == 2'd0) ? 2'd2 : newest - 1'b1;
            default: begin
                case (newest)
                    2'd0: delayed_slot = 2'd1;
                    2'd1: delayed_slot = 2'd2;
                    default: delayed_slot = 2'd0;
                endcase
            end
        endcase
    endfunction

    function automatic logic [1:0] next_write_slot(
        input logic [1:0] current,
        input logic [1:0] active_read,
        input logic       reader_active
    );
        logic [1:0] candidate;
        candidate = (current == 2'd2) ? 2'd0 : current + 1'b1;
        if (reader_active && (candidate == active_read))
            candidate = (candidate == 2'd2) ? 2'd0 : candidate + 1'b1;
        next_write_slot = candidate;
    endfunction

    always_comb begin
        delayed_candidate = delayed_slot(newest_complete_slot, frame_delay);
        if (park_mode && (park_slot <= 2'd2) && valid_slots[park_slot])
            rd_candidate = park_slot;
        else if (valid_slots[delayed_candidate])
            rd_candidate = delayed_candidate;
        else if (valid_slots[newest_complete_slot])
            rd_candidate = newest_complete_slot;
        else
            rd_candidate = read_slot;

        wr_frame_addr = slot_addr(write_slot);
        rd_frame_addr = slot_addr(rd_candidate);
        rd_frame_available = (valid_slots != 3'b000) &&
                             (park_mode ? valid_slots[rd_candidate] : 1'b1);
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_slot          <= 2'd0;
            read_slot           <= 2'd0;
            newest_complete_slot <= 2'd0;
            valid_slots         <= 3'b000;
            overwrite_event     <= 1'b0;
        end else if (!enable) begin
            write_slot          <= 2'd0;
            read_slot           <= 2'd0;
            newest_complete_slot <= 2'd0;
            valid_slots         <= 3'b000;
            overwrite_event     <= 1'b0;
        end else begin
            overwrite_event <= wr_frame_start && valid_slots[write_slot];

            if (wr_frame_start)
                valid_slots[write_slot] <= 1'b0;

            if (rd_frame_start)
                read_slot <= rd_candidate;

            if (wr_frame_done) begin
                valid_slots[write_slot] <= 1'b1;
                newest_complete_slot    <= write_slot;
                write_slot <= next_write_slot(write_slot, read_slot,
                                               rd_frame_busy || rd_frame_start);
            end
        end
    end

    // wr_frame_start is intentionally present in this boundary manager's
    // interface: the selected write address remains stable for the full frame.
    logic unused_wr_start;
    assign unused_wr_start = wr_frame_start;

endmodule : snix_axi_vdma_frame_store

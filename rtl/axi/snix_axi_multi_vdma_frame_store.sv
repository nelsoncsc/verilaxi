// snix_axi_multi_vdma_frame_store — N-tap temporal frame store
//
// Manages NUM_SLOTS = NUM_TAPS+1 frame slots: one writer slot plus N reader
// slots (tap 0 = newest/current, tap 1 = previous, ..., tap N-1 = oldest).
//
// Port arrays are flat-packed for Yosys compatibility.
// Element i of a packed array is accessed as: signal[i*W +: W].
//
// Slot rotation policy:
//   - Writer advances to the next slot that is not read-locked by any tap.
//   - On wr_frame_done the completed slot enters the age queue at position 0;
//     existing entries shift down (age[1] <- age[0], ...).
//   - A tap holds its read lock from rd_frame_start[i] until rd_frame_done[i].
//   - rd_taps_available goes high once NUM_TAPS distinct complete frames exist.

module snix_axi_multi_vdma_frame_store #(
    parameter int NUM_TAPS   = 2,    // 1, 2, or 3
    parameter int ADDR_WIDTH = 32
) (
    input  logic clk,
    input  logic rst_n,
    input  logic enable,

    // Flat-packed slot addresses: slot i at [i*ADDR_WIDTH +: ADDR_WIDTH]
    // NUM_TAPS+1 slots total.
    input  logic [(NUM_TAPS+1)*ADDR_WIDTH-1:0] frame_addr_flat,

    // Writer
    input  logic                         wr_frame_start,
    input  logic                         wr_frame_done,
    output logic [ADDR_WIDTH-1:0]        wr_frame_addr,
    output logic                         wr_slot_available,
    output logic                         overwrite_event,

    // Readers (flat-packed): bit i = tap i
    input  logic [NUM_TAPS-1:0]          rd_frame_start,
    input  logic [NUM_TAPS-1:0]          rd_frame_done,
    // Flat-packed output addresses: tap i at [i*ADDR_WIDTH +: ADDR_WIDTH]
    output logic [NUM_TAPS*ADDR_WIDTH-1:0] rd_frame_addr_flat,
    output logic                           rd_taps_available,

    // Observability
    output logic [1:0]                   write_slot,
    output logic [NUM_TAPS*2-1:0]        tap_slot_flat,  // 2-bit slot per tap
    output logic [NUM_TAPS:0]            valid_slots,
    output logic [NUM_TAPS:0]            slot_read_locked
);
    localparam int NS = NUM_TAPS + 1;  // max 4

    // Internal unpacked arrays (fine for Yosys — only port-level is restricted)
    logic [1:0] age      [0:NUM_TAPS-1];
    logic       valid_age[0:NUM_TAPS-1];
    logic [1:0] rd_locked_slot[0:NUM_TAPS-1];
    logic       tap_rd_lock[0:NUM_TAPS-1];

    // Advance write slot, skipping read-locked slots.
    // Unrolled to NS steps (max 4) so Yosys can elaborate it without
    // needing to resolve a parameterised repeat bound in a function.
    function automatic logic [1:0] next_wr_slot(
        input logic [1:0]   current,
        input logic [3:0]   locked   // padded to 4 bits; upper bits 0 if NS<4
    );
        logic [1:0] c;
        c = (current == 2'(NS-1)) ? 2'd0 : current + 2'd1;
        if (locked[c]) c = (c == 2'(NS-1)) ? 2'd0 : c + 2'd1;
        if (locked[c]) c = (c == 2'(NS-1)) ? 2'd0 : c + 2'd1;
        if (locked[c]) c = (c == 2'(NS-1)) ? 2'd0 : c + 2'd1;
        next_wr_slot = c;
    endfunction

    // ── per-tap read lock (registered) ───────────────────────────────
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < NUM_TAPS; i++) begin
                tap_rd_lock[i]    <= 1'b0;
                rd_locked_slot[i] <= 2'd0;
            end
        end else if (!enable) begin
            for (int i = 0; i < NUM_TAPS; i++) begin
                tap_rd_lock[i]    <= 1'b0;
                rd_locked_slot[i] <= 2'd0;
            end
        end else begin
            for (int i = 0; i < NUM_TAPS; i++) begin
                if (rd_frame_start[i] && valid_age[i]) begin
                    tap_rd_lock[i]    <= 1'b1;
                    rd_locked_slot[i] <= age[i];
                end else if (rd_frame_done[i]) begin
                    tap_rd_lock[i] <= 1'b0;
                end
            end
        end
    end

    // Aggregate: which slot indices are read-locked
    always_comb begin
        for (int s = 0; s < NS; s++) begin
            slot_read_locked[s] = 1'b0;
            for (int i = 0; i < NUM_TAPS; i++)
                if (tap_rd_lock[i] && (rd_locked_slot[i] == 2'(s)))
                    slot_read_locked[s] = 1'b1;
        end
        for (int s = NS; s <= NUM_TAPS; s++)
            slot_read_locked[s] = 1'b0;
    end

    // ── write slot + age queue ────────────────────────────────────────
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_slot      <= 2'd0;
            valid_slots     <= '0;
            overwrite_event <= 1'b0;
            for (int i = 0; i < NUM_TAPS; i++) begin
                age[i]       <= 2'(i + 1);
                valid_age[i] <= 1'b0;
            end
        end else if (!enable) begin
            write_slot      <= 2'd0;
            valid_slots     <= '0;
            overwrite_event <= 1'b0;
            for (int i = 0; i < NUM_TAPS; i++) begin
                age[i]       <= 2'(i + 1);
                valid_age[i] <= 1'b0;
            end
        end else begin
            overwrite_event <= 1'b0;

            if (wr_frame_start)
                valid_slots[write_slot] <= 1'b0;

            if (wr_frame_done) begin
                valid_slots[write_slot] <= 1'b1;
                overwrite_event         <= valid_slots[write_slot];
                // Shift age queue: oldest drops off, newest enters at 0
                for (int i = NUM_TAPS-1; i > 0; i--) begin
                    age[i]       <= age[i-1];
                    valid_age[i] <= valid_age[i-1];
                end
                age[0]       <= write_slot;
                valid_age[0] <= 1'b1;
                write_slot   <= next_wr_slot(write_slot, 4'(slot_read_locked));
            end
        end
    end

    // ── output address mux ────────────────────────────────────────────
    always_comb begin
        wr_frame_addr     = frame_addr_flat[write_slot*ADDR_WIDTH +: ADDR_WIDTH];
        wr_slot_available = !slot_read_locked[write_slot];
        rd_taps_available = 1'b1;
        for (int i = 0; i < NUM_TAPS; i++) begin
            logic [1:0] ts;
            ts = valid_age[i] ? age[i] : 2'd0;
            tap_slot_flat[i*2 +: 2]               = ts;
            rd_frame_addr_flat[i*ADDR_WIDTH +: ADDR_WIDTH] =
                frame_addr_flat[ts*ADDR_WIDTH +: ADDR_WIDTH];
            if (!valid_age[i]) rd_taps_available = 1'b0;
        end
    end

endmodule : snix_axi_multi_vdma_frame_store

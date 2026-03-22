// snix_axis_upsizer.sv
//
// AXI-Stream width upsizer: packs RATIO consecutive narrow input beats
// into one wide output beat.  Beat[0] occupies the LSBs of the output
// word; Beat[RATIO-1] occupies the MSBs.
//
// Parameters
//   IN_DATA_WIDTH  — narrow-side bus width in bits (multiple of 8)
//   OUT_DATA_WIDTH — wide-side bus width; must equal N * IN_DATA_WIDTH
//                    for integer N >= 2
//
// TLAST / TKEEP
//   When TLAST arrives before phase reaches RATIO-1 (a short packet),
//   the partial word is emitted immediately.  Upper TKEEP lanes are
//   cleared to mark the unused byte positions.  A full-width packet
//   (RATIO beats with TLAST on the last) sets all TKEEP bits.
//
// Flow control
//   s_axis_tready is deasserted while an output word is waiting for the
//   downstream (r_tvalid && !m_axis_tready), so m_axis_tvalid never
//   deasserts between handshakes.

`default_nettype none

module snix_axis_upsizer #(
    parameter int IN_DATA_WIDTH  = 8,   // narrow-side width in bits (multiple of 8)
    parameter int OUT_DATA_WIDTH = 32   // wide-side width; must be N*IN_DATA_WIDTH, N>=2
) (
    input  wire  clk,
    input  wire  rst_n,

    // Slave — narrow (IN_DATA_WIDTH bits)
    input  wire  [IN_DATA_WIDTH-1:0]    s_axis_tdata,
    input  wire  [IN_DATA_WIDTH/8-1:0]  s_axis_tkeep,
    input  wire                         s_axis_tvalid,
    output logic                        s_axis_tready,
    input  wire                         s_axis_tlast,

    // Master — wide (OUT_DATA_WIDTH bits)
    output logic [OUT_DATA_WIDTH-1:0]   m_axis_tdata,
    output logic [OUT_DATA_WIDTH/8-1:0] m_axis_tkeep,
    output logic                        m_axis_tvalid,
    input  wire                         m_axis_tready,
    output logic                        m_axis_tlast
);

    localparam int RATIO      = OUT_DATA_WIDTH / IN_DATA_WIDTH;
    localparam int IN_KEEP_W  = IN_DATA_WIDTH  / 8;
    localparam int OUT_KEEP_W = OUT_DATA_WIDTH / 8;
    localparam int PHASE_W    = (RATIO < 2) ? 1 : $clog2(RATIO);

    // ------------------------------------------------------------------ //
    //  Beat buffer: accumulates phases 0 .. RATIO-2                       //
    // ------------------------------------------------------------------ //
    logic [RATIO-1:0][IN_DATA_WIDTH-1:0] buf_data;
    logic [RATIO-1:0][IN_KEEP_W-1:0]    buf_keep;
    logic [PHASE_W-1:0]                 phase;

    // ------------------------------------------------------------------ //
    //  Output holding register                                            //
    //  Once r_tvalid is asserted it stays asserted until m_axis_tready,  //
    //  satisfying the AXI-Stream TVALID stability rule.                  //
    // ------------------------------------------------------------------ //
    logic [OUT_DATA_WIDTH-1:0] r_tdata;
    logic [OUT_KEEP_W-1:0]     r_tkeep;
    logic                      r_tlast;
    logic                      r_tvalid;

    assign m_axis_tdata  = r_tdata;
    assign m_axis_tkeep  = r_tkeep;
    assign m_axis_tlast  = r_tlast;
    assign m_axis_tvalid = r_tvalid;

    // Accept input whenever the output register is free or being consumed.
    assign s_axis_tready = !r_tvalid || m_axis_tready;

    // ------------------------------------------------------------------ //
    //  Combinational word assembly                                        //
    //  Combines previously buffered beats with the arriving input beat.  //
    //  Upper slots are zeroed when TLAST fires before the word is full.  //
    // ------------------------------------------------------------------ //
    logic [OUT_DATA_WIDTH-1:0] asm_tdata;
    logic [OUT_KEEP_W-1:0]     asm_tkeep;

    always_comb begin
        asm_tdata = '0;
        asm_tkeep = '0;
        for (int i = 0; i < RATIO; i++) begin
            if (i < int'(phase)) begin
                asm_tdata[i*IN_DATA_WIDTH +: IN_DATA_WIDTH] = buf_data[i];
                asm_tkeep[i*IN_KEEP_W     +: IN_KEEP_W    ] = buf_keep[i];
            end
        end
        // Current beat occupies slot [phase]; upper slots stay zero.
        asm_tdata[int'(phase)*IN_DATA_WIDTH +: IN_DATA_WIDTH] = s_axis_tdata;
        asm_tkeep[int'(phase)*IN_KEEP_W     +: IN_KEEP_W    ] = s_axis_tkeep;
    end

    // ------------------------------------------------------------------ //
    //  Sequential logic                                                   //
    // ------------------------------------------------------------------ //
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase    <= '0;
            buf_data <= '0;
            buf_keep <= '0;
            r_tdata  <= '0;
            r_tkeep  <= '0;
            r_tlast  <= 1'b0;
            r_tvalid <= 1'b0;
        end else begin

            // Consume the output register on a downstream handshake.
            if (r_tvalid && m_axis_tready)
                r_tvalid <= 1'b0;

            // Process the incoming beat when both sides handshake.
            if (s_axis_tvalid && s_axis_tready) begin
                if (s_axis_tlast || phase == PHASE_W'(RATIO - 1)) begin
                    // Emit: either a complete word or a short-packet partial word.
                    r_tdata  <= asm_tdata;
                    r_tkeep  <= asm_tkeep;
                    r_tlast  <= s_axis_tlast;
                    r_tvalid <= 1'b1;
                    phase    <= '0;
                end else begin
                    // Buffer this beat and advance to the next slot.
                    buf_data[phase] <= s_axis_tdata;
                    buf_keep[phase] <= s_axis_tkeep;
                    phase           <= PHASE_W'(int'(phase) + 1);
                end
            end

        end
    end

endmodule

`default_nettype wire

module snix_axis_afifo #(parameter DATA_WIDTH  = 32,
                         parameter FIFO_DEPTH  = 16,
                         parameter FRAME_FIFO  = 1)   // 1=store-and-forward, 0=cut-through
                        (
                         input logic                         s_axis_clk,
                         input logic                         s_axis_rst_n,
                         input  logic [DATA_WIDTH-1:0]       s_axis_tdata,
                         input  logic                        s_axis_tvalid,
                         input  logic                        s_axis_tlast,
                         output logic                        s_axis_tready,

                         input logic                         m_axis_clk,
                         input logic                         m_axis_rst_n,                   
                         output logic [DATA_WIDTH-1:0]       m_axis_tdata,
                         output logic                        m_axis_tvalid,
                         output logic                        m_axis_tlast,
                         input  logic                        m_axis_tready);



    localparam ADDR_WIDTH = $clog2(FIFO_DEPTH);
    logic [ADDR_WIDTH:0]         n_items;
    logic [DATA_WIDTH-1:0]       fifo_tdata;
    logic                        fifo_tlast;
    logic                        wr_en;
    logic                        rd_en;
    logic                        fifo_full;
    logic                        fifo_empty;

    logic                        frame_wr_toggle;
    logic                        frame_wr_sync1;
    logic                        frame_wr_sync2;
    logic                        frame_wr_sync2_d;
    logic                        frame_done_pulse;
    
    typedef enum logic {
        IDLE,
        STREAM
    } state_t;

    state_t state, next_state;  

    always_ff @(posedge s_axis_clk or negedge s_axis_rst_n)
        if (!s_axis_rst_n)
            frame_wr_toggle <= 1'b0;
        else if (wr_en && s_axis_tlast)
            frame_wr_toggle <= ~frame_wr_toggle;

    always_ff @(posedge m_axis_clk or negedge m_axis_rst_n)
        if (!m_axis_rst_n) begin
            frame_wr_sync1   <= 1'b0;
            frame_wr_sync2   <= 1'b0;
            frame_wr_sync2_d <= 1'b0;
        end
        else begin
            frame_wr_sync1   <= frame_wr_toggle;
            frame_wr_sync2   <= frame_wr_sync1;
            frame_wr_sync2_d <= frame_wr_sync2;
        end

    assign frame_done_pulse = frame_wr_sync2 ^ frame_wr_sync2_d;

    // FSM
    always_ff @(posedge m_axis_clk or negedge m_axis_rst_n)
        if (!m_axis_rst_n)
            state <= IDLE;
        else
            state <= next_state;


    always_comb begin
        next_state = state;
        case (state)
            IDLE: begin
                if (frame_done_pulse) 
                    next_state = STREAM;
            end
            STREAM: begin
                if (rd_en && fifo_tlast)
                    next_state = IDLE;
            end
        endcase
    end

    assign wr_en         = s_axis_tvalid & s_axis_tready;
    assign s_axis_tready = !fifo_full;


    assign m_axis_tvalid = !fifo_empty && (FRAME_FIFO ? state == STREAM : 1'b1);
    assign rd_en         = m_axis_tvalid && m_axis_tready;

    assign m_axis_tdata  = fifo_tdata;
    assign m_axis_tlast  = fifo_tlast;

    snix_async_fifo #(.DATA_WIDTH(DATA_WIDTH + 1),
                      .FIFO_DEPTH(FIFO_DEPTH))

        async_fifo_u0(.wclk(s_axis_clk),
                      .wrst_n(s_axis_rst_n),
                      .wdata({s_axis_tdata, s_axis_tlast}),
                      .wr_en(wr_en),
                      .wfull(fifo_full),
                      
                      .rclk(m_axis_clk),
                      .rrst_n(m_axis_rst_n),
                      .rd_en(rd_en),
                      .rdata({fifo_tdata, fifo_tlast}),
                      .rd_n_items(n_items),
                      .rempty(fifo_empty));

endmodule: snix_axis_afifo

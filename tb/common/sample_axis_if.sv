module sample_axis_if #(parameter int DATA_WIDTH = 8,
                        parameter int USER_WIDTH = 1)
                       (axis_if #(.DATA_WIDTH(DATA_WIDTH),
                                  .USER_WIDTH(USER_WIDTH)) axis_if_t,

                        axis_if #(.DATA_WIDTH(DATA_WIDTH),
                                  .USER_WIDTH(USER_WIDTH)) axis_if_s);

    always_ff @(posedge axis_if_t.ACLK or negedge axis_if_t.ARESETn)
        if(!axis_if_t.ARESETn) begin
            axis_if_s.tvalid <= 1'b0;
            axis_if_s.tready <= 1'b0;
            axis_if_s.tdata  <= {DATA_WIDTH{1'b0}};
            axis_if_s.tuser  <= {USER_WIDTH{1'b0}};
            axis_if_s.tlast  <= 1'b0;
        end
        else begin
           axis_if_s.tvalid  <= axis_if_t.tvalid;
           axis_if_s.tready  <= axis_if_t.tready;
           axis_if_s.tdata   <= axis_if_t.tdata;
           axis_if_s.tuser   <= axis_if_t.tuser;
           axis_if_s.tlast   <= axis_if_t.tlast;
        end

endmodule: sample_axis_if
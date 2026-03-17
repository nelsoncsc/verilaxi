// -------------------------------------------------
// Class: axis_source
// -------------------------------------------------
class axis_source #(int DATA_WIDTH = 8, int USER_WIDTH = 1);
    virtual axis_if.src vif;
    bit backpressure = 0;
    int p_valid = 80;

    function new(virtual axis_if.src axis_vif);
        this.vif = axis_vif;
    endfunction: new

    task send_packet(int num_beats, int idle_cycles = 1);
        int count = 0;
        
        // Prepare first beat
        vif.tdata  = $urandom_range(0, 2**DATA_WIDTH-1);
        vif.tuser  = {USER_WIDTH{1'b1}};
        vif.tlast  = (num_beats == 1);
        //vif.tvalid = 1'b1;
        while(count < num_beats) begin
            vif.tvalid = !backpressure ? 1'b1 : ($urandom_range(0, 99) < p_valid);
            @(posedge vif.ACLK);

            // handshake occurs
            if(vif.tvalid && vif.tready) begin
                $display("[SRC] beat %0d tdata=%0d tuser=%b tlast=%b", count, vif.tdata, vif.tuser, vif.tlast);
                count++;

                if(count < num_beats) begin
                    // prepare next beat BEFORE next handshake
                    vif.tdata = $urandom_range(0, 2**DATA_WIDTH-1);
                    vif.tuser = (count == 0) ? {USER_WIDTH{1'b1}} : {USER_WIDTH{1'b0}};
                    vif.tlast = (count == num_beats-1);
                end else begin
                    // end of packet
                    vif.tvalid = 0;
                    vif.tlast  = 0;
                end
            end
        end
        // After last beat, drop tvalid for idle_cycles
        repeat (idle_cycles) @(posedge vif.ACLK);
    endtask: send_packet

endclass: axis_source

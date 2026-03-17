// -------------------------------------------------
// Class: axis_sink
// -------------------------------------------------
class axis_sink;
    virtual axis_if.sink vif;
    bit backpressure = 0;
    int p_ready = 80;

    function new(virtual axis_if.sink axis_vif);
        this.vif = axis_vif;
    endfunction: new

    task recv_packet();
        int count = 0;
        while(1) begin
            if(backpressure)
                vif.tready = ($urandom_range(0,99) < p_ready);
            else
                vif.tready = 1'b1;

            @(posedge vif.ACLK);

            if(vif.tvalid && vif.tready) begin
                $display("[SINK] beat %0d tdata=%0d tuser=%0d tlast=%b", count, vif.tdata, vif.tuser, vif.tlast);
                count++;
                if(vif.tlast)
                    break; // end packet
            end
        end
        // Deassert tready after packet done
        vif.tready = 0;
    endtask: recv_packet

endclass: axis_sink

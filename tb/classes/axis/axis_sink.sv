// -------------------------------------------------
// Class: axis_sink
// -------------------------------------------------
class axis_sink #(int DATA_WIDTH = 8,
                  int USER_WIDTH = 1,
                  int KEEP_WIDTH = ((DATA_WIDTH + 7) / 8));
    virtual axis_if.sink vif;
    bit backpressure = 0;
    int p_ready = 80;
    int seed = 32'h51c0_cafe;
    int timeout_cycles = 10000;

    function new(virtual axis_if.sink axis_vif);
        this.vif = axis_vif;
    endfunction: new

    task recv_packet();
        int count = 0;
        int waited = 0;
        logic [KEEP_WIDTH-1:0] observed_tkeep;
        logic [USER_WIDTH-1:0] observed_tuser;
        while(1) begin
            bit ready_now;

            ready_now = !backpressure ? 1'b1
                                      : (($urandom(seed) % 100) < p_ready);

            @(negedge vif.ACLK);
            vif.tready = ready_now;

            @(posedge vif.ACLK);
            waited++;

            if(vif.tvalid && vif.tready) begin
                observed_tkeep = vif.tkeep;
                observed_tuser = vif.tuser;
                $display("[SINK] beat %0d tdata=0x%0h tkeep=%0b tuser=%0h tlast=%b",
                         count, vif.tdata, observed_tkeep, observed_tuser, vif.tlast);
                count++;
                waited = 0;
                if(vif.tlast)
                    break; // end packet
            end

            if (waited >= timeout_cycles) begin
                $fatal(1, "axis_sink.recv_packet timeout after %0d cycles without TLAST", timeout_cycles);
            end
        end
        // Deassert tready after packet done
        @(negedge vif.ACLK);
        vif.tready = 0;
    endtask: recv_packet

endclass: axis_sink

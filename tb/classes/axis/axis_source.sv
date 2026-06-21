// -------------------------------------------------
// Class: axis_source
// -------------------------------------------------
class axis_source #(int DATA_WIDTH = 8,
                    int USER_WIDTH = 1,
                    int KEEP_WIDTH = ((DATA_WIDTH + 7) / 8));
    virtual axis_if.src vif;
    bit backpressure = 0;
    int p_valid = 80;
    int seed    = 32'h1bad_f00d;
    int bp_seed = 32'hdeadbeef;

    function new(virtual axis_if.src axis_vif);
        this.vif  = axis_vif;
        this.seed    = $urandom();
        this.bp_seed = $urandom();
    endfunction: new

    function automatic logic [DATA_WIDTH-1:0] gen_rand_data();
        logic [DATA_WIDTH-1:0] value;
        for (int i = 0; i < (DATA_WIDTH + 7) / 8; i++) begin
            value[i*8 +: 8] = $urandom(seed);
            seed = seed * 32'h6c62272e ^ 32'hdc4a8873;
        end
        return value;
    endfunction: gen_rand_data

    task send_packet(int num_beats, int idle_cycles = 1);
        int count = 0;
        bit drive_valid = 0;
        logic [DATA_WIDTH-1:0] curr_tdata;
        logic [KEEP_WIDTH-1:0] curr_tkeep;
        logic [USER_WIDTH-1:0] curr_tuser;
        logic                  curr_tlast;

        curr_tdata = gen_rand_data();
        curr_tkeep = {KEEP_WIDTH{1'b1}};
        curr_tuser = {USER_WIDTH{1'b1}};
        curr_tlast = (num_beats == 1);

        @(negedge vif.ACLK);
        vif.tvalid = 1'b0;
        vif.tkeep  = '0;
        vif.tlast  = 1'b0;

        while (count < num_beats) begin
            if (!drive_valid) begin
                bit launch_now;

                launch_now = !backpressure ? 1'b1
                                           : (($urandom(bp_seed) % 100) < p_valid);

                @(negedge vif.ACLK);
                if (launch_now) begin
                    vif.tdata  = curr_tdata;
                    vif.tkeep  = curr_tkeep;
                    vif.tuser  = curr_tuser;
                    vif.tlast  = curr_tlast;
                    vif.tvalid = 1'b1;
                    drive_valid = 1'b1;
                end else begin
                    vif.tvalid = 1'b0;
                end
            end

            @(posedge vif.ACLK);

            if (drive_valid && vif.tready) begin
                $display("[SRC] beat %0d tdata=0x%0h tkeep=%0b tuser=%b tlast=%b",
                         count, curr_tdata, curr_tkeep, curr_tuser, curr_tlast);
                count++;
                drive_valid = 1'b0;

                if (count < num_beats) begin
                    curr_tdata = gen_rand_data();
                    curr_tkeep = {KEEP_WIDTH{1'b1}};
                    curr_tuser = (count == 0) ? {USER_WIDTH{1'b1}}
                                              : {USER_WIDTH{1'b0}};
                    curr_tlast = (count == num_beats-1);
                end
            end
        end

        @(negedge vif.ACLK);
        vif.tvalid = 1'b0;
        vif.tkeep  = '0;
        vif.tlast  = 1'b0;

        repeat (idle_cycles) @(posedge vif.ACLK);
    endtask: send_packet

endclass: axis_source

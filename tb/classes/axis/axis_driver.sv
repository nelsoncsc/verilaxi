class axis_driver;
    // Handles to BFMs
    axis_source  src_bfm;
    axis_sink    sink_bfm;

    // Constructor
    function new(axis_source s, axis_sink r);
        src_bfm  = s;
        sink_bfm = r;
    endfunction: new

    // Coordinated send/receive task
    task send_and_recv(int length, int idle_cycles = 1, int post_cycles = 2);
        fork
            src_bfm.send_packet(length, idle_cycles);
            sink_bfm.recv_packet();
        join
        repeat (post_cycles) @(posedge src_bfm.vif.ACLK); // optional wait after
    endtask: send_and_recv  

endclass: axis_driver

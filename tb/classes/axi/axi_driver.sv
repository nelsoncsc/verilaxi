class axi_driver #(int ADDR_WIDTH = 32, int DATA_WIDTH = 64, int ID_WIDTH = 4);

    axi_master #(.ADDR_WIDTH(ADDR_WIDTH),
                 .DATA_WIDTH(DATA_WIDTH),
                 .ID_WIDTH(ID_WIDTH)) m;

    function new(axi_master m_handle);
        m = m_handle;
    endfunction: new

    // -----------------------------
    // Write burst
    // -----------------------------
    task write_array(logic [ADDR_WIDTH-1:0] base_addr, 
                     ref logic [DATA_WIDTH-1:0] data[], 
                     int burst_len);

        $display("[%0t] AXI WRITE burst_len=%0d", $time, burst_len);
        m.write_burst(base_addr, data, burst_len);
        repeat (1) @(posedge m.vif.ACLK);
    endtask: write_array

    // -----------------------------
    // Read burst
    // -----------------------------
    task read_array(logic [ADDR_WIDTH-1:0] base_addr, 
                    ref logic [DATA_WIDTH-1:0] data[], 
                    int burst_len);

        $display("[%0t] AXI READ burst_len=%0d", $time, burst_len);
        m.read_burst(base_addr, data, burst_len);
    endtask: read_array

    // -----------------------------
    // Check results
    // -----------------------------
    task check_data(ref logic [DATA_WIDTH-1:0] expected[], 
                    ref logic [DATA_WIDTH-1:0] actual[], 
                    int burst_len);

        for (int i=0; i<burst_len; i++) begin
            if (actual[i] !== expected[i])
                $error("Mismatch beat %0d: exp=%h got=%h", i, expected[i], actual[i]);
            else
                $display("Beat %0d OK: %h", i, actual[i]);
        end
        $display("AXI burst test PASSED");
    endtask: check_data

    // -----------------------------
    // Full write-read-check sequence
    // -----------------------------
    task write_read_check(logic [ADDR_WIDTH-1:0]     base_addr,
                          ref logic [DATA_WIDTH-1:0] wr_data[],
                          ref logic [DATA_WIDTH-1:0] rd_data[],
                          int burst_len);
                          
        write_array(base_addr, wr_data, burst_len);
        read_array(base_addr, rd_data, burst_len);
        check_data(wr_data, rd_data, burst_len);
    endtask: write_read_check

endclass: axi_driver

class axil_driver #(int ADDR_WIDTH = 32, int DATA_WIDTH = 32);

    // AXI-Lite master handle
    axil_master #(.ADDR_WIDTH(ADDR_WIDTH),
                  .DATA_WIDTH(DATA_WIDTH)) m;
    
    // Constructor
    function new(axil_master m_handle);
        m = m_handle;
    endfunction: new

    // -----------------------------
    // Task: write an array of data to consecutive addresses
    // -----------------------------
    task write_array(logic [ADDR_WIDTH-1:0] base_addr, 
                     ref logic [DATA_WIDTH-1:0] data[], 
                     int count);

        $display("[%0t] AXI-Lite WRITE", $time);
        for (int i = 0; i < count; i++) begin
            m.write(base_addr + i*4, data[i]);
        end
        repeat (1) @(posedge m.vif.ACLK);
    endtask: write_array

    // -----------------------------
    // Task: read array of data from consecutive addresses
    // -----------------------------
    /* verilator lint_off UNDRIVEN */
    task read_array(logic [ADDR_WIDTH-1:0] base_addr, 
                    ref logic [DATA_WIDTH-1:0] data[], 
                    int count);

        $display("[%0t] AXI-Lite READ", $time);
        for (int i = 0; i < count; i++) begin
            logic [DATA_WIDTH-1:0] tmp;
            m.read(base_addr + i*4, tmp);
            data[i] = tmp;  // <- use index, NOT .at()
        end
    endtask: read_array
    /* verilator lint_on UNDRIVEN */

    // -----------------------------
    // Task: check read data against expected
    // -----------------------------
    task check_data(ref logic [DATA_WIDTH-1:0] expected[], 
                    ref logic [DATA_WIDTH-1:0] actual[], 
                    int count);

        for (int i = 0; i < count; i++) begin
            if (actual[i] !== expected[i])
                $error("Mismatch beat %0d: exp=%h got=%h", i, expected[i], actual[i]);
            else
                $display("Beat %0d OK: %h", i, actual[i]);
        end
        $display("AXI burst test PASSED");
    endtask: check_data

    // -----------------------------
    // Task: full write-read-check sequence
    // -----------------------------
    task write_read_check(logic [ADDR_WIDTH-1:0] base_addr, 
                          ref logic [DATA_WIDTH-1:0] wr_data[], 
                          ref logic [DATA_WIDTH-1:0] rd_data[], 
                          int count);
                          
        write_array(base_addr, wr_data, count);
        read_array(base_addr, rd_data, count);
        check_data(wr_data, rd_data, count);
    endtask: write_read_check

endclass: axil_driver

`timescale 1ns/1ps

module tb_snix_rr_arbiter;

    parameter NUM_REQS = 4;

    // Signals
    logic clk;
    logic rst_n;
    logic accept;
    logic [NUM_REQS-1:0] req;
    logic [NUM_REQS-1:0] grant;

    // Internal
    int rr_ptr_snapshot;
    int last_grant_idx;

    // DUT
    snix_rr_arbiter #(.NUM_REQS(NUM_REQS)) dut (
        .clk(clk),
        .rst_n(rst_n),
        .accept(accept),
        .req(req),
        .grant(grant)
    );

    // Clock generation
    initial clk = 0;
    always #5 clk = ~clk;

    // Reset
    initial begin
        rst_n = 0;
        accept = 0;
        req = '0;
        last_grant_idx = -1;
        #20;
        rst_n = 1;
    end

    // Get grant index
    function automatic int get_grant_index(logic [NUM_REQS-1:0] g);
        for(int i=0;i<NUM_REQS;i++) if(g[i]) return i;
        return -1;
    endfunction

    // Monitor table
    initial begin
        $display("Time\tclk\trst\treq\tgrant\taccept\tpointer");
        forever @(posedge clk) begin
            rr_ptr_snapshot = dut.rr_ptr;
            $display("%0t\t%b\t%b\t%b\t%b\t%b\t%0d",
                     $time, clk, rst_n, req, grant, accept, rr_ptr_snapshot);
        end
    end

    // Task to issue requests
    task automatic issue_request(input logic [NUM_REQS-1:0] r);
        int idx, expected;
        begin
            req = r;
            accept = 1;
            @(posedge clk); // sample
            @(posedge clk); // pointer update

            idx = get_grant_index(grant);

            if(idx == -1 && r != 0)
                $display("ERROR: No grant for req=%b at time %0t", r, $time);
            else if(idx != -1) begin
                // Compute expected grant (round-robin)
                if(last_grant_idx != -1) begin
                    expected = last_grant_idx;
                    for(int i=1;i<=NUM_REQS;i++) begin
                        int cand = (last_grant_idx + i) % NUM_REQS;
                        if(r[cand]) begin expected = cand; break; end
                    end
                    if(idx != expected)
                        $display("ERROR: RR violation! Last=%0d, Grant=%0d, Req=%b at time %0t",
                                 last_grant_idx, idx, r, $time);
                    else
                        $display("PASS: Grant=%0d for Req=%b at time %0t", idx, r, $time);
                end
                else
                    $display("PASS: First Grant=%0d for Req=%b at time %0t", idx, r, $time);

                last_grant_idx = idx;
            end

            accept = 0;
            req = 0;
            @(posedge clk); // idle cycle
        end
    endtask

    // Test sequence
    initial begin
        @(posedge rst_n);
        $display("Starting Round-Robin Test...");

        // Single request
        issue_request(4'b0001);

        // Multiple requests
        issue_request(4'b1010);

        // All requests
        issue_request(4'b1111);

        // Random requests
        repeat(6) begin
            logic [NUM_REQS-1:0] r = $urandom_range(0, 2**NUM_REQS-1);
            issue_request(r);
        end

        $display("Simulation finished.");
        $stop;
    end

endmodule

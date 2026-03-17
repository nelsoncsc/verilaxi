module snix_rr_arbiter #(parameter int NUM_REQS = 4)
                        (input  logic clk,
                         input  logic rst_n,
                         input  logic accept,
                         input  logic [NUM_REQS-1:0] req,
                         output logic [NUM_REQS-1:0] grant);

    localparam int PTR_W = NUM_REQS <= 1 ? 1 : $clog2(NUM_REQS);

    logic [PTR_W-1:0] rr_ptr;
    logic [NUM_REQS-1:0] req_r;   // registered request
    logic [NUM_REQS-1:0] grant_r; // registered grant
    logic found;
    int idx;

    // Register the request
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n)
            req_r <= '0;
        else
            req_r <= req;
    end

    // Grant generation (synchronous)
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            grant_r <= '0;
        end
        else begin
            found = 1'b0;
            grant_r = '0;

            for(int i=0; i<NUM_REQS; i++) begin
                idx = int'(rr_ptr) + i >= NUM_REQS ? int'(rr_ptr) + i - NUM_REQS : int'(rr_ptr) + i;
                if(req_r[idx] && !found) begin
                    grant_r[idx] = 1'b1;
                    found = 1'b1;
                end
            end
        end
    end

    // Pointer update
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n)
            rr_ptr <= PTR_W'(0);
        else if(accept && |grant_r) begin
            for(int i=0; i<NUM_REQS; i++) begin
                if(grant_r[i]) begin
                    rr_ptr <= i==NUM_REQS-1 ? PTR_W'(0) : PTR_W'(i + 1'b1);
                end
            end
        end
    end

    // Output
    assign grant = grant_r;

endmodule: snix_rr_arbiter
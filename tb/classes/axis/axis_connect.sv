// -------------------------------------------------
// Class: axis_connect
// Connect source to sink interface
// -------------------------------------------------
class axis_connect;
    virtual axis_if.src  src_vif;
    virtual axis_if.sink sink_vif;

    function new(virtual axis_if.src src_v, virtual axis_if.sink sink_v);
        this.src_vif  = src_v;
        this.sink_vif = sink_v;
    endfunction: new

    task passthrough();
        forever @(posedge src_vif.ACLK) begin
            // Propagate only when source is valid and sink is ready
            sink_vif.tdata  = src_vif.tdata;
            sink_vif.tuser  = src_vif.tuser;
            sink_vif.tlast  = src_vif.tlast;
            src_vif.tready  = sink_vif.tready;
            sink_vif.tvalid = src_vif.tvalid; 
        end
    endtask: passthrough

endclass: axis_connect

#include <verilated.h>
#include <verilated_fst_c.h>   // Use FST instead of VCD
#include "Vtestbench.h"

int main(int argc, char **argv)
{
    // Create Verilator simulation context
    VerilatedContext* contextp = new VerilatedContext;
    contextp->commandArgs(argc, argv);
    contextp->traceEverOn(true); // enable tracing

    // Determine waveform filename
    const char* fst_name = "waves.fst";   // default
    if (argc > 1) {
        fst_name = argv[1];
    }

    // Create top-level module
    Vtestbench* top = new Vtestbench{contextp};

    // Create FST trace
    VerilatedFstC* tfp = new VerilatedFstC;
    top->trace(tfp, 99);      // trace 99 levels deep
    tfp->open(fst_name);     // waveform file

    // Initialize simulation at time 0
    top->eval();
    tfp->dump(0);

    // Main simulation loop
    while (!contextp->gotFinish()) {
        contextp->timeInc(1);  // advance time by 1
        top->eval();
        tfp->dump(contextp->time());
    }

    // Close trace and clean up
    tfp->close();
    int errors = (int)contextp->errorCount();
    delete tfp;
    delete top;
    delete contextp;
    return (errors > 0) ? 1 : 0;
}

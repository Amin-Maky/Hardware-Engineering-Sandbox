//-----------------------------------------------------------------------------
// STEP 2: SystemVerilog Interface (Signals, Clocking Blocks & Modports)
//-----------------------------------------------------------------------------
interface <dut>_if (
    input logic clk
);
    // Importing types and parameters from the package defined in Step 1
    import <dut>_tb_pkg::*;

    //-------------------------------------------------------------------------
    // 2.1 Physical Hardware Signals (Actual pins connected to the DUT)
    //-------------------------------------------------------------------------
    logic    rst_n;       // Active-low reset
    logic    start;       // Handshake: Start trigger (TB -> DUT)
    data_t   in_data;     // Input payload stream   (TB -> DUT)
    
    result_t out_result;  // Computed result        (DUT -> TB)
    data_t   out_data;    // Processed data         (DUT -> TB)
    logic    done;        // Handshake: Done flag   (DUT -> TB)

    //-------------------------------------------------------------------------
    // 2.2 Driver Clocking Block (Active: Drives inputs, samples status)
    //-------------------------------------------------------------------------
    // Note 1 (The Orchestrator): Declaring @(posedge clk) binds this block to the clock edge.
    // This is why, in the Driver class, we use @(vif.drv_cb) instead of @(posedge vif.clk).
    // It ensures we wait for the clock edge while respecting the skew settings below.
    clocking drv_cb @(posedge clk);
        
        // Note 2 (Eliminating Race Conditions via Skew):
        // - input #1step: Samples signals one time-step before the clock edge (in the Preponed region),
        //   ensuring stable data before any flip-flop triggers.
        // - output #1ns: Drives signals 1ns after the clock edge (simulating real Clock-to-Q delay),
        //   preventing signal contention with the clock edge.
        default input #1step output #1ns;
        
        // Note 3 (Direction Perspective): 
        // In a clocking block, 'input' and 'output' are defined from the Testbench's perspective, not the DUT's!
        // - DUT input  ---> becomes output here (the Driver drives the signal).
        // - DUT output ---> becomes input here (the Driver samples/reads the signal).
        output rst_n;
        output start;
        output in_data;
        
        input  done;
        input  out_result;
        input  out_data;
    endclocking : drv_cb

    //-------------------------------------------------------------------------
    // 2.3 Monitor Clocking Block (Passive: Read-only access to ALL signals)
    //-------------------------------------------------------------------------
    // Note 4 (Why a dedicated Monitor block?):
    // The Monitor is a passive observer. It needs to see both what the Driver sends
    // and what the DUT returns. Thus, all signals are defined as 'input' to ensure
    // the Monitor cannot accidentally drive or change any signal values.
    clocking mon_cb @(posedge clk);
        default input #1step output #1ns;
        
        input rst_n;
        input start;
        input in_data;
        input done;
        input out_result;
        input out_data;
    endclocking : mon_cb

    //-------------------------------------------------------------------------
    // 2.4 Modports for TB Classes (Direction Protection / Access Control)
    //-------------------------------------------------------------------------
    // Note 5 (Why Modports are essential):
    // Modports act as access gates, restricting each class to its specific clocking block:
    // 1. Prevents Monitor bugs: If you accidentally use an assignment (<=) instead of a 
    //    comparison (==) in the Monitor, the compiler throws an error because the signals 
    //    are defined as 'input' (read-only) in mon_cb.
    // 2. Prevents Driver-to-DUT collisions: If you accidentally try to drive a DUT 
    //    output pin, the modport/clocking block constraint catches it at compile time.
    //
    // Usage in Classes:
    // - Driver class : virtual <dut>_if.DRV vif;  -->  @(vif.drv_cb); vif.drv_cb.start <= 1'b1;
    // - Monitor class: virtual <dut>_if.MON vif;  -->  @(vif.mon_cb); if (vif.mon_cb.done) ...
    modport DRV (clocking drv_cb, input clk);
    modport MON (clocking mon_cb, input clk);



    //-----------------------------------------------------------------------------
    // STEP 3: SystemVerilog Assertions (SVA) for Protocol Verification
    //-----------------------------------------------------------------------------
    // Note 6 (SVA Placement & Scheduling):
    // Assertions are placed directly inside the interface to monitor physical pins
    // without TB class overhead. They sample signals in the Preponed region (just 
    // like 'input #1step' in clocking blocks), ensuring zero race conditions.

    // 3.1 Reset Check: Ensures outputs are safely driven to zero when rst_n is low.
    // Using '0 (unsized zero) makes it scalable for any parameterized width.
    property p_reset_state;
        @(posedge clk) !rst_n |-> (done == 1'b0 && out_result == '0 && out_data == '0);
    endproperty
    AST_RESET: assert property (p_reset_state) 
        else $error("[SVA ERROR] Outputs not zero during reset at time %0t!", $time);

    // 3.2 Protocol Check: Prevents illegal 'start' assertion during reset.
    property p_no_start_in_reset;
        @(posedge clk) !rst_n |-> (start == 1'b0);
    endproperty
    AST_START_IN_RST: assert property (p_no_start_in_reset) 
        else $error("[SVA ERROR] 'start' asserted while 'rst_n' is low at time %0t!", $time);

    // 3.3 Handshake Latency: 
    // - Option A (Single-Cycle DUT): start |=> done;
    // - Option B (Multi-Cycle DUT) : start |-> ##[1:TIMEOUT_CYCLES] done;
    // 'disable iff' aborts the check if reset occurs mid-transaction.
    property p_start_to_done;
        @(posedge clk) disable iff (!rst_n)
        start |=> done; // Change to ##[1:MAX_LATENCY] for multi-cycle DUTs
    endproperty
    AST_LATENCY: assert property (p_start_to_done) 
        else $error("[SVA ERROR] Handshake timeout/latency violation at time %0t!", $time);

    // 3.4 Data Integrity (No X/Z): Ensures valid logic levels on outputs when done is high.
    property p_result_known;
        @(posedge clk) disable iff (!rst_n)
        done |-> (!$isunknown(out_result) && !$isunknown(out_data));
    endproperty
    AST_KNOWN_RES: assert property (p_result_known) 
        else $error("[SVA ERROR] Output contains X/Z when 'done' is high at time %0t!", $time);

    // 3.5 Data Stability & Vivado XSim Quirk (For Multi-Cycle DUTs):
    // If the DUT takes multiple cycles, input data must remain stable until 'done'.
    // XSIM NOTE: Always pass '@(posedge clk)' explicitly as the 3rd argument to $past 
    // or 2nd argument to $stable in Vivado XSim to prevent clock-inference compile errors!
    /*
    property p_data_stability;
        @(posedge clk) disable iff (!rst_n)
        (start && !done) |=> $stable(in_data, @(posedge clk));
        // Equivalent using $past: (in_data == $past(in_data, 1, @(posedge clk)))
    endproperty
    AST_DATA_STABLE: assert property (p_data_stability)
        else $error("[SVA ERROR] 'in_data' changed before 'done' at time %0t!", $time);
    */
    
endinterface : <dut>_if

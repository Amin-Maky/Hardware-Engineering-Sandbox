//=============================================================================
// File Name   : tb_<dut_name>.sv
// DUT         : <dut_name>
// Simulator   : Vivado XSim / QuestaSim / VCS
// Description : Layered SystemVerilog Testbench (Interface + SVA + OOP + FCov)
//=============================================================================

`timescale 1ns / 1ps
`default_nettype none

//-----------------------------------------------------------------------------
// STEP 1: Verification Package (Shared Parameters, Types & Classes)
//-----------------------------------------------------------------------------
package <dut>_tb_pkg;

    // 1.1 Global DUT & TB Configuration Parameters
    // (If you need to change the data width or number of tests, modify them here only)
    parameter int DATA_WIDTH      = 16;
    parameter int RESULT_WIDTH    = $clog2(DATA_WIDTH + 1); // Automatic width calculation using $clog2
    parameter int PAYLOAD_LEN     = 16;

    // 1.2 Timing & Simulation Control Constants
    parameter time CLK_PERIOD     = 10ns; // 100 MHz
    parameter int  RESET_CYCLES   = 5;
    parameter int  NUM_RANDOM_RUNS= 20;
    parameter int  WATCHDOG_LIMIT = 50_000; // Using "_" for readability of large numbers

    // 1.3 Clean Data Type Aliases (Prevents repeating logic [WIDTH-1:0] throughout the code)
    typedef logic [DATA_WIDTH-1:0]   data_t;
    typedef logic [RESULT_WIDTH-1:0] result_t;

    // 1.4 Test Scenario Enumeration
    // (Combination of Directed Corner Cases and Constrained Random)
    typedef enum int unsigned {
        SCEN_CORNER_ZERO      = 0,
        SCEN_CORNER_MAX       = 1,
        SCEN_CORNER_ALTERNATE = 2, // e.g., 16'hAAAA / 16'h5555 for bit interference testing
        SCEN_RANDOM           = 3
    } scenario_e;

    //-----------------------------------------------------------------------------
    // STEP 4: Transaction Class & Constrained-Random Stimulus
    //-----------------------------------------------------------------------------
    // Note 1 (What is a Transaction?):
    // A Transaction bundles all signals of a single bus operation into one object.
    // Instead of thinking about individual pins toggling at every clock, the TB 
    // components communicate by passing these high-level packets via Mailboxes.
    class <dut>_transaction;

        //-------------------------------------------------------------------------
        // 4.1 Stimulus Fields (Inputs to DUT - Declared as 'rand' or 'randc')
        //-------------------------------------------------------------------------
        // - 'rand' : Standard random (like rolling a die; values can repeat).
        // - 'randc': Cyclic random (like dealing cards; doesn't repeat until all 
        //            possible values have been generated). Great for opcodes/modes!
        rand  data_t       in_data;
        randc op_mode_e    op_mode;    // Example enum from Step 1
        rand  int unsigned start_delay; // Random idle cycles between transactions

        //-------------------------------------------------------------------------
        // 4.2 Observed Fields (Outputs from DUT - MUST NOT be 'rand')
        //-------------------------------------------------------------------------
        // The Monitor fills these fields when sampling the interface.
        result_t out_result;
        data_t   out_data;
        logic    done;

        //-------------------------------------------------------------------------
        // 4.3 Constraints (Guiding the Random Solver towards Corner Cases)
        //-------------------------------------------------------------------------
        // Note 2 (Why weighted distributions 'dist'?):
        // Pure randomness rarely hits 32-bit/16-bit corner cases (e.g., 0x0000, 0xFFFF).
        // Using 'dist' forces the solver to hit critical edge cases frequently.
        //   ':=' assigns weight to EVERY single value in a range.
        //   ':/' divides the weight equally across the ENTIRE range.
        constraint c_data_corners {
            in_data dist {
                '0                  := 10, // 10% weight: All zeros (Minimum)
                '1                  := 10, // 10% weight: All ones  (Maximum)
                DATA_WIDTH'(16'hAAAA) := 5,  //  5% weight: Alternating bits (1010...)
                DATA_WIDTH'(16'h5555) := 5,  //  5% weight: Alternating bits (0101...)
                [1 : ('1 - 1)]      :/ 70  // 70% weight shared across all normal values
            };
        }

        // Controlling protocol timing (e.g., testing back-to-back vs. delayed starts)
        constraint c_timing {
            start_delay dist {
                0       := 50, // 50% chance of back-to-back transactions (stress test!)
                [1 : 5] :/ 50  // 50% chance of 1 to 5 idle cycles between transactions
            };
        }

        //-------------------------------------------------------------------------
        // 4.4 Utility Methods (Deep Copy & Print)
        //-------------------------------------------------------------------------
        // Note 3 (Why Deep Copy is critical):
        // Class variables are handles (pointers). If the Generator re-randomizes the 
        // same object handle in a loop without cloning it via copy(), it will overwrite 
        // the transactions already sitting in the Mailbox waiting for the Driver!
        function <dut>_transaction copy();
            copy = new();
            copy.in_data     = this.in_data;
            copy.op_mode     = this.op_mode;
            copy.start_delay = this.start_delay;
            copy.out_result  = this.out_result;
            copy.out_data    = this.out_data;
            copy.done        = this.done;
            return copy;
        endfunction : copy

        // Helper function for clean debug logs in the console
        function void display(string tag = "TR");
            $display("[%0t] [%s] op=%s | in_data=0x%0h (delay=%0d) | out_res=0x%0h | done=%0b",
                     $time, tag, op_mode.name(), in_data, start_delay, out_result, done);
        endfunction : display

    endclass : <dut>_transaction

endpackage : <dut>_tb_pkg

`default_nettype wire

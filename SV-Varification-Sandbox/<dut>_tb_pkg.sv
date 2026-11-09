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

    // [In steps 4 through 7, the Transaction, Generator, Driver, Monitor, Scoreboard, and Env classes will be defined here]

endpackage : <dut>_tb_pkg

`default_nettype wire

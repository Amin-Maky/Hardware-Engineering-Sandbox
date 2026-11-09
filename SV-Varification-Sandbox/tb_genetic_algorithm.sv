`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: Academic Project
// Engineer: Amin Maky
// 
// Create Date: Fall 2025
// Design Name: Genetic Algorithm Accelerator
// Module Name: tb_genetic_algorithm (Testbench)
// Project Name: GA_Prj
// Target Devices: xc7vx485tffg1157-1 (Virtex-7)
// Tool Versions: Vivado 2024.2
// Description: 
// Testbench for functional verification and validation of the top-level 
// Genetic Algorithm hardware accelerator (v1.0.0). 
// Generates a 100 MHz reference clock and synchronous/asynchronous reset, 
// streams randomized initial population vectors into the DUT, drives control 
// handshakes (start_ga), and monitors execution until convergence (ga_done). 
// Logs the final optimal chromosome and fitness score.
// 
// Dependencies: 
// - genetic_algorithm (Top-Level DUT)
// 
// Revision:
// Revision 1.00 - Testbench designed, verified, and validated (Amin Maky)
// Additional Comments:
// Verification environment for GitHub release v1.0.0.
// 
//////////////////////////////////////////////////////////////////////////////////
`timescale 1ns / 1ps

// =============================================================================
// Interface Definition with Integrated SystemVerilog Assertions (SVA)
// =============================================================================

// Enum to identify test scenario types for corner case coverage
// Declared before interface and classes for universal visibility
typedef enum {
    RANDOM_POPULATION,
    CORNER_ALL_ONES,
    CORNER_ALL_ZEROS,
    CORNER_IDENTICAL_POP
} test_scenario_e;

interface ga_if #(
    parameter int CHROMOSOME_WIDTH = 16,
    parameter int FITNESS_WIDTH    = 5
)(
    input logic clk
);
    logic                          rst_n;
    logic                          start_ga;
    logic [CHROMOSOME_WIDTH-1:0]   initial_population;
    logic [CHROMOSOME_WIDTH-1:0]   best_chromosome;
    logic [FITNESS_WIDTH-1:0]      best_fitness;
    logic                          ga_done;

    // Coverage sampling signals and synchronization event (Bridge for module-level coverage)
    logic [FITNESS_WIDTH-1:0]      cov_best_fitness;
    int                            cov_execution_cycles;
    test_scenario_e                cov_scenario_type;
    event                          cov_sample_event;

    // Clocking block for synchronous driving
    clocking drv_cb @(posedge clk);
        default input #1step output #1ns;
        output rst_n;
        output start_ga;
        output initial_population;
        input  ga_done;
    endclocking

    // Clocking block for synchronous monitoring
    clocking mon_cb @(posedge clk);
        default input #1step;
        input rst_n;
        input start_ga;
        input best_chromosome;
        input best_fitness;
        input ga_done;
    endclocking

    // Modports for structural isolation
    modport DRV (clocking drv_cb, output rst_n, start_ga, initial_population);
    modport MON (clocking mon_cb, input rst_n, start_ga, best_chromosome, best_fitness, ga_done);

    // -------------------------------------------------------------------------
    // Phase 2 SystemVerilog Assertions (Embedded inside Interface)
    // Refactored for Vivado XSim: Explicit clocking, disable conditions, and explicit $past clocking
    // -------------------------------------------------------------------------

    // Rule 1: Reset behavior check
    property p_reset_outputs_cleared;
        @(posedge clk) !rst_n |-> (ga_done == 1'b0 && best_fitness == '0 && best_chromosome == '0);
    endproperty
    assert_reset_outputs: assert property (@(posedge clk) disable iff (1'b0) p_reset_outputs_cleared)
        else $error("[SVA-FAIL] Non-zero outputs detected during reset assertion!");

    // Rule 2: Protocol check - Clean release of reset
    property p_clean_reset_recovery;
        @(posedge clk) disable iff (!rst_n) $rose(rst_n) |-> (ga_done == 1'b0);
    endproperty
    assert_clean_reset_recovery: assert property (p_clean_reset_recovery)
        else $error("[SVA-FAIL] ga_done asserted prematurely on reset release!");

    // Rule 3: Protocol check - Stability of Done handshake
    property p_done_glitch_free;
        @(posedge clk) disable iff (!rst_n) ga_done && !start_ga |=> ga_done;
    endproperty
    assert_done_glitch_free: assert property (p_done_glitch_free)
        else $error("[SVA-FAIL] ga_done toggled unexpectedly before new execution started!");

    // Rule 4: Data integrity - Output stability when ga_done is active
    // Explicit $past clocking provided to avoid Vivado XSim clock inference failure
    property p_output_stable_when_done;
        @(posedge clk) disable iff (!rst_n) ga_done |=>
            (best_chromosome == $past(best_chromosome, 1, 1'b1, @(posedge clk))) &&
            (best_fitness == $past(best_fitness, 1, 1'b1, @(posedge clk)));
    endproperty
    assert_output_stable_when_done: assert property (p_output_stable_when_done)
        else $error("[SVA-FAIL] Best chromosome or fitness value changed while ga_done was active!");

    // Rule 5: Monotonicity property (Elitism preservation)
    // Explicit $past clocking provided to resolve [XSIM 43-4463]
    property p_monotonic_elitism;
        @(posedge clk) disable iff (!rst_n) best_fitness >= $past(best_fitness, 1, 1'b1, @(posedge clk));
    endproperty
    assert_monotonic_elitism: assert property (p_monotonic_elitism)
        else $error("[SVA-FAIL] Elitism violation! Best fitness decreased: past=%0d, current=%0d",
                    $past(best_fitness, 1, 1'b1, @(posedge clk)), best_fitness);

    // Rule 6: Boundary check - Fitness range
    property p_fitness_upper_bound;
        @(posedge clk) disable iff (!rst_n) best_fitness <= CHROMOSOME_WIDTH;
    endproperty
    assert_fitness_upper_bound: assert property (p_fitness_upper_bound)
        else $error("[SVA-FAIL] best_fitness value (%0d) exceeds max boundary (%0d)!",
                    best_fitness, CHROMOSOME_WIDTH);

    // Rule 7: One-Max invariant - Bit population parity
    property p_onemax_invariant;
        @(posedge clk) disable iff (!rst_n) ga_done |-> (best_fitness == $countones(best_chromosome));
    endproperty
    assert_onemax_invariant: assert property (p_onemax_invariant)
        else $error("[SVA-FAIL] Hardware invariant failure: bit count mismatch on completion!");

    // SVA Cover Properties
    cover_ga_completion:    cover property (@(posedge clk) disable iff (!rst_n) ga_done == 1'b1);
    cover_optimal_solution: cover property (@(posedge clk) disable iff (!rst_n) ga_done && (best_fitness == CHROMOSOME_WIDTH));

endinterface


// =============================================================================
// Class-Based Verification Components with Functional Coverage (Phase 4)
// =============================================================================

// -----------------------------------------------------------------------------
// Transaction Class (Supports Targeted & Constrained-Random Corner Cases)
// -----------------------------------------------------------------------------
class ga_transaction #(
    parameter int CHROMOSOME_WIDTH = 16,
    parameter int POPULATION_SIZE  = 16,
    parameter int FITNESS_WIDTH    = 5
);
    rand test_scenario_e            scenario_type;
    rand bit [CHROMOSOME_WIDTH-1:0] seed_population[POPULATION_SIZE];
    rand bit [CHROMOSOME_WIDTH-1:0] identical_pattern;

    // Monitored response fields
    bit [CHROMOSOME_WIDTH-1:0]      observed_chromosome;
    bit [FITNESS_WIDTH-1:0]         observed_fitness;
    int                             execution_cycles;
    int                             run_id;

    // Corner case constraints
    constraint c_scenario_data {
        if (scenario_type == CORNER_ALL_ONES) {
            foreach (seed_population[i]) seed_population[i] == {CHROMOSOME_WIDTH{1'b1}};
        } else if (scenario_type == CORNER_ALL_ZEROS) {
            foreach (seed_population[i]) seed_population[i] == '0;
        } else if (scenario_type == CORNER_IDENTICAL_POP) {
            foreach (seed_population[i]) seed_population[i] == identical_pattern;
            identical_pattern != '0;
            identical_pattern != {CHROMOSOME_WIDTH{1'b1}};
        }
    }

    function void print(input string tag = "GA_TX");
        $display("[%s] Run ID: %0d | Scenario: %s | Cycles: %0d | Best Chromo: 0x%04h | Best Fitness: %0d",
                 tag, run_id, scenario_type.name(), execution_cycles, observed_chromosome, observed_fitness);
    endfunction
endclass


// -----------------------------------------------------------------------------
// Generator Class (Directed Corner Cases + Randomized Test Suite)
// -----------------------------------------------------------------------------
class ga_generator #(
    parameter int CHROMOSOME_WIDTH = 16,
    parameter int POPULATION_SIZE  = 16,
    parameter int FITNESS_WIDTH    = 5
);
    mailbox #(ga_transaction #(CHROMOSOME_WIDTH, POPULATION_SIZE, FITNESS_WIDTH)) gen2drv_mbx;
    int repeat_count;

    function new(input mailbox #(ga_transaction #(CHROMOSOME_WIDTH, POPULATION_SIZE, FITNESS_WIDTH)) mbx, input int count);
        this.gen2drv_mbx   = mbx;
        this.repeat_count = count;
    endfunction

    task run();
        ga_transaction #(CHROMOSOME_WIDTH, POPULATION_SIZE, FITNESS_WIDTH) tx;

        // 1. Explicit Corner Case 1: All Ones (Pre-solved optimal population)
        tx = new();
        void'(tx.randomize() with { scenario_type == CORNER_ALL_ONES; });
        tx.run_id = 1;
        gen2drv_mbx.put(tx);

        // 2. Explicit Corner Case 2: All Zeros (Absolute worst starting state)
        tx = new();
        void'(tx.randomize() with { scenario_type == CORNER_ALL_ZEROS; });
        tx.run_id = 2;
        gen2drv_mbx.put(tx);

        // 3. Explicit Corner Case 3: Zero Diversity (Identical non-trivial chromosomes)
        tx = new();
        void'(tx.randomize() with { scenario_type == CORNER_IDENTICAL_POP; });
        tx.run_id = 3;
        gen2drv_mbx.put(tx);

        // 4. Randomized Stimulus Runs
        for (int i = 4; i <= repeat_count; i++) begin
            tx = new();
            if (!tx.randomize() with { scenario_type == RANDOM_POPULATION; }) begin
                $fatal(1, "[GEN-FAIL] Transaction randomization failed for run #%0d!", i);
            end
            tx.run_id = i;
            gen2drv_mbx.put(tx);
        end
    endtask
endclass


// -----------------------------------------------------------------------------
// Driver Class
// -----------------------------------------------------------------------------
class ga_driver #(
    parameter int CHROMOSOME_WIDTH = 16,
    parameter int POPULATION_SIZE  = 16,
    parameter int FITNESS_WIDTH    = 5
);
    virtual ga_if #(CHROMOSOME_WIDTH, FITNESS_WIDTH) vif;
    mailbox #(ga_transaction #(CHROMOSOME_WIDTH, POPULATION_SIZE, FITNESS_WIDTH)) gen2drv_mbx;
    mailbox #(ga_transaction #(CHROMOSOME_WIDTH, POPULATION_SIZE, FITNESS_WIDTH)) drv2mon_mbx;

    function new(input virtual ga_if #(CHROMOSOME_WIDTH, FITNESS_WIDTH) vif_inst,
                 input mailbox #(ga_transaction #(CHROMOSOME_WIDTH, POPULATION_SIZE, FITNESS_WIDTH)) mbx,
                 input mailbox #(ga_transaction #(CHROMOSOME_WIDTH, POPULATION_SIZE, FITNESS_WIDTH)) mon_mbx);
        this.vif         = vif_inst;
        this.gen2drv_mbx = mbx;
        this.drv2mon_mbx = mon_mbx;
    endfunction

    task reset_dut();
        vif.drv_cb.rst_n              <= 1'b0;
        vif.drv_cb.start_ga           <= 1'b0;
        vif.drv_cb.initial_population <= '0;
        repeat (3) @(vif.drv_cb);
        vif.drv_cb.rst_n              <= 1'b1;
        @(vif.drv_cb);
    endtask

    task drive_transaction(input ga_transaction #(CHROMOSOME_WIDTH, POPULATION_SIZE, FITNESS_WIDTH) tx);
        reset_dut();

        // Forward transaction context (such as scenario_type) to the monitor
        drv2mon_mbx.put(tx);

        // Initiate handshake
        vif.drv_cb.start_ga <= 1'b1;
        @(vif.drv_cb);
        vif.drv_cb.start_ga <= 1'b0;

        // Stream initial population into accelerator memory
        for (int i = 0; i < POPULATION_SIZE; i++) begin
            vif.drv_cb.initial_population <= tx.seed_population[i];
            @(vif.drv_cb);
        end
        vif.drv_cb.initial_population <= '0;
    endtask

    task run();
        ga_transaction #(CHROMOSOME_WIDTH, POPULATION_SIZE, FITNESS_WIDTH) tx;
        forever begin
            gen2drv_mbx.get(tx);
            drive_transaction(tx);
            // Wait for DUT to assert completion
            @(vif.drv_cb);
            wait (vif.ga_done == 1'b1);
            repeat (10) @(vif.drv_cb); // Inter-iteration recovery delay
        end
    endtask
endclass


// -----------------------------------------------------------------------------
// Monitor Class with Integrated Functional Coverage
// -----------------------------------------------------------------------------
class ga_monitor #(
    parameter int CHROMOSOME_WIDTH = 16,
    parameter int POPULATION_SIZE  = 16,
    parameter int FITNESS_WIDTH    = 5
);
    virtual ga_if #(CHROMOSOME_WIDTH, FITNESS_WIDTH) vif;
    mailbox #(ga_transaction #(CHROMOSOME_WIDTH, POPULATION_SIZE, FITNESS_WIDTH)) mon2scb_mbx;
    mailbox #(ga_transaction #(CHROMOSOME_WIDTH, POPULATION_SIZE, FITNESS_WIDTH)) drv2mon_mbx;

    function new(input virtual ga_if #(CHROMOSOME_WIDTH, FITNESS_WIDTH) vif_inst,
                 input mailbox #(ga_transaction #(CHROMOSOME_WIDTH, POPULATION_SIZE, FITNESS_WIDTH)) scb_mbx,
                 input mailbox #(ga_transaction #(CHROMOSOME_WIDTH, POPULATION_SIZE, FITNESS_WIDTH)) d2m_mbx);
        this.vif         = vif_inst;
        this.mon2scb_mbx = scb_mbx;
        this.drv2mon_mbx = d2m_mbx;
    endfunction

    task run();
        ga_transaction #(CHROMOSOME_WIDTH, POPULATION_SIZE, FITNESS_WIDTH) tx_drv;
        ga_transaction #(CHROMOSOME_WIDTH, POPULATION_SIZE, FITNESS_WIDTH) tx;
        int cycle_count;

        forever begin
            cycle_count = 0;
            drv2mon_mbx.get(tx_drv); // Receive active scenario context

            // Wait for execution start
            wait (vif.mon_cb.start_ga == 1'b1);
            @(vif.mon_cb);

            // Count operational cycles until completion
            while (!vif.mon_cb.ga_done) begin
                cycle_count++;
                @(vif.mon_cb);
            end

            // Capture stable response packet
            tx = new();
            tx.scenario_type       = tx_drv.scenario_type;
            tx.run_id              = tx_drv.run_id;
            tx.observed_chromosome = vif.mon_cb.best_chromosome;
            tx.observed_fitness    = vif.mon_cb.best_fitness;
            tx.execution_cycles    = cycle_count;

            // Trigger module-level functional coverage via interface bridge
            vif.cov_best_fitness     = tx.observed_fitness;
            vif.cov_execution_cycles = tx.execution_cycles;
            vif.cov_scenario_type    = tx.scenario_type;
            -> vif.cov_sample_event;

            mon2scb_mbx.put(tx);

            // Wait until ga_done falls before accepting next sample
            wait (vif.mon_cb.ga_done == 1'b0);
        end
    endtask
endclass


// -----------------------------------------------------------------------------
// Scoreboard Class (Golden Reference Model & Verification Engine)
// -----------------------------------------------------------------------------
class ga_scoreboard #(
    parameter int CHROMOSOME_WIDTH = 16,
    parameter int POPULATION_SIZE  = 16,
    parameter int FITNESS_WIDTH    = 5,
    parameter int MAX_GENERATIONS  = 20
);
    mailbox #(ga_transaction #(CHROMOSOME_WIDTH, POPULATION_SIZE, FITNESS_WIDTH)) mon2scb_mbx;
    int pass_count;
    int fail_count;
    int transaction_idx;

    function new(input mailbox #(ga_transaction #(CHROMOSOME_WIDTH, POPULATION_SIZE, FITNESS_WIDTH)) mbx);
        this.mon2scb_mbx        = mbx;
        this.pass_count         = 0;
        this.fail_count         = 0;
        this.transaction_idx    = 0;
    endfunction

    // Behavioral Golden Model: Computes expected One-Max fitness
    function bit [FITNESS_WIDTH-1:0] calculate_expected_fitness(input bit [CHROMOSOME_WIDTH-1:0] chromo);
        int ones_count;
        ones_count = 0;
        for (int i = 0; i < CHROMOSOME_WIDTH; i++) begin
            if (chromo[i] == 1'b1) ones_count++;
        end
        return ones_count[FITNESS_WIDTH-1:0];
    endfunction

    task run();
        ga_transaction #(CHROMOSOME_WIDTH, POPULATION_SIZE, FITNESS_WIDTH) tx;
        bit [FITNESS_WIDTH-1:0] expected_fitness;
        bit                     error_flag;

        forever begin
            mon2scb_mbx.get(tx);
            transaction_idx++;
            error_flag       = 0;
            expected_fitness = calculate_expected_fitness(tx.observed_chromosome);

            $display("\n=======================================================");
            $display("   SCOREBOARD REPORT: EVALUATION RUN #%0d [%s]",
                     transaction_idx, tx.scenario_type.name());
            $display("=======================================================");
            $display(" Active Cycles      : %0d", tx.execution_cycles);
            $display(" Best Chromosome    : %b (0x%04h)", tx.observed_chromosome, tx.observed_chromosome);
            $display(" DUT Best Fitness   : %0d", tx.observed_fitness);
            $display(" Golden Ref Fitness : %0d", expected_fitness);

            // Check 1: Golden Model validation
            if (tx.observed_fitness !== expected_fitness) begin
                $error("[FAIL] Fitness mismatch! Observed=%0d, Expected=%0d",
                       tx.observed_fitness, expected_fitness);
                error_flag = 1;
            end

            // Check 2: Physical upper boundary check
            if (tx.observed_fitness > CHROMOSOME_WIDTH) begin
                $error("[FAIL] Fitness overflow: %0d exceeds max %0d",
                       tx.observed_fitness, CHROMOSOME_WIDTH);
                error_flag = 1;
            end

            // Check 3: Corner case all-ones must finish with maximum fitness
            if (tx.scenario_type == CORNER_ALL_ONES && tx.observed_fitness != CHROMOSOME_WIDTH) begin
                $error("[FAIL] All-ones corner case did not yield optimal fitness!");
                error_flag = 1;
            end

            if (!error_flag) begin
                $display(" SCOREBOARD VERDICT : [PASS]");
                pass_count++;
            end else begin
                $display(" SCOREBOARD VERDICT : [FAIL]");
                fail_count++;
            end
            $display("=======================================================");
        end
    endtask

    function void print_summary(input real cov_pct);
        $display("\n#######################################################");
        $display("          COMPREHENSIVE TESTBENCH FINAL SUMMARY        ");
        $display("#######################################################");
        $display(" Total Transactions Checked : %0d", (pass_count + fail_count));
        $display(" Passed                     : %0d", pass_count);
        $display(" Failed                     : %0d", fail_count);
        $display(" Functional Coverage        : %0.2f%%", cov_pct);

        if (fail_count == 0 && pass_count > 0) begin
            $display(" OVERALL VERDICT            : ALL TEST SUITES PASSED");
        end else begin
            $display(" OVERALL VERDICT            : TEST SUITE FAILED");
        end
        $display("#######################################################\n");
    endfunction
endclass


// -----------------------------------------------------------------------------
// Environment Class
// -----------------------------------------------------------------------------
class ga_environment #(
    parameter int CHROMOSOME_WIDTH = 16,
    parameter int POPULATION_SIZE  = 16,
    parameter int FITNESS_WIDTH    = 5,
    parameter int MAX_GENERATIONS  = 20
);
    ga_generator  #(CHROMOSOME_WIDTH, POPULATION_SIZE, FITNESS_WIDTH)                   generator;
    ga_driver     #(CHROMOSOME_WIDTH, POPULATION_SIZE, FITNESS_WIDTH)                   driver;
    ga_monitor    #(CHROMOSOME_WIDTH, POPULATION_SIZE, FITNESS_WIDTH)                   monitor;
    ga_scoreboard #(CHROMOSOME_WIDTH, POPULATION_SIZE, FITNESS_WIDTH, MAX_GENERATIONS) scoreboard;

    mailbox #(ga_transaction #(CHROMOSOME_WIDTH, POPULATION_SIZE, FITNESS_WIDTH)) gen2drv_mbx;
    mailbox #(ga_transaction #(CHROMOSOME_WIDTH, POPULATION_SIZE, FITNESS_WIDTH)) drv2mon_mbx;
    mailbox #(ga_transaction #(CHROMOSOME_WIDTH, POPULATION_SIZE, FITNESS_WIDTH)) mon2scb_mbx;

    virtual ga_if #(CHROMOSOME_WIDTH, FITNESS_WIDTH) vif;
    int num_tests;

    function new(input virtual ga_if #(CHROMOSOME_WIDTH, FITNESS_WIDTH) vif_inst, input int tests);
        this.vif         = vif_inst;
        this.num_tests   = tests;
        gen2drv_mbx      = new();
        drv2mon_mbx      = new();
        mon2scb_mbx      = new();

        generator  = new(gen2drv_mbx, tests);
        driver     = new(vif, gen2drv_mbx, drv2mon_mbx);
        monitor    = new(vif, mon2scb_mbx, drv2mon_mbx);
        scoreboard = new(mon2scb_mbx);
    endfunction

    task run();
        fork
            generator.run();
            driver.run();
            monitor.run();
            scoreboard.run();
        join_any

        // Wait until all planned transactions are fully processed by the Scoreboard
        wait (scoreboard.pass_count + scoreboard.fail_count == num_tests);
        #100ns;
    endtask
endclass


// =============================================================================
// Top-Level Testbench Module
// =============================================================================
module tb_genetic_algorithm;

    // Configuration Parameters
    localparam int CHROMOSOME_WIDTH = 16;
    localparam int POPULATION_SIZE  = 16;
    localparam int MAX_GENERATIONS  = 20;
    localparam int FITNESS_WIDTH    = 5;
    localparam int CLK_PERIOD       = 10;    // 100 MHz (10ns period)
    localparam int NUM_TEST_RUNS    = 6;     // 3 Corner cases + 3 Randomized runs
    localparam int WATCHDOG_CYCLES  = 30000; // Timeout limit across all executions

    // Clock generator
    logic clk;
    initial clk = 0;
    always #(CLK_PERIOD / 2) clk = ~clk;

    // Interface Instantiation
    ga_if #(
        .CHROMOSOME_WIDTH(CHROMOSOME_WIDTH),
        .FITNESS_WIDTH(FITNESS_WIDTH)
    ) intf (
        .clk(clk)
    );

    // DUT Instantiation
    genetic_algorithm #(
        .CHROMOSOME_WIDTH (CHROMOSOME_WIDTH),
        .POPULATION_SIZE  (POPULATION_SIZE),
        .MAX_GENERATIONS  (MAX_GENERATIONS),
        .FITNESS_WIDTH    (FITNESS_WIDTH)
    ) dut (
        .clk               (clk),
        .rst_n             (intf.rst_n),
        .start_ga          (intf.start_ga),
        .initial_population(intf.initial_population),
        .best_chromosome   (intf.best_chromosome),
        .best_fitness      (intf.best_fitness),
        .ga_done           (intf.ga_done)
    );

    // -------------------------------------------------------------------------
    // Functional Coverage Model (Module-Level Instantiation for Vivado XSim)
    // -------------------------------------------------------------------------
    covergroup cg_genetic_algorithm @(intf.cov_sample_event);
        option.per_instance = 1;
        option.comment      = "Functional coverage metrics for GA accelerator";

        // Coverpoint 1: Best Fitness achieved
        cp_fitness: coverpoint intf.cov_best_fitness {
            bins zero_fitness    = {0};
            bins low_fitness     = {[1:5]};
            bins medium_fitness  = {[6:11]};
            bins high_fitness    = {[12:15]};
            bins perfect_fitness = {16}; // Target solution reached
        }

        // Coverpoint 2: Execution cycle duration bins
        cp_cycles: coverpoint intf.cov_execution_cycles {
            bins fast_convergence = {[1:1000]};
            bins mid_convergence  = {[1001:3000]};
            bins full_generation  = {[3001:7000]};
        }

        // Coverpoint 3: Stimulus scenario distribution
        cp_scenario: coverpoint intf.cov_scenario_type {
            bins rand_pop        = {RANDOM_POPULATION};
            bins all_ones_corner = {CORNER_ALL_ONES};
            bins all_zero_corner = {CORNER_ALL_ZEROS};
            bins no_diversity    = {CORNER_IDENTICAL_POP};
        }

        // Cross Coverage: Verify fitness outcomes across all test types
        cross_scenario_fitness: cross cp_scenario, cp_fitness;
    endgroup

    cg_genetic_algorithm cg_inst = new();

    // Global Safety Watchdog
    initial begin
        repeat (WATCHDOG_CYCLES) @(posedge clk);
        $fatal(1, "\n[WATCHDOG TIMEOUT] Simulation aborted! Reached maximum cycle limit (%0d).", WATCHDOG_CYCLES);
    end

    // Test Orchestration
    ga_environment #(
        .CHROMOSOME_WIDTH(CHROMOSOME_WIDTH),
        .POPULATION_SIZE(POPULATION_SIZE),
        .FITNESS_WIDTH(FITNESS_WIDTH),
        .MAX_GENERATIONS(MAX_GENERATIONS)
    ) env;

    // Explicit Virtual Interface reference variable (Resolves Vivado XSim constructor binding limitation)
    virtual ga_if #(CHROMOSOME_WIDTH, FITNESS_WIDTH) vif_inst;

    initial begin
        $display("\n>>> Starting Genetic Algorithm Testbench (Phase 4: Functional Coverage & Corner Cases) <<<\n");
        vif_inst = intf;
        env = new(vif_inst, NUM_TEST_RUNS);
        env.run();
        env.scoreboard.print_summary(cg_inst.get_inst_coverage());
        $finish;
    end

endmodule

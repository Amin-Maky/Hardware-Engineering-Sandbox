# My Project Management Sandbox Notes

## Master Hardware Template

```text
<project-name>/                     # Root of the repository
├── .gitignore                      # Must ignore all build/, work/, logs/, waves/, *.jou, *.log
├── .gitmodules                     # If using external Git submodules (e.g., AXI IPs)
├── LICENSE                         # License file (MIT, Apache 2.0, Solderpad, etc.)
├── README.md                       # High-level overview, quickstart, architecture summary
├── Bender.yml / fusesoc.core       # (Optional) Modern hardware package manager manifest
├── env.sh                          # Script to set $PROJ_ROOT, $PATH, and tool environments
├── Makefile                        # Top-level Makefile (delegates to sim/, fpga/, sw/)
│
├── docs/                           # All documentation (NO diagrams inside scripts/!)
│   ├── figures/                    # .drawio, .svg, .png, waveforms screenshots
│   ├── specs/                      # Micro-architecture specifications, memory maps
│   └── user_guide/                 # Markdown files (like your CVA6-lab docs)
│
├── rtl/                            # Synthesizable Hardware Design ONLY
│   ├── include/                    # Global headers (.svh, .vh) used across multiple modules
│   │   └── proj_macros.svh
│   ├── pkgs/                       # SystemVerilog packages (*_pkg.sv) - Must compile first!
│   │   └── proj_pkg.sv
│   ├── core/                       # Logical grouping of sub-modules (or flat for small projects)
│   ├── periph/                     # Peripherals / Interfaces
│   └── top_module.sv               # Top-level RTL wrapper
│
├── ips/ (or vendor/)               # Third-party IPs, external repos, or hard macros
│
├── filelists/                      # Centralized filelists (.f) used by BOTH sim and synthesis
│   ├── rtl.f                       # Pure synthesizable RTL + packages + incdirs
│   ├── tb_sv.f                     # SystemVerilog testbench files + VIPs
│   └── top_sim.f                   # Includes rtl.f + tb_sv.f (using -f flag)
│
├── tb/ (or verif/)                 # All Verification Sources (NO simulation outputs here!)
│   ├── include/                    # Verification headers/macros
│   ├── pkgs/                       # Testbench packages
│   ├── sv/                         # SystemVerilog testbenches & UVM/SV components
│   │   └── top_tb.sv
│   ├── cpp/                        # Verilator C++ testbenches / DPI-C sources
│   │   └── sim_main.cpp
│   ├── cocotb/                     # (Optional) Python-based testbenches
│   ├── vip/                        # Verification IPs (AXI, UART bus functional models)
│   └── wrappers/                   # Simulation-specific wrappers (e.g., RAM behavior models)
│
├── sw/ (or benchmarks/)            # Software / Firmware running ON the hardware
│   ├── include/                    # C/Assembly headers (.h)
│   ├── lib/                        # Drivers, HAL, printf implementations
│   ├── linker/                     # Linker scripts (.ld)
│   ├── boot/                       # Bootloader / crt0.S / boot.S
│   ├── apps/ (or tests/)           # Bare-metal C or Assembly test programs
│   ├── Makefile                    # Compiles C/ASM to .elf, .hex, .bin, .dump
│   └── build/                      # (gitignored) Compiled software artifacts (.elf, .hex)
│
├── model/ (or iss/)                # Golden Reference Models (Python, C++, SystemC)
│   ├── iss/                        # Instruction Set Simulator / Golden Predictor
│   └── fault_injector/             # Models for reliability/fault-tolerance analysis
│
├── scripts/                        # Automation, Parsers, and Utility Scripts (Executable code)
│   ├── cosim_runner.py             # Co-simulation & trace diffing script
│   ├── log_parser.py               # Extracts metrics/errors from simulation logs
│   ├── plotting/                   # Python/MATLAB scripts to generate paper-ready plots
│   └── gen_filelist.py             # Custom scripts to auto-generate .f files
│
├── sim/                            # Simulation Workspace (Execution environment ONLY)
│   ├── Makefile                    # Simulation-specific Makefile (Verilator, Questa, VCS)
│   ├── waves/                      # Saved waveform configurations (.gtkw, .do, .tcl)
│   └── build/ (or work/)           # (gitignored) All generated sim files go inside here:
│       ├── compile/                #   - Compiled libraries (work/, obj_dir/)
│       ├── logs/                   #   - Simulation transcripts (.log)
│       └── regressions/            #   - Isolated folders per test run (test_1/, test_2/)
│
├── fpga/                           # FPGA Implementation & Prototyping
│   ├── constraints/                # Timing & Physical constraints (.xdc, .sdc, .pcf)
│   ├── scripts/ (or vivado/, ise/) # Tool-specific Tcl scripts (create_prj, syn, impl)
│   ├── ips/                        # FPGA-specific IPs (.xci, Xilinx BRAM, PLLs)
│   ├── wrappers/                   # Board-level top wrappers (connecting pins/clocks)
│   ├── Makefile                    # Runs Vivado/Quartus in batch mode
│   └── build/                      # (gitignored) Vivado projects, bitstreams, reports
│
└── asic/ (or syn/)                 # ASIC Synthesis & Place-and-Route (Synopsys DC, Genus)
    ├── constraints/                # .sdc files
    ├── scripts/                    # .tcl scripts for synthesis/STA
    └── build/                      # (gitignored) Gate-level netlists, area/power/timing reports
```
> **Golden Rule (Out-of-tree build):** Never generate logs, waveforms (`.vcd`, `.fst`, `.wlf`), or compiled objects (`work/`, `obj_dir/`) inside `rtl/` or `tb/`. Everything generated by tools must be confined to `*/build/` directories so `rm -rf build/` cleans the entire workspace safely.
---
## `filelist.f` Template

There are 2 useful templates:

  1. Synthesizable RTL Filelist Template
  2. Verification & Simulation Filelist Template

### Synthesizable RTL Filelist Template

```bash
// =============================================================================
// File        : rtl.f
// Description : Master filelist for synthesizable RTL design ONLY.
//               Used by both Simulation (Verilator/Questa/VCS) and Synthesis.
// Prerequisite: Environment variable $PROJ_ROOT must be set to repository root.
//               Note: Compile order strictly matters (Packages -> Modules -> Top).
// =============================================================================

// -----------------------------------------------------------------------------
// 1. Global Compile-Time Macros (+define+)
// -----------------------------------------------------------------------------
// Un-comment or pass via command line/Makefile to configure the design
// +define+SYNTHESIS
// +define+DATA_WIDTH=32
// +define+USE_CUSTOM_ALU


// -----------------------------------------------------------------------------
// 2. Include Directories (+incdir+)
// -----------------------------------------------------------------------------
// Directories searched when the compiler encounters `include "filename.svh"
// Do NOT put specific file names here; only directory paths.
+incdir+${PROJ_ROOT}/rtl/include
+incdir+${PROJ_ROOT}/ips/axi/include


// -----------------------------------------------------------------------------
// 3. Nested / External IP Filelists (-f / -F)
// -----------------------------------------------------------------------------
// -f : Paths inside the sub-filelist are resolved relative to current directory
//      (Safe when using ${PROJ_ROOT} inside all .f files).
// -F : Paths inside the sub-filelist are resolved relative to that .f file's location.
// -f ${PROJ_ROOT}/ips/common_cells/cells.f


// -----------------------------------------------------------------------------
// 4. Library Directories (-y and +libext+) - Optional
// -----------------------------------------------------------------------------
// Tells the compiler where to automatically look for unresolved module names
// without listing every single file manually (Great for standard cells or primitives).
// -y ${PROJ_ROOT}/rtl/lib/primitives
// +libext+.sv+.v


// -----------------------------------------------------------------------------
// 5. SystemVerilog Packages (*_pkg.sv) - MUST BE COMPILED FIRST!
// -----------------------------------------------------------------------------
// Order matters if one package imports another package.
${PROJ_ROOT}/rtl/pkgs/global_config_pkg.sv
${PROJ_ROOT}/rtl/pkgs/isa_pkg.sv
${PROJ_ROOT}/rtl/pkgs/core_types_pkg.sv


// -----------------------------------------------------------------------------
// 6. SystemVerilog Interfaces (*_if.sv)
// -----------------------------------------------------------------------------
${PROJ_ROOT}/rtl/interfaces/axi_bus_if.sv
${PROJ_ROOT}/rtl/interfaces/mem_if.sv


// -----------------------------------------------------------------------------
// 7. RTL Design Modules (Bottom-Up Hierarchy: Leaf modules -> Sub-systems)
// -----------------------------------------------------------------------------
// --- Primitives & Tech-Wrapper Modules ---
${PROJ_ROOT}/rtl/common/fifo_sync.sv
${PROJ_ROOT}/rtl/common/sram_wrapper.sv

// --- Core / Datapath Modules ---
${PROJ_ROOT}/rtl/core/alu.sv
${PROJ_ROOT}/rtl/core/regfile.sv
${PROJ_ROOT}/rtl/core/decoder.sv
${PROJ_ROOT}/rtl/core/controller.sv

// --- Peripherals ---
${PROJ_ROOT}/rtl/periph/uart_rx.sv
${PROJ_ROOT}/rtl/periph/uart_tx.sv


// -----------------------------------------------------------------------------
// 8. Top-Level Synthesizable Wrapper
// -----------------------------------------------------------------------------
${PROJ_ROOT}/rtl/top_system.sv
```

### Verification & Simulation Filelist Template
```bash
// =============================================================================
// File        : sim.f
// Description : Master filelist for RTL Simulation and Verification.
//               Inherits synthesizable files from rtl.f and adds testbench/VIPs.
// Prerequisite: Environment variable $PROJ_ROOT must be set to repository root.
// =============================================================================

// -----------------------------------------------------------------------------
// 1. Simulation-Specific Macros (+define+)
// -----------------------------------------------------------------------------
+define+SIMULATION
+define+ASSERT_ON
// +define+DUMP_VCD
// +define+FAULT_INJECTION_EN


// -----------------------------------------------------------------------------
// 2. Testbench & VIP Include Directories (+incdir+)
// -----------------------------------------------------------------------------
+incdir+${PROJ_ROOT}/tb/include
+incdir+${PROJ_ROOT}/tb/vip/axi_vip/include


// -----------------------------------------------------------------------------
// 3. Import Synthesizable RTL Filelist (-f)
// -----------------------------------------------------------------------------
// Pulls in all RTL packages, interfaces, and design modules in exact order
-f ${PROJ_ROOT}/filelists/rtl.f


// -----------------------------------------------------------------------------
// 4. Simulation Models & Behavioral Wrappers (Non-Synthesizable)
// -----------------------------------------------------------------------------
// Behavioral models for memories, PLLs, or FPGA hard blocks
${PROJ_ROOT}/tb/wrappers/sim_sram_model.sv
${PROJ_ROOT}/tb/wrappers/clk_rst_gen.sv


// -----------------------------------------------------------------------------
// 5. Verification Packages & VIPs (Verification IP)
// -----------------------------------------------------------------------------
${PROJ_ROOT}/tb/pkgs/tb_utils_pkg.sv
${PROJ_ROOT}/tb/vip/axi_vip/axi_vip_pkg.sv
${PROJ_ROOT}/tb/vip/axi_vip/axi_vip_if.sv


// -----------------------------------------------------------------------------
// 6. Testbench Components & Top-Level Testbench
// -----------------------------------------------------------------------------
// C/C++ DPI-C or Verilator harness files (if passed directly via .f)
// ${PROJ_ROOT}/tb/cpp/dpi_functions.cpp

// SystemVerilog Top Testbench
${PROJ_ROOT}/tb/sv/top_tb.sv
```
### Quick Reference Cheat Sheet
```bash
// =============================================================================
//                        FILELIST (.f) QUICK CHEAT SHEET
// =============================================================================
// +incdir+<path>       : Add directory to search path for `include directives.
// +define+<macro>      : Define a text macro (same as `define <macro> in code).
// +define+<macro>=<val>: Define a macro with a specific value.
// -f <file.f>          : Include another filelist (paths relative to CWD).
// -F <file.f>          : Include another filelist (paths relative to <file.f>).
// -v <file.v>          : Specify a Verilog library file (compiled only if referenced).
// -y <path>            : Specify a library directory for unresolved modules.
// +libext+<ext1>+<ext2>: Specify file extensions for -y search (e.g., +libext+.sv+.v).
// =============================================================================
```
---
## Master Environment Setup Template (`env.sh`)
```bash
#!/usr/bin/env bash
# =============================================================================
# File        : env.sh
# Description : Master environment setup script for Hardware/RTL projects.
#               Sets directory anchors, updates PATH/PYTHONPATH, activates
#               Python venv, and configures EDA/Cross-compiler toolchains.
# Usage       : MUST BE SOURCED ->  source env.sh   (or:  . env.sh)
# =============================================================================

# -----------------------------------------------------------------------------
# 1. Execution Guard (Prevent running as ./env.sh instead of sourcing)
# -----------------------------------------------------------------------------
# In Bash/Zsh, 'return' only succeeds inside a sourced script or function.
if ! (return 0 2>/dev/null); then
    echo "[ERROR] Do NOT execute this script directly (./env.sh)!"
    echo "        Please source it instead:  source env.sh"
    exit 1
fi

# -----------------------------------------------------------------------------
# 2. Resolve Repository Root ($PROJ_ROOT) - Compatible with Bash & Zsh
# -----------------------------------------------------------------------------
if [ -n "${BASH_SOURCE[0]}" ]; then
    _SCRIPT_PATH="${BASH_SOURCE[0]}"
elif [ -n "${ZSH_VERSION}" ]; then
    _SCRIPT_PATH="${(%):-%x}"
else
    _SCRIPT_PATH="$0"
fi

export PROJ_ROOT="$(cd "$(dirname "${_SCRIPT_PATH}")" && pwd)"
unset _SCRIPT_PATH

# -----------------------------------------------------------------------------
# 3. Project Directory Anchors (1-to-1 match with Master Directory Template)
# -----------------------------------------------------------------------------
export DOCS_DIR="${PROJ_ROOT}/docs"
export RTL_DIR="${PROJ_ROOT}/rtl"
export IPS_DIR="${PROJ_ROOT}/ips"
export FILELISTS_DIR="${PROJ_ROOT}/filelists"
export TB_DIR="${PROJ_ROOT}/tb"
export SW_DIR="${PROJ_ROOT}/sw"
export MODEL_DIR="${PROJ_ROOT}/model"
export SCRIPTS_DIR="${PROJ_ROOT}/scripts"
export SIM_DIR="${PROJ_ROOT}/sim"
export FPGA_DIR="${PROJ_ROOT}/fpga"
export ASIC_DIR="${PROJ_ROOT}/asic"

# Centralized Build / Output Directories (Out-of-tree build targets)
export SW_BUILD_DIR="${SW_DIR}/build"
export SIM_BUILD_DIR="${SIM_DIR}/build"
export FPGA_BUILD_DIR="${FPGA_DIR}/build"
export ASIC_BUILD_DIR="${ASIC_DIR}/build"

# -----------------------------------------------------------------------------
# 4. Helper Function: Idempotent PATH/PYTHONPATH Prepend
# -----------------------------------------------------------------------------
# Prevents duplicate entries if 'source env.sh' is run multiple times.
_prepend_path() {
    local var_name="$1"
    local new_dir="$2"
    eval "local current_val=\"\${${var_name}:-}\""
    if [ -d "${new_dir}" ] && [[ ":${current_val}:" != *":${new_dir}:"* ]]; then
        export "${var_name}=${new_dir}${current_val:+:${current_val}}"
    fi
}

# Add scripts/ to system PATH (run cosim_runner.py or log_parser.py anywhere)
_prepend_path PATH "${SCRIPTS_DIR}"

# Add model/ and scripts/ to PYTHONPATH (for Cocotb, ISS, Fault Injector, etc.)
_prepend_path PYTHONPATH "${MODEL_DIR}"
_prepend_path PYTHONPATH "${SCRIPTS_DIR}"
_prepend_path PYTHONPATH "${TB_DIR}/cocotb"

# -----------------------------------------------------------------------------
# 5. Python Virtual Environment Auto-Activation (Optional)
# -----------------------------------------------------------------------------
# Automatically activates .venv if present in the project root
if [ -f "${PROJ_ROOT}/.venv/bin/activate" ]; then
    # shellcheck disable=SC1091
    source "${PROJ_ROOT}/.venv/bin/activate"
fi

# -----------------------------------------------------------------------------
# 6. EDA Tools & Cross-Compiler Toolchain Configuration
# -----------------------------------------------------------------------------
# Use ':=' or ':-' so user/server pre-configured paths are not overwritten.

# Software Cross-Compiler (e.g., RISC-V or MIPS GCC Toolchain)
export CROSS_COMPILE="${CROSS_COMPILE:-riscv64-unknown-elf-}"
# _prepend_path PATH "/opt/riscv/bin"

# EDA Tool Paths (Uncomment and adjust for local workstation / university server)
# _prepend_path PATH "/tools/Xilinx/Vivado/2023.2/bin"
# _prepend_path PATH "/tools/questasim/bin"
# _prepend_path PATH "/tools/synopsys/vcs/bin"

# EDA License Servers (For commercial tools like Questa, VCS, Synopsys DC)
# export LM_LICENSE_FILE="${LM_LICENSE_FILE:-27000@license-server.univ.edu}"

unset -f _prepend_path

# -----------------------------------------------------------------------------
# 7. Quick Navigation Aliases (Quality-of-Life for Terminal Workflow)
# -----------------------------------------------------------------------------
alias cdroot='cd "${PROJ_ROOT}"'
alias cdrtl='cd "${RTL_DIR}"'
alias cdtb='cd "${TB_DIR}"'
alias cdsim='cd "${SIM_DIR}"'
alias cdsw='cd "${SW_DIR}"'
alias cdfpga='cd "${FPGA_DIR}"'

# -----------------------------------------------------------------------------
# 8. Environment Summary & Sanity Check
# -----------------------------------------------------------------------------
echo "=================================================================="
echo " Project Environment Initialized"
echo "------------------------------------------------------------------"
echo " PROJ_ROOT   : ${PROJ_ROOT}"
echo " PYTHON      : $(command -v python3 || echo 'NOT FOUND')"
echo " VERILATOR   : $(command -v verilator || echo 'NOT FOUND')"
echo " VIVADO      : $(command -v vivado || echo 'NOT FOUND')"
echo " GCC PREFIX  : ${CROSS_COMPILE} ($(command -v "${CROSS_COMPILE}gcc" || echo 'NOT FOUND'))"
echo "=================================================================="
```



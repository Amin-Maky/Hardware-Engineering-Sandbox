from pathlib import Path

PC_START = 0
PC_STEP = 1


REG_MAP = {
    "$zero": 0, "zero": 0,
    "$at": 1,   "at": 1,
    "$v0": 2,   "v0": 2,
    "$v1": 3,   "v1": 3,
    "$a0": 4,   "a0": 4,
    "$a1": 5,   "a1": 5,
    "$a2": 6,   "a2": 6,
    "$a3": 7,   "a3": 7,
    "$a4": 8,   "a4": 8,
    "$t0": 9,   "t0": 9,
}

INSTRUCTIONS = {
    # R-Type: add rd, rs, rt
    "add":  {"type": "R", "opcode": 0, "funct": 0x20},
    "sub":  {"type": "R", "opcode": 0, "funct": 0x22},
    "and":  {"type": "R", "opcode": 0, "funct": 0x24},
    "or":   {"type": "R", "opcode": 0, "funct": 0x25},
    "slt":  {"type": "R", "opcode": 0, "funct": 0x2A},

    # I-Type: addi rt, rs, imm
    "addi": {"type": "I", "opcode": 0x08},
    "andi": {"type": "I", "opcode": 0x0C},
    "ori":  {"type": "I", "opcode": 0x0D},
    "lw":   {"type": "I", "opcode": 0x23},
    "sw":   {"type": "I", "opcode": 0x2B},
    "beq":  {"type": "I", "opcode": 0x04},

    # J-Type: j target
    "j":    {"type": "J", "opcode": 0x02},
    "jal":  {"type": "J", "opcode": 0x03},
}

asm_path = Path("app.S")

output_lines = []

# =========================================================
# PASS 1: Finding label addresses and cleaning instructions
# =========================================================

labels = {}
instructions_list = []
current_pc = PC_START

with open(asm_path, mode="r") as file:
    for line in file:
        code_part = line.split("#", maxsplit=1)[0]
        clean_line = code_part.strip()
        
        if not clean_line:
            continue
        
        if ":" in clean_line:    # Extract label and record its address
            label_part, rest_of_line = clean_line.split(":", maxsplit=1)
            label_name = label_part.strip()
            labels[label_name] = current_pc
            
            clean_line = rest_of_line.strip()
            if not clean_line:
                continue
        
        instructions_list.append((current_pc, clean_line))
        current_pc += PC_STEP

print("Symbol Table (Labels):", labels)
print("-" * 40)



# ======================================================
# PASS 2: Converting instructions to 32-bit machine code
# ======================================================

for pc, clean_line in instructions_list:
    parts = clean_line.split(maxsplit=1)
    instruction_name = parts[0]

    if instruction_name not in INSTRUCTIONS:
        print(f"Error at PC={pc}: Unknown instruction '{instruction_name}'")
        continue
    
    info = INSTRUCTIONS[instruction_name]
    inst_type = info["type"]
    args_part = parts[1]
    operands = [op.strip() for op in args_part.split(",")]

    if inst_type == "R":
        # MIPS R-Type: rd, rs, rt -> funct & opcode=0rd = REG_MAP[operands[0]]
        rd = REG_MAP[operands[0]]
        rs = REG_MAP[operands[1]]
        rt = REG_MAP[operands[2]]
        shamt = 0
        funct = info["funct"]

        machine_code = (0 << 26) | (rs << 21) | (rt << 16) | (rd << 11) | (shamt << 6) | funct

        binary_code = f"{machine_code:032b}"

        # print(f"{instruction_name} is an R-Type instruction (funct={hex(info['funct'])})")
        # print(f"binary_code:{binary_code}")
        # print(binary_code)

    elif inst_type == "I":
        # MIPS I-Type: rt, rs, imm -> opcode
        rt = REG_MAP[operands[0]]
        rs = REG_MAP[operands[1]]
        raw_imm = operands[2]

        if raw_imm in labels:
            imm_val = labels[raw_imm]
        else:
            imm_val = int(raw_imm, 0)
        
        imm = imm_val & 0xFFFF

        machine_code = (info["opcode"] << 26) | (rs << 21) | (rt << 16) | imm

        binary_code = f"{machine_code:032b}"

        # print(f"{instruction_name} is an I-Type instruction (opcode={hex(info['opcode'])})")
        # print(f"binary_code:{binary_code}")
        # print(binary_code)

    elif inst_type == "J":
        # MIPS J-Type: target -> opcode
        raw_target = operands[0]

        if raw_target in labels:
            target_val = labels[raw_target]
        else:
            target_val = int(raw_target, 0)

        target = target_val & 0x03FFFFFF

        machine_code = (info["opcode"] << 26) | target

        binary_code = f"{machine_code:032b}"

        # print(f"{instruction_name} is a J-Type instruction (opcode={hex(info['opcode'])})")
        # print(f"binary_code:{binary_code}")
        # print(binary_code)

    print(binary_code)
    output_lines.append(binary_code)

out_path = Path("program.txt")
with open(out_path, mode="w") as out_file:
    for line in output_lines:
        out_file.write(f"{line}\n")

print(f"Successfully wrote {len(output_lines)} instructions to {out_path}")

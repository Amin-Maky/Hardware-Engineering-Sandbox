from pathlib import Path

log_path = Path("modelsim.log")

with open(log_path, mode="r") as file:
    for line in file:
        clean_line = line.strip()
        if "Error" in clean_line:
            print(clean_line)

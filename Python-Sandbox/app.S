    # ---  Start Our Custom APK ---
    # ==========================================
    # 1. Register Initialization (Setup)
    # ==========================================
    addi a1, $zero, 10             # initializing ...
    addi a2, $zero, 2              # initializing ...
    addi a3, $zero, 8              # initializing ...
    
    # ==========================================
    # 2. Test
    # ==========================================
branch:
    add a4, a3, a2
    beq a4, a1, branch
    
    # --- Finish Our Custom APK ---

loop:
    j loop


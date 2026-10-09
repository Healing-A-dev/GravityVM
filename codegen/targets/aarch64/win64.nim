import std/[strutils, tables]
import ../../../core/memory

var aarch64_win64* = initTable[string, proc(d0: string, d1: string, d2: string): string]()
var rodata_counter = 0
var comp_counter = 0
var current_section = "none"
var labelCounter = 0

proc setSection(sec: string): string =
    if current_section == sec: return ""
    current_section = sec
    case sec
    of ".text": return "    .section .text\n"
    of ".data": return "    .section .data\n"
    of ".rodata": return "    .section .rdata\n"
    of ".bss": return "    .section .bss\n"
    else: return "    .section " & sec & "\n"

proc resolveReg(arg: string): string =
    var clean = arg.replace("!", "").replace("[", "").replace("]", "")
    if clean.contains("sra") or clean == "%rax": return "x0"
    if clean.contains("srb") or clean == "%rbx": return "x1"
    if clean.contains("src") or clean == "%rcx": return "x2"
    if clean.contains("srd") or clean == "%rdx": return "x3"
    if clean.contains("sre"): return "x4"
    if clean == "%rdi": return "x0"
    if clean == "%rsi": return "x1"
    if clean == "%rdx": return "x2"
    if clean == "%rcx": return "x3"
    if clean == "%r8": return "x4"
    if clean == "%r9": return "x5"
    if clean.startsWith("x") and clean.len in [2, 3]: return clean
    return ""

proc loadStackOffset(reg: string, offset: int): string =
    if offset >= -256 and offset <= 255:
        return "    ldr " & reg & ", [x29, #" & $offset & "]\n"
    elif offset > 255 and offset <= 32760 and (offset mod 8) == 0:
        return "    ldr " & reg & ", [x29, #" & $offset & "]\n"
    else:
        var res = ""
        let absOffset = abs(offset)
        if absOffset <= 4095:
            if offset < 0:
                res.add("    sub x16, x29, #" & $absOffset & "\n")
            else:
                res.add("    add x16, x29, #" & $absOffset & "\n")
        else:
            res.add("    mov x16, #" & $absOffset & "\n")
            if offset < 0:
                res.add("    sub x16, x29, x16\n")
            else:
                res.add("    add x16, x29, x16\n")
        res.add("    ldr " & reg & ", [x16]\n")
        return res

proc storeStackOffset(reg: string, offset: int): string =
    if offset >= -256 and offset <= 255:
        return "    str " & reg & ", [x29, #" & $offset & "]\n"
    elif offset > 255 and offset <= 32760 and (offset mod 8) == 0:
        return "    str " & reg & ", [x29, #" & $offset & "]\n"
    else:
        var res = ""
        let absOffset = abs(offset)
        if absOffset <= 4095:
            if offset < 0:
                res.add("    sub x16, x29, #" & $absOffset & "\n")
            else:
                res.add("    add x16, x29, #" & $absOffset & "\n")
        else:
            res.add("    mov x16, #" & $absOffset & "\n")
            if offset < 0:
                res.add("    sub x16, x29, x16\n")
            else:
                res.add("    add x16, x29, x16\n")
        res.add("    str " & reg & ", [x16]\n")
        return res

proc loadVal(arg: string, reg: string): string =
    if arg == "" or arg == "0":
        return "    mov " & reg & ", #0\n"

    let r = resolveReg(arg)
    if r != "":
        if r == reg: return ""
        return "    mov " & reg & ", " & r & "\n"

    var clean = arg.replace("!", "").replace("[", "").replace("]", "").replace("$", "")
    if clean.contains("(%rbp)") or clean.contains("(%rsp)"):
        let offsetStr = clean.replace("(%rbp)", "").replace("(%rsp)", "")
        var offset = 0
        try: offset = parseInt(offsetStr)
        except: offset = 0
        return loadStackOffset(reg, offset)

    if arg.startsWith("str_") or arg.startsWith("$str_"):
        let lbl = if arg.startsWith("$str_"): arg[1..^1] else: arg
        return "    adrp " & reg & ", " & lbl & "\n    add " & reg & ", " & reg & ", :lo12:" & lbl & "\n"

    if clean.startsWith("@"):
        let lbl = "G" & clean[1..^1]
        return "    adrp x12, " & lbl & "\n    add x12, x12, :lo12:" & lbl & "\n    ldr " & reg & ", [x12]\n"
    elif clean.startsWith("%"):
        let lbl = "B" & clean[1..^1]
        return "    adrp x12, " & lbl & "\n    add x12, x12, :lo12:" & lbl & "\n    ldr " & reg & ", [x12]\n"
    elif clean.len > 1 and clean.startsWith("0") and not clean.startsWith("-") and clean.allCharsInSet(Digits):
        let lbl = "L" & clean
        return "    adrp x12, " & lbl & "\n    add x12, x12, :lo12:" & lbl & "\n    ldr " & reg & ", [x12]\n"
    elif (clean.startsWith("L") or clean.startsWith("B")) and not clean.contains("\""):
        return "    adrp x12, " & clean & "\n    add x12, x12, :lo12:" & clean & "\n    ldr " & reg & ", [x12]\n"

    try:
        let val = parseInt(clean)
        if val >= 0 and val <= 65535:
            return "    mov " & reg & ", #" & $val & "\n"
        else:
            return "    ldr " & reg & ", =" & $val & "\n"
    except:
        return "    ldr " & reg & ", =" & clean & "\n"

proc storeVal(reg: string, dest: string): string =
    let r = resolveReg(dest)
    if r != "":
        if r == reg: return ""
        return "    mov " & r & ", " & reg & "\n"

    var clean = dest.replace("!", "").replace("[", "").replace("]", "").replace("$", "")
    if clean.contains("(%rbp)") or clean.contains("(%rsp)"):
        let offsetStr = clean.replace("(%rbp)", "").replace("(%rsp)", "")
        var offset = 0
        try: offset = parseInt(offsetStr)
        except: offset = 0
        return storeStackOffset(reg, offset)

    var sym = ""
    if clean.startsWith("@"): sym = "G" & clean[1..^1]
    elif clean.startsWith("%"): sym = "B" & clean[1..^1]
    elif clean.len > 1 and clean.startsWith("0") and clean.allCharsInSet(Digits): sym = "L" & clean
    elif clean.startsWith("L") or clean.startsWith("B"): sym = clean
    else: sym = "L" & clean

    return "    adrp x12, " & sym & "\n    add x12, x12, :lo12:" & sym & "\n    str " & reg & ", [x12]\n"

proc getUniqueLabel(prefix: string): string =
    inc labelCounter
    return prefix & "_" & $labelCounter

# --- OPCODES ---
aarch64_win64["STORE"] = proc(d0: string, d1: string, d2: string): string =
    var to_append = ""
    var dest = d0
    var src = d1
    if src == "": src = "0"
    if src.startsWith("[") and src.endsWith("]"): src = src[1..^2]

    if dest.startsWith("!") or dest.contains("(%rbp)") or dest.contains("(%rsp)"):
        to_append.add(setSection(".text"))
        to_append.add(loadVal(src, "x11"))
        to_append.add(storeVal("x11", dest))
        return to_append

    var safeValue = src
    if safeValue.contains("%") or safeValue.contains("$") or safeValue.contains("@"): safeValue = "0"

    to_append.add(setSection(".data"))
    if dest.startsWith("@"): to_append.add("G" & dest[1..^1] & ": .quad " & safeValue & "\n")
    elif dest.startsWith("$"): to_append.add("L" & dest[1..^1] & ": .quad " & safeValue & "\n")
    elif dest.startsWith("%"): to_append.add("B" & dest[1..^1] & ": .quad " & safeValue & "\n")
    return to_append

aarch64_win64["UPD"] = proc(d0: string, d1: string, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d1, "x11"))
    s.add(storeVal("x11", d0))
    return s

aarch64_win64["LBL"] = proc(d0: string, d1: string, d2: string): string =
    var s = setSection(".text")
    var lbl = d0.replace("[", "").replace("]", "")

    if lbl == "ENTRY":
        s.add("    .global _pei386_runtime_relocator\n")
        s.add("_pei386_runtime_relocator:\n")
        s.add("    ret\n\n")
        s.add("    .global mainCRTStartup\n")
        s.add("mainCRTStartup:\n")
        s.add("    stp x29, x30, [sp, -16]!\n")
        s.add("    mov x29, sp\n")
        s.add("    bl newton_init_runtime\n")
        s.add("    b ENTRY\n")
        s.add("ENTRY:\n")
        return s

    s.add(lbl & ":\n")
    if lbl.startsWith("F_"):
        s.add("    stp x29, x30, [sp, -16]!\n")
        s.add("    mov x29, sp\n")
    return s

aarch64_win64["CALL"] = proc(d0: string, d1: string, d2: string): string =
    var s = setSection(".text")
    let funcLabel = d0.replace("[", "").replace("]", "")
    s.add("    bl " & funcLabel & "\n")

    var argCount = 0
    try: argCount = parseInt(d1)
    except: discard

    if argCount > 0:
        let popBytes = (argCount * 8 + 15) and not 15
        s.add("    add sp, sp, #" & $popBytes & "\n")

    if d2 != "00" and d2 != "":
        s.add(storeVal("x0", d2))
    return s

aarch64_win64["CALLD"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d1, "x9"))
    s.add("    blr x9\n")
    if d2 != "0" and d2 != "":
        let popBytes = (parseInt(d2) * 8 + 15) and not 15
        s.add("    add sp, sp, #" & $popBytes & "\n")
    s.add(storeVal("x0", d0))
    return s

aarch64_win64["RET"] = proc(d0: string, d1: string, d2: string): string =
    var s = setSection(".text")
    if d0 != "" and d0 != "0" and d0 != "00":
        s.add(loadVal(d0, "x0"))
    s.add("    mov sp, x29\n")
    s.add("    ldp x29, x30, [sp], 16\n")
    s.add("    ret\n")
    return s

aarch64_win64["PUSH"] = proc(d0: string, d1: string, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d0, "x9"))
    s.add("    str x9, [sp, -16]!\n")
    return s

aarch64_win64["GETARG"] = proc(d0: string, d1: string, d2: string): string =
    var index = 0
    try: index = parseInt(d1)
    except: discard
    let offset = 16 + (index * 16)
    var s = setSection(".text")
    s.add("    ldr x0, [x29, #" & $offset & "]\n")
    s.add(storeVal("x0", d0))
    return s

aarch64_win64["EXPO"] = proc(d0, d1, d2: string): string =
    return ".global " & d0.replace("[","").replace("]","") & "\n"

aarch64_win64["ETRN"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add("    # FFI SHIELD (AARCH64 WIN64)\n")
    s.add("    stp x19, x20, [sp, -16]!\n")
    s.add("    bl " & d0.replace("[","").replace("]","") & "\n")
    s.add("    ldp x19, x20, [sp], 16\n")
    s.add("    lsl x0, x0, #1\n")
    s.add("    orr x0, x0, #1\n")
    return s

# --- ARITHMETIC ---
aarch64_win64["ADD"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d0, "x0"))
    s.add(loadVal(d1, "x9"))
    s.add("    add x0, x0, x9\n")
    s.add("    sub x0, x0, #1\n")
    return s

aarch64_win64["SUB"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d0, "x0"))
    s.add(loadVal(d1, "x9"))
    s.add("    sub x0, x0, x9\n")
    s.add("    add x0, x0, #1\n")
    return s

aarch64_win64["MUL"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d0, "x0"))
    s.add("    asr x0, x0, #1\n")
    s.add(loadVal(d1, "x9"))
    s.add("    asr x9, x9, #1\n")
    s.add("    mul x0, x0, x9\n")
    s.add("    lsl x0, x0, #1\n")
    s.add("    orr x0, x0, #1\n")
    return s

aarch64_win64["DIV"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d0, "x0"))
    s.add("    asr x0, x0, #1\n")
    s.add(loadVal(d1, "x9"))
    s.add("    asr x9, x9, #1\n")
    s.add("    sdiv x0, x0, x9\n")
    s.add("    lsl x0, x0, #1\n")
    s.add("    orr x0, x0, #1\n")
    return s

aarch64_win64["INC"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d0, "x9"))
    s.add("    add x9, x9, #2\n")
    s.add(storeVal("x9", d0))
    return s

aarch64_win64["DEC"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d0, "x9"))
    s.add("    sub x9, x9, #2\n")
    s.add(storeVal("x9", d0))
    return s

# --- LOGIC & COMPARISON ---
aarch64_win64["LT"] = proc(d0: string, d1: string, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d0, "x9"))
    s.add(loadVal(d1, "x10"))
    s.add("    cmp x9, x10\n")
    s.add("    cset x0, lt\n")
    s.add("    lsl x0, x0, #1\n")
    s.add("    orr x0, x0, #1\n")
    s.add(storeVal("x0", d2))
    return s

aarch64_win64["GT"] = proc(d0: string, d1: string, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d0, "x9"))
    s.add(loadVal(d1, "x10"))
    s.add("    cmp x9, x10\n")
    s.add("    cset x0, gt\n")
    s.add("    lsl x0, x0, #1\n")
    s.add("    orr x0, x0, #1\n")
    s.add(storeVal("x0", d2))
    return s

aarch64_win64["EQ"] = proc(d0: string, d1: string, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d0, "x9"))
    s.add(loadVal(d1, "x10"))
    s.add("    cmp x9, x10\n")
    s.add("    cset x0, eq\n")
    s.add("    lsl x0, x0, #1\n")
    s.add("    orr x0, x0, #1\n")
    s.add(storeVal("x0", d2))
    return s

# --- Control Flow ---
aarch64_win64["JMP"] = proc(d0: string, d1: string, d2: string): string =
    return setSection(".text") & "    b " & d0.replace("[", "").replace("]", "") & "\n"

aarch64_win64["JNZ"] = proc(d0: string, d1: string, d2: string): string =
    var s = setSection(".text")
    s.add("    cmp x0, #3\n")
    s.add("    b.eq " & d0.replace("[", "").replace("]", "") & "\n")
    return s

aarch64_win64["JEZ"] = proc(d0: string, d1: string, d2: string): string =
    return setSection(".text") & "    cbz x0, " & d0.replace("[", "").replace("]", "") & "\n"

aarch64_win64["JF"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d0, "x0"))
    s.add("    cmp x0, #1\n")
    s.add("    b.eq " & d1.replace("[", "").replace("]", "") & "\n")
    return s

aarch64_win64["CMP"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d0, "x0"))
    s.add(loadVal(d1, "x1"))
    s.add("    bl runtime_eq\n")
    if d2 != "" and d2 != "00":
        s.add(storeVal("x0", d2))
    return s

# --- IO & META ---
aarch64_win64["WRITE"] = proc(d0: string, d1: string, d2: string): string =
    if d0.startsWith("[\"") and d0.endsWith("\"]"):
        let content = d0[2..^3].replace("\\n", "\\r\\n")
        let lbl = "str_" & $rodata_counter
        rodata_counter.inc()
        var s = setSection(".rodata")
        s.add("    .align 3\n" & lbl & "_header:\n    .quad 1\n" & lbl & ":\n    .asciz \"" & content & "\"\n")
        s.add(setSection(".text"))
        s.add("    adrp x0, " & lbl & "\n    add x0, x0, :lo12:" & lbl & "\n")
        s.add("    bl print_string\n")
        return s

    var s = setSection(".text")
    s.add(loadVal(d0, "x0"))
    s.add("    bl print_int\n")
    return s

aarch64_win64["EXIT"] = proc(d0: string, d1: string, d2: string): string =
    var s = setSection(".text")
    s.add("    bl F_main\n")
    s.add("    mov x0, #0\n")
    s.add("    bl sys_newton_exit\n")
    return s

aarch64_win64["STR"] = proc(d0, d1, d2: string): string =
    var s = setSection(".rodata")
    let label = d0.replace("[", "").replace("]", "").replace("$", "")
    var hexContent = d1.replace("[", "").replace("]", "")
    var byteStr = ""

    if hexContent.len > 0:
        for i in countup(0, hexContent.len - 2, 2):
            if i > 0: byteStr.add(", ")
            byteStr.add("0x" & hexContent[i .. i+1])
    else:
        byteStr = "0"

    s.add("    .align 3\n")
    s.add(label & "_header:\n")
    s.add("    .quad 1\n")
    s.add(label & ":\n")
    if byteStr != "0":
        s.add("    .byte " & byteStr & ", 0\n")
    else:
        s.add("    .byte 0\n")
    return s

aarch64_win64["WRITES"] = proc(d0: string, d1: string, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d0, "x0"))
    s.add("    bl print_string\n")
    return s

aarch64_win64["READ"] = proc(d0: string, d1: string, d2: string): string =
    var s = setSection(".text")
    s.add("    bl read_string\n")
    s.add(storeVal("x0", d0))
    return s

# --- MAP / ARRAY OPERATIONS ---
aarch64_win64["NEWMAP"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add("    mov x0, #16\n")
    s.add("    bl _malloc\n")
    s.add("    mov x9, #2\n    str x9, [x0]\n")
    s.add("    add x0, x0, #8\n")
    s.add("    mov x9, #0\n    str x9, [x0]\n")
    s.add(storeVal("x0", d0))
    return s

aarch64_win64["MSET"] = proc(d0: string, d1: string, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d0, "x0"))
    s.add(loadVal(d1, "x1"))
    s.add(loadVal(d2, "x2"))
    s.add("    bl collection_set\n")
    return s

aarch64_win64["MGET"] = proc(d0: string, d1: string, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d1, "x0"))
    s.add(loadVal(d2, "x1"))
    s.add("    bl collection_get\n")
    s.add(storeVal("x0", d0))
    return s

aarch64_win64["MLEN"] = proc(d0: string, d1: string, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d1, "x0"))
    s.add("    bl collection_len\n")
    s.add(storeVal("x0", d0))
    return s

aarch64_win64["MHEAD"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d1, "x0"))
    s.add("    bl map_head\n")
    s.add(storeVal("x0", d0))
    return s

aarch64_win64["MKEY"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d1, "x0"))
    s.add("    bl node_key\n")
    s.add(storeVal("x0", d0))
    return s

aarch64_win64["MVAL"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d1, "x0"))
    s.add("    bl node_val\n")
    s.add(storeVal("x0", d0))
    return s

aarch64_win64["MNEXT"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d1, "x0"))
    s.add("    bl node_next\n")
    s.add(storeVal("x0", d0))
    return s

aarch64_win64["DEL"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d0, "x0"))
    s.add(loadVal(d1, "x1"))
    s.add("    bl map_delete\n")
    return s

aarch64_win64["NEWARR"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d1, "x0"))
    s.add("    bl new_array\n")
    s.add(storeVal("x0", d0))
    return s

# --- FILE I/O OPERATIONS ---
aarch64_win64["FOPEN"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d1, "x0"))
    s.add(loadVal(d2, "x1"))
    s.add("    asr x1, x1, #1\n")
    s.add("    mov x2, #420\n")
    s.add("    bl file_open\n")
    s.add("    lsl x0, x0, #1\n")
    s.add("    orr x0, x0, #1\n")
    s.add(storeVal("x0", d0))
    return s

aarch64_win64["FWRITE"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d0, "x0"))
    s.add("    asr x0, x0, #1\n")
    s.add(loadVal(d1, "x1"))
    s.add("    bl file_write\n")
    return s

aarch64_win64["FREAD"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d1, "x0"))
    s.add("    asr x0, x0, #1\n")
    s.add(loadVal(d2, "x1"))
    s.add("    asr x1, x1, #1\n")
    s.add("    bl file_read\n")
    s.add(storeVal("x0", d0))
    return s

aarch64_win64["READF"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d1, "x0"))
    s.add("    bl read_file\n")
    s.add(storeVal("x0", d0))
    return s

aarch64_win64["FCLOSE"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d0, "x0"))
    s.add("    asr x0, x0, #1\n")
    s.add("    bl file_close\n")
    return s

# --- ARGV ---
aarch64_win64["ARGV"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    let lblSafe = getUniqueLabel("argv_safe")
    let lblDone = getUniqueLabel("argv_done")

    s.add(loadVal(d0, "x0"))
    s.add("    asr x0, x0, #1\n")
    s.add("    adrp x9, __argc\n    ldr x9, [x9, :lo12:__argc]\n")
    s.add("    cmp x0, x9\n")
    s.add("    b.lt " & lblSafe & "\n")
    s.add("    mov x9, #1\n")
    s.add(storeVal("x9", d1))
    s.add("    b " & lblDone & "\n")
    s.add(lblSafe & ":\n")
    s.add("    bl runtime_get_arg\n")
    s.add(storeVal("x0", d1))
    s.add(lblDone & ":\n")
    return s

aarch64_win64["CAT"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d1, "x0"))
    s.add(loadVal(d2, "x1"))
    s.add("    bl string_concat\n")
    s.add(storeVal("x0", d0))
    return s

aarch64_win64["TYPEOF"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d1, "x0"))
    s.add("    bl get_type_str\n")
    s.add(storeVal("x0", d0))
    return s

aarch64_win64["MALLOC"] = proc(d0: string, d1: string, d2: string): string = return "    # [MALLOC]\n"
aarch64_win64["FREE"] = proc(d0: string, d1: string, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d0, "x0"))
    s.add("    bl _free\n")
    return s

aarch64_win64["COPY"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d0, "x0"))
    s.add(storeVal("x0", d1))
    return s

aarch64_win64["ITS"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d1, "x0"))
    s.add("    bl runtime_to_string\n")
    s.add(storeVal("x0", d0))
    return s

aarch64_win64["MOVSD"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add("    adrp x12, " & d0 & "\n    ldr d0, [x12, :lo12:" & d0 & "]\n")
    return s

aarch64_win64["FSTORE"] = proc(d0, d1, d2: string): string =
    var s = setSection(".data")
    s.add(d0 & ": .double " & d1 & "\n")
    return s

# --- NETWORKING ---
aarch64_win64["NET_SOCKET"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add("    bl socket_create\n")
    s.add(storeVal("x0", d0))
    return s

aarch64_win64["NET_BIND"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d0, "x0"))
    s.add(loadVal(d1, "x1"))
    s.add("    bl socket_bind\n")
    return s

aarch64_win64["NET_LISTEN"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d0, "x0"))
    s.add("    bl socket_listen\n")
    return s

aarch64_win64["NET_ACCEPT"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d1, "x0"))
    s.add("    bl socket_accept\n")
    s.add(storeVal("x0", d0))
    return s

aarch64_win64["NET_WRITE"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d0, "x0"))
    s.add(loadVal(d1, "x1"))
    s.add("    bl socket_write\n")
    return s

aarch64_win64["NET_CLOSE"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d0, "x0"))
    s.add("    bl socket_close\n")
    return s

aarch64_win64["NET_RECV"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d1, "x0"))
    s.add(loadVal(d2, "x1"))
    s.add("    bl socket_read\n")
    s.add(storeVal("x0", d0))
    return s

aarch64_win64["NOP"] = proc(d0: string, d1: string, d2: string): string = return "    nop\n"
aarch64_win64["__required"] = proc(d0: string, d1: string, d2: string): string = return ""
aarch64_win64["__makeTemp"] = proc(d0: string, d1: string, d2: string): string = return ""
aarch64_win64["__finalize"] = proc(d0: string, d1: string, d2: string): string = return ""
aarch64_win64["__comment"] = proc(d0: string, d1: string, d2: string): string =
    DebugInformation.add("    " & d1 & ": " & d2)
    return "    # " & d0

aarch64_win64["MOV"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d1, "x9"))
    s.add(storeVal("x9", d0))
    return s

aarch64_win64["NSUB"] = proc(d0, d1, d2: string): string =
    var size = 0
    try: size = parseInt(d0.replace("$", ""))
    except: size = 16
    let aligned = (size + 15) and not 15
    return setSection(".text") & "    sub sp, sp, #" & $aligned & "\n"

aarch64_win64["NADD"] = proc(d0, d1, d2: string): string =
    var size = 0
    try: size = parseInt(d0.replace("$", ""))
    except: size = 16
    let aligned = (size + 15) and not 15
    return setSection(".text") & "    add sp, sp, #" & $aligned & "\n"

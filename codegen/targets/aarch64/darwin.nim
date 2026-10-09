import std/[strutils, tables]
import ../../../core/memory

var aarch64_darwin* = initTable[string, proc(d0: string, d1: string, d2: string): string]()
var rodata_counter = 0
var comp_counter = 0
var current_section = "none"
var labelCounter = 0

proc setSection(sec: string): string =
    if current_section == sec: return ""
    current_section = sec
    case sec
    of ".text": return "    .section __TEXT,__text\n"
    of ".data": return "    .section __DATA,__data\n"
    of ".rodata": return "    .section __TEXT,__cstring,cstring_literals\n"
    of ".bss": return "    .section __DATA,__bss\n"
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
    if arg == "" or arg == "0" or arg == "00":
        return "    mov " & reg & ", #0\n"

    let r = resolveReg(arg)
    if r != "":
        if r == reg: return ""
        return "    mov " & reg & ", " & r & "\n"

    var clean = arg.replace("!", "").replace("[", "").replace("]", "").replace("$", "")
    if clean == "0" or clean == "00":
        return "    mov " & reg & ", #0\n"

    if clean.contains("(%rbp)") or clean.contains("(%rsp)"):
        let offsetStr = clean.replace("(%rbp)", "").replace("(%rsp)", "")
        var offset = 0
        try: offset = parseInt(offsetStr)
        except: offset = 0
        return loadStackOffset(reg, offset)

    if arg.startsWith("str_") or arg.startsWith("$str_"):
        let lbl = if arg.startsWith("$str_"): arg[1..^1] else: arg
        return "    adrp " & reg & ", " & lbl & "@PAGE\n    add " & reg & ", " & reg & ", " & lbl & "@PAGEOFF\n"

    if clean.startsWith("@"):
        let lbl = "G" & clean[1..^1]
        return "    adrp x12, " & lbl & "@PAGE\n    add x12, x12, " & lbl & "@PAGEOFF\n    ldr " & reg & ", [x12]\n"
    elif clean.startsWith("%"):
        let lbl = "B" & clean[1..^1]
        return "    adrp x12, " & lbl & "@PAGE\n    add x12, x12, " & lbl & "@PAGEOFF\n    ldr " & reg & ", [x12]\n"
    elif clean.len > 1 and clean.startsWith("0") and not clean.startsWith("-") and clean != "00" and clean.allCharsInSet(Digits):
        let lbl = "L" & clean
        return "    adrp x12, " & lbl & "@PAGE\n    add x12, x12, " & lbl & "@PAGEOFF\n    ldr " & reg & ", [x12]\n"
    elif (clean.startsWith("L") or clean.startsWith("B")) and not clean.contains("\""):
        return "    adrp x12, " & clean & "@PAGE\n    add x12, x12, " & clean & "@PAGEOFF\n    ldr " & reg & ", [x12]\n"

    try:
        let val = parseInt(clean)
        if val >= 0 and val <= 65535:
            return "    mov " & reg & ", #" & $val & "\n"
        else:
            return "    ldr " & reg & ", =" & $val & "\n"
    except:
        return "    ldr " & reg & ", =" & clean & "\n"

proc storeVal(reg: string, dest: string): string =
    if dest == "" or dest == "0" or dest == "00":
        return ""

    let r = resolveReg(dest)
    if r != "":
        if r == reg: return ""
        return "    mov " & r & ", " & reg & "\n"

    var clean = dest.replace("!", "").replace("[", "").replace("]", "").replace("$", "")
    if clean == "0" or clean == "00":
        return ""

    if clean.contains("(%rbp)") or clean.contains("(%rsp)"):
        let offsetStr = clean.replace("(%rbp)", "").replace("(%rsp)", "")
        var offset = 0
        try: offset = parseInt(offsetStr)
        except: offset = 0
        return storeStackOffset(reg, offset)

    var sym = ""
    if clean.startsWith("@"): sym = "G" & clean[1..^1]
    elif clean.startsWith("%"): sym = "B" & clean[1..^1]
    elif clean.len > 1 and clean.startsWith("0") and clean != "00" and clean.allCharsInSet(Digits): sym = "L" & clean
    elif clean.startsWith("L") or clean.startsWith("B"): sym = clean
    else: sym = "L" & clean

    return "    adrp x12, " & sym & "@PAGE\n    add x12, x12, " & sym & "@PAGEOFF\n    str " & reg & ", [x12]\n"

proc getUniqueLabel(prefix: string): string =
    inc labelCounter
    return prefix & "_" & $labelCounter

# --- OPCODES ---
aarch64_darwin["STORE"] = proc(d0: string, d1: string, d2: string): string =
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

aarch64_darwin["UPD"] = proc(d0: string, d1: string, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d1, "x11"))
    s.add(storeVal("x11", d0))
    return s

aarch64_darwin["LBL"] = proc(d0: string, d1: string, d2: string): string =
    var s = setSection(".text")
    var lbl = d0.replace("[", "").replace("]", "")

    if lbl == "ENTRY" and not generateObjectFile:
        s.add("    .global _main\n")
        s.add("_main:\n")
        s.add("    stp x29, x30, [sp, -16]!\n")
        s.add("    mov x29, sp\n")
        s.add("    adrp x9, _argc@PAGE\n    str x0, [x9, _argc@PAGEOFF]\n")
        s.add("    adrp x9, _sys_argv@PAGE\n    str x1, [x9, _sys_argv@PAGEOFF]\n")
        s.add("    mov x2, sp\n")
        s.add("    adrp x9, _sys_stack_base@PAGE\n    str x2, [x9, _sys_stack_base@PAGEOFF]\n")
        s.add("    b ENTRY\n")
        s.add("ENTRY:\n")
        return s
    elif lbl == "ENTRY" and generateObjectFile:
        s.add("    .global _ENTRY\n")

    s.add(lbl & ":\n")
    if lbl.startsWith("F_"):
        s.add("    stp x29, x30, [sp, -16]!\n")
        s.add("    mov x29, sp\n")
    return s

aarch64_darwin["CALL"] = proc(d0: string, d1: string, d2: string): string =
    var s = setSection(".text")
    let funcLabel = d0.replace("[", "").replace("]", "")
    let sym = if not funcLabel.startsWith("_") and not funcLabel.startsWith("F_") and not funcLabel.startsWith("L") and not funcLabel.startsWith("*"): "_" & funcLabel else: funcLabel
    s.add("    bl " & sym & "\n")

    var argCount = 0
    try: argCount = parseInt(d1)
    except: discard

    if argCount > 0:
        let popBytes = (argCount * 8 + 15) and not 15
        s.add("    add sp, sp, #" & $popBytes & "\n")

    if d2 != "00" and d2 != "":
        s.add(storeVal("x0", d2))
    return s

aarch64_darwin["CALLD"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d1, "x9"))
    s.add("    blr x9\n")
    if d2 != "0" and d2 != "":
        let popBytes = (parseInt(d2) * 8 + 15) and not 15
        s.add("    add sp, sp, #" & $popBytes & "\n")
    s.add(storeVal("x0", d0))
    return s

aarch64_darwin["RET"] = proc(d0: string, d1: string, d2: string): string =
    var s = setSection(".text")
    if d0 != "" and d0 != "0" and d0 != "00":
        s.add(loadVal(d0, "x0"))
    s.add("    mov sp, x29\n")
    s.add("    ldp x29, x30, [sp], 16\n")
    s.add("    ret\n")
    return s

aarch64_darwin["PUSH"] = proc(d0: string, d1: string, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d0, "x9"))
    s.add("    str x9, [sp, -16]!\n")
    return s

aarch64_darwin["GETARG"] = proc(d0: string, d1: string, d2: string): string =
    var index = 0
    try: index = parseInt(d1)
    except: discard
    let offset = 16 + (index * 16)
    var s = setSection(".text")
    s.add("    ldr x0, [x29, #" & $offset & "]\n")
    s.add(storeVal("x0", d0))
    return s

aarch64_darwin["EXPO"] = proc(d0, d1, d2: string): string =
    return ".global _" & d0.replace("[","").replace("]","") & "\n"

aarch64_darwin["ETRN"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add("    # FFI SHIELD (AARCH64 DARWIN)\n")
    s.add("    stp x19, x20, [sp, -16]!\n")
    s.add("    bl _" & d0.replace("[","").replace("]","") & "\n")
    s.add("    ldp x19, x20, [sp], 16\n")
    s.add("    lsl x0, x0, #1\n")
    s.add("    orr x0, x0, #1\n")
    return s

# --- ARITHMETIC ---
aarch64_darwin["ADD"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d0, "x0"))
    s.add(loadVal(d1, "x9"))
    s.add("    add x0, x0, x9\n")
    s.add("    sub x0, x0, #1\n")
    return s

aarch64_darwin["SUB"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d0, "x0"))
    s.add(loadVal(d1, "x9"))
    s.add("    sub x0, x0, x9\n")
    s.add("    add x0, x0, #1\n")
    return s

aarch64_darwin["MUL"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d0, "x0"))
    s.add("    asr x0, x0, #1\n")
    s.add(loadVal(d1, "x9"))
    s.add("    asr x9, x9, #1\n")
    s.add("    mul x0, x0, x9\n")
    s.add("    lsl x0, x0, #1\n")
    s.add("    orr x0, x0, #1\n")
    return s

aarch64_darwin["DIV"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d0, "x0"))
    s.add("    asr x0, x0, #1\n")
    s.add(loadVal(d1, "x9"))
    s.add("    asr x9, x9, #1\n")
    s.add("    sdiv x0, x0, x9\n")
    s.add("    lsl x0, x0, #1\n")
    s.add("    orr x0, x0, #1\n")
    return s

aarch64_darwin["INC"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d0, "x9"))
    s.add("    add x9, x9, #2\n")
    s.add(storeVal("x9", d0))
    return s

aarch64_darwin["DEC"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d0, "x9"))
    s.add("    sub x9, x9, #2\n")
    s.add(storeVal("x9", d0))
    return s

# --- LOGIC & COMPARISON ---
aarch64_darwin["LT"] = proc(d0: string, d1: string, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d0, "x9"))
    s.add(loadVal(d1, "x10"))
    s.add("    cmp x9, x10\n")
    s.add("    cset x0, lt\n")
    s.add("    lsl x0, x0, #1\n")
    s.add("    orr x0, x0, #1\n")
    s.add(storeVal("x0", d2))
    return s

aarch64_darwin["GT"] = proc(d0: string, d1: string, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d0, "x9"))
    s.add(loadVal(d1, "x10"))
    s.add("    cmp x9, x10\n")
    s.add("    cset x0, gt\n")
    s.add("    lsl x0, x0, #1\n")
    s.add("    orr x0, x0, #1\n")
    s.add(storeVal("x0", d2))
    return s

aarch64_darwin["EQ"] = proc(d0: string, d1: string, d2: string): string =
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
aarch64_darwin["JMP"] = proc(d0: string, d1: string, d2: string): string =
    return setSection(".text") & "    b " & d0.replace("[", "").replace("]", "") & "\n"

aarch64_darwin["JNZ"] = proc(d0: string, d1: string, d2: string): string =
    var s = setSection(".text")
    s.add("    cmp x0, #3\n")
    s.add("    b.eq " & d0.replace("[", "").replace("]", "") & "\n")
    return s

aarch64_darwin["JEZ"] = proc(d0: string, d1: string, d2: string): string =
    return setSection(".text") & "    cbz x0, " & d0.replace("[", "").replace("]", "") & "\n"

aarch64_darwin["JF"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d0, "x0"))
    s.add("    cmp x0, #1\n")
    s.add("    b.eq " & d1.replace("[", "").replace("]", "") & "\n")
    return s

aarch64_darwin["CMP"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d0, "x0"))
    s.add(loadVal(d1, "x1"))
    s.add("    bl _runtime_eq\n")
    if d2 != "" and d2 != "00":
        s.add(storeVal("x0", d2))
    return s

# --- IO & META ---
aarch64_darwin["WRITE"] = proc(d0: string, d1: string, d2: string): string =
    if d0.startsWith("[\"") and d0.endsWith("\"]"):
        let content = d0[2..^3].replace("\\n", "\\n")
        let lbl = "str_" & $rodata_counter
        rodata_counter.inc()
        var s = setSection(".rodata")
        s.add(lbl & ":\n    .asciz \"" & content & "\"\n")
        s.add(setSection(".text"))
        s.add("    adrp x0, " & lbl & "@PAGE\n    add x0, x0, " & lbl & "@PAGEOFF\n")
        s.add("    bl _print_string\n")
        return s

    var s = setSection(".text")
    s.add(loadVal(d0, "x0"))
    s.add("    bl _print_int\n")
    return s

aarch64_darwin["EXIT"] = proc(d0: string, d1: string, d2: string): string =
    var s = setSection(".text")
    s.add("    bl F_main\n")
    if not generateObjectFile:
        s.add("    mov x0, #0\n")
        s.add("    bl _exit_program\n")
    else:
        s.add("    mov x0, #0\n")
        s.add("    ret\n")
    return s

aarch64_darwin["STR"] = proc(d0, d1, d2: string): string =
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

aarch64_darwin["WRITES"] = proc(d0: string, d1: string, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d0, "x0"))
    s.add("    bl _print_string\n")
    return s

aarch64_darwin["READ"] = proc(d0: string, d1: string, d2: string): string =
    var s = setSection(".text")
    s.add("    bl _read_string\n")
    s.add(storeVal("x0", d0))
    return s

# --- MAP / ARRAY OPERATIONS ---
aarch64_darwin["NEWMAP"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add("    mov x0, #16\n")
    s.add("    bl __malloc\n")
    s.add("    mov x9, #2\n    str x9, [x0]\n")
    s.add("    add x0, x0, #8\n")
    s.add("    mov x9, #0\n    str x9, [x0]\n")
    s.add(storeVal("x0", d0))
    return s

aarch64_darwin["MSET"] = proc(d0: string, d1: string, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d0, "x0"))
    s.add(loadVal(d1, "x1"))
    s.add(loadVal(d2, "x2"))
    s.add("    bl _collection_set\n")
    return s

aarch64_darwin["MGET"] = proc(d0: string, d1: string, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d1, "x0"))
    s.add(loadVal(d2, "x1"))
    s.add("    bl _collection_get\n")
    s.add(storeVal("x0", d0))
    return s

aarch64_darwin["MLEN"] = proc(d0: string, d1: string, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d1, "x0"))
    s.add("    bl _collection_len\n")
    s.add(storeVal("x0", d0))
    return s

aarch64_darwin["MHEAD"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d1, "x0"))
    s.add("    bl _map_head\n")
    s.add(storeVal("x0", d0))
    return s

aarch64_darwin["MKEY"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d1, "x0"))
    s.add("    bl _node_key\n")
    s.add(storeVal("x0", d0))
    return s

aarch64_darwin["MVAL"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d1, "x0"))
    s.add("    bl _node_val\n")
    s.add(storeVal("x0", d0))
    return s

aarch64_darwin["MNEXT"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d1, "x0"))
    s.add("    bl _node_next\n")
    s.add(storeVal("x0", d0))
    return s

aarch64_darwin["DEL"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d0, "x0"))
    s.add(loadVal(d1, "x1"))
    s.add("    bl _map_delete\n")
    return s

aarch64_darwin["NEWARR"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d1, "x0"))
    s.add("    bl _new_array\n")
    s.add(storeVal("x0", d0))
    return s

# --- FILE I/O OPERATIONS ---
aarch64_darwin["FOPEN"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d1, "x0"))
    s.add(loadVal(d2, "x1"))
    s.add("    asr x1, x1, #1\n")
    s.add("    mov x2, #420\n")
    s.add("    bl _file_open\n")
    s.add("    lsl x0, x0, #1\n")
    s.add("    orr x0, x0, #1\n")
    s.add(storeVal("x0", d0))
    return s

aarch64_darwin["FWRITE"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d0, "x0"))
    s.add("    asr x0, x0, #1\n")
    s.add(loadVal(d1, "x1"))
    s.add("    bl _file_write\n")
    return s

aarch64_darwin["FREAD"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d1, "x0"))
    s.add("    asr x0, x0, #1\n")
    s.add(loadVal(d2, "x1"))
    s.add("    asr x1, x1, #1\n")
    s.add("    bl _file_read\n")
    s.add(storeVal("x0", d0))
    return s

aarch64_darwin["READF"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d1, "x0"))
    s.add("    bl _read_file\n")
    s.add(storeVal("x0", d0))
    return s

aarch64_darwin["FCLOSE"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d0, "x0"))
    s.add("    asr x0, x0, #1\n")
    s.add("    bl _file_close\n")
    return s

# --- ARGV ---
aarch64_darwin["ARGV"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    let lblSafe = getUniqueLabel("argv_safe")
    let lblDone = getUniqueLabel("argv_done")

    s.add(loadVal(d0, "x0"))
    s.add("    asr x0, x0, #1\n")
    s.add("    adrp x9, _argc@PAGE\n    ldr x9, [x9, _argc@PAGEOFF]\n")
    s.add("    cmp x0, x9\n")
    s.add("    b.lt " & lblSafe & "\n")
    s.add("    mov x9, #1\n")
    s.add(storeVal("x9", d1))
    s.add("    b " & lblDone & "\n")
    s.add(lblSafe & ":\n")
    s.add("    bl _runtime_get_arg\n")
    s.add(storeVal("x0", d1))
    s.add(lblDone & ":\n")
    return s

aarch64_darwin["CAT"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d1, "x0"))
    s.add(loadVal(d2, "x1"))
    s.add("    bl _string_concat\n")
    s.add(storeVal("x0", d0))
    return s

aarch64_darwin["TYPEOF"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d1, "x0"))
    s.add("    bl _get_type_str\n")
    s.add(storeVal("x0", d0))
    return s

aarch64_darwin["MALLOC"] = proc(d0: string, d1: string, d2: string): string = return "    # [MALLOC]\n"
aarch64_darwin["FREE"] = proc(d0: string, d1: string, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d0, "x0"))
    s.add("    bl __free\n")
    return s

aarch64_darwin["COPY"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d0, "x0"))
    s.add(storeVal("x0", d1))
    return s

aarch64_darwin["ITS"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d1, "x0"))
    s.add("    bl _runtime_to_string\n")
    s.add(storeVal("x0", d0))
    return s

aarch64_darwin["MOVSD"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add("    adrp x12, " & d0 & "@PAGE\n    ldr d0, [x12, " & d0 & "@PAGEOFF]\n")
    return s

aarch64_darwin["FSTORE"] = proc(d0, d1, d2: string): string =
    var s = setSection(".data")
    s.add(d0 & ": .double " & d1 & "\n")
    return s

# --- NETWORKING ---
aarch64_darwin["NET_SOCKET"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add("    bl _socket_create\n")
    s.add(storeVal("x0", d0))
    return s

aarch64_darwin["NET_BIND"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d0, "x0"))
    s.add(loadVal(d1, "x1"))
    s.add("    bl _socket_bind\n")
    return s

aarch64_darwin["NET_LISTEN"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d0, "x0"))
    s.add("    bl _socket_listen\n")
    return s

aarch64_darwin["NET_ACCEPT"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d1, "x0"))
    s.add("    bl _socket_accept\n")
    s.add(storeVal("x0", d0))
    return s

aarch64_darwin["NET_WRITE"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d0, "x0"))
    s.add(loadVal(d1, "x1"))
    s.add("    bl _socket_write\n")
    return s

aarch64_darwin["NET_CLOSE"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d0, "x0"))
    s.add("    bl _socket_close\n")
    return s

aarch64_darwin["NET_RECV"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d1, "x0"))
    s.add(loadVal(d2, "x1"))
    s.add("    bl _socket_read\n")
    s.add(storeVal("x0", d0))
    return s

aarch64_darwin["NOP"] = proc(d0: string, d1: string, d2: string): string = return "    nop\n"
aarch64_darwin["__required"] = proc(d0: string, d1: string, d2: string): string = return ""
aarch64_darwin["__makeTemp"] = proc(d0: string, d1: string, d2: string): string = return ""
aarch64_darwin["__finalize"] = proc(d0: string, d1: string, d2: string): string = return ""
aarch64_darwin["__comment"] = proc(d0: string, d1: string, d2: string): string =
    DebugInformation.add("    " & d1 & ": " & d2)
    return "    # " & d0

aarch64_darwin["MOV"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(loadVal(d1, "x9"))
    s.add(storeVal("x9", d0))
    return s

aarch64_darwin["NSUB"] = proc(d0, d1, d2: string): string =
    var size = 0
    try: size = parseInt(d0.replace("$", ""))
    except: size = 16
    let aligned = (size + 15) and not 15
    return setSection(".text") & "    sub sp, sp, #" & $aligned & "\n"

aarch64_darwin["NADD"] = proc(d0, d1, d2: string): string =
    var size = 0
    try: size = parseInt(d0.replace("$", ""))
    except: size = 16
    let aligned = (size + 15) and not 15
    return setSection(".text") & "    add sp, sp, #" & $aligned & "\n"

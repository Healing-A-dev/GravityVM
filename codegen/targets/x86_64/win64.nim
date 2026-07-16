import std/[strutils, tables]

var x86_64_win64* = initTable[string, proc(d0: string, d1: string, d2: string): string]()
var rodata_counter = 0
var comp_counter = 0
var current_section = "none"
var labelCounter = 0


proc setSection(sec: string): string =
    if current_section == sec: return ""
    current_section = sec
    return "    .section " & sec & "\n"


proc fromHexStr(s: string): string =
  result = ""
  for i in countup(0, s.len - 2, 2):
    result.add(chr(parseHexInt(s[i .. i+1])))


proc resolve(arg: string): string =
    if arg.startsWith("str_"): return "$" & arg
    if arg.startsWith("$str_"): return arg
    if arg.contains("sra"): return "%rax"
    var cleanArg = arg.replace("!", "").replace("[", "").replace("]", "")

    if cleanArg.contains("(%rbp)"): return cleanArg.replace("$", "")

    if cleanArg == "%rdi": return "%rdi"
    if cleanArg == "%rsi": return "%rsi"
    if cleanArg == "%rdx": return "%rdx"
    if cleanArg == "%rcx": return "%rcx"
    if cleanArg in ["%rax", "%rbx", "%rcx", "%rdx", "%rdi", "%rsi", "%rsp", "%rbp", "%r8", "%r9"]: return cleanArg

    if cleanArg.startsWith("$"):
        let inner = cleanArg.substr(1)
        if inner.contains("F_"): return "$" & inner
        if inner.len > 1 and inner.startsWith("0") and inner.allCharsInSet(Digits):
            return "L" & inner & "(%rip)"
        if inner.allCharsInSet(Digits): return "$" & inner
        return "L" & inner & "(%rip)"
    if cleanArg.startsWith("%"): return cleanArg.substr(1) & "(%rip)"
    if cleanArg.startsWith("@"): return "G" & cleanArg[1..^1] & "(%rip)"
    if (cleanArg.startsWith("L") or cleanArg.startsWith("B")) and not cleanArg.contains("\""): return cleanArg & "(%rip)"
    return "$" & cleanArg


proc getUniqueLabel(prefix: string): string =
  inc labelCounter
  return prefix & "_" & $labelCounter


proc load(arg: string, reg: string): string =
    let res = resolve(arg)
    if res.startsWith("$str_"):
        return "    lea " & res[1..^1] & "(%rip), " & reg & "\n"
    return "    mov " & res & ", " & reg & "\n"


proc genComp(d0, d1, d2, cond, tr, fl: string): string =
    comp_counter.inc()
    let lblTrue = "L_true_" & $comp_counter
    let lblDone = "L_done_" & $comp_counter
    return setSection(".text") & load(d0, "%rax") & load(d1, "%r11") & "    cmp %r11, %rax\n    " & cond & " " & lblTrue & "\n    mov $1, %rax\n    jmp " & lblDone & "\n" & lblTrue & ":\n    mov $3, %rax\n" & lblDone & ":\n    mov %rax, " & resolve(d2) & "\n"


# --- OPCODES ---
x86_64_win64["STORE"] = proc(d0: string, d1: string, d2: string): string =
    var to_append = ""
    var dest = d0
    var src = d1
    if src == "": src = "0"
    if src.startsWith("[") and src.endsWith("]"): src = src[1..^2]

    if src == "0":
        if dest.contains("(%rbp)") or dest.startsWith("!"):
            let cleanDest = resolve(dest.replace("!", ""))
            return setSection(".text") & "    movq $0, " & cleanDest & "\n"

        if dest.startsWith("!") or dest.contains("(%rbp)"):
            let cleanDest = resolve(dest.replace("!", ""))
            to_append.add(setSection(".text"))
            to_append.add(load(src, "%r11"))
            to_append.add("    mov %r11, " & cleanDest & "\n")
            return to_append

    var safeValue = src
    if safeValue.contains("%") or safeValue.contains("$") or safeValue.contains("@"): safeValue = "0"
    to_append.add(setSection(".data"))
    if dest.startsWith("@"): to_append.add("G" & dest[1..^1] & ": .quad " & safeValue & "\n")
    elif dest.startsWith("$"): to_append.add("L" & dest[1..^1] & ": .quad " & safeValue & "\n")
    elif dest.startsWith("%"): to_append.add("B" & dest[1..^1] & ": .quad " & safeValue & "\n")
    return to_append

x86_64_win64["UPD"] = proc(d0: string, d1: string, d2: string): string =
    return setSection(".text") & load(d1, "%r11") & "    mov %r11, " & resolve(d0) & "\n"

x86_64_win64["LBL"] = proc(d0: string, d1: string, d2: string): string =
    var s = setSection(".text")
    var lbl = d0.replace("[", "").replace("]", "")
    if lbl == "ENTRY":
        s.add("    .global _pei386_runtime_relocator\n")
        s.add("_pei386_runtime_relocator:\n")
        s.add("    ret\n\n")

        # Entrypoint
        s.add("    .global mainCRTStartup\nmainCRTStartup:\n")
        s.add("    push %rbp\n    mov %rsp, %rbp\n")

        s.add("    sub $32, %rsp\n    and $-16, %rsp\n")


        s.add("    mov $0, %rcx\n")
        s.add("    mov $0, %rdx\n")
        s.add("    mov %rbp, %r8\n")
        s.add("    call newton_init_runtime\n\n")
        return s

    s.add(lbl & ":\n")
    if lbl.startsWith("F_"): s.add("    push %rbp\n    mov %rsp, %rbp\n")
    return s

x86_64_win64["CALL"] = proc(d0: string, d1: string, d2: string): string =
    var s = setSection(".text") & "    call " & d0.replace("[", "").replace("]", "") & "\n"
    var argCount = 0
    try: argCount = parseInt(d1)
    except: discard
    if argCount > 0: s.add("    add $" & $(argCount * 8) & ", %rsp\n")
    if d2 != "00": s.add("    mov %rax, " & resolve(d2) & "\n")
    return s

x86_64_win64["CALLD"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text") & load(d1, "%rax") & "    call *%rax\n"
    if d2 != "0": s.add("    add $" & $(parseInt(d2) * 8) & ", %rsp\n")
    s.add("    mov %rax, " & resolve(d0) & "\n")
    return s

x86_64_win64["RET"] = proc(d0: string, d1: string, d2: string): string =
    var s = setSection(".text")
    if d0 != "" and d0 != "0" and d0 != "00": s.add(load(d0, "%rax"))
    return s & "    leave\n    ret\n"

x86_64_win64["PUSH"] = proc(d0: string, d1: string, d2: string): string = return setSection(".text") & load(d0, "%r11") & "    push %r11\n"

x86_64_win64["GETARG"] = proc(d0: string, d1: string, d2: string): string =
    var index = 0
    try: index = parseInt(d1)
    except: discard
    return setSection(".text") & "    mov " & $(16 + (index * 8)) & "(%rbp), %rax\n    mov %rax, " & resolve(d0) & "\n"

x86_64_win64["ADD"] = proc(d0, d1, d2: string): string = return setSection(".text") & load(d0, "%rax") & load(d1, "%r11") & "    add %r11, %rax\n    dec %rax\n"
x86_64_win64["SUB"] = proc(d0, d1, d2: string): string = return setSection(".text") & load(d0, "%rax") & load(d1, "%r11") & "    sub %r11, %rax\n    inc %rax\n"
x86_64_win64["MUL"] = proc(d0, d1, d2: string): string = return setSection(".text") & load(d0, "%rax") & "    sar $1, %rax\n" & load(d1, "%rbx") & "    sar $1, %rbx\n    imul %rbx, %rax\n    shl $1, %rax\n    or $1, %rax\n"
x86_64_win64["DIV"] = proc(d0, d1, d2: string): string = return setSection(".text") & load(d0, "%rax") & "    sar $1, %rax\n" & load(d1, "%rbx") & "    sar $1, %rbx\n    cqo\n    idiv %rbx\n    shl $1, %rax\n    or $1, %rax\n"
x86_64_win64["INC"] = proc(d0, d1, d2: string): string = return setSection(".text") & "    addq $2, " & resolve(d0) & "\n"
x86_64_win64["DEC"] = proc(d0, d1, d2: string): string = return setSection(".text") & "    subq $2, " & resolve(d0) & "\n"

x86_64_win64["LT"] = proc(d0: string, d1: string, d2: string): string = return genComp(d0, d1, d2, "jl", "3", "1")
x86_64_win64["GT"] = proc(d0: string, d1: string, d2: string): string = return genComp(d0, d1, d2, "jg", "3", "1")
x86_64_win64["EQ"] = proc(d0: string, d1: string, d2: string): string = return genComp(d0, d1, d2, "je", "3", "1")

x86_64_win64["JMP"] = proc(d0: string, d1: string, d2: string): string = return setSection(".text") & "    jmp " & d0.replace("[", "").replace("]", "") & "\n"
x86_64_win64["JNZ"] = proc(d0: string, d1: string, d2: string): string = return setSection(".text") & "    cmp $3, %rax\n    je " & d0 & "\n"
x86_64_win64["JEZ"] = proc(d0: string, d1: string, d2: string): string = return setSection(".text") & "    test %rax, %rax\n    jz " & d0.replace("[", "").replace("]", "") & "\n"
x86_64_win64["JF"] = proc(d0, d1, d2: string): string = return setSection(".text") & load(d0, "%rax") & "    cmp $1, %rax\n    je " & d1 & "\n"

x86_64_win64["CMP"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text") & load(d0, "%rdi") & load(d1, "%rsi") & "    call runtime_eq\n"
    if d2 != "" and d2 != "00": s.add("    mov %rax, " & resolve(d2) & "\n")
    return s

x86_64_win64["WRITE"] = proc(d0: string, d1: string, d2: string): string =
    if d0.startsWith("[\"") and d0.endsWith("\"]"):
        let lbl = "str_" & $rodata_counter
        rodata_counter.inc()
        # [WINDOWS FIX] Convert \n to \r\n for Windows WriteFile!
        return setSection(".rodata") & "    .align 8\n" & lbl & "_header:\n    .quad 1\n" & lbl & ":\n    .ascii \"" & d0[2..^3].replace("\\n", "\\r\\n") & "\"\n    .byte 0\n" & setSection(".text") & "    lea " & lbl & "(%rip), %rdi\n    call print_string\n"
    return setSection(".text") & load(d0, "%rdi") & "    call print_int\n"

x86_64_win64["EXIT"] = proc(d0: string, d1: string, d2: string): string = return setSection(".text") & "    call F_main\n    mov $0, %rdi\n    call sys_newton_exit\n"

x86_64_win64["STR"] = proc(d0, d1, d2: string): string =
    var byteStr = ""
    var hexContent = d1.replace("[", "").replace("]", "")
    if hexContent.len > 0:
        for i in countup(0, hexContent.len - 2, 2):
            if i > 0: byteStr.add(", ")
            byteStr.add("0x" & hexContent[i .. i+1])
    else: byteStr = "0"
    return setSection(".rodata") & "    .align 8\n" & resolve(d0).replace("$", "") & "_header:\n    .quad 1\n" & resolve(d0).replace("$", "") & ":\n" & (if byteStr != "0": "    .byte " & byteStr & ", 0\n" else: "    .byte 0\n")

x86_64_win64["WRITES"] = proc(d0: string, d1: string, d2: string): string = return setSection(".text") & load(d0, "%rdi") & "    call print_string\n"
x86_64_win64["READ"] = proc(d0: string, d1: string, d2: string): string = return setSection(".text") & "    call read_string\n    mov %rax, " & resolve(d0) & "\n"
x86_64_win64["NEWMAP"] = proc(d0, d1, d2: string): string = return setSection(".text") & "    mov $16, %rdi\n    call _malloc\n    movq $2, (%rax)\n    add $8, %rax\n    movq $0, (%rax)\n    mov %rax, " & resolve(d0) & "\n"
x86_64_win64["MSET"] = proc(d0: string, d1: string, d2: string): string = return setSection(".text") & load(d0, "%rdi") & load(d1, "%rsi") & load(d2, "%rdx") & "    call collection_set\n"
x86_64_win64["MGET"] = proc(d0: string, d1: string, d2: string): string = return setSection(".text") & load(d1, "%rdi") & load(d2, "%rsi") & "    call collection_get\n    mov %rax, " & resolve(d0) & "\n"
x86_64_win64["MLEN"] = proc(d0: string, d1: string, d2: string): string = return setSection(".text") & load(d1, "%rdi") & "    call collection_len\n    mov %rax, " & resolve(d0) & "\n"
x86_64_win64["MHEAD"] = proc(d0, d1, d2: string): string = return setSection(".text") & load(d1, "%rdi") & "    call map_head\n    mov %rax, " & resolve(d0) & "\n"
x86_64_win64["MKEY"] = proc(d0, d1, d2: string): string = return setSection(".text") & load(d1, "%rdi") & "    call node_key\n    mov %rax, " & resolve(d0) & "\n"
x86_64_win64["MVAL"] = proc(d0, d1, d2: string): string = return setSection(".text") & load(d1, "%rdi") & "    call node_val\n    mov %rax, " & resolve(d0) & "\n"
x86_64_win64["MNEXT"] = proc(d0, d1, d2: string): string = return setSection(".text") & load(d1, "%rdi") & "    call node_next\n    mov %rax, " & resolve(d0) & "\n"
x86_64_win64["DEL"] = proc(d0, d1, d2: string): string = return setSection(".text") & load(d0, "%rdi") & load(d1, "%rsi") & "    call collection_delete\n"
x86_64_win64["NEWARR"] = proc(d0, d1, d2: string): string = return setSection(".text") & load(d1, "%rdi") & "    call new_array\n    mov %rax, " & resolve(d0) & "\n"

x86_64_win64["FOPEN"] = proc(d0, d1, d2: string): string = return setSection(".text") & load(d1, "%rdi") & load(d2, "%rsi") & "    call file_open\n    mov %rax, " & resolve(d0) & "\n"
x86_64_win64["FWRITE"] = proc(d0, d1, d2: string): string = return setSection(".text") & load(d0, "%rdi") & load(d1, "%rsi") & "    call file_write\n"
x86_64_win64["FREAD"] = proc(d0, d1, d2: string): string = return setSection(".text") & load(d1, "%rdi") & load(d2, "%rsi") & "    call file_read\n    mov %rax, " & resolve(d0) & "\n"
x86_64_win64["READF"] = proc(d0, d1, d2: string): string = return setSection(".text") & load(d1, "%rdi") & "    call read_file\n    mov %rax, " & resolve(d0) & "\n"
x86_64_win64["FCLOSE"] = proc(d0, d1, d2: string): string = return setSection(".text") & load(d0, "%rdi") & "    call file_close\n"

x86_64_win64["ARGV"] = proc(d0, d1, d2: string): string =
    let lblSafe = "argv_safe_" & $labelCounter
    let lblDone = "argv_done_" & $labelCounter
    labelCounter.inc()
    return setSection(".text") & load(d0, "%rax") & "    sar $1, %rax\n    cmp newton_argc(%rip), %rax\n    jl " & lblSafe & "\n    movq $1, " & resolve(d1) & "\n    jmp " & lblDone & "\n" & lblSafe & ":\n    mov %rax, %rdi\n    call runtime_get_arg\n    mov %rax, " & resolve(d1) & "\n" & lblDone & ":\n"

x86_64_win64["CAT"] = proc(d0, d1, d2: string): string = return setSection(".text") & load(d1, "%rdi") & load(d2, "%rsi") & "    call string_concat\n    mov %rax, " & resolve(d0) & "\n"
x86_64_win64["TYPEOF"] = proc(d0, d1, d2: string): string = return setSection(".text") & load(d1, "%rdi") & "    call get_type_str\n    mov %rax, " & resolve(d0) & "\n"
x86_64_win64["MALLOC"] = proc(d0: string, d1: string, d2: string): string = return "    # [MALLOC]\n"
x86_64_win64["FREE"] = proc(d0: string, d1: string, d2: string): string = return setSection(".text") & load(d0, "%rdi") & "    call _free\n"
x86_64_win64["COPY"] = proc(d0, d1, d2: string): string = return setSection(".text") & load(d0, "%rax") & "    mov %rax, " & resolve(d1) & "\n"
x86_64_win64["ITS"] = proc(d0, d1, d2: string): string = return setSection(".text") & load(d1, "%rdi") & "    call runtime_to_string\n    mov %rax, " & resolve(d0) & "\n"
x86_64_win64["MOVSD"] = proc(d0, d1, d2: string): string = return setSection(".text") & "    movsd " & d0 & "(%rip), %" & d1 & "\n"
x86_64_win64["FSTORE"] = proc(d0, d1, d2: string): string = return setSection(".data") & d0 & ": .double " & d1 & "\n"
x86_64_win64["NOP"] = proc(d0: string, d1: string, d2: string): string = return "    nop\n"
x86_64_win64["__required"] = proc(d0: string, d1: string, d2: string): string = return ""
x86_64_win64["__makeTemp"] = proc(d0: string, d1: string, d2: string): string = return ""
x86_64_win64["__comment"] = proc(d0: string, d1: string, d2: string): string = return "    # " & d0
x86_64_win64["MOV"] = proc(d0, d1, d2: string): string = return load(d1, resolve(d0))
x86_64_win64["NSUB"] = proc(d0, d1, d2: string): string =
    var stackSize = 0
    try: stackSize = parseInt(resolve(d0).replace("$", ""))
    except: return "    sub " & resolve(d0) & ", %rsp\n"
    return "    sub $" & $((stackSize + 32 + 15) and not 15) & ", %rsp\n"
x86_64_win64["NADD"] = proc(d0, d1, d2: string): string =
    var stackSize = 0
    try: stackSize = parseInt(resolve(d0).replace("$", ""))
    except: return "    add " & resolve(d0) & ", %rsp\n"
    return "    add $" & $((stackSize + 32 + 15) and not 15) & ", %rsp\n"

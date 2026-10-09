import std/[strutils, tables]
import ../../../core/memory

var x86_64_darwin* = initTable[string, proc(d0: string, d1: string, d2: string): string]()
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

proc resolve(arg: string): string =
    if arg == "" or arg == "0" or arg == "00": return "$0"
    if arg.startsWith("str_"): return "$" & arg
    if arg.startsWith("$str_"): return arg
    if arg.contains("sra"): return "%rax"

    var cleanArg = arg.replace("!", "").replace("[", "").replace("]", "")
    if cleanArg == "" or cleanArg == "0" or cleanArg == "00": return "$0"
    if cleanArg.contains("(%rbp)"): return cleanArg.replace("$", "")
    if cleanArg in ["%rax", "%rbx", "%rcx", "%rdx", "%rdi", "%rsi", "%rsp", "%rbp", "%r8", "%r9"]: return cleanArg

    if cleanArg.startsWith("$"):
        let inner = cleanArg.substr(1)
        if inner.contains("F_"): return "$" & inner
        try:
            discard parseInt(inner)
            if inner.len > 1 and inner.startsWith("0") and not inner.startsWith("-") and inner != "00":
                return "L" & inner & "(%rip)"
            return "$" & inner
        except ValueError:
            return "L" & inner & "(%rip)"

    if cleanArg.startsWith("%"): return "B" & cleanArg.substr(1) & "(%rip)"
    if cleanArg.startsWith("@"): return "G" & cleanArg[1..^1] & "(%rip)"
    if (cleanArg.startsWith("L") or cleanArg.startsWith("B")) and not cleanArg.contains("\"") and cleanArg != "L00": return cleanArg & "(%rip)"
    return "$" & cleanArg

proc getUniqueLabel(prefix: string): string =
  inc labelCounter
  return prefix & "_" & $labelCounter

proc mov(src: string, dst: string): string =
    if dst.startsWith("%"):
        if src.startsWith("$str_"):
            return "    lea " & src[1..^1] & "(%rip), " & dst & "\n"
        elif src.startsWith("str_"):
            return "    lea " & src & "(%rip), " & dst & "\n"
        elif src.startsWith("$F_"):
            return "    lea " & src[1..^1] & "(%rip), " & dst & "\n"
    return "    mov " & src & ", " & dst & "\n"

proc cmp(src: string, dst: string): string =
    if src.startsWith("$str_"):
        return "    lea " & src[1..^1] & "(%rip), %r11\n    cmp %r11, " & dst & "\n"
    elif src.startsWith("str_"):
        return "    lea " & src & "(%rip), %r11\n    cmp %r11, " & dst & "\n"
    elif src.startsWith("$F_"):
        return "    lea " & src[1..^1] & "(%rip), %r11\n    cmp %r11, " & dst & "\n"
    return "    cmp " & src & ", " & dst & "\n"

# --- OPCODES ---
x86_64_darwin["STORE"] = proc(d0: string, d1: string, d2: string): string =
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
        to_append.add(mov(resolve(src), "%r11"))
        to_append.add("    mov %r11, " & cleanDest & "\n")
        return to_append

    var safeValue = src
    if safeValue.contains("%") or safeValue.contains("$") or safeValue.contains("@"): safeValue = "0"

    to_append.add(setSection(".data"))
    if dest.startsWith("@"): to_append.add("G" & dest[1..^1] & ": .quad " & safeValue & "\n")
    elif dest.startsWith("$"): to_append.add("L" & dest[1..^1] & ": .quad " & safeValue & "\n")
    elif dest.startsWith("%"): to_append.add("B" & dest[1..^1] & ": .quad " & safeValue & "\n")
    return to_append

x86_64_darwin["UPD"] = proc(d0: string, d1: string, d2: string): string =
    var to_append = setSection(".text")
    to_append.add(mov(resolve(d1), "%r11"))
    to_append.add("    mov %r11, " & resolve(d0) & "\n")
    return to_append

x86_64_darwin["LBL"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    var lbl = d0.replace("[", "").replace("]", "")

    to_append.add(setSection(".text"))

    if lbl == "ENTRY" and not generateObjectFile:
        to_append.add("    .global _main\n")
        to_append.add("_main:\n")
        to_append.add("    push %rbp\n")
        to_append.add("    mov %rsp, %rbp\n")
        to_append.add("    mov %rdi, _argc(%rip)\n")
        to_append.add("    mov %rsi, _sys_argv(%rip)\n")
        to_append.add("    mov %rsp, _sys_stack_base(%rip)\n")
        return to_append
    elif lbl == "ENTRY" and generateObjectFile:
        to_append.add("    .global _ENTRY\n")
        to_append.add("_ENTRY:\n")
        return to_append

    to_append.add(lbl & ":\n")

    if lbl.startsWith("F_"):
        to_append.add("    push %rbp\n")
        to_append.add("    mov %rsp, %rbp\n")
    return to_append

x86_64_darwin["CALL"] = proc(d0: string, d1: string, d2: string): string =
    var s = setSection(".text")
    let funcLabel = d0.replace("[", "").replace("]", "")
    let sym = if not funcLabel.startsWith("_") and not funcLabel.startsWith("F_") and not funcLabel.startsWith("L") and not funcLabel.startsWith("*"): "_" & funcLabel else: funcLabel

    s.add("    call " & sym & "\n")

    var argCount = 0
    try: argCount = parseInt(d1)
    except: discard

    if argCount > 0:
        s.add("    add $" & $(argCount * 8) & ", %rsp\n")

    if d2 != "00":
        s.add("    mov %rax, " & resolve(d2) & "\n")
    return s

x86_64_darwin["CALLD"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(mov(resolve(d1), "%rax"))
    s.add("    call *%rax\n")

    if d2 != "0":
        let popSize = parseInt(d2) * 8
        s.add("    add $" & $popSize & ", %rsp\n")

    s.add("    mov %rax, " & resolve(d0) & "\n")
    return s

x86_64_darwin["RET"] = proc(d0: string, d1: string, d2: string): string =
    var to_append = setSection(".text")
    if d0 != "" and d0 != "0" and d0 != "00":
        to_append.add(mov(resolve(d0), "%rax"))
    to_append.add("    leave\n    ret\n")
    return to_append

x86_64_darwin["PUSH"] = proc(d0: string, d1: string, d2: string): string =
    let r = resolve(d0)
    if r.startsWith("$str_") or r.startsWith("str_") or r.startsWith("$F_"):
        return setSection(".text") & mov(r, "%r11") & "    push %r11\n"
    return setSection(".text") & "    push " & r & "\n"

x86_64_darwin["GETARG"] = proc(d0: string, d1: string, d2: string): string =
    var index = 0
    try: index = parseInt(d1)
    except: discard
    let offset = 16 + (index * 8)
    let src = $offset & "(%rbp)"
    return setSection(".text") & "    mov " & src & ", %rax\n    mov %rax, " & resolve(d0) & "\n"

x86_64_darwin["EXPO"] = proc(d0, d1, d2: string): string =
    let lbl: string = d0.replace("[","").replace("]","")
    return ".global " & lbl & "\n"

x86_64_darwin["ETRN"] = proc(d0, d1, d2: string): string =
    var to_append: string = ""
    to_append.add("    # FFI SHIELD (DARWIN)\n")
    to_append.add("    push %r10\n")
    to_append.add("    push %r11\n")
    to_append.add("    mov %rsp, %r15\n")
    to_append.add("    and $-16, %rsp\n")
    to_append.add("    xor %rax, %rax\n")
    to_append.add("    call _" & d0.replace("[","").replace("]","") & "\n")
    to_append.add("    mov %r15, %rsp\n")
    to_append.add("    pop %r11\n")
    to_append.add("    pop %r10\n")
    to_append.add("    shl $1, %rax\n")
    to_append.add("    or $1, %rax\n")
    return to_append

# --- ARITHMETIC ---
x86_64_darwin["ADD"] = proc(d0, d1, d2: string): string =
    return setSection(".text") &
           mov(resolve(d0), "%rax") &
           "    add " & resolve(d1) & ", %rax\n" &
           "    dec %rax\n"

x86_64_darwin["SUB"] = proc(d0, d1, d2: string): string =
    return setSection(".text") &
           mov(resolve(d0), "%rax") &
           "    sub " & resolve(d1) & ", %rax\n" &
           "    inc %rax\n"

x86_64_darwin["MUL"] = proc(d0, d1, d2: string): string =
    return setSection(".text") &
           mov(resolve(d0), "%rax") &
           "    sar $1, %rax\n" &
           mov(resolve(d1), "%rbx") &
           "    sar $1, %rbx\n" &
           "    imul %rbx, %rax\n" &
           "    shl $1, %rax\n" &
           "    or $1, %rax\n"

x86_64_darwin["DIV"] = proc(d0, d1, d2: string): string =
    return setSection(".text") &
           mov(resolve(d0), "%rax") &
           "    sar $1, %rax\n" &
           mov(resolve(d1), "%rbx") &
           "    sar $1, %rbx\n" &
           "    cqo\n" &
           "    idiv %rbx\n" &
           "    shl $1, %rax\n" &
           "    or $1, %rax\n"

x86_64_darwin["INC"] = proc(d0, d1, d2: string): string =
    return setSection(".text") & "    addq $2, " & resolve(d0) & "\n"

x86_64_darwin["DEC"] = proc(d0, d1, d2: string): string =
    return setSection(".text") & "    subq $2, " & resolve(d0) & "\n"

# --- LOGIC & COMPARISON ---
x86_64_darwin["LT"] = proc(d0: string, d1: string, d2: string): string =
    let lblTrue = getUniqueLabel("lt_true")
    let lblDone = getUniqueLabel("lt_done")
    var s = setSection(".text")
    s.add(mov(resolve(d0), "%rax"))
    s.add(cmp(resolve(d1), "%rax"))
    s.add("    jl " & lblTrue & "\n")
    s.add("    mov $1, %rax\n")
    s.add("    jmp " & lblDone & "\n")
    s.add(lblTrue & ":\n")
    s.add("    mov $3, %rax\n")
    s.add(lblDone & ":\n")
    s.add("    mov %rax, " & resolve(d2) & "\n")
    return s

x86_64_darwin["GT"] = proc(d0: string, d1: string, d2: string): string =
    let lblTrue = getUniqueLabel("gt_true")
    let lblDone = getUniqueLabel("gt_done")
    var s = setSection(".text")
    s.add(mov(resolve(d0), "%rax"))
    s.add(cmp(resolve(d1), "%rax"))
    s.add("    jg " & lblTrue & "\n")
    s.add("    mov $1, %rax\n")
    s.add("    jmp " & lblDone & "\n")
    s.add(lblTrue & ":\n")
    s.add("    mov $3, %rax\n")
    s.add(lblDone & ":\n")
    s.add("    mov %rax, " & resolve(d2) & "\n")
    return s

x86_64_darwin["EQ"] = proc(d0: string, d1: string, d2: string): string =
    let lblTrue = "L_EQ_T_" & $comp_counter
    let lblDone = "L_EQ_D_" & $comp_counter
    comp_counter.inc()
    var s = setSection(".text")
    s.add(mov(resolve(d0), "%rax"))
    s.add(cmp(resolve(d1), "%rax"))
    s.add("    je " & lblTrue & "\n")
    s.add("    mov $1, %rax\n    jmp " & lblDone & "\n")
    s.add(lblTrue & ":\n    mov $3, %rax\n")
    s.add(lblDone & ":\n    mov %rax, " & resolve(d2) & "\n")
    return s

# --- Control Flow ---
x86_64_darwin["JMP"] = proc(d0: string, d1: string, d2: string): string =
    return setSection(".text") & "    jmp " & d0.replace("[", "").replace("]", "") & "\n"

x86_64_darwin["JNZ"] = proc(d0: string, d1: string, d2: string): string =
    var s = setSection(".text")
    s.add("    cmp $3, %rax\n")
    s.add("    je " & d0 & "\n")
    return s

x86_64_darwin["JEZ"] = proc(d0: string, d1: string, d2: string): string =
    return setSection(".text") & "    test %rax, %rax\n    jz " & d0.replace("[", "").replace("]", "") & "\n"

x86_64_darwin["JF"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(mov(resolve(d0), "%rax"))
    s.add("    cmp $1, %rax\n")
    s.add("    je " & d1 & "\n")
    return s

x86_64_darwin["CMP"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(mov(resolve(d0), "%rdi"))
    s.add(mov(resolve(d1), "%rsi"))
    s.add("    call _runtime_eq\n")
    if d2 != "" and d2 != "00":
         s.add("    mov %rax, " & resolve(d2) & "\n")
    return s

# --- IO & META ---
x86_64_darwin["WRITE"] = proc(d0: string, d1: string, d2: string): string =
    var arg = d0
    if arg.startsWith("[\"") and arg.endsWith("\"]"):
        let content = arg[2..^3].replace("\\n", "\\n")
        let lbl = "str_" & $rodata_counter
        rodata_counter.inc()
        return setSection(".rodata") & lbl & ":\n    .asciz \"" & content & "\"\n" &
               setSection(".text") & "    lea " & lbl & "(%rip), %rdi\n    call _print_string\n"

    return setSection(".text") & "    mov " & resolve(arg) & ", %rdi\n    call _print_int\n"

x86_64_darwin["EXIT"] = proc(d0: string, d1: string, d2: string): string =
    var to_append = setSection(".text")
    to_append.add("    call F_main\n")
    if not generateObjectFile:
        to_append.add("    mov $0, %rdi\n")
        to_append.add("    call _exit_program\n")
    else:
        to_append.add("    mov $0, %rax\n")
        to_append.add("    leave\n")
        to_append.add("    ret\n")
    return to_append

x86_64_darwin["STR"] = proc(d0, d1, d2: string): string =
    var s = setSection(".rodata")
    let label = resolve(d0).replace("$", "")
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

x86_64_darwin["WRITES"] = proc(d0: string, d1: string, d2: string): string =
    var s = setSection(".text")
    s.add(mov(resolve(d0), "%rdi"))
    s.add("    call _print_string\n")
    return s

x86_64_darwin["READ"] = proc(d0: string, d1: string, d2: string): string =
    var s = setSection(".text")
    s.add("    call _read_string\n")
    s.add("    mov %rax, " & resolve(d0) & "\n")
    return s

# --- MAP / ARRAY OPERATIONS ---
x86_64_darwin["NEWMAP"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add("    mov $16, %rdi\n")
    s.add("    call __malloc\n")
    s.add("    movq $2, (%rax)\n")
    s.add("    add $8, %rax\n")
    s.add("    movq $0, (%rax)\n")
    s.add("    mov %rax, " & resolve(d0) & "\n")
    return s

x86_64_darwin["MSET"] = proc(d0: string, d1: string, d2: string): string =
    var s = setSection(".text")
    s.add(mov(resolve(d0), "%rdi"))
    s.add(mov(resolve(d1), "%rsi"))
    s.add(mov(resolve(d2), "%rdx"))
    s.add("    call _collection_set\n")
    return s

x86_64_darwin["MGET"] = proc(d0: string, d1: string, d2: string): string =
    var s = setSection(".text")
    s.add(mov(resolve(d1), "%rdi"))
    s.add(mov(resolve(d2), "%rsi"))
    s.add("    call _collection_get\n")
    s.add("    mov %rax, " & resolve(d0) & "\n")
    return s

x86_64_darwin["MLEN"] = proc(d0: string, d1: string, d2: string): string =
    var s = setSection(".text")
    s.add(mov(resolve(d1), "%rdi"))
    s.add("    call _collection_len\n")
    s.add("    mov %rax, " & resolve(d0) & "\n")
    return s

x86_64_darwin["MHEAD"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(mov(resolve(d1), "%rdi"))
    s.add("    call _map_head\n")
    s.add("    mov %rax, " & resolve(d0) & "\n")
    return s

x86_64_darwin["MKEY"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(mov(resolve(d1), "%rdi"))
    s.add("    call _node_key\n")
    s.add("    mov %rax, " & resolve(d0) & "\n")
    return s

x86_64_darwin["MVAL"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(mov(resolve(d1), "%rdi"))
    s.add("    call _node_val\n")
    s.add("    mov %rax, " & resolve(d0) & "\n")
    return s

x86_64_darwin["MNEXT"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(mov(resolve(d1), "%rdi"))
    s.add("    call _node_next\n")
    s.add("    mov %rax, " & resolve(d0) & "\n")
    return s

x86_64_darwin["DEL"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(mov(resolve(d0), "%rdi"))
    s.add(mov(resolve(d1), "%rsi"))
    s.add("    call _map_delete\n")
    return s

x86_64_darwin["NEWARR"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(mov(resolve(d1), "%rdi"))
    s.add("    call _new_array\n")
    s.add("    mov %rax, " & resolve(d0) & "\n")
    return s

# --- FILE I/O OPERATIONS ---
x86_64_darwin["FOPEN"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(mov(resolve(d1), "%rdi"))
    s.add(mov(resolve(d2), "%rsi"))
    s.add("    sar $1, %rsi\n")
    s.add("    mov $420, %rdx\n")
    s.add("    call _file_open\n")
    s.add("    shl $1, %rax\n")
    s.add("    or $1, %rax\n")
    s.add("    mov %rax, " & resolve(d0) & "\n")
    return s

x86_64_darwin["FWRITE"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(mov(resolve(d0), "%rdi"))
    s.add("    sar $1, %rdi\n")
    s.add(mov(resolve(d1), "%rsi"))
    s.add("    call _file_write\n")
    return s

x86_64_darwin["FREAD"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(mov(resolve(d1), "%rdi"))
    s.add("    sar $1, %rdi\n")
    s.add(mov(resolve(d2), "%rsi"))
    s.add("    sar $1, %rsi\n")
    s.add("    call _file_read\n")
    s.add("    mov %rax, " & resolve(d0) & "\n")
    return s

x86_64_darwin["READF"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(mov(resolve(d1), "%rdi"))
    s.add("    call _read_file\n")
    s.add("    mov %rax, " & resolve(d0) & "\n")
    return s

x86_64_darwin["FCLOSE"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(mov(resolve(d0), "%rdi"))
    s.add("    sar $1, %rdi\n")
    s.add("    call _file_close\n")
    return s

# --- ARGV ---
x86_64_darwin["ARGV"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    let lblSafe = getUniqueLabel("argv_safe")
    let lblDone = getUniqueLabel("argv_done")

    s.add(mov(resolve(d0), "%rax"))
    s.add("    sar $1, %rax\n")
    s.add("    cmp _argc(%rip), %rax\n")
    s.add("    jl " & lblSafe & "\n")
    s.add("    movq $1, " & resolve(d1) & "\n")
    s.add("    jmp " & lblDone & "\n")
    s.add(lblSafe & ":\n")
    s.add("    mov %rax, %rdi\n")
    s.add("    call _runtime_get_arg\n")
    s.add("    mov %rax, " & resolve(d1) & "\n")
    s.add(lblDone & ":\n")
    return s

x86_64_darwin["CAT"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(mov(resolve(d1), "%rdi"))
    s.add(mov(resolve(d2), "%rsi"))
    s.add("    call _string_concat\n")
    s.add("    mov %rax, " & resolve(d0) & "\n")
    return s

x86_64_darwin["TYPEOF"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(mov(resolve(d1), "%rdi"))
    s.add("    call _get_type_str\n")
    s.add("    mov %rax, " & resolve(d0) & "\n")
    return s

x86_64_darwin["MALLOC"] = proc(d0: string, d1: string, d2: string): string = return "    # [MALLOC]\n"
x86_64_darwin["FREE"] = proc(d0: string, d1: string, d2: string): string =
    var to_append = setSection(".text")
    to_append.add(mov(resolve(d0), "%rdi"))
    to_append.add("    call __free\n")
    return to_append

x86_64_darwin["COPY"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(mov(resolve(d0), "%rax"))
    s.add("    mov %rax, " & resolve(d1) & "\n")
    return s

x86_64_darwin["ITS"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(mov(resolve(d1), "%rdi"))
    s.add("    call _runtime_to_string\n")
    s.add("    mov %rax, " & resolve(d0) & "\n")
    return s

x86_64_darwin["MOVSD"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add("    movsd " & d0 & "(%rip), %" & d1 & "\n")
    return s

x86_64_darwin["FSTORE"] = proc(d0, d1, d2: string): string =
    var s = setSection(".data")
    s.add(d0 & ": .double " & d1 & "\n")
    return s

# --- NETWORKING ---
x86_64_darwin["NET_SOCKET"] = proc(d0, d1, d2: string): string =
    return setSection(".text") & "    call _socket_create\n    mov %rax, " & resolve(d0) & "\n"

x86_64_darwin["NET_BIND"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(mov(resolve(d0), "%rdi"))
    s.add(mov(resolve(d1), "%rsi"))
    s.add("    call _socket_bind\n")
    return s

x86_64_darwin["NET_LISTEN"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(mov(resolve(d0), "%rdi"))
    s.add("    call _socket_listen\n")
    return s

x86_64_darwin["NET_ACCEPT"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(mov(resolve(d1), "%rdi"))
    s.add("    call _socket_accept\n")
    s.add("    mov %rax, " & resolve(d0) & "\n")
    return s

x86_64_darwin["NET_WRITE"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(mov(resolve(d0), "%rdi"))
    s.add(mov(resolve(d1), "%rsi"))
    s.add("    call _socket_write\n")
    return s

x86_64_darwin["NET_CLOSE"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(mov(resolve(d0), "%rdi"))
    s.add("    call _socket_close\n")
    return s

x86_64_darwin["NET_RECV"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add(mov(resolve(d1), "%rdi"))
    s.add(mov(resolve(d2), "%rsi"))
    s.add("    call _socket_read\n")
    s.add("    mov %rax, " & resolve(d0) & "\n")
    return s

x86_64_darwin["NOP"] = proc(d0: string, d1: string, d2: string): string = return "    nop\n"
x86_64_darwin["__required"] = proc(d0: string, d1: string, d2: string): string = return ""
x86_64_darwin["__makeTemp"] = proc(d0: string, d1: string, d2: string): string = return ""
x86_64_darwin["__finalize"] = proc(d0: string, d1: string, d2: string): string = return ""
x86_64_darwin["__comment"] = proc(d0: string, d1: string, d2: string): string =
    DebugInformation.add("    " & d1 & ": " & d2)
    return "    # " & d0

x86_64_darwin["MOV"] = proc(d0, d1, d2: string): string =
    return mov(resolve(d1), resolve(d0))

x86_64_darwin["NSUB"] = proc(d0, d1, d2: string): string =
    return "    sub " & resolve(d0) & ", %rsp\n"

x86_64_darwin["NADD"] = proc(d0, d1, d2: string): string =
    return "    add " & resolve(d0) & ", %rsp\n"

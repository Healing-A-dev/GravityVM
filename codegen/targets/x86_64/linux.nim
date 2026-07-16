import std/[strutils, tables]
import ../../../core/memory

var x86_64_linux* = initTable[string, proc(d0: string, d1: string, d2: string): string]()
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
#
proc resolve(arg: string): string =
    if arg.startsWith("str_"): return "$" & arg
    if arg.startsWith("$str_"): return arg
    if arg.contains("sra"): return "%rax"

    var cleanArg = arg.replace("!", "").replace("[", "").replace("]", "")
    if cleanArg.contains("(%rbp)"): return cleanArg.replace("$", "")
    if cleanArg in ["%rax", "%rbx", "%rcx", "%rdx", "%rdi", "%rsi", "%rsp", "%rbp", "%r8", "%r9"]: return cleanArg

    if cleanArg.startsWith("$"):
        let inner = cleanArg.substr(1)
        if inner.contains("F_"): return "$" & inner
        try:
            discard parseInt(inner)
            if inner.len > 1 and inner.startsWith("0") and not inner.startsWith("-"):
                return "L" & inner & "(%rip)"
            return "$" & inner
        except ValueError:
            return "L" & inner & "(%rip)"

    if cleanArg.startsWith("%"): return cleanArg.substr(1) & "(%rip)"
    if cleanArg.startsWith("@"): return "G" & cleanArg[1..^1] & "(%rip)"
    if (cleanArg.startsWith("L") or cleanArg.startsWith("B")) and not cleanArg.contains("\""): return cleanArg & "(%rip)"
    return "$" & cleanArg

proc getUniqueLabel(prefix: string): string =
  inc labelCounter
  return prefix & "_" & $labelCounter

# --- OPCODES ---
x86_64_linux["STORE"] = proc(d0: string, d1: string, d2: string): string =
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
            to_append.add("    mov " & resolve(src) & ", %r11\n")
            to_append.add("    mov %r11, " & cleanDest & "\n")
            return to_append

    var safeValue = src
    if safeValue.contains("%") or safeValue.contains("$") or safeValue.contains("@"): safeValue = "0"

    to_append.add(setSection(".data"))
    if dest.startsWith("@"): to_append.add("G" & dest[1..^1] & ": .quad " & safeValue & "\n")
    elif dest.startsWith("$"): to_append.add("L" & dest[1..^1] & ": .quad " & safeValue & "\n")
    elif dest.startsWith("%"): to_append.add("B" & dest[1..^1] & ": .quad " & safeValue & "\n")
    return to_append

x86_64_linux["UPD"] = proc(d0: string, d1: string, d2: string): string =
    var to_append = setSection(".text")
    to_append.add("    mov " & resolve(d1) & ", %r11\n")
    to_append.add("    mov %r11, " & resolve(d0) & "\n")
    return to_append

x86_64_linux["LBL"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    var lbl = d0.replace("[", "").replace("]", "")

    to_append.add(setSection(".text"))

    if lbl == "ENTRY" and not generateObjectFile:
        to_append.add("    .global _start\n")
        to_append.add("_start:\n")
        to_append.add("    mov (%rsp), %rdi\n")
        to_append.add("    mov %rdi, __argc(%rip)\n")
        to_append.add("    lea 8(%rsp), %rsi\n")
        to_append.add("    mov %rsi, __sys_argv(%rip)\n")
        to_append.add("    mov %rsp, %rax\n")
        to_append.add("    mov %rax, __sys_stack_base(%rip)\n")
        return to_append
    elif lbl == "ENTRY" and generateObjectFile:
        to_append.add("    .global ENTRY\n")

    to_append.add(lbl & ":\n")

    if lbl.startsWith("F_"):
        to_append.add("    push %rbp\n")
        to_append.add("    mov %rsp, %rbp\n")
    return to_append

x86_64_linux["CALL"] = proc(d0: string, d1: string, d2: string): string =
    var s = setSection(".text")
    let funcLabel = d0.replace("[", "").replace("]", "")

    s.add("    call " & funcLabel & "\n")

    var argCount = 0
    try: argCount = parseInt(d1)
    except: discard

    if argCount > 0:
        s.add("    add $" & $(argCount * 8) & ", %rsp\n")

    if d2 != "00":
        s.add("    mov %rax, " & resolve(d2) & "\n")
    return s

x86_64_linux["CALLD"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add("    mov " & resolve(d1) & ", %rax\n")
    s.add("    call *%rax\n")

    if d2 != "0":
        let popSize = parseInt(d2) * 8
        s.add("    add $" & $popSize & ", %rsp\n")

    s.add("    mov %rax, " & resolve(d0) & "\n")

    return s

x86_64_linux["RET"] = proc(d0: string, d1: string, d2: string): string =
    var to_append = setSection(".text")
    if d0 != "" and d0 != "0" and d0 != "00":
        to_append.add("    mov " & resolve(d0) & ", %rax\n")
    to_append.add("    leave\n    ret\n")
    return to_append

x86_64_linux["PUSH"] = proc(d0: string, d1: string, d2: string): string =
    return setSection(".text") & "    push " & resolve(d0) & "\n"

x86_64_linux["GETARG"] = proc(d0: string, d1: string, d2: string): string =
    var index = 0
    try: index = parseInt(d1)
    except: discard
    let offset = 16 + (index * 8)
    let src = $offset & "(%rbp)"
    return setSection(".text") & "    mov " & src & ", %rax\n    mov %rax, " & resolve(d0) & "\n"

x86_64_linux["EXPO"] = proc(d0, d1, d2: string): string =
    let lbl: string = d0.replace("[","").replace("]","")
    return ".global " & lbl & "\n"


x86_64_linux["ETRN"] = proc(d0, d1, d2: string): string =
    var to_append: string = ""
    to_append.add("    # FFI SHIELD\n")
    to_append.add("    push %r10\n")
    to_append.add("    push %r11\n")
    to_append.add("    mov %rsp, %r15\n")
    to_append.add("    and $-16, %rsp\n")
    to_append.add("    xor %rax, %rax\n")
    to_append.add("    call " & d0.replace("[","").replace("]","") & "\n")
    to_append.add("    mov %r15, %rsp\n")
    to_append.add("    pop %r11\n")
    to_append.add("    pop %r10\n")
    to_append.add("    shl $1, %rax\n")
    to_append.add("    or $1, %rax\n")

    return to_append

# --- ARITHMETIC ---
x86_64_linux["ADD"] = proc(d0, d1, d2: string): string =
    return setSection(".text") &
           "    mov " & resolve(d0) & ", %rax\n" &
           "    add " & resolve(d1) & ", %rax\n" &
           "    dec %rax\n"

x86_64_linux["SUB"] = proc(d0, d1, d2: string): string =
    return setSection(".text") &
           "    mov " & resolve(d0) & ", %rax\n" &
           "    sub " & resolve(d1) & ", %rax\n" &
           "    inc %rax\n"

x86_64_linux["MUL"] = proc(d0, d1, d2: string): string =
    return setSection(".text") &
           "    mov " & resolve(d0) & ", %rax\n" &
           "    sar $1, %rax\n" &
           "    mov " & resolve(d1) & ", %rbx\n" &
           "    sar $1, %rbx\n" &
           "    imul %rbx, %rax\n" &
           "    shl $1, %rax\n" &
           "    or $1, %rax\n"

x86_64_linux["DIV"] = proc(d0, d1, d2: string): string =
    return setSection(".text") &
           "    mov " & resolve(d0) & ", %rax\n" &
           "    sar $1, %rax\n" &
           "    mov " & resolve(d1) & ", %rbx\n" &
           "    sar $1, %rbx\n" &
           "    cqo\n" &
           "    idiv %rbx\n" &
           "    shl $1, %rax\n" &
           "    or $1, %rax\n"

x86_64_linux["INC"] = proc(d0, d1, d2: string): string =
    return setSection(".text") & "    addq $2, " & resolve(d0) & "\n"

x86_64_linux["DEC"] = proc(d0, d1, d2: string): string =
    return setSection(".text") & "    subq $2, " & resolve(d0) & "\n"

# --- LOGIC & COMPARISON ---
x86_64_linux["LT"] = proc(d0: string, d1: string, d2: string): string =
    let lblTrue = getUniqueLabel("lt_true")
    let lblDone = getUniqueLabel("lt_done")
    var s = setSection(".text")

    s.add("    mov " & resolve(d0) & ", %rax\n")
    s.add("    cmp " & resolve(d1) & ", %rax\n")
    s.add("    jl " & lblTrue & "\n")
    s.add("    mov $1, %rax\n")
    s.add("    jmp " & lblDone & "\n")
    s.add(lblTrue & ":\n")
    s.add("    mov $3, %rax\n")
    s.add(lblDone & ":\n")
    s.add("    mov %rax, " & resolve(d2) & "\n")
    return s

x86_64_linux["GT"] = proc(d0: string, d1: string, d2: string): string =
    let lblTrue = getUniqueLabel("gt_true")
    let lblDone = getUniqueLabel("gt_done")
    var s = setSection(".text")

    s.add("    mov " & resolve(d0) & ", %rax\n")
    s.add("    cmp " & resolve(d1) & ", %rax\n")
    s.add("    jg " & lblTrue & "\n")

    s.add("    mov $1, %rax\n")
    s.add("    jmp " & lblDone & "\n")

    s.add(lblTrue & ":\n")
    s.add("    mov $3, %rax\n")

    s.add(lblDone & ":\n")
    s.add("    mov %rax, " & resolve(d2) & "\n")
    return s

x86_64_linux["EQ"] = proc(d0: string, d1: string, d2: string): string =
    let lblTrue = ".EQ_T_" & $comp_counter
    let lblDone = ".EQ_D_" & $comp_counter
    comp_counter.inc()
    var s = setSection(".text")
    s.add("    mov " & resolve(d0) & ", %rax\n")
    s.add("    cmp " & resolve(d1) & ", %rax\n")
    s.add("    je " & lblTrue & "\n")
    s.add("    mov $0, %rax\n    jmp " & lblDone & "\n")
    s.add(lblTrue & ":\n    mov $1, %rax\n")
    s.add(lblDone & ":\n")
    return s

#--- Control Flow ---
x86_64_linux["JMP"] = proc(d0: string, d1: string, d2: string): string =
    return setSection(".text") & "    jmp " & d0.replace("[", "").replace("]", "") & "\n"

x86_64_linux["JNZ"] = proc(d0: string, d1: string, d2: string): string =
    var s = setSection(".text")
    s.add("    cmp $3, %rax\n")
    s.add("    je " & d0 & "\n")
    return s

x86_64_linux["JEZ"] = proc(d0: string, d1: string, d2: string): string =
    return setSection(".text") & "    test %rax, %rax\n    jz " & d0.replace("[", "").replace("]", "") & "\n"

x86_64_linux["JF"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add("    mov " & resolve(d0) & ", %rax\n")
    s.add("    cmp $1, %rax\n")
    s.add("    je " & d1 & "\n")
    return s

x86_64_linux["CMP"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add("    mov " & resolve(d0) & ", %rdi\n")
    s.add("    mov " & resolve(d1) & ", %rsi\n")
    s.add("    call runtime_eq\n")
    if d2 != "" and d2 != "00":
         s.add("    mov %rax, " & resolve(d2) & "\n")

    return s

# --- IO & META ---
x86_64_linux["WRITE"] = proc(d0: string, d1: string, d2: string): string =
    var arg = d0
    if arg.startsWith("[\"") and arg.endsWith("\"]"):
        let content = arg[2..^3].replace("\\n", "\\n")
        let lbl = "str_" & $rodata_counter
        rodata_counter.inc()
        return setSection(".rodata") & lbl & ":\n    .ascii \"" & content & "\"\n    .byte 0\n" &
               setSection(".text") & "    mov $1, %rax\n    mov $1, %rdi\n    lea " & lbl & "(%rip), %rsi\n    mov $" & d1 & ", %rdx\n    syscall\n"

    return setSection(".text") & "    mov " & resolve(arg) & ", %rdi\n    call print_int\n"

x86_64_linux["EXIT"] = proc(d0: string, d1: string, d2: string): string =
    var to_append = setSection(".text")
    to_append.add("    call F_main\n")
    if not generateObjectFile:
        to_append.add("    mov $0, %rdi\n")
        to_append.add("    call exit_program\n")
    else:
        to_append.add("    mov $0, %rax\n")
        to_append.add("    leave\n")
        to_append.add("    ret\n")
    return to_append

x86_64_linux["STR"] = proc(d0, d1, d2: string): string =
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

    s.add("    .align 8\n")
    s.add(label & "_header:\n")
    s.add("    .quad 1\n")
    s.add(label & ":\n")
    if byteStr != "0":
        s.add("    .byte " & byteStr & ", 0\n")
    else:
        s.add("    .byte 0\n")
    return s

x86_64_linux["WRITES"] = proc(d0: string, d1: string, d2: string): string =
    var s = setSection(".text")
    s.add("    mov " & resolve(d0) & ", %rdi\n")
    s.add("    call print_string\n")
    return s

x86_64_linux["READ"] = proc(d0: string, d1: string, d2: string): string =
    var s = setSection(".text")
    s.add("    call read_string\n")
    s.add("    mov %rax, " & resolve(d0) & "\n")
    return s

# --- 6. MAP/ARRAY OPERATIONS (Runtime Calls) ---
x86_64_linux["NEWMAP"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")

    s.add("    mov $16, %rdi\n")
    s.add("    call _malloc\n")
    s.add("    movq $2, (%rax)\n")
    s.add("    add $8, %rax\n")
    s.add("    movq $0, (%rax)\n")
    s.add("    mov %rax, " & resolve(d0) & "\n")
    return s

x86_64_linux["MSET"] = proc(d0: string, d1: string, d2: string): string =
    var s = setSection(".text")
    s.add("    mov " & resolve(d0) & ", %rdi\n")
    s.add("    mov " & resolve(d1) & ", %rsi\n")
    s.add("    mov " & resolve(d2) & ", %rdx\n")
    s.add("    call collection_set\n")
    return s

x86_64_linux["MGET"] = proc(d0: string, d1: string, d2: string): string =
    var s = setSection(".text")
    s.add("    mov " & resolve(d1) & ", %rdi\n")
    s.add("    mov " & resolve(d2) & ", %rsi\n")
    s.add("    call collection_get\n")
    s.add("    mov %rax, " & resolve(d0) & "\n")
    return s

x86_64_linux["MLEN"] = proc(d0: string, d1: string, d2: string): string =
    var s = setSection(".text")
    s.add("    mov " & resolve(d1) & ", %rdi\n")
    s.add("    call collection_len\n")
    s.add("    mov %rax, " & resolve(d0) & "\n")
    return s

x86_64_linux["MHEAD"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add("    mov " & resolve(d1) & ", %rdi\n")
    s.add("    call map_head\n")
    s.add("    mov %rax, " & resolve(d0) & "\n")
    return s

x86_64_linux["MKEY"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add("    mov " & resolve(d1) & ", %rdi\n")
    s.add("    call node_key\n")
    s.add("    mov %rax, " & resolve(d0) & "\n")
    return s

x86_64_linux["MVAL"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add("    mov " & resolve(d1) & ", %rdi\n")
    s.add("    call node_val\n")
    s.add("    mov %rax, " & resolve(d0) & "\n")
    return s

x86_64_linux["MNEXT"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add("    mov " & resolve(d1) & ", %rdi\n")
    s.add("    call node_next\n")
    s.add("    mov %rax, " & resolve(d0) & "\n")
    return s

x86_64_linux["DEL"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add("    mov " & resolve(d0) & ", %rdi\n")  # Map Pointer
    s.add("    mov " & resolve(d1) & ", %rsi\n")  # Key

    s.add("    call map_delete\n")
    return s

x86_64_linux["NEWARR"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add("    mov " & resolve(d1) & ", %rdi\n")
    s.add("    call new_array\n")
    s.add("    mov %rax, " & resolve(d0) & "\n")
    return s


# --- FILE I/O OPERATIONS ---
x86_64_linux["FOPEN"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add("    mov " & resolve(d1) & ", %rdi\n") # Path
    s.add("    mov " & resolve(d2) & ", %rsi\n")
    s.add("    sar $1, %rsi\n")
    s.add("    mov $420, %rdx\n")
    s.add("    call file_open\n")
    s.add("    shl $1, %rax\n")
    s.add("    or $1, %rax\n")
    s.add("    mov %rax, " & resolve(d0) & "\n")
    return s

x86_64_linux["FWRITE"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add("    mov " & resolve(d0) & ", %rdi\n")
    s.add("    sar $1, %rdi\n")  # Convert Tagged Int -> Raw Int
    s.add("    mov " & resolve(d1) & ", %rsi\n")
    s.add("    call file_write\n")
    return s

x86_64_linux["FREAD"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add("    mov " & resolve(d1) & ", %rdi\n")
    s.add("    sar $1, %rdi\n")  # Untag FD
    s.add("    mov " & resolve(d2) & ", %rsi\n")
    s.add("    sar $1, %rsi\n")  # Untag Length
    s.add("    call file_read\n")
    s.add("    mov %rax, " & resolve(d0) & "\n") # Return Boxed String
    return s

x86_64_linux["READF"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add("    mov " & resolve(d1) & ", %rdi\n") # Path
    s.add("    call read_file\n")
    s.add("    mov %rax, " & resolve(d0) & "\n") # Result
    return s

x86_64_linux["FCLOSE"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add("    mov " & resolve(d0) & ", %rdi\n")
    s.add("    sar $1, %rdi\n")  # Untag FD
    s.add("    call file_close\n")
    return s

# --- ARGV ---
x86_64_linux["ARGV"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    let lblSafe = getUniqueLabel("argv_safe")
    let lblDone = getUniqueLabel("argv_done")

    s.add("    mov " & resolve(d0) & ", %rax\n")
    s.add("    sar $1, %rax\n")
    s.add("    cmp __argc(%rip), %rax\n")
    s.add("    jl " & lblSafe & "\n")
    s.add("    movq $1, " & resolve(d1) & "\n")
    s.add("    jmp " & lblDone & "\n")
    s.add(lblSafe & ":\n")
    s.add("    mov %rax, %rdi\n")
    s.add("    call runtime_get_arg\n")
    s.add("    mov %rax, " & resolve(d1) & "\n")

    s.add(lblDone & ":\n")
    return s

# --- STRING CONCATENTATION ---
x86_64_linux["CAT"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add("    mov " & resolve(d1) & ", %rdi\n")   # Str A
    s.add("    mov " & resolve(d2) & ", %rsi\n")   # Str B
    s.add("    call string_concat\n")
    s.add("    mov %rax, " & resolve(d0) & "\n")   # Result
    return s


# --- TYPING ---
x86_64_linux["TYPEOF"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")

    s.add("    mov " & resolve(d1) & ", %rdi\n")
    s.add("    call get_type_str\n")
    s.add("    mov %rax, " & resolve(d0) & "\n")
    return s

# --- Memory Allocation & Free ---
x86_64_linux["MALLOC"] = proc(d0: string, d1: string, d2: string): string = return "    # [MALLOC]\n"
x86_64_linux["FREE"] = proc(d0: string, d1: string, d2: string): string =
    var to_append = setSection(".text")
    to_append.add("    mov " & resolve(d0) & ", %rdi\n")
    to_append.add("    call free")
    return to_append

x86_64_linux["COPY"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add("    mov " & resolve(d0) & ", %rax\n")
    s.add("    mov %rax, " & resolve(d1) & "\n")
    return s

# --- Type conversion ----
x86_64_linux["ITS"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add("    mov " & resolve(d1) & ", %rdi\n")  # Load Integer
    s.add("    call runtime_to_string\n")             # Call Assembly Helper
    s.add("    mov %rax, " & resolve(d0) & "\n")  # Store Pointer
    return s


# --- Floats ---
x86_64_linux["MOVSD"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add("    movsd " & d0 & "(%rip), %" & d1 & "\n")
    return s

x86_64_linux["FSTORE"] = proc(d0, d1, d2: string): string =
    var s = setSection(".data")
    s.add(d0 & ": .double " & d1 & "\n")
    return s


# --- NETWORKING --- #
x86_64_linux["NET_SOCKET"] = proc(d0, d1, d2: string): string =
    return setSection(".text") & "    call socket_create\n    mov %rax, " & resolve(d0) & "\n"

x86_64_linux["NET_BIND"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add("    mov " & resolve(d0) & ", %rdi\n")
    s.add("    mov " & resolve(d1) & ", %rsi\n")
    s.add("    call socket_bind\n")
    return s

x86_64_linux["NET_LISTEN"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add("    mov " & resolve(d0) & ", %rdi\n")
    s.add("    call socket_listen\n")
    return s

x86_64_linux["NET_ACCEPT"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add("    mov " & resolve(d1) & ", %rdi\n")
    s.add("    call socket_accept\n")
    s.add("    mov %rax, " & resolve(d0) & "\n")
    return s

x86_64_linux["NET_WRITE"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add("    mov " & resolve(d0) & ", %rdi\n") # FD
    s.add("    mov " & resolve(d1) & ", %rsi\n") # String
    s.add("    call socket_write\n")
    return s

x86_64_linux["NET_CLOSE"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add("    mov " & resolve(d0) & ", %rdi\n")
    s.add("    call socket_close\n")
    return s

x86_64_linux["NET_RECV"] = proc(d0, d1, d2: string): string =
    var s = setSection(".text")
    s.add("    mov " & resolve(d1) & ", %rdi\n") # FD
    s.add("    mov " & resolve(d2) & ", %rsi\n") # Size
    s.add("    call socket_read\n")
    s.add("    mov %rax, " & resolve(d0) & "\n") # Result String
    return s


# --- Boiler Plate ----
x86_64_linux["NOP"] = proc(d0: string, d1: string, d2: string): string = return "    nop\n"
x86_64_linux["__required"] = proc(d0: string, d1: string, d2: string): string = return ""
x86_64_linux["__makeTemp"] = proc(d0: string, d1: string, d2: string): string = return ""
x86_64_linux["__comment"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    DebugInformation.add("    " & d1 & ": " & d2)
    return "    # " & d0

x86_64_linux["MOV"] = proc(d0, d1, d2: string): string =
    return "    mov " & resolve(d1) & ", " & resolve(d0) & "\n"

x86_64_linux["NSUB"] = proc(d0, d1, d2: string): string =
    return "    sub " & resolve(d0) & ", %rsp\n"

x86_64_linux["NADD"] = proc(d0, d1, d2: string): string =
    return "    add " & resolve(d0) & ", %rsp\n"

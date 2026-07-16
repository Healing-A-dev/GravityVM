import std/[strutils, tables]
import ../../../../core/memory

# Use the exact table name expected by the VM
var vm_transpiler_c* = initTable[string, proc(d0: string, d1: string, d2: string): string]()
var labelCounter: int = 0
var current_label: string = ""

proc getUniqueLabel(prefix: string): string =
  inc labelCounter
  return prefix & "_" & $labelCounter

proc resolveC(arg: string): string =
    if arg == "" or arg == "0": return "0"

    var cleanArg = arg.replace("!", "").replace("[", "").replace("]", "").replace("$", "")

    if cleanArg.contains("(%rbp)"):
        let offsetStr = cleanArg.replace("(%rbp)", "")
        if offsetStr == "": return "stack[rbp]"
        try:
            let offset = parseInt(offsetStr) div 8
            if offset < 0: return "stack[rbp - " & $(-offset) & "]"
            else: return "stack[rbp + " & $offset & "]"
        except:
            return "stack[rbp]"

    if cleanArg == "%rax": return "sra"
    if cleanArg == "%rbx": return "srb"
    if cleanArg == "%rcx": return "src"
    if cleanArg == "%rdx": return "srd"
    if cleanArg == "%rsp": return "rsp"
    if cleanArg == "%rbp": return "rbp"
    if cleanArg in ["%rdi", "%rsi", "%r8", "%r9"]: return cleanArg.replace("%", "reg_")

    if cleanArg.startsWith("@"): return "G_" & cleanArg[1..^1]
    if cleanArg.startsWith("%"): return "B_" & cleanArg[1..^1]
    if cleanArg.startsWith("str_"):
        return "(long long)" & cleanArg

    return cleanArg

# ==========================================
# --- 1. Control Flow & The Virtual Stack ---
# ==========================================

vm_transpiler_c["LBL"] = proc(d0, d1, d2: string): string =
    let lbl = d0.replace("[", "").replace("]", "")
    if lbl == "ENTRY":
        return "ENTRY:\n"

    var s = lbl & ":\n"
    if lbl.startsWith("F_"):
        # Standard function prologue mapped to the C stack
        s &= "    stack[--rsp] = rbp;\n    rbp = rsp;\n"
    else:
        current_label = lbl
    return s

vm_transpiler_c["PUSH"] = proc(d0, d1, d2: string): string =
    return "    stack[--rsp] = " & resolveC(d0) & ";\n"

vm_transpiler_c["CALL"] = proc(d0, d1, d2: string): string =
    let funcLabel = d0.replace("[", "").replace("]", "")
    let retLabel = getUniqueLabel("RET_ADDR")

    var s = "    stack[--rsp] = (long long)&&" & retLabel & ";\n"
    s &= "    goto " & funcLabel & ";\n"
    s &= retLabel & ":\n"

    var argCount = 0
    try: argCount = parseInt(d1)
    except: discard

    if argCount > 0:
        s &= "    rsp += " & $argCount & ";\n"

    if d2 != "" and d2 != "00":
        s &= "    " & resolveC(d2) & " = sra;\n"
    return s

vm_transpiler_c["RET"] = proc(d0, d1, d2: string): string =
    var s = ""
    if d0 != "" and d0 != "0" and d0 != "00":
        s &= "    sra = " & resolveC(d0) & ";\n"

    # Function epilogue & computed goto return
    s &= "    rsp = rbp;\n"
    s &= "    rbp = stack[rsp++];\n"
    s &= "    goto *(void*)stack[rsp++];\n"
    return s

vm_transpiler_c["GETARG"] = proc(d0, d1, d2: string): string =
    # Old RBP is at rbp. Return address is at rbp+1. Args start at rbp+2.
    var index = 0
    try: index = parseInt(d1)
    except: discard
    let offset = 2 + index
    return "    " & resolveC(d0) & " = stack[rbp + " & $offset & "];\n"


# ==========================================
# --- 2. Arithmetic & Logic (Inlined) ---
# ==========================================

vm_transpiler_c["STORE"] = proc(d0, d1, d2: string): string =
    var dest = resolveC(d0)
    var src = resolveC(d1)

    # If it's a Global, a Branch label, or a generic Register, declare it statically
    if dest.startsWith("G_") or dest.startsWith("B_") or dest.startsWith("reg_"):
        return "    static long long " & dest & " = 0;\n    " & dest & " = " & src & ";\n"

    return "    " & dest & " = " & src & ";\n"

vm_transpiler_c["ADD"] = proc(d0, d1, d2: string): string =
    return "    sra = TAG(UNTAG(" & resolveC(d0) & ") + UNTAG(" & resolveC(d1) & "));\n"

vm_transpiler_c["SUB"] = proc(d0, d1, d2: string): string =
    return "    sra = TAG(UNTAG(" & resolveC(d0) & ") - UNTAG(" & resolveC(d1) & "));\n"

vm_transpiler_c["MUL"] = proc(d0, d1, d2: string): string =
    return "    sra = TAG(UNTAG(" & resolveC(d0) & ") * UNTAG(" & resolveC(d1) & "));\n"

vm_transpiler_c["DIV"] = proc(d0, d1, d2: string): string =
    var s = "    if (UNTAG(" & resolveC(d1) & ") == 0) sra = TAG(0);\n"
    s &= "    else sra = TAG(UNTAG(" & resolveC(d0) & ") / UNTAG(" & resolveC(d1) & "));\n"
    return s

vm_transpiler_c["INC"] = proc(d0, d1, d2: string): string =
    return "    " & resolveC(d0) & " += 2;\n" # +2 to account for tag bit

vm_transpiler_c["DEC"] = proc(d0, d1, d2: string): string =
    return "    " & resolveC(d0) & " -= 2;\n"

vm_transpiler_c["LT"] = proc(d0, d1, d2: string): string =
    return "    " & resolveC(d2) & " = (UNTAG(" & resolveC(d0) & ") < UNTAG(" & resolveC(d1) & ")) ? 3 : 1;\n"

vm_transpiler_c["GT"] = proc(d0, d1, d2: string): string =
    return "    " & resolveC(d2) & " = (UNTAG(" & resolveC(d0) & ") > UNTAG(" & resolveC(d1) & ")) ? 3 : 1;\n"

vm_transpiler_c["EQ"] = proc(d0, d1, d2: string): string =
    return "    sra = (" & resolveC(d0) & " == " & resolveC(d1) & ") ? 1 : 0;\n"


# ==========================================
# --- 3. Branching & Variables ---
# ==========================================

vm_transpiler_c["JMP"] = proc(d0, d1, d2: string): string =
    return "    goto " & d0.replace("[", "").replace("]", "") & ";\n"

vm_transpiler_c["JNZ"] = proc(d0, d1, d2: string): string =
    return "    if (sra == 3) goto " & d0 & ";\n"

vm_transpiler_c["JEZ"] = proc(d0, d1, d2: string): string =
    return "    if (sra == 0) goto " & d0.replace("[", "").replace("]", "") & ";\n"

vm_transpiler_c["STR"] = proc(d0, d1, d2: string): string =
    var hex = d1.replace("[", "").replace("]", "")
    var bytes = ""
    if hex.len > 0:
        for i in countup(0, hex.len - 2, 2):
            bytes.add("\\x" & hex[i..i+1])

    let label = d0.replace("$", "").replace("!", "").replace("[", "").replace("]", "")

    # Generate a standard C global char array
    return "    static const char " & label & "[] = \"" & bytes & "\";\n"
# ==========================================
# --- 4. Hardware/Runtime Calls ---
# ==========================================

vm_transpiler_c["NEWMAP"] = proc(d0, d1, d2: string): string =
    return "    " & resolveC(d0) & " = gvm_map_new();\n"

vm_transpiler_c["MSET"] = proc(d0, d1, d2: string): string =
    return "    gvm_map_set(" & resolveC(d0) & ", " & resolveC(d1) & ", " & resolveC(d2) & ");\n"

vm_transpiler_c["CAT"] = proc(d0, d1, d2: string): string =
    return "    " & resolveC(d0) & " = gvm_str_cat(" & resolveC(d1) & ", " & resolveC(d2) & ");\n"

vm_transpiler_c["FOPEN"] = proc(d0, d1, d2: string): string =
    var s = "    " & resolveC(d0) & " = gvm_file_open(" & resolveC(d1) & ", " & resolveC(d2) & ");\n"
    # Re-tag file descriptor logic from x86
    s &= "    " & resolveC(d0) & " = (" & resolveC(d0) & " << 1) | 1;\n"
    return s

vm_transpiler_c["EXIT"] = proc(d0, d1, d2: string): string =
    if current_label != "L500":
        return "    exit(UNTAG(" & resolveC(d0) & "));\n"
    return ""

# --- Memory Allocation & Copying ---
vm_transpiler_c["MALLOC"] = proc(d0, d1, d2: string): string = return "    // [MALLOC]\n"

vm_transpiler_c["FREE"] = proc(d0, d1, d2: string): string =
    return "    free((void*)" & resolveC(d0) & ");\n"

vm_transpiler_c["COPY"] = proc(d0, d1, d2: string): string =
    return "    " & resolveC(d1) & " = " & resolveC(d0) & ";\n"

# --- Typing ---
vm_transpiler_c["ITS"] = proc(d0, d1, d2: string): string =
    return "    " & resolveC(d0) & " = gvm_int_to_str(" & resolveC(d1) & ");\n"

vm_transpiler_c["TYPEOF"] = proc(d0, d1, d2: string): string =
    return "    " & resolveC(d0) & " = gvm_typeof(" & resolveC(d1) & ");\n"

vm_transpiler_c["NEWARR"] = proc(d0, d1, d2: string): string =
    var s = "    {\n"
    s &= "        long long cap = UNTAG(" & resolveC(d1) & ");\n"
    s &= "        long long* block = (long long*)malloc(sizeof(long long) * (cap + 2));\n"
    s &= "        block[0] = cap;\n"
    s &= "        block[1] = 0;\n"
    s &= "        " & resolveC(d0) & " = ((long long)block) | 4;\n"
    s &= "    }\n"
    return s

vm_transpiler_c["MGET"] = proc(d0, d1, d2: string): string =
    return "    " & resolveC(d0) & " = gvm_map_get(" & resolveC(d1) & ", " & resolveC(d2) & ");\n"

vm_transpiler_c["MLEN"] = proc(d0, d1, d2: string): string =
    return "    " & resolveC(d0) & " = gvm_map_len(" & resolveC(d1) & ");\n"

vm_transpiler_c["MHEAD"] = proc(d0, d1, d2: string): string =
    return "    " & resolveC(d0) & " = gvm_map_head(" & resolveC(d1) & ");\n"

vm_transpiler_c["MKEY"] = proc(d0, d1, d2: string): string =
    return "    " & resolveC(d0) & " = gvm_map_key(" & resolveC(d1) & ");\n"

vm_transpiler_c["MVAL"] = proc(d0, d1, d2: string): string =
    return "    " & resolveC(d0) & " = gvm_map_val(" & resolveC(d1) & ");\n"

vm_transpiler_c["MNEXT"] = proc(d0, d1, d2: string): string =
    return "    " & resolveC(d0) & " = gvm_map_next(" & resolveC(d1) & ");\n"

vm_transpiler_c["DEL"] = proc(d0, d1, d2: string): string =
    return "    gvm_map_del(" & resolveC(d0) & ", " & resolveC(d1) & ");\n"

vm_transpiler_c["READF"] = proc(d0, d1, d2: string): string =
    return "    " & resolveC(d0) & " = gvm_file_read_all(" & resolveC(d1) & ");\n"

vm_transpiler_c["FWRITE"] = proc(d0, d1, d2: string): string =
    return "    gvm_file_write(UNTAG(" & resolveC(d0) & "), " & resolveC(d1) & ");\n"

vm_transpiler_c["FREAD"] = proc(d0, d1, d2: string): string =
    return "    " & resolveC(d0) & " = gvm_file_read(UNTAG(" & resolveC(d1) & "), UNTAG(" & resolveC(d2) & "));\n"

vm_transpiler_c["FCLOSE"] = proc(d0, d1, d2: string): string =
    return "    gvm_file_close(UNTAG(" & resolveC(d0) & "));\n"

vm_transpiler_c["ARGV"] = proc(d0, d1, d2: string): string =
    return "    " & resolveC(d1) & " = gvm_get_argv(" & resolveC(d0) & ");\n"

vm_transpiler_c["NET_SOCKET"] = proc(d0, d1, d2: string): string =
    return "    " & resolveC(d0) & " = gvm_net_socket();\n"

vm_transpiler_c["NET_BIND"] = proc(d0, d1, d2: string): string =
    return "    gvm_net_bind(UNTAG(" & resolveC(d0) & "), UNTAG(" & resolveC(d1) & "));\n"

vm_transpiler_c["NET_LISTEN"] = proc(d0, d1, d2: string): string =
    return "    gvm_net_listen(UNTAG(" & resolveC(d0) & "));\n"

vm_transpiler_c["NET_ACCEPT"] = proc(d0, d1, d2: string): string =
    return "    " & resolveC(d0) & " = gvm_net_accept(UNTAG(" & resolveC(d1) & "));\n"

vm_transpiler_c["NET_WRITE"] = proc(d0, d1, d2: string): string =
    return "    gvm_net_write(UNTAG(" & resolveC(d0) & "), " & resolveC(d1) & ");\n"

vm_transpiler_c["NET_RECV"] = proc(d0, d1, d2: string): string =
    return "    " & resolveC(d0) & " = gvm_net_recv(UNTAG(" & resolveC(d1) & "), UNTAG(" & resolveC(d2) & "));\n"

vm_transpiler_c["NET_CLOSE"] = proc(d0, d1, d2: string): string =
    return "    gvm_net_close(UNTAG(" & resolveC(d0) & "));\n"

vm_transpiler_c["UPD"] = proc(d0, d1, d2: string): string =
    return "    " & resolveC(d0) & " = " & resolveC(d1) & ";\n"

vm_transpiler_c["CALLD"] = proc(d0, d1, d2: string): string =
    let retLabel = getUniqueLabel("RET_ADDR")
    var s = "    stack[--rsp] = (long long)&&" & retLabel & ";\n"
    # Dereference and jump to the function pointer
    s &= "    goto *(void*)" & resolveC(d1) & ";\n"
    s &= retLabel & ":\n"

    if d2 != "0":
        let popSize = parseInt(d2)
        s &= "    rsp += " & $popSize & ";\n"

    s &= "    " & resolveC(d0) & " = sra;\n"
    return s

vm_transpiler_c["EXPO"] = proc(d0, d1, d2: string): string =
    # C handles global scope natively, so we just comment it for debugging
    return "    // EXPORT " & d0.replace("[", "").replace("]", "") & "\n"

vm_transpiler_c["ETRN"] = proc(d0, d1, d2: string): string =
    var s = "    // FFI SHIELD\n"
    # Call the external function and immediately tag the return value
    let funcName = d0.replace("[", "").replace("]", "")
    s &= "    sra = ((long long)" & funcName & "() << 1) | 1;\n"
    return s

vm_transpiler_c["JF"] = proc(d0, d1, d2: string): string =
    return "    if (" & resolveC(d0) & " == 1) goto " & d1 & ";\n"

vm_transpiler_c["CMP"] = proc(d0, d1, d2: string): string =
    # Inline the string vs integer comparison from your runtime_eq block
    var s = "    if (" & resolveC(d0) & " != 0 && " & resolveC(d1) & " != 0 && (" & resolveC(d0) & " & 7) == 0 && (" & resolveC(d1) & " & 7) == 0) {\n"
    s &= "        sra = (strcmp((char*)" & resolveC(d0) & ", (char*)" & resolveC(d1) & ") == 0) ? 1 : 0;\n"
    s &= "    } else {\n"
    s &= "        sra = (" & resolveC(d0) & " == " & resolveC(d1) & ") ? 1 : 0;\n"
    s &= "    }\n"

    if d2 != "" and d2 != "00":
        s &= "    " & resolveC(d2) & " = sra;\n"
    return s

vm_transpiler_c["WRITE"] = proc(d0, d1, d2: string): string =
    var arg = d0
    if arg.startsWith("[\"") and arg.endsWith("\"]"):
        let content = arg[2..^3].replace("\\n", "\\n")
        return "    printf(\"%s\", \"" & content & "\");\n"
    return "    printf(\"%lld\", UNTAG(" & resolveC(arg) & "));\n"

vm_transpiler_c["WRITES"] = proc(d0, d1, d2: string): string =
    return "    printf(\"%s\", (char*)" & resolveC(d0) & ");\n"

vm_transpiler_c["READ"] = proc(d0, d1, d2: string): string =
    var s = "    {\n"
    s &= "        char* buf = malloc(2048);\n"
    s &= "        if (fgets(buf, 2048, stdin) != NULL) {\n"
    s &= "            buf[strcspn(buf, \"\\n\")] = 0;\n"  # Strip trailing newline
    s &= "            " & resolveC(d0) & " = (long long)buf;\n"
    s &= "        } else {\n"
    s &= "            " & resolveC(d0) & " = (long long)\"\";\n"
    s &= "        }\n"
    s &= "    }\n"
    return s
# --- Floats ---
vm_transpiler_c["MOVSD"] = proc(d0, d1, d2: string): string =
    return "    " & d1.replace("%", "") & " = " & resolveC(d0) & ";\n"

vm_transpiler_c["FSTORE"] = proc(d0, d1, d2: string): string =
    return "    static double " & resolveC(d0) & " = " & d1 & ";\n"

# --- Boilerplate ---
vm_transpiler_c["NOP"] = proc(d0, d1, d2: string): string = return "    // NOP\n"
vm_transpiler_c["__required"] = proc(d0, d1, d2: string): string = return ""
vm_transpiler_c["__makeTemp"] = proc(d0, d1, d2: string): string = return ""
vm_transpiler_c["__finalize"] = proc(d0, d1, d2: string): string =
    var str: string = ""
    str &= "    stack[--rsp] = (long long)&&RET_ADDR_INIT;\n"
    str &= "    goto F_main;\n"
    str &= "RET_ADDR_INIT:\n"
    str &= "    rsp = rbp;\n"
    str &= "    rbp = stack[rsp++];\n"
    str &= "    exit(0);\n"
    return str

vm_transpiler_c["__comment"] = proc(d0, d1, d2: string): string =
    var to_append: string = ""
    DebugInformation.add("    " & d1 & " => " & d2)
    to_append &= "-- " & d0
    return to_append

vm_transpiler_c["MOV"] = proc(d0, d1, d2: string): string =
    return "    " & resolveC(d0) & " = " & resolveC(d1) & ";\n"

vm_transpiler_c["NSUB"] = proc(d0, d1, d2: string): string =
    return "    rsp -= " & resolveC(d0) & ";\n"

vm_transpiler_c["NADD"] = proc(d0, d1, d2: string): string =
    return "    rsp += " & resolveC(d0) & ";\n"

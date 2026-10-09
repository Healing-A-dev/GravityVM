# ==============================================================================
# GravityVM Transpiler Template: transpiler.nim
# Replace <LANGUAGE_NAME> with your backend identifier (e.g. ruby, rust, go)
# ==============================================================================

import tables
import strutils
import ../../../../core/memory

var vm_transpiler_<LANGUAGE_NAME>* = initTable[string, proc(d0: string, d1: string, d2: string): string]()
var labelCounter = 0
var isFirstLabel = true

# ==============================================================================
# Operand Resolver Helper
# Resolves GravityVM bytecode operands (registers, stack offsets, pools, literals)
# to target language expressions.
# ==============================================================================
proc resolve<LANGUAGE_NAME>(arg: string): string =
    if arg.len == 0 or arg == "0": return "0"
    let cleanArg = arg.strip().replace("!", "").replace("[", "").replace("]", "")

    # Virtual Registers
    if cleanArg == "%rax" or cleanArg == "sra": return "sra"
    if cleanArg == "%rbx" or cleanArg == "srb": return "srb"
    if cleanArg == "%rcx" or cleanArg == "src": return "src"
    if cleanArg == "%rdx" or cleanArg == "srd": return "srd"
    if cleanArg == "%rsp" or cleanArg == "rsp": return "rsp"
    if cleanArg == "%rbp" or cleanArg == "rbp": return "rbp"
    if cleanArg in ["%rdi", "%rsi", "%rdx", "%rcx", "%r8", "%r9"]:
        return "B" & cleanArg[1..^1]
    if cleanArg == "sre": return "sre"
    if cleanArg == "srnl": return "\"\\n\""

    # Virtual Stack Offsets (8-byte aligned)
    if cleanArg.contains("(%rbp)") or cleanArg.contains("(%rsp)"):
        let offsetStr = cleanArg.replace("(%rbp)", "").replace("(%rsp)", "").replace("$", "")
        var offset = 0
        try: offset = parseInt(offsetStr) div 8
        except: offset = 0
        if offset < 0: return "stack[rbp - " & $(-offset) & "]"
        else: return "stack[rbp + " & $offset & "]"

    # Literals and Memory Pools
    case cleanArg[0]
    of '$':
        let rem = cleanArg[1..^1]
        var isNum = true
        for ch in rem:
            if not ch.isDigit:
                isNum = false; break
        if isNum: return rem
        elif rem.startsWith("str_"): return rem
        else: return rem
    of '@': return "G_" & cleanArg[1..^1]
    of '%': return "B" & cleanArg[1..^1]
    else: return cleanArg

# ==============================================================================
# Boilerplate & Lifecycle Hooks
# ==============================================================================
vm_transpiler_<LANGUAGE_NAME>["__required"] = proc(d0: string, d1: string, d2: string): string =
    labelCounter = 0
    isFirstLabel = true
    return ""

vm_transpiler_<LANGUAGE_NAME>["__makeTemp"] = proc(d0: string, d1: string, d2: string): string = ""

vm_transpiler_<LANGUAGE_NAME>["__finalize"] = proc(d0: string, d1: string, d2: string): string =
    # Emitted after all bytecode instructions are processed.
    # Close switch/loop constructs or emit return trampolines here.
    return ""

vm_transpiler_<LANGUAGE_NAME>["__comment"] = proc(d0: string, d1: string, d2: string): string =
    DebugInformation.add("    " & d1 & " => " & d2)
    return "    // " & d0 & "\n"

# ==============================================================================
# Basic Machine Operations
# ==============================================================================
vm_transpiler_<LANGUAGE_NAME>["NOP"] = proc(d0: string, d1: string, d2: string): string = "    // NOP\n"
vm_transpiler_<LANGUAGE_NAME>["MALLOC"] = proc(d0: string, d1: string, d2: string): string = ""
vm_transpiler_<LANGUAGE_NAME>["FREE"] = proc(d0: string, d1: string, d2: string): string = ""

vm_transpiler_<LANGUAGE_NAME>["STORE"] = proc(d0: string, d1: string, d2: string): string =
    var val = d1
    try:
        discard parseFloat(val)
    except:
        val = val.replace("\n", "\\n")
        if not val.startsWith("\"") and not val.startsWith("'"):
             if val.contains("\""): val = "'" & val & "'"
             else: val = "\"" & val & "\""

    let target = resolve<LANGUAGE_NAME>(d0)
    return "    " & target & " = " & val & ";\n"

vm_transpiler_<LANGUAGE_NAME>["READ"] = proc(d0: string, d1: string, d2: string): string =
    let target = resolve<LANGUAGE_NAME>(d0)
    return "    " & target & " = read_line();\n"

vm_transpiler_<LANGUAGE_NAME>["WRITE"] = proc(d0: string, d1: string, d2: string): string =
    return "    print_string(" & resolve<LANGUAGE_NAME>(d0) & ");\n"

vm_transpiler_<LANGUAGE_NAME>["WRITES"] = proc(d0: string, d1: string, d2: string): string =
    return "    print_string(" & resolve<LANGUAGE_NAME>(d0) & ");\n"

vm_transpiler_<LANGUAGE_NAME>["UPD"] = proc(d0: string, d1: string, d2: string): string =
    return "    " & resolve<LANGUAGE_NAME>(d0) & " = " & resolve<LANGUAGE_NAME>(d1) & ";\n"

vm_transpiler_<LANGUAGE_NAME>["COPY"] = proc(d0: string, d1: string, d2: string): string =
    return "    " & resolve<LANGUAGE_NAME>(d1) & " = " & resolve<LANGUAGE_NAME>(d0) & ";\n"

# ==============================================================================
# Tagged Arithmetic & Logic
# ==============================================================================
vm_transpiler_<LANGUAGE_NAME>["ADD"] = proc(d0: string, d1: string, d2: string): string =
    return "    sra = TAG(UNTAG(" & resolve<LANGUAGE_NAME>(d0) & ") + UNTAG(" & resolve<LANGUAGE_NAME>(d1) & "));\n"

vm_transpiler_<LANGUAGE_NAME>["SUB"] = proc(d0: string, d1: string, d2: string): string =
    return "    sra = TAG(UNTAG(" & resolve<LANGUAGE_NAME>(d0) & ") - UNTAG(" & resolve<LANGUAGE_NAME>(d1) & "));\n"

vm_transpiler_<LANGUAGE_NAME>["MUL"] = proc(d0: string, d1: string, d2: string): string =
    return "    sra = TAG(UNTAG(" & resolve<LANGUAGE_NAME>(d0) & ") * UNTAG(" & resolve<LANGUAGE_NAME>(d1) & "));\n"

vm_transpiler_<LANGUAGE_NAME>["DIV"] = proc(d0: string, d1: string, d2: string): string =
    return "    sra = TAG(Math.floor(UNTAG(" & resolve<LANGUAGE_NAME>(d0) & ") / UNTAG(" & resolve<LANGUAGE_NAME>(d1) & ")));\n"

vm_transpiler_<LANGUAGE_NAME>["EXP"] = proc(d0: string, d1: string, d2: string): string =
    return "    sra = TAG(Math.pow(UNTAG(" & resolve<LANGUAGE_NAME>(d0) & "), UNTAG(" & resolve<LANGUAGE_NAME>(d1) & ")));\n"

vm_transpiler_<LANGUAGE_NAME>["INC"] = proc(d0: string, d1: string, d2: string): string =
    let target = resolve<LANGUAGE_NAME>(d0)
    return "    " & target & " += 2;\n"

vm_transpiler_<LANGUAGE_NAME>["DEC"] = proc(d0: string, d1: string, d2: string): string =
    let target = resolve<LANGUAGE_NAME>(d0)
    return "    " & target & " -= 2;\n"

vm_transpiler_<LANGUAGE_NAME>["LT"] = proc(d0: string, d1: string, d2: string): string =
    var s = "    sra = (UNTAG(" & resolve<LANGUAGE_NAME>(d0) & ") < UNTAG(" & resolve<LANGUAGE_NAME>(d1) & ")) ? 3 : 1;\n"
    if d2 != "" and d2 != "00": s &= "    " & resolve<LANGUAGE_NAME>(d2) & " = sra;\n"
    return s

vm_transpiler_<LANGUAGE_NAME>["GT"] = proc(d0: string, d1: string, d2: string): string =
    var s = "    sra = (UNTAG(" & resolve<LANGUAGE_NAME>(d0) & ") > UNTAG(" & resolve<LANGUAGE_NAME>(d1) & ")) ? 3 : 1;\n"
    if d2 != "" and d2 != "00": s &= "    " & resolve<LANGUAGE_NAME>(d2) & " = sra;\n"
    return s

vm_transpiler_<LANGUAGE_NAME>["CMP"] = proc(d0: string, d1: string, d2: string): string =
    var s = "    sra = (" & resolve<LANGUAGE_NAME>(d0) & " == " & resolve<LANGUAGE_NAME>(d1) & ") ? 3 : 1;\n"
    if d2 != "" and d2 != "00": s &= "    " & resolve<LANGUAGE_NAME>(d2) & " = sra;\n"
    return s

# ==============================================================================
# Control Flow & State Machine
# ==============================================================================
vm_transpiler_<LANGUAGE_NAME>["LBL"] = proc(d0: string, d1: string, d2: string): string =
    let clean = d0.replace("[", "").replace("]", "").replace("$", "")
    return "::" & clean & "::\n"

vm_transpiler_<LANGUAGE_NAME>["JMP"] = proc(d0: string, d1: string, d2: string): string =
    return "    goto " & resolve<LANGUAGE_NAME>(d0).replace("[", "").replace("]", "") & ";\n"

vm_transpiler_<LANGUAGE_NAME>["JNZ"] = proc(d0: string, d1: string, d2: string): string =
    return "    if (sra == 3) goto " & resolve<LANGUAGE_NAME>(d0).replace("[", "").replace("]", "") & ";\n"

vm_transpiler_<LANGUAGE_NAME>["JEZ"] = proc(d0: string, d1: string, d2: string): string =
    return "    if (sra == 0 || sra == 1) goto " & resolve<LANGUAGE_NAME>(d0).replace("[", "").replace("]", "") & ";\n"

vm_transpiler_<LANGUAGE_NAME>["JF"] = proc(d0, d1, d2: string): string =
    return "    if (" & resolve<LANGUAGE_NAME>(d0) & " == 1) goto " & resolve<LANGUAGE_NAME>(d1).replace("[", "").replace("]", "") & ";\n"

vm_transpiler_<LANGUAGE_NAME>["EXIT"] = proc(d0: string, d1: string, d2: string): string =
    # GravityVM entrypoint protocol: EXIT in startup calls F_main before terminating
    inc labelCounter
    let retLabel = "RET_ADDR_" & $labelCounter
    var s = "    rsp -= 1; stack[rsp] = \"" & retLabel & "\";\n"
    s &= "    goto F_main;\n"
    s &= "::" & retLabel & "::\n"
    s &= "    exit_program(UNTAG(" & resolve<LANGUAGE_NAME>(d0) & "));\n"
    return s

# ==============================================================================
# Functions & Stack Calls
# ==============================================================================
vm_transpiler_<LANGUAGE_NAME>["PUSH"] = proc(d0: string, d1: string, d2: string): string =
    return "    rsp -= 1; stack[rsp] = " & resolve<LANGUAGE_NAME>(d0) & ";\n"

vm_transpiler_<LANGUAGE_NAME>["CALL"] = proc(d0: string, d1: string, d2: string): string =
    let funcLabel = resolve<LANGUAGE_NAME>(d0).replace("[", "").replace("]", "")
    if funcLabel.startsWith("F_") or funcLabel.startsWith("L"):
        inc labelCounter
        let retLabel = "RET_ADDR_" & $labelCounter
        var s = "    rsp -= 1; stack[rsp] = \"" & retLabel & "\";\n"
        s &= "    goto " & funcLabel & ";\n"
        s &= "::" & retLabel & "::\n"
        var argCount = 0
        try: argCount = parseInt(d1)
        except: discard
        if argCount > 0: s &= "    rsp += " & $argCount & ";\n"
        if d2 != "" and d2 != "00": s &= "    " & resolve<LANGUAGE_NAME>(d2) & " = sra;\n"
        return s
    else:
        var s = "    sra = gvm_runtime[\"" & funcLabel & "\"]();\n"
        if d2 != "" and d2 != "00": s &= "    " & resolve<LANGUAGE_NAME>(d2) & " = sra;\n"
        return s

vm_transpiler_<LANGUAGE_NAME>["RET"] = proc(d0: string, d1: string, d2: string): string =
    var s = ""
    if d0 != "" and d0 != "0" and d0 != "00": s &= "    sra = " & resolve<LANGUAGE_NAME>(d0) & ";\n"
    s &= "    rsp = rbp; rbp = stack[rsp]; rsp += 1;\n"
    s &= "    ret_target = stack[rsp]; rsp += 1; goto DISPATCH;\n"
    return s

vm_transpiler_<LANGUAGE_NAME>["GETARG"] = proc(d0: string, d1: string, d2: string): string =
    var index = 0
    try: index = parseInt(d1)
    except: discard
    let offset = 2 + index
    return "    " & resolve<LANGUAGE_NAME>(d0) & " = stack[rbp + " & $offset & "];\n"

# ==============================================================================
# Collections (Heap Maps & Arrays)
# ==============================================================================
vm_transpiler_<LANGUAGE_NAME>["NEWMAP"] = proc(d0, d1, d2: string): string =
    return "    " & resolve<LANGUAGE_NAME>(d0) & " = gvm_runtime.new_map();\n"

vm_transpiler_<LANGUAGE_NAME>["NEWARR"] = proc(d0, d1, d2: string): string =
    return "    " & resolve<LANGUAGE_NAME>(d0) & " = gvm_runtime.new_array();\n"

vm_transpiler_<LANGUAGE_NAME>["MSET"] = proc(d0: string, d1: string, d2: string): string =
    return "    Brdi = " & resolve<LANGUAGE_NAME>(d0) & "; Brsi = " & resolve<LANGUAGE_NAME>(d1) & "; Brdx = " & resolve<LANGUAGE_NAME>(d2) & "; gvm_runtime.collection_set();\n"

vm_transpiler_<LANGUAGE_NAME>["MGET"] = proc(d0: string, d1: string, d2: string): string =
    return "    Brdi = " & resolve<LANGUAGE_NAME>(d1) & "; Brsi = " & resolve<LANGUAGE_NAME>(d2) & "; " & resolve<LANGUAGE_NAME>(d0) & " = gvm_runtime.collection_get();\n"

vm_transpiler_<LANGUAGE_NAME>["MLEN"] = proc(d0: string, d1: string, d2: string): string =
    return "    Brdi = " & resolve<LANGUAGE_NAME>(d1) & "; " & resolve<LANGUAGE_NAME>(d0) & " = gvm_runtime.newton_sizeof();\n"

vm_transpiler_<LANGUAGE_NAME>["DEL"] = proc(d0: string, d1: string, d2: string): string =
    return "    Brdi = " & resolve<LANGUAGE_NAME>(d0) & "; Brsi = " & resolve<LANGUAGE_NAME>(d1) & "; gvm_runtime.collection_delete();\n"

# ==============================================================================
# Strings & System Builtins
# ==============================================================================
vm_transpiler_<LANGUAGE_NAME>["STR"] = proc(d0, d1, d2: string): string =
    var hexContent = d1.replace("[", "").replace("]", "")
    var text = ""
    if hexContent.len > 0:
        for i in countup(0, hexContent.len - 2, 2):
            try: text.add(chr(parseHexInt(hexContent[i .. i+1])))
            except: discard
    let label = d0.replace("$", "").replace("!", "").replace("[", "").replace("]", "")
    return "    " & label & " = \"" & text.replace("\"", "\\\"").replace("\n", "\\n") & "\";\n"

vm_transpiler_<LANGUAGE_NAME>["CAT"] = proc(d0, d1, d2: string): string =
    return "    " & resolve<LANGUAGE_NAME>(d0) & " = gvm_str_cat(" & resolve<LANGUAGE_NAME>(d1) & ", " & resolve<LANGUAGE_NAME>(d2) & ");\n"

vm_transpiler_<LANGUAGE_NAME>["TYPEOF"] = proc(d0, d1, d2: string): string =
    return "    " & resolve<LANGUAGE_NAME>(d0) & " = gvm_runtime.get_type_str(" & resolve<LANGUAGE_NAME>(d1) & ");\n"

vm_transpiler_<LANGUAGE_NAME>["ITS"] = proc(d0, d1, d2: string): string =
    return "    " & resolve<LANGUAGE_NAME>(d0) & " = gvm_runtime.runtime_to_string(" & resolve<LANGUAGE_NAME>(d1) & ");\n"

vm_transpiler_<LANGUAGE_NAME>["MOV"] = proc(d0, d1, d2: string): string =
    return "    " & resolve<LANGUAGE_NAME>(d0) & " = " & resolve<LANGUAGE_NAME>(d1) & ";\n"

vm_transpiler_<LANGUAGE_NAME>["NSUB"] = proc(d0, d1, d2: string): string =
    var val = resolve<LANGUAGE_NAME>(d0)
    try: return "    rsp -= " & $(parseInt(val) div 8) & ";\n"
    except: return "    rsp -= (" & val & " / 8);\n"

vm_transpiler_<LANGUAGE_NAME>["NADD"] = proc(d0, d1, d2: string): string =
    var val = resolve<LANGUAGE_NAME>(d0)
    try: return "    rsp += " & $(parseInt(val) div 8) & ";\n"
    except: return "    rsp += (" & val & " / 8);\n"

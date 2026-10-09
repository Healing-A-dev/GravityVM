import tables
import strutils
import ../../../../core/memory

var vm_transpiler_javascript* = initTable[string, proc(d0: string, d1: string, d2: string): string]()
var labelCounter = 0
var isFirstLabel = true

proc resolveJs(arg: string): string =
    if arg.len == 0 or arg == "0": return "0"
    let cleanArg = arg.strip().replace("!", "").replace("[", "").replace("]", "")

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

    if cleanArg.contains("(%rbp)") or cleanArg.contains("(%rsp)"):
        let offsetStr = cleanArg.replace("(%rbp)", "").replace("(%rsp)", "").replace("$", "")
        var offset = 0
        try: offset = parseInt(offsetStr) div 8
        except: offset = 0
        if offset < 0: return "stack[rbp - " & $(-offset) & "]"
        else: return "stack[rbp + " & $offset & "]"

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

# --- Boilerplate ---
vm_transpiler_javascript["__required"] = proc(d0: string, d1: string, d2: string): string =
    labelCounter = 0
    isFirstLabel = true
    return ""
vm_transpiler_javascript["__makeTemp"] = proc(d0: string, d1: string, d2: string): string = ""
vm_transpiler_javascript["__finalize"] = proc(d0: string, d1: string, d2: string): string =
    return "            default:\n                pc = null;\n                break;\n        }\n    }\n"

vm_transpiler_javascript["__comment"] = proc(d0: string, d1: string, d2: string): string =
    DebugInformation.add("    " & d1 & " => " & d2)
    return "            // " & d0 & "\n"

# --- Instructions ---
vm_transpiler_javascript["NOP"] = proc(d0: string, d1: string, d2: string): string = "            // NOP\n"
vm_transpiler_javascript["MALLOC"] = proc(d0: string, d1: string, d2: string): string = ""
vm_transpiler_javascript["FREE"] = proc(d0: string, d1: string, d2: string): string = ""

vm_transpiler_javascript["STORE"] = proc(d0: string, d1: string, d2: string): string =
    var val = d1
    try:
        discard parseFloat(val)
    except:
        val = val.replace("\n", "\\n")
        if not val.startsWith("\"") and not val.startsWith("'"):
             if val.contains("\""): val = "'" & val & "'"
             else: val = "\"" & val & "\""

    let target = resolveJs(d0)
    return "            " & target & " = " & val & ";\n"

vm_transpiler_javascript["READ"] = proc(d0: string, d1: string, d2: string): string =
    let target = resolveJs(d0)
    return "            " & target & " = fs.readFileSync(0, 'utf-8').trim();\n"

vm_transpiler_javascript["WRITE"] = proc(d0: string, d1: string, d2: string): string =
    var src = resolveJs(d0)
    return "            print_string(" & src & ");\n"

vm_transpiler_javascript["WRITES"] = proc(d0: string, d1: string, d2: string): string =
    var src = resolveJs(d0)
    return "            print_string(" & src & ");\n"

vm_transpiler_javascript["UPD"] = proc(d0: string, d1: string, d2: string): string =
    return "            " & resolveJs(d0) & " = " & resolveJs(d1) & ";\n"

# --- Math ---
vm_transpiler_javascript["ADD"] = proc(d0: string, d1: string, d2: string): string =
    return "            sra = TAG(UNTAG(" & resolveJs(d0) & ") + UNTAG(" & resolveJs(d1) & "));\n"

vm_transpiler_javascript["SUB"] = proc(d0: string, d1: string, d2: string): string =
    return "            sra = TAG(UNTAG(" & resolveJs(d0) & ") - UNTAG(" & resolveJs(d1) & "));\n"

vm_transpiler_javascript["MUL"] = proc(d0: string, d1: string, d2: string): string =
    return "            sra = TAG(UNTAG(" & resolveJs(d0) & ") * UNTAG(" & resolveJs(d1) & "));\n"

vm_transpiler_javascript["DIV"] = proc(d0: string, d1: string, d2: string): string =
    return "            sra = TAG(Math.floor(UNTAG(" & resolveJs(d0) & ") / UNTAG(" & resolveJs(d1) & ")));\n"

vm_transpiler_javascript["EXP"] = proc(d0: string, d1: string, d2: string): string =
    return "            sra = TAG(Math.floor(Math.pow(UNTAG(" & resolveJs(d0) & "), UNTAG(" & resolveJs(d1) & "))));\n"

vm_transpiler_javascript["COPY"] = proc(d0: string, d1: string, d2: string): string =
    return "            " & resolveJs(d1) & " = " & resolveJs(d0) & ";\n"

# --- Control Flow ---
vm_transpiler_javascript["LBL"] = proc(d0: string, d1: string, d2: string): string =
    let clean = d0.replace("[", "").replace("]", "").replace("$", "")
    var s = ""
    if isFirstLabel:
        isFirstLabel = false
        s &= "    let pc = \"" & clean & "\";\n"
        s &= "    while (pc !== null) {\n"
        s &= "        switch (pc) {\n"
        s &= "            case \"" & clean & "\":\n"
    else:
        s &= "                pc = \"" & clean & "\"; break;\n"
        s &= "            case \"" & clean & "\":\n"
    if clean.startsWith("F_"):
        s &= "                stack[--rsp] = rbp; rbp = rsp;\n"
    return s

vm_transpiler_javascript["JMP"] = proc(d0: string, d1: string, d2: string): string =
    let target = resolveJs(d0).replace("[", "").replace("]", "")
    return "                pc = \"" & target & "\"; break;\n"

vm_transpiler_javascript["JNZ"] = proc(d0: string, d1: string, d2: string): string =
    let target = resolveJs(d0).replace("[", "").replace("]", "")
    return "                if (sra === 3) { pc = \"" & target & "\"; break; }\n"

vm_transpiler_javascript["JEZ"] = proc(d0: string, d1: string, d2: string): string =
    let target = resolveJs(d0).replace("[", "").replace("]", "")
    return "                if (sra === 0 || sra === 1) { pc = \"" & target & "\"; break; }\n"

vm_transpiler_javascript["JF"] = proc(d0, d1, d2: string): string =
    let target = resolveJs(d1).replace("[", "").replace("]", "")
    return "                if (" & resolveJs(d0) & " === 1) { pc = \"" & target & "\"; break; }\n"

vm_transpiler_javascript["CMP"] = proc(d0: string, d1: string, d2: string): string =
    var s = "            sra = (" & resolveJs(d0) & " === " & resolveJs(d1) & ") ? 3 : 1;\n"
    if d2 != "" and d2 != "00":
        s &= "            " & resolveJs(d2) & " = sra;\n"
    return s

vm_transpiler_javascript["EXIT"] = proc(d0: string, d1: string, d2: string): string =
    inc labelCounter
    let retLabel = "RET_ADDR_" & $labelCounter
    var s = "                stack[--rsp] = \"" & retLabel & "\";\n"
    s &= "                pc = \"F_main\"; break;\n"
    s &= "            case \"" & retLabel & "\":\n"
    s &= "                process.exit(UNTAG(" & resolveJs(d0) & "));\n"
    return s

# --- Logic & Optimization ---
vm_transpiler_javascript["INC"] = proc(d0: string, d1: string, d2: string): string =
    let target = resolveJs(d0)
    return "            " & target & " += 2;\n"

vm_transpiler_javascript["DEC"] = proc(d0: string, d1: string, d2: string): string =
    let target = resolveJs(d0)
    return "            " & target & " -= 2;\n"

vm_transpiler_javascript["LT"] = proc(d0: string, d1: string, d2: string): string =
    var s = "            sra = (UNTAG(" & resolveJs(d0) & ") < UNTAG(" & resolveJs(d1) & ")) ? 3 : 1;\n"
    if d2 != "" and d2 != "00":
        s &= "            " & resolveJs(d2) & " = sra;\n"
    return s

vm_transpiler_javascript["GT"] = proc(d0: string, d1: string, d2: string): string =
    var s = "            sra = (UNTAG(" & resolveJs(d0) & ") > UNTAG(" & resolveJs(d1) & ")) ? 3 : 1;\n"
    if d2 != "" and d2 != "00":
        s &= "            " & resolveJs(d2) & " = sra;\n"
    return s

vm_transpiler_javascript["EQ"] = proc(d0: string, d1: string, d2: string): string =
    var s = "            sra = (" & resolveJs(d0) & " === " & resolveJs(d1) & ") ? 3 : 1;\n"
    if d2 != "" and d2 != "00":
        s &= "            " & resolveJs(d2) & " = sra;\n"
    return s

# --- Function & Stack ---
vm_transpiler_javascript["PUSH"] = proc(d0: string, d1: string, d2: string): string =
    return "            stack[--rsp] = " & resolveJs(d0) & ";\n"

vm_transpiler_javascript["CALL"] = proc(d0: string, d1: string, d2: string): string =
    let funcLabel = resolveJs(d0).replace("[", "").replace("]", "")
    if funcLabel.startsWith("F_") or funcLabel.startsWith("L"):
        inc labelCounter
        let retLabel = "RET_ADDR_" & $labelCounter
        var s = "            stack[--rsp] = \"" & retLabel & "\";\n"
        s &= "            pc = \"" & funcLabel & "\"; break;\n"
        s &= "        case \"" & retLabel & "\":\n"
        var argCount = 0
        try: argCount = parseInt(d1)
        except: discard
        if argCount > 0:
            s &= "            rsp += " & $argCount & ";\n"
        if d2 != "" and d2 != "00":
            s &= "            " & resolveJs(d2) & " = sra;\n"
        return s
    else:
        var s = "            sra = gvm_runtime[\"" & funcLabel & "\"]();\n"
        if d2 != "" and d2 != "00":
            s &= "            " & resolveJs(d2) & " = sra;\n"
        return s

vm_transpiler_javascript["RET"] = proc(d0: string, d1: string, d2: string): string =
    var s = ""
    if d0 != "" and d0 != "0" and d0 != "00":
        s &= "            sra = " & resolveJs(d0) & ";\n"
    s &= "            rsp = rbp; rbp = stack[rsp++]; pc = stack[rsp++]; break;\n"
    return s

vm_transpiler_javascript["GETARG"] = proc(d0: string, d1: string, d2: string): string =
    var index = 0
    try: index = parseInt(d1)
    except: discard
    let offset = 2 + index
    return "            " & resolveJs(d0) & " = stack[rbp + " & $offset & "];\n"

vm_transpiler_javascript["CALLD"] = proc(d0, d1, d2: string): string =
    return "            // CALLD not supported in pure script\n"

vm_transpiler_javascript["EXPO"] = proc(d0, d1, d2: string): string =
    return "// EXPORT " & d0 & "\n"

vm_transpiler_javascript["ETRN"] = proc(d0, d1, d2: string): string =
    return "            // ETRN " & d0 & "\n"

# --- Collections ---
vm_transpiler_javascript["NEWMAP"] = proc(d0, d1, d2: string): string =
    return "            " & resolveJs(d0) & " = gvm_runtime.new_map();\n"

vm_transpiler_javascript["MSET"] = proc(d0: string, d1: string, d2: string): string =
    return "            Brdi = " & resolveJs(d0) & "; Brsi = " & resolveJs(d1) & "; Brdx = " & resolveJs(d2) & "; gvm_runtime.collection_set();\n"

vm_transpiler_javascript["MGET"] = proc(d0: string, d1: string, d2: string): string =
    return "            Brdi = " & resolveJs(d1) & "; Brsi = " & resolveJs(d2) & "; " & resolveJs(d0) & " = gvm_runtime.collection_get();\n"

vm_transpiler_javascript["MLEN"] = proc(d0: string, d1: string, d2: string): string =
    return "            Brdi = " & resolveJs(d1) & "; " & resolveJs(d0) & " = gvm_runtime.newton_sizeof();\n"

vm_transpiler_javascript["MHEAD"] = proc(d0, d1, d2: string): string = return "            " & resolveJs(d0) & " = 0;\n"
vm_transpiler_javascript["MKEY"] = proc(d0, d1, d2: string): string = return "            " & resolveJs(d0) & " = 0;\n"
vm_transpiler_javascript["MVAL"] = proc(d0, d1, d2: string): string = return "            " & resolveJs(d0) & " = 0;\n"
vm_transpiler_javascript["MNEXT"] = proc(d0, d1, d2: string): string = return "            " & resolveJs(d0) & " = 0;\n"
vm_transpiler_javascript["DEL"] = proc(d0: string, d1: string, d2: string): string =
    return "            Brdi = " & resolveJs(d0) & "; Brsi = " & resolveJs(d1) & "; gvm_runtime.collection_delete();\n"

vm_transpiler_javascript["NEWARR"] = proc(d0, d1, d2: string): string =
    return "            " & resolveJs(d0) & " = gvm_runtime.new_array();\n"

# --- Strings & Types ---
vm_transpiler_javascript["STR"] = proc(d0, d1, d2: string): string =
    var hexContent = d1.replace("[", "").replace("]", "")
    var text = ""
    if hexContent.len > 0:
        for i in countup(0, hexContent.len - 2, 2):
            try: text.add(chr(parseHexInt(hexContent[i .. i+1])))
            except: discard
    let label = d0.replace("$", "").replace("!", "").replace("[", "").replace("]", "")
    return "    const " & label & " = \"" & text.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n") & "\";\n"

vm_transpiler_javascript["CAT"] = proc(d0, d1, d2: string): string =
    return "            " & resolveJs(d0) & " = gvm_str_cat(" & resolveJs(d1) & ", " & resolveJs(d2) & ");\n"

vm_transpiler_javascript["TYPEOF"] = proc(d0, d1, d2: string): string =
    return "            " & resolveJs(d0) & " = gvm_runtime.get_type_str(" & resolveJs(d1) & ");\n"

vm_transpiler_javascript["ITS"] = proc(d0, d1, d2: string): string =
    return "            " & resolveJs(d0) & " = gvm_runtime.runtime_to_string(" & resolveJs(d1) & ");\n"

vm_transpiler_javascript["ARGV"] = proc(d0, d1, d2: string): string =
    return "            let _idx = UNTAG(" & resolveJs(d0) & "); " & resolveJs(d1) & " = process.argv[_idx] || \"\";\n"

# --- File I/O ---
vm_transpiler_javascript["FOPEN"] = proc(d0, d1, d2: string): string =
    return "            " & resolveJs(d0) & " = fs.openSync(" & resolveJs(d1) & ", 'r');\n"

vm_transpiler_javascript["FWRITE"] = proc(d0: string, d1: string, d2: string): string =
    return "            if (" & resolveJs(d0) & ") fs.writeSync(" & resolveJs(d0) & ", String(" & resolveJs(d1) & "));\n"

vm_transpiler_javascript["FREAD"] = proc(d0: string, d1: string, d2: string): string =
    return "            if (" & resolveJs(d1) & ") " & resolveJs(d0) & " = fs.readFileSync(" & resolveJs(d1) & ", 'utf-8');\n"

vm_transpiler_javascript["READF"] = proc(d0: string, d1: string, d2: string): string =
    return "            " & resolveJs(d0) & " = fs.readFileSync(" & resolveJs(d1) & ", 'utf-8');\n"

vm_transpiler_javascript["FCLOSE"] = proc(d0: string, d1: string, d2: string): string =
    return "            if (" & resolveJs(d0) & ") fs.closeSync(" & resolveJs(d0) & ");\n"

# --- Floats & Regs ---
vm_transpiler_javascript["MOVSD"] = proc(d0, d1, d2: string): string =
    return "            " & resolveJs(d1) & " = " & resolveJs(d0) & ";\n"

vm_transpiler_javascript["FSTORE"] = proc(d0, d1, d2: string): string =
    return "            " & resolveJs(d0) & " = " & d1 & ";\n"

vm_transpiler_javascript["MOV"] = proc(d0, d1, d2: string): string =
    return "            " & resolveJs(d0) & " = " & resolveJs(d1) & ";\n"

vm_transpiler_javascript["NSUB"] = proc(d0, d1, d2: string): string =
    var val = resolveJs(d0)
    try:
        let intVal = parseInt(val)
        return "            rsp -= " & $(intVal div 8) & ";\n"
    except:
        return "            rsp -= Math.floor(" & val & " / 8);\n"

vm_transpiler_javascript["NADD"] = proc(d0, d1, d2: string): string =
    var val = resolveJs(d0)
    try:
        let intVal = parseInt(val)
        return "            rsp += " & $(intVal div 8) & ";\n"
    except:
        return "            rsp += Math.floor(" & val & " / 8);\n"

# --- Networking stubs ---
vm_transpiler_javascript["NET_SOCKET"] = proc(d0, d1, d2: string): string = return "            " & resolveJs(d0) & " = 0;\n"
vm_transpiler_javascript["NET_BIND"] = proc(d0, d1, d2: string): string = return ""
vm_transpiler_javascript["NET_LISTEN"] = proc(d0, d1, d2: string): string = return ""
vm_transpiler_javascript["NET_ACCEPT"] = proc(d0, d1, d2: string): string = return "            " & resolveJs(d0) & " = 0;\n"
vm_transpiler_javascript["NET_WRITE"] = proc(d0, d1, d2: string): string = return ""
vm_transpiler_javascript["NET_CLOSE"] = proc(d0, d1, d2: string): string = return ""
vm_transpiler_javascript["NET_RECV"] = proc(d0, d1, d2: string): string = return "            " & resolveJs(d0) & " = \"\";\n"

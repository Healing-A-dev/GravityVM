import tables
import strutils
import ../../../../core/memory

var vm_transpiler_python* = initTable[string, proc(d0: string, d1: string, d2: string): string]()
var labelCounter = 0
var isFirstLabel = true

proc resolvePy(arg: string): string =
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
vm_transpiler_python["__required"] = proc(d0: string, d1: string, d2: string): string =
    labelCounter = 0
    isFirstLabel = true
    return ""
vm_transpiler_python["__makeTemp"] = proc(d0: string, d1: string, d2: string): string = ""
vm_transpiler_python["__finalize"] = proc(d0: string, d1: string, d2: string): string =
    return "        else:\n            break\n"

vm_transpiler_python["__comment"] = proc(d0: string, d1: string, d2: string): string =
    DebugInformation.add("    " & d1 & " => " & d2)
    let indent = if isFirstLabel: "    " else: "            "
    return indent & "# " & d0 & "\n"

# --- Instructions ---
vm_transpiler_python["NOP"] = proc(d0: string, d1: string, d2: string): string = "            pass\n"
vm_transpiler_python["MALLOC"] = proc(d0: string, d1: string, d2: string): string = ""
vm_transpiler_python["FREE"] = proc(d0: string, d1: string, d2: string): string = ""

vm_transpiler_python["STORE"] = proc(d0: string, d1: string, d2: string): string =
    var val = d1
    try:
        discard parseFloat(val)
    except:
        val = val.replace("\n", "\\n")
        if not val.startsWith("\"") and not val.startsWith("'"):
             if val.contains("\""): val = "'" & val & "'"
             else: val = "\"" & val & "\""

    let target = resolvePy(d0)
    let indent = if target.startsWith("stack["): "            " else: "    "
    return indent & target & " = " & val & "\n"

vm_transpiler_python["READ"] = proc(d0: string, d1: string, d2: string): string =
    let target = resolvePy(d0)
    return "            " & target & " = sys.stdin.readline().strip()\n"

vm_transpiler_python["WRITE"] = proc(d0: string, d1: string, d2: string): string =
    var src = resolvePy(d0)
    return "            print_string(" & src & ")\n"

vm_transpiler_python["WRITES"] = proc(d0: string, d1: string, d2: string): string =
    var src = resolvePy(d0)
    return "            print_string(" & src & ")\n"

vm_transpiler_python["UPD"] = proc(d0: string, d1: string, d2: string): string =
    return "            " & resolvePy(d0) & " = " & resolvePy(d1) & "\n"

# --- Math ---
vm_transpiler_python["ADD"] = proc(d0: string, d1: string, d2: string): string =
    return "            sra = TAG(UNTAG(" & resolvePy(d0) & ") + UNTAG(" & resolvePy(d1) & "))\n"

vm_transpiler_python["SUB"] = proc(d0: string, d1: string, d2: string): string =
    return "            sra = TAG(UNTAG(" & resolvePy(d0) & ") - UNTAG(" & resolvePy(d1) & "))\n"

vm_transpiler_python["MUL"] = proc(d0: string, d1: string, d2: string): string =
    return "            sra = TAG(UNTAG(" & resolvePy(d0) & ") * UNTAG(" & resolvePy(d1) & "))\n"

vm_transpiler_python["DIV"] = proc(d0: string, d1: string, d2: string): string =
    return "            sra = TAG(UNTAG(" & resolvePy(d0) & ") // UNTAG(" & resolvePy(d1) & "))\n"

vm_transpiler_python["EXP"] = proc(d0: string, d1: string, d2: string): string =
    return "            sra = TAG(UNTAG(" & resolvePy(d0) & ") ** UNTAG(" & resolvePy(d1) & "))\n"

vm_transpiler_python["COPY"] = proc(d0: string, d1: string, d2: string): string =
    return "            " & resolvePy(d1) & " = " & resolvePy(d0) & "\n"

# --- Control Flow & Block State Machine ---
vm_transpiler_python["LBL"] = proc(d0: string, d1: string, d2: string): string =
    let clean = d0.replace("[", "").replace("]", "").replace("$", "")
    var s = ""
    if isFirstLabel:
        isFirstLabel = false
        s &= "    pc = \"" & clean & "\"\n"
        s &= "    while pc is not None:\n"
        s &= "        if pc == \"" & clean & "\":\n"
    else:
        s &= "            pc = \"" & clean & "\"; continue\n"
        s &= "        elif pc == \"" & clean & "\":\n"
    if clean.startsWith("F_"):
        s &= "            rsp -= 1; stack[rsp] = rbp; rbp = rsp\n"
    return s

vm_transpiler_python["JMP"] = proc(d0: string, d1: string, d2: string): string =
    let target = resolvePy(d0).replace("[", "").replace("]", "")
    return "            pc = \"" & target & "\"; continue\n"

vm_transpiler_python["JNZ"] = proc(d0: string, d1: string, d2: string): string =
    let target = resolvePy(d0).replace("[", "").replace("]", "")
    return "            if sra == 3: pc = \"" & target & "\"; continue\n"

vm_transpiler_python["JEZ"] = proc(d0: string, d1: string, d2: string): string =
    let target = resolvePy(d0).replace("[", "").replace("]", "")
    return "            if sra == 0 or sra == 1: pc = \"" & target & "\"; continue\n"

vm_transpiler_python["JF"] = proc(d0, d1, d2: string): string =
    let target = resolvePy(d1).replace("[", "").replace("]", "")
    return "            if " & resolvePy(d0) & " == 1: pc = \"" & target & "\"; continue\n"

vm_transpiler_python["CMP"] = proc(d0: string, d1: string, d2: string): string =
    var s = "            sra = 3 if (" & resolvePy(d0) & " == " & resolvePy(d1) & ") else 1\n"
    if d2 != "" and d2 != "00":
        s &= "            " & resolvePy(d2) & " = sra\n"
    return s

vm_transpiler_python["EXIT"] = proc(d0: string, d1: string, d2: string): string =
    inc labelCounter
    let retLabel = "RET_ADDR_" & $labelCounter
    var s = "            rsp -= 1; stack[rsp] = \"" & retLabel & "\"\n"
    s &= "            pc = \"F_main\"; continue\n"
    s &= "        elif pc == \"" & retLabel & "\":\n"
    s &= "            sys.exit(UNTAG(" & resolvePy(d0) & "))\n"
    return s

# --- Logic & Optimization ---
vm_transpiler_python["INC"] = proc(d0: string, d1: string, d2: string): string =
    let target = resolvePy(d0)
    return "            " & target & " += 2\n"

vm_transpiler_python["DEC"] = proc(d0: string, d1: string, d2: string): string =
    let target = resolvePy(d0)
    return "            " & target & " -= 2\n"

vm_transpiler_python["LT"] = proc(d0: string, d1: string, d2: string): string =
    var s = "            sra = 3 if (UNTAG(" & resolvePy(d0) & ") < UNTAG(" & resolvePy(d1) & ")) else 1\n"
    if d2 != "" and d2 != "00":
        s &= "            " & resolvePy(d2) & " = sra\n"
    return s

vm_transpiler_python["GT"] = proc(d0: string, d1: string, d2: string): string =
    var s = "            sra = 3 if (UNTAG(" & resolvePy(d0) & ") > UNTAG(" & resolvePy(d1) & ")) else 1\n"
    if d2 != "" and d2 != "00":
        s &= "            " & resolvePy(d2) & " = sra\n"
    return s

vm_transpiler_python["EQ"] = proc(d0: string, d1: string, d2: string): string =
    var s = "            sra = 3 if (" & resolvePy(d0) & " == " & resolvePy(d1) & ") else 1\n"
    if d2 != "" and d2 != "00":
        s &= "            " & resolvePy(d2) & " = sra\n"
    return s

# --- Function & Stack ---
vm_transpiler_python["PUSH"] = proc(d0: string, d1: string, d2: string): string =
    return "            rsp -= 1; stack[rsp] = " & resolvePy(d0) & "\n"

vm_transpiler_python["CALL"] = proc(d0: string, d1: string, d2: string): string =
    let funcLabel = resolvePy(d0).replace("[", "").replace("]", "")
    if funcLabel.startsWith("F_") or funcLabel.startsWith("L"):
        inc labelCounter
        let retLabel = "RET_ADDR_" & $labelCounter
        var s = "            rsp -= 1; stack[rsp] = \"" & retLabel & "\"\n"
        s &= "            pc = \"" & funcLabel & "\"; continue\n"
        s &= "        elif pc == \"" & retLabel & "\":\n"
        var argCount = 0
        try: argCount = parseInt(d1)
        except: discard
        if argCount > 0:
            s &= "            rsp += " & $argCount & "\n"
        if d2 != "" and d2 != "00":
            s &= "            " & resolvePy(d2) & " = sra\n"
        return s
    else:
        var s = "            sra = gvm_runtime[\"" & funcLabel & "\"]()\n"
        if d2 != "" and d2 != "00":
            s &= "            " & resolvePy(d2) & " = sra\n"
        return s

vm_transpiler_python["RET"] = proc(d0: string, d1: string, d2: string): string =
    var s = ""
    if d0 != "" and d0 != "0" and d0 != "00":
        s &= "            sra = " & resolvePy(d0) & "\n"
    s &= "            rsp = rbp; rbp = stack[rsp]; rsp += 1; pc = stack[rsp]; rsp += 1; continue\n"
    return s

vm_transpiler_python["GETARG"] = proc(d0: string, d1: string, d2: string): string =
    var index = 0
    try: index = parseInt(d1)
    except: discard
    let offset = 2 + index
    return "            " & resolvePy(d0) & " = stack[rbp + " & $offset & "]\n"

vm_transpiler_python["CALLD"] = proc(d0, d1, d2: string): string =
    return "            # CALLD not supported in pure script\n"

vm_transpiler_python["EXPO"] = proc(d0, d1, d2: string): string =
    return "# EXPORT " & d0 & "\n"

vm_transpiler_python["ETRN"] = proc(d0, d1, d2: string): string =
    return "            # ETRN " & d0 & "\n"

# --- Collections ---
vm_transpiler_python["NEWMAP"] = proc(d0, d1, d2: string): string =
    return "            " & resolvePy(d0) & " = gvm_runtime[\"new_map\"]()\n"

vm_transpiler_python["MSET"] = proc(d0: string, d1: string, d2: string): string =
    return "            Brdi = " & resolvePy(d0) & "; Brsi = " & resolvePy(d1) & "; Brdx = " & resolvePy(d2) & "; gvm_runtime[\"collection_set\"]()\n"

vm_transpiler_python["MGET"] = proc(d0: string, d1: string, d2: string): string =
    return "            Brdi = " & resolvePy(d1) & "; Brsi = " & resolvePy(d2) & "; " & resolvePy(d0) & " = gvm_runtime[\"collection_get\"]()\n"

vm_transpiler_python["MLEN"] = proc(d0: string, d1: string, d2: string): string =
    return "            Brdi = " & resolvePy(d1) & "; " & resolvePy(d0) & " = gvm_runtime[\"newton_sizeof\"]()\n"

vm_transpiler_python["MHEAD"] = proc(d0, d1, d2: string): string = return "            " & resolvePy(d0) & " = 0\n"
vm_transpiler_python["MKEY"] = proc(d0, d1, d2: string): string = return "            " & resolvePy(d0) & " = 0\n"
vm_transpiler_python["MVAL"] = proc(d0, d1, d2: string): string = return "            " & resolvePy(d0) & " = 0\n"
vm_transpiler_python["MNEXT"] = proc(d0, d1, d2: string): string = return "            " & resolvePy(d0) & " = 0\n"
vm_transpiler_python["DEL"] = proc(d0: string, d1: string, d2: string): string =
    return "            Brdi = " & resolvePy(d0) & "; Brsi = " & resolvePy(d1) & "; gvm_runtime[\"collection_delete\"]()\n"

vm_transpiler_python["NEWARR"] = proc(d0, d1, d2: string): string =
    return "            " & resolvePy(d0) & " = gvm_runtime[\"new_array\"]()\n"

# --- Strings & Types ---
vm_transpiler_python["STR"] = proc(d0, d1, d2: string): string =
    var hexContent = d1.replace("[", "").replace("]", "")
    var text = ""
    if hexContent.len > 0:
        for i in countup(0, hexContent.len - 2, 2):
            try: text.add(chr(parseHexInt(hexContent[i .. i+1])))
            except: discard
    let label = d0.replace("$", "").replace("!", "").replace("[", "").replace("]", "")
    return "    " & label & " = \"" & text.replace("\\", "\\\\").replace("\"", "\\\"").replace("\n", "\\n") & "\"\n"

vm_transpiler_python["CAT"] = proc(d0, d1, d2: string): string =
    return "            " & resolvePy(d0) & " = gvm_str_cat(" & resolvePy(d1) & ", " & resolvePy(d2) & ")\n"

vm_transpiler_python["TYPEOF"] = proc(d0, d1, d2: string): string =
    return "            " & resolvePy(d0) & " = gvm_runtime[\"get_type_str\"](" & resolvePy(d1) & ")\n"

vm_transpiler_python["ITS"] = proc(d0, d1, d2: string): string =
    return "            " & resolvePy(d0) & " = gvm_runtime[\"runtime_to_string\"](" & resolvePy(d1) & ")\n"

vm_transpiler_python["ARGV"] = proc(d0, d1, d2: string): string =
    return "            idx = UNTAG(" & resolvePy(d0) & "); " & resolvePy(d1) & " = sys.argv[idx] if idx < len(sys.argv) else \"\"\n"

# --- File I/O ---
vm_transpiler_python["FOPEN"] = proc(d0, d1, d2: string): string =
    return "            " & resolvePy(d0) & " = open(" & resolvePy(d1) & ", 'r')\n"

vm_transpiler_python["FWRITE"] = proc(d0: string, d1: string, d2: string): string =
    return "            if " & resolvePy(d0) & ": " & resolvePy(d0) & ".write(str(" & resolvePy(d1) & "))\n"

vm_transpiler_python["FREAD"] = proc(d0: string, d1: string, d2: string): string =
    return "            " & resolvePy(d0) & " = " & resolvePy(d1) & ".read()\n"

vm_transpiler_python["READF"] = proc(d0: string, d1: string, d2: string): string =
    return "            with open(" & resolvePy(d1) & ", 'r') as _f: " & resolvePy(d0) & " = _f.read()\n"

vm_transpiler_python["FCLOSE"] = proc(d0: string, d1: string, d2: string): string =
    return "            if " & resolvePy(d0) & ": " & resolvePy(d0) & ".close()\n"

# --- Floats & Regs ---
vm_transpiler_python["MOVSD"] = proc(d0, d1, d2: string): string =
    return "            " & resolvePy(d1) & " = " & resolvePy(d0) & "\n"

vm_transpiler_python["FSTORE"] = proc(d0, d1, d2: string): string =
    let target = resolvePy(d0)
    let indent = if target.startsWith("stack["): "            " else: "    "
    return indent & target & " = " & d1 & "\n"

vm_transpiler_python["MOV"] = proc(d0, d1, d2: string): string =
    return "            " & resolvePy(d0) & " = " & resolvePy(d1) & "\n"

vm_transpiler_python["NSUB"] = proc(d0, d1, d2: string): string =
    var val = resolvePy(d0)
    try:
        let intVal = parseInt(val)
        return "            rsp -= " & $(intVal div 8) & "\n"
    except:
        return "            rsp -= (" & val & " // 8)\n"

vm_transpiler_python["NADD"] = proc(d0, d1, d2: string): string =
    var val = resolvePy(d0)
    try:
        let intVal = parseInt(val)
        return "            rsp += " & $(intVal div 8) & "\n"
    except:
        return "            rsp += (" & val & " // 8)\n"

# --- Networking stubs ---
vm_transpiler_python["NET_SOCKET"] = proc(d0, d1, d2: string): string = return "            " & resolvePy(d0) & " = 0\n"
vm_transpiler_python["NET_BIND"] = proc(d0, d1, d2: string): string = return ""
vm_transpiler_python["NET_LISTEN"] = proc(d0, d1, d2: string): string = return ""
vm_transpiler_python["NET_ACCEPT"] = proc(d0, d1, d2: string): string = return "            " & resolvePy(d0) & " = 0\n"
vm_transpiler_python["NET_WRITE"] = proc(d0, d1, d2: string): string = return ""
vm_transpiler_python["NET_CLOSE"] = proc(d0, d1, d2: string): string = return ""
vm_transpiler_python["NET_RECV"] = proc(d0, d1, d2: string): string = return "            " & resolvePy(d0) & " = \"\"\n"

import tables
import strutils
import ../../../../core/memory

var vm_transpiler_lua* = initTable[string, proc(d0: string, d1: string, d2: string): string]()
var labels: seq[string] = @[]
var returnLabels: seq[string] = @[]
var labelCounter = 0

proc append(to: var string, data: string): string {.discardable.} =
    to = to & data & "\n"
    return to

proc resolveLua(arg: string): string =
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
    if cleanArg == "srnl": return "srnl"

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
        else: return "L" & rem
    of '@': return "G_" & cleanArg[1..^1]
    of '%': return "B" & cleanArg[1..^1]
    else: return cleanArg

# --- Boilerplate ---
vm_transpiler_lua["__required"] = proc(d0: string, d1: string, d2: string): string =
    returnLabels.setLen(0)
    labelCounter = 0
    return ""
vm_transpiler_lua["__makeTemp"] = proc(d0: string, d1: string, d2: string): string = ""
vm_transpiler_lua["__finalize"] = proc(d0: string, d1: string, d2: string): string =
    var s = "::DISPATCH::\n"
    for i, lbl in returnLabels:
        if i == 0:
            s &= "    if ret_target == \"" & lbl & "\" then goto " & lbl & "\n"
        else:
            s &= "    elseif ret_target == \"" & lbl & "\" then goto " & lbl & "\n"
    s &= "    end\n"
    return s

vm_transpiler_lua["__comment"] = proc(d0: string, d1: string, d2: string): string =
    DebugInformation.add("    " & d1 & " => " & d2)
    return "-- " & d0 & "\n"

# --- Instructions ---
vm_transpiler_lua["NOP"] = proc(d0: string, d1: string, d2: string): string = ""
vm_transpiler_lua["MALLOC"] = proc(d0: string, d1: string, d2: string): string = ""
vm_transpiler_lua["FREE"] = proc(d0: string, d1: string, d2: string): string = ""

vm_transpiler_lua["STORE"] = proc(d0: string, d1: string, d2: string): string =
    var val = d1
    try:
        discard parseFloat(val)
    except:
        val = val.replace("\n", "\\n")
        if not val.startsWith("\"") and not val.startsWith("'"):
             if val.contains("\""): val = "'" & val & "'"
             else: val = "\"" & val & "\""

    let target = resolveLua(d0)
    return "    " & target & " = " & val & "\n"

vm_transpiler_lua["READ"] = proc(d0: string, d1: string, d2: string): string =
    let target = resolveLua(d0)
    return "    " & target & " = io.read()\n"

vm_transpiler_lua["WRITE"] = proc(d0: string, d1: string, d2: string): string =
    var src = resolveLua(d0)
    return "    print_string(" & src & ")\n"

vm_transpiler_lua["WRITES"] = proc(d0: string, d1: string, d2: string): string =
    var src = resolveLua(d0)
    return "    print_string(" & src & ")\n"

vm_transpiler_lua["UPD"] = proc(d0: string, d1: string, d2: string): string =
    return "    " & resolveLua(d0) & " = " & resolveLua(d1) & "\n"

# --- Math ---
vm_transpiler_lua["ADD"] = proc(d0: string, d1: string, d2: string): string =
    return "    sra = TAG(UNTAG(" & resolveLua(d0) & ") + UNTAG(" & resolveLua(d1) & "))\n"

vm_transpiler_lua["SUB"] = proc(d0: string, d1: string, d2: string): string =
    return "    sra = TAG(UNTAG(" & resolveLua(d0) & ") - UNTAG(" & resolveLua(d1) & "))\n"

vm_transpiler_lua["MUL"] = proc(d0: string, d1: string, d2: string): string =
    return "    sra = TAG(UNTAG(" & resolveLua(d0) & ") * UNTAG(" & resolveLua(d1) & "))\n"

vm_transpiler_lua["DIV"] = proc(d0: string, d1: string, d2: string): string =
    return "    sra = TAG(math.floor(UNTAG(" & resolveLua(d0) & ") / UNTAG(" & resolveLua(d1) & ")))\n"

vm_transpiler_lua["EXP"] = proc(d0: string, d1: string, d2: string): string =
    return "    sra = TAG(math.floor(UNTAG(" & resolveLua(d0) & ") ^ UNTAG(" & resolveLua(d1) & ")))\n"

vm_transpiler_lua["COPY"] = proc(d0: string, d1: string, d2: string): string =
    return "    " & resolveLua(d1) & " = " & resolveLua(d0) & "\n"

# --- Control Flow ---
vm_transpiler_lua["LBL"] = proc(d0: string, d1: string, d2: string): string =
    let v1 = resolveLua(d0).replace("[", "").replace("]", "")
    if v1 == "ENTRY":
        return "::ENTRY::\n"
    var s = "::" & v1 & "::\n"
    if v1.startsWith("F_"):
        s &= "    rsp = rsp - 1; stack[rsp] = rbp; rbp = rsp\n"
    return s

vm_transpiler_lua["JMP"] = proc(d0: string, d1: string, d2: string): string =
    return "    goto " & resolveLua(d0).replace("[", "").replace("]", "") & "\n"

vm_transpiler_lua["JNZ"] = proc(d0: string, d1: string, d2: string): string =
    return "    if sra == 3 then goto " & resolveLua(d0).replace("[", "").replace("]", "") & " end\n"

vm_transpiler_lua["JEZ"] = proc(d0: string, d1: string, d2: string): string =
    return "    if sra == 0 or sra == 1 then goto " & resolveLua(d0).replace("[", "").replace("]", "") & " end\n"

vm_transpiler_lua["JF"] = proc(d0, d1, d2: string): string =
    return "    if " & resolveLua(d0) & " == 1 then goto " & resolveLua(d1).replace("[", "").replace("]", "") & " end\n"

vm_transpiler_lua["CMP"] = proc(d0: string, d1: string, d2: string): string =
    var s = "    if " & resolveLua(d0) & " == " & resolveLua(d1) & " then sra = 3 else sra = 1 end\n"
    if d2 != "" and d2 != "00":
        s &= "    " & resolveLua(d2) & " = sra\n"
    return s

vm_transpiler_lua["EXIT"] = proc(d0: string, d1: string, d2: string): string =
    inc labelCounter
    let retLabel = "RET_ADDR_" & $labelCounter
    returnLabels.add(retLabel)
    var s = "    rsp = rsp - 1; stack[rsp] = \"" & retLabel & "\"\n"
    s &= "    goto F_main\n"
    s &= "::" & retLabel & "::\n"
    s &= "    os.exit(" & resolveLua(d0) & ")\n"
    return s

# --- Logic & Optimization ---
vm_transpiler_lua["INC"] = proc(d0: string, d1: string, d2: string): string =
    let target = resolveLua(d0)
    return "    " & target & " = " & target & " + 2\n"

vm_transpiler_lua["DEC"] = proc(d0: string, d1: string, d2: string): string =
    let target = resolveLua(d0)
    return "    " & target & " = " & target & " - 2\n"

vm_transpiler_lua["LT"] = proc(d0: string, d1: string, d2: string): string =
    var s = "    if " & resolveLua(d0) & " < " & resolveLua(d1) & " then sra = 3 else sra = 1 end\n"
    if d2 != "" and d2 != "00":
        s &= "    " & resolveLua(d2) & " = sra\n"
    return s

vm_transpiler_lua["GT"] = proc(d0: string, d1: string, d2: string): string =
    var s = "    if " & resolveLua(d0) & " > " & resolveLua(d1) & " then sra = 3 else sra = 1 end\n"
    if d2 != "" and d2 != "00":
        s &= "    " & resolveLua(d2) & " = sra\n"
    return s

vm_transpiler_lua["EQ"] = proc(d0: string, d1: string, d2: string): string =
    var s = "    if " & resolveLua(d0) & " == " & resolveLua(d1) & " then sra = 3 else sra = 1 end\n"
    if d2 != "" and d2 != "00":
        s &= "    " & resolveLua(d2) & " = sra\n"
    return s

# --- Function & Stack ---
vm_transpiler_lua["PUSH"] = proc(d0: string, d1: string, d2: string): string =
    return "    rsp = rsp - 1; stack[rsp] = " & resolveLua(d0) & "\n"

vm_transpiler_lua["CALL"] = proc(d0: string, d1: string, d2: string): string =
    let funcLabel = resolveLua(d0).replace("[", "").replace("]", "")
    if funcLabel.startsWith("F_") or funcLabel.startsWith("L"):
        inc labelCounter
        let retLabel = "RET_ADDR_" & $labelCounter
        returnLabels.add(retLabel)
        var s = "    rsp = rsp - 1; stack[rsp] = \"" & retLabel & "\"\n"
        s &= "    goto " & funcLabel & "\n"
        s &= "::" & retLabel & "::\n"
        var argCount = 0
        try: argCount = parseInt(d1)
        except: discard
        if argCount > 0:
            s &= "    rsp = rsp + " & $argCount & "\n"
        if d2 != "" and d2 != "00":
            s &= "    " & resolveLua(d2) & " = sra\n"
        return s
    else:
        var s = "    sra = gvm_runtime[\"" & funcLabel & "\"]()\n"
        if d2 != "" and d2 != "00":
            s &= "    " & resolveLua(d2) & " = sra\n"
        return s

vm_transpiler_lua["RET"] = proc(d0: string, d1: string, d2: string): string =
    var s = ""
    if d0 != "" and d0 != "0" and d0 != "00":
        s &= "    sra = " & resolveLua(d0) & "\n"
    s &= "    rsp = rbp\n"
    s &= "    rbp = stack[rsp]; rsp = rsp + 1\n"
    s &= "    ret_target = stack[rsp]; rsp = rsp + 1; goto DISPATCH\n"
    return s

vm_transpiler_lua["GETARG"] = proc(d0: string, d1: string, d2: string): string =
    var index = 0
    try: index = parseInt(d1)
    except: discard
    let offset = 2 + index
    return "    " & resolveLua(d0) & " = stack[rbp + " & $offset & "]\n"

vm_transpiler_lua["CALLD"] = proc(d0, d1, d2: string): string =
    return "    -- CALLD not supported in pure script\n"

vm_transpiler_lua["EXPO"] = proc(d0, d1, d2: string): string =
    return "-- EXPORT " & d0 & "\n"

vm_transpiler_lua["ETRN"] = proc(d0, d1, d2: string): string =
    return "    -- ETRN " & d0 & "\n"

# --- Collections ---
vm_transpiler_lua["NEWMAP"] = proc(d0, d1, d2: string): string =
    return "    " & resolveLua(d0) & " = gvm_runtime.new_map()\n"

vm_transpiler_lua["MSET"] = proc(d0: string, d1: string, d2: string): string =
    return "    Brdi = " & resolveLua(d0) & "; Brsi = " & resolveLua(d1) & "; Brdx = " & resolveLua(d2) & "; gvm_runtime.collection_set()\n"

vm_transpiler_lua["MGET"] = proc(d0: string, d1: string, d2: string): string =
    return "    Brdi = " & resolveLua(d1) & "; Brsi = " & resolveLua(d2) & "; " & resolveLua(d0) & " = gvm_runtime.collection_get()\n"

vm_transpiler_lua["MLEN"] = proc(d0: string, d1: string, d2: string): string =
    return "    Brdi = " & resolveLua(d1) & "; " & resolveLua(d0) & " = gvm_runtime.newton_sizeof()\n"

vm_transpiler_lua["MHEAD"] = proc(d0, d1, d2: string): string =
    return "    " & resolveLua(d0) & " = 0\n"

vm_transpiler_lua["MKEY"] = proc(d0, d1, d2: string): string =
    return "    " & resolveLua(d0) & " = 0\n"

vm_transpiler_lua["MVAL"] = proc(d0, d1, d2: string): string =
    return "    " & resolveLua(d0) & " = 0\n"

vm_transpiler_lua["MNEXT"] = proc(d0, d1, d2: string): string =
    return "    " & resolveLua(d0) & " = 0\n"

vm_transpiler_lua["DEL"] = proc(d0: string, d1: string, d2: string): string =
    return "    Brdi = " & resolveLua(d0) & "; Brsi = " & resolveLua(d1) & "; gvm_runtime.collection_delete()\n"

vm_transpiler_lua["NEWARR"] = proc(d0, d1, d2: string): string =
    return "    " & resolveLua(d0) & " = gvm_runtime.new_array()\n"

# --- Strings & Types ---
vm_transpiler_lua["STR"] = proc(d0, d1, d2: string): string =
    var hexContent = d1.replace("[", "").replace("]", "")
    var text = ""
    if hexContent.len > 0:
        for i in countup(0, hexContent.len - 2, 2):
            try: text.add(chr(parseHexInt(hexContent[i .. i+1])))
            except: discard
    return "    " & resolveLua(d0) & " = \"" & text.replace("\"", "\\\"").replace("\n", "\\n") & "\"\n"

vm_transpiler_lua["CAT"] = proc(d0, d1, d2: string): string =
    return "    " & resolveLua(d0) & " = gvm_str_cat(" & resolveLua(d1) & ", " & resolveLua(d2) & ")\n"

vm_transpiler_lua["TYPEOF"] = proc(d0, d1, d2: string): string =
    return "    " & resolveLua(d0) & " = gvm_runtime.get_type_str(" & resolveLua(d1) & ")\n"

vm_transpiler_lua["ITS"] = proc(d0, d1, d2: string): string =
    return "    " & resolveLua(d0) & " = gvm_runtime.runtime_to_string(" & resolveLua(d1) & ")\n"

vm_transpiler_lua["ARGV"] = proc(d0, d1, d2: string): string =
    return "    " & resolveLua(d1) & " = arg[UNTAG(" & resolveLua(d0) & ")] or \"\"\n"

# --- File I/O ---
vm_transpiler_lua["FOPEN"] = proc(d0, d1, d2: string): string =
    return "    " & resolveLua(d0) & " = io.open(" & resolveLua(d1) & ", \"r\")\n"

vm_transpiler_lua["FWRITE"] = proc(d0, d1, d2: string): string =
    return "    if " & resolveLua(d0) & " then " & resolveLua(d0) & ":write(" & resolveLua(d1) & ") end\n"

vm_transpiler_lua["FREAD"] = proc(d0, d1, d2: string): string =
    return "    if " & resolveLua(d1) & " then " & resolveLua(d0) & " = " & resolveLua(d1) & ":read(\"*a\") end\n"

vm_transpiler_lua["READF"] = proc(d0, d1, d2: string): string =
    return "    file_tmp = io.open(" & resolveLua(d1) & ", \"r\"); if file_tmp then " & resolveLua(d0) & " = file_tmp:read(\"*a\"); file_tmp:close() end\n"

vm_transpiler_lua["FCLOSE"] = proc(d0, d1, d2: string): string =
    return "    if " & resolveLua(d0) & " then " & resolveLua(d0) & ":close() end\n"

# --- Floats & Regs ---
vm_transpiler_lua["MOVSD"] = proc(d0, d1, d2: string): string =
    return "    " & resolveLua(d1) & " = " & resolveLua(d0) & "\n"

vm_transpiler_lua["FSTORE"] = proc(d0, d1, d2: string): string =
    return "    " & resolveLua(d0) & " = " & d1 & "\n"

vm_transpiler_lua["MOV"] = proc(d0, d1, d2: string): string =
    return "    " & resolveLua(d0) & " = " & resolveLua(d1) & "\n"

vm_transpiler_lua["NSUB"] = proc(d0, d1, d2: string): string =
    var val = resolveLua(d0)
    try:
        let intVal = parseInt(val)
        return "    rsp = rsp - " & $(intVal div 8) & "\n"
    except:
        return "    rsp = rsp - (" & val & " // 8)\n"

vm_transpiler_lua["NADD"] = proc(d0, d1, d2: string): string =
    var val = resolveLua(d0)
    try:
        let intVal = parseInt(val)
        return "    rsp = rsp + " & $(intVal div 8) & "\n"
    except:
        return "    rsp = rsp + (" & val & " // 8)\n"

# --- Networking stubs ---
vm_transpiler_lua["NET_SOCKET"] = proc(d0, d1, d2: string): string = return "    " & resolveLua(d0) & " = 0\n"
vm_transpiler_lua["NET_BIND"] = proc(d0, d1, d2: string): string = return ""
vm_transpiler_lua["NET_LISTEN"] = proc(d0, d1, d2: string): string = return ""
vm_transpiler_lua["NET_ACCEPT"] = proc(d0, d1, d2: string): string = return "    " & resolveLua(d0) & " = 0\n"
vm_transpiler_lua["NET_WRITE"] = proc(d0, d1, d2: string): string = return ""
vm_transpiler_lua["NET_CLOSE"] = proc(d0, d1, d2: string): string = return ""
vm_transpiler_lua["NET_RECV"] = proc(d0, d1, d2: string): string = return "    " & resolveLua(d0) & " = \"\"\n"

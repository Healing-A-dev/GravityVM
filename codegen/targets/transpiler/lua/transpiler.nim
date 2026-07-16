import tables
import strutils
import ../../../../core/memory

var vm_transpiler_lua* = initTable[string, proc(d0: string, d1: string, d2: string): string]()
var labels: seq[string] = @[]

# --- Utility ---

proc append(to: var string, data: string): string {.discardable.} =
    to = to & data & "\n"
    return to

# --- Debug Helper ---
proc resolveLua(arg: string): string =
    # DEBUG: Print the raw input character codes
    if arg == "" or arg == "0":
        echo "\e[33m[DEBUG] resolveLua received empty/zero string! Raw len: ", arg.len, "\e[0m"

    if arg.len == 0: return "0"
    let cleanArg = arg.strip()

    # DEBUG: Check if we are losing variable references
    if cleanArg == "0" or cleanArg == "0.0":
        # Un-comment this line to see every zero resolution:
        # echo "[DEBUG] Resolving literal zero. Is this expected?"
        discard

    case cleanArg[0]
    of '$': return "L" & cleanArg[1..^1] # $01 -> L01
    of '@': return "G" & cleanArg[1..^1] # @01 -> G01
    of '%': return "B" & cleanArg[1..^1] # %01 -> B01
    of '[':
        # Recursive strip: [$01] -> $01 -> L01
        return resolveLua(cleanArg[1..^2])
    else:
        return cleanArg

# --- Boilerplate ---

vm_transpiler_lua["__required"] = proc(d0: string, d1: string, d2: string): string = ""
vm_transpiler_lua["__makeTemp"] = proc(d0: string, d1: string, d2: string): string = ""
vm_transpiler_lua["__finalize"] = proc(d0: string, d1: string, d2: string): string = ""
vm_transpiler_lua["__comment"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    DebugInformation.add("    " & d1 & " => " & d2)
    return to_append.append("-- " & d0)

# --- Instructions ---

vm_transpiler_lua["NOP"] = proc(d0: string, d1: string, d2: string): string = ""
vm_transpiler_lua["MALLOC"] = proc(d0: string, d1: string, d2: string): string = ""
vm_transpiler_lua["FREE"] = proc(d0: string, d1: string, d2: string): string = ""

vm_transpiler_lua["STORE"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    # Only STORE needs to worry about quoting strings.
    # Math/Logic ops assume inputs are vars or numbers.
    var val = d1
    try:
        discard parseFloat(val)
    except:
        val = val.replace("\n", "\\n")
        if not val.startsWith("\"") and not val.startsWith("'"):
             if val.contains("\""): val = "'" & val & "'"
             else: val = "\"" & val & "\""

    let target = resolveLua(d0)
    to_append.append("    " & target & " = " & val)
    return to_append

vm_transpiler_lua["READ"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    let target = resolveLua(d0)
    to_append.append("    " & target & " = io.read()")
    return to_append

vm_transpiler_lua["WRITE"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    var src = resolveLua(d0)
    to_append.append("    io.write(" & src & ")")
    return to_append

vm_transpiler_lua["UPD"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    var src = resolveLua(d1)
    var dest = resolveLua(d0)
    to_append.append("    " & dest & " = " & src)
    return to_append

# --- Math (Pure Variable Mapping) ---

vm_transpiler_lua["ADD"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    to_append.append("    " & resolveLua(d2) & " = " & resolveLua(d0) & " + " & resolveLua(d1))
    return to_append

vm_transpiler_lua["SUB"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    to_append.append("    " & resolveLua(d2) & " = " & resolveLua(d0) & " - " & resolveLua(d1))
    return to_append

vm_transpiler_lua["MUL"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    to_append.append("    " & resolveLua(d2) & " = " & resolveLua(d0) & " * " & resolveLua(d1))
    return to_append

vm_transpiler_lua["DIV"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    to_append.append("    " & resolveLua(d2) & " = " & resolveLua(d0) & " / " & resolveLua(d1))
    return to_append

vm_transpiler_lua["EXP"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    to_append.append("    " & resolveLua(d2) & " = " & resolveLua(d0) & " ^ " & resolveLua(d1))
    return to_append

vm_transpiler_lua["COPY"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    to_append.append("    " & resolveLua(d0) & " = " & resolveLua(d1))
    return to_append

# --- Control Flow ---

vm_transpiler_lua["LBL"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    let v1 = resolveLua(d0)
    if labels.len > 0:
      to_append.append("    end")
      discard labels.pop()

    if v1.startsWith("F"):
      to_append.append("\n    ::" & v1 & ":: do")
      labels.add(v1)
    else:
      to_append.append("\n    ::" & v1 & "::")
      
    return to_append

vm_transpiler_lua["JMP"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    to_append.append("    goto " & resolveLua(d0))
    return to_append

vm_transpiler_lua["JNZ"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    # Jump if sra (result) is NOT 0 (True)
    to_append.append("    if sra ~= 0 then goto " & resolveLua(d0) & " end")
    return to_append

vm_transpiler_lua["JEZ"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    # Jump if sra (result) IS 0 (False)
    to_append.append("    if sra == 0 then goto " & resolveLua(d0) & " end")
    return to_append

vm_transpiler_lua["CMP"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    # Just call compare. State (sra) is updated automatically in Lua.
    to_append.append("    compare(" & resolveLua(d0) & ", " & resolveLua(d1) & ")")
    return to_append

vm_transpiler_lua["EXIT"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    to_append.append("    os.exit(" & resolveLua(d0) & ")")
    return to_append

# --- Logic & Optimization ---

vm_transpiler_lua["INC"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    let target = resolveLua(d0)
    to_append.append("    " & target & " = " & target & " + 1")
    return to_append

vm_transpiler_lua["DEC"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    let target = resolveLua(d0)
    to_append.append("    " & target & " = " & target & " - 1")
    return to_append

vm_transpiler_lua["LT"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""

    let v1 = resolveLua(d0)
    let v2 = resolveLua(d1)

    # 1. Compare values (Sets sra to 0, 1, or 2)
    to_append.append("    compare(" & v1 & ", " & v2 & ")")

    # 2. Normalize State for Gravity
    # Gravity expects sra=1 for True.
    # Our Lua compare sets sra=2 for Less Than.
    to_append.append("    if sra == 2 then sra = 1 else sra = 0 end")

    return to_append


vm_transpiler_lua["GT"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    to_append.append("    compare(" & resolveLua(d0) & ", " & resolveLua(d1) & ")")

    # Normalize: Greater Than is sra=1
    to_append.append("    if sra == 1 then sra = 1 else sra = 0 end")

    return to_append


vm_transpiler_lua["RET"] = proc(d0: string, d1: string, d2: string): string =
  var to_append: string = ""
  to_append.append("    return " & resolveLua(d0))
  
  return to_append


vm_transpiler_lua["CALL"]  = proc(d0: string, d1: string, d2: string): string =
  var to_append: string = ""
  to_append.append("    goto " & resolveLua(d0))
  return to_append 

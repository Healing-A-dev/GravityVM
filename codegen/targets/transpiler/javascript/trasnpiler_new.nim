import tables
import strutils
import ../../../../core/memory

var vm_transpiler_javascript* = initTable[string, proc(d0: string, d1: string, d2: string): string]()
var labels: Table[string, int] = initTable[string, int]()
var LABELS: seq[string] = @[]
var FIRST: string = ""

# --- Utility ---

proc append(to: var string, data: string): string {.discardable.} =
    to = to & data & "\n"
    return to

proc calculateSpaces(count: int = LABELS.len): string =
    var out_string: string = ""
    if count <= 0: return ""
    while out_string.len < count * 4:
        out_string = out_string & " "
    return out_string

# --- Debug Helper ---
proc resolveJavascript(arg: string): string =
    # DEBUG: Print the raw input character codes
    if arg == "" or arg == "0":
        echo "\e[33m[DEBUG] resolveJavascript received empty/zero string! Raw len: ", arg.len, "\e[0m"

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
        return resolveJavascript(cleanArg[1..^2])
    else:
        return cleanArg

# --- Boilerplate ---

vm_transpiler_javascript["__required"] = proc(d0: string, d1: string, d2: string): string = ""
vm_transpiler_javascript["__makeTemp"] = proc(d0: string, d1: string, d2: string): string = ""

vm_transpiler_javascript["__finalize"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    if FIRST != "":
        return "    }\n    " & resolveJavascript(FIRST) & "();"
    return ""

vm_transpiler_javascript["__comment"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    DebugInformation.add("    " & d1 & " => " & d2)
    return to_append.append(calculateSpaces() & "// " & d0)

# --- Instructions ---

vm_transpiler_javascript["NOP"] = proc(d0: string, d1: string, d2: string): string = ""

vm_transpiler_javascript["STORE"] = proc(d0: string, d1: string, d2: string): string =
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

    let target = resolveJavascript(d0)
    to_append.append("    let " & target & " = " & val & ";")
    return to_append

vm_transpiler_javascript["READ"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    let target = resolveJavascript(d0)
    to_append.append(calculateSpaces() & "    " & target & " = prompt();")
    return to_append

vm_transpiler_javascript["WRITE"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    var src = resolveJavascript(d0)
    to_append.append(calculateSpaces() & "    process.stdout.write(" & src & ");")
    return to_append

vm_transpiler_javascript["UPD"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    var src = resolveJavascript(d1)
    to_append.append(calculateSpaces() & "    " & d0[1..^1] & " = " & src & ";")
    return to_append

# --- Math (Pure Variable Mapping) ---

vm_transpiler_javascript["ADD"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    to_append.append(calculateSpaces() & "    " & resolveJavascript(d2) & " = " & resolveJavascript(d0) & " + " & resolveJavascript(d1) & ";")
    return to_append

vm_transpiler_javascript["SUB"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    to_append.append(calculateSpaces() & "    " & resolveJavascript(d2) & " = " & resolveJavascript(d0) & " - " & resolveJavascript(d1) & ";")
    return to_append

vm_transpiler_javascript["MUL"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    to_append.append(calculateSpaces() & "    " & resolveJavascript(d2) & " = " & resolveJavascript(d0) & " * " & resolveJavascript(d1) & ";")
    return to_append

vm_transpiler_javascript["DIV"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    to_append.append(calculateSpaces() & "    " & resolveJavascript(d2) & " = " & resolveJavascript(d0) & " / " & resolveJavascript(d1) & ";")
    return to_append

vm_transpiler_javascript["EXP"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    to_append.append(calculateSpaces() & "    " & resolveJavascript(d2) & " = " & resolveJavascript(d0) & " ^ " & resolveJavascript(d1) & ";")
    return to_append

vm_transpiler_javascript["COPY"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    to_append.append(calculateSpaces() & "    " & resolveJavascript(d0) & " = " & resolveJavascript(d1) & ";")
    return to_append

# --- Control Flow ---

vm_transpiler_javascript["LBL"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    if LABELS.len > 0:
        to_append.append("    }")
        LABELS[0] = d0
    else:
        FIRST = d0
        LABELS.add(d0)
    to_append.append(calculateSpaces() & "\n    function " & resolveJavascript(d0) & "() {")
    return to_append

vm_transpiler_javascript["JMP"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    to_append.append(calculateSpaces() & "    " & resolveJavascript(d0) & "();")
    return to_append

vm_transpiler_javascript["JNZ"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    # Jump if sra (result) is NOT 0 (True)
    to_append.append(calculateSpaces() & "    if (sra != 0) { " & resolveJavascript(d0) & "(); }")
    return to_append

vm_transpiler_javascript["JEZ"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    # Jump if sra (result) IS 0 (False)
    to_append.append(calculateSpaces() & "    if (sra == 0) { " & resolveJavascript(d0) & "(); }")
    return to_append

vm_transpiler_javascript["CMP"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    # Just call compare. State (sra) is updated automatically in Lua.
    to_append.append(calculateSpaces() & "    compare(" & resolveJavascript(d0) & ", " & resolveJavascript(d1) & ");")
    return to_append

vm_transpiler_javascript["EXIT"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    to_append.append(calculateSpaces() & "    process.exit(" & resolveJavascript(d0) & ");")
    return to_append

# --- Logic & Optimization ---

vm_transpiler_javascript["INC"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    let target = resolveJavascript(d0)
    to_append.append(calculateSpaces() & "    " & target & " = " & target & " + 1;")
    return to_append

vm_transpiler_javascript["DEC"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    let target = resolveJavascript(d0)
    to_append.append(calculateSpaces() & "    " & target & " = " & target & " - 1;")
    return to_append

vm_transpiler_javascript["LT"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""

    let v1 = resolveJavascript(d0)
    let v2 = resolveJavascript(d1)

    # Debug Trap: If we see "compare(0.0, 5.0)", warn the user!
    if (v1 == "0" or v1 == "0.0"):
        echo "\e[31m[WARNING] Transpiler saw '0 < 5' instead of '$count < 5'. check out.gvt!\e[0m"

    # 1. Compare values (Sets sra to 0, 1, or 2)
    to_append.append(calculateSpaces() & "    compare(" & v1 & ", " & v2 & ");")

    # 2. Normalize State for Gravity
    # Gravity expects sra=1 for True.
    # Our Lua compare sets sra=2 for Less Than.
    to_append.append(calculateSpaces() & "    if (sra == 2) { sra = 1; } else { sra = 0; }")

    return to_append

vm_transpiler_javascript["GT"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    to_append.append(calculateSpaces() & "    compare(" & resolveJavascript(d0) & ", " & resolveJavascript(d1) & ")")

    # Normalize: Greater Than is sra=1
    to_append.append(calculateSpaces() & "    if (sra == 1) { sra = 1; } else { sra = 0; }")

    return to_append

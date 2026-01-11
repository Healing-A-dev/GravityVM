import tables
import strutils
import ../../../../core/memory

var vm_transpiler_javascript* = initTable[string, proc(d0: string, d1: string, d2: string): string]()
var labels: Table[string, int] = initTable[string, int]()

# Label Holder (Only hold one label at a time)
var LABELS: seq[string] = @[]
var FIRST: string = ""


# Utility Functions #
proc append(to: var string, data: string): string {.discardable.} =
    to = to & data & "\n"
    return to

proc calculateSpaces(count: int = LABELS.len): string =
    var out_string: string = ""

    if count <= 0: return ""

    while out_string.len < count * 4:
        out_string = out_string & " "

    return out_string


# Compiler Boilerplate #
vm_transpiler_javascript["__required"] = proc(d0: string, d1: string, d2: string): string =
    return ""

vm_transpiler_javascript["__makeTemp"] = proc(d0: string, d1: string, d2: string): string =
    return ""

vm_transpiler_javascript["__comment"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    DebugInformation.add("    " & d1 & " => " & d2)
    return to_append.append(calculateSpaces() & "// " & d0)

vm_transpiler_javascript["__finalize"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    if FIRST != "":
        return "    }\n    " & FIRST & "();"
    return ""



# Transpiler Functions #
vm_transpiler_javascript["NOP"] = proc(d0: string, d1: string, d2: string): string =
    return ""

#
vm_transpiler_javascript["STORE"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    var d1 = d1
    var spaces: string = calculateSpaces()

    try:
        discard parseFloat(d1)
    except:
        d1 = d1.replace("\n", "\\n")
        if d1.contains("\""):
            d1 = "'" & d1 & "'"
        else:
            d1 = '"' & d1 & '"'

    case d0[0]
    of '@':
        to_append.append(spaces & "    let G" & d0[1..<d0.len] & " = " & d1 & ";")
    of '$':
        to_append.append(spaces & "    let L" & d0[1..<d0.len] & " = " & d1 & ";")
    of '%':
        to_append.append(spaces & "    let B" & d0[1..<d0.len] & " = " & d1 & ";")
    of '[':
        let d2: string = d0[1..<d0.len - 1]
        to_append.append(spaces & "    " & d2 & " = " & d1 & ";")
    else:
        return ""

    return to_append

#
vm_transpiler_javascript["READ"] = proc(d0: string, d1: string, d2: string): string =
    var d0:string = d0
    var to_append: string = ""
    var spaces = calculateSpaces()
    case d0[0]:
    of '@':
        d0 = "G" & d0[1..<d0.len]
    of '$':
        d0 = "L" & d0[1..<d0.len]
    of '%':
        d0 = "G" & d0[1..<d0.len]
    of '[':
        let d1: string = d0[1..<d0.len - 1]
        if REGISTER.hasKey(d1):
            d0 = d0
    else:
        d0 = d0

    #to_append.append(spaces & "    readline.question(\"\", STDIN => {")
    #to_append.append(spaces & "        " & d0 & " = STDIN;")
    #to_append.append(spaces & "        readline.close();")
    #to_append.append(spaces & "    });")
    to_append.append(calculateSpaces() & "    " & d0 & " = prompt()")
    return to_append

#
vm_transpiler_javascript["WRITE"] = proc(d0: string, d1: string, d2: string): string =
    var d0: string = d0
    var d1: string = d1
    var d2: string = d2
    var to_append: string = ""

    case d0[0]
    of '@':
        d0 = "G" & d0[1..<d0.len]
    of '$':
        d0 = "L" & d0[1..<d0.len]
    of '%':
        d0 = "B" & d0[1..<d0.len]
    of '[':
        let d3: string = d0[1..<(d0.len - 1)]
        if REGISTER.hasKey(d3):
            if REGISTER[d3] != "":
                if REGISTER[d3][0] == '[' and REGISTER[d3][REGISTER[d3].len - 1] == ']':
                    d0 = "\"" & REGISTER[d3][1..<REGISTER[d3].len - 1] & "\""
                else:
                    d0 = "\"" & REGISTER[d3] & "\""
        else:
            d0 = "\"" & d3 & "\""
    else:
        echo "WIP"
        return ""

    to_append.append(calculateSpaces() & "    process.stdout.write(" & d0 & ");")
    return to_append

#
vm_transpiler_javascript["UPD"] = proc(d0: string, d1: string, d2: string): string =
    var d0: string = d0
    var d1: string = d1
    var to_append: string = ""

    case d0[0]:
    of '@':
        d0 = "G" & d0[1..<d0.len]
    of '$':
        d0 = "L" & d0[1..<d0.len]
    of '%':
        d0 = "B" & d0[1..<d0.len]
    of '[':
        d0 = "" & d0[1..<d0.len - 1] & ""
    else:
        discard

    case d1[0]:
    of '@':
        d1 = "G" & d1[1..<d1.len]
    of '$':
        d1 = "L" & d1[1..<d1.len]
    of '%':
        d1 = "B" & d1[1..<d1.len]
    of '[':
        let d3: string = d1[1..<(d1.len - 1)]
        if REGISTER.hasKey(d3):
            if REGISTER[d3] != "":
                if REGISTER[d3][0] == '[' and REGISTER[d3][REGISTER[d3].len - 1] == ']':
                    d1 = REGISTER[d3][1..<REGISTER[d3].len - 1]
                else:
                    d1 = REGISTER[d3]
        else:
            d1 = "\"" & d3 & "\""
    else:
        discard

    to_append.append(calculateSpaces() & "    " & d0 & " = " & d1 & ";")
    return to_append

#
vm_transpiler_javascript["ADD"] = proc(d0: string, d1: string, d2: string): string =
    var d0: string = d0
    var d1: string = d1
    var register: string = d2[1..<(d2.len - 1)]
    var to_append: string = ""

    if d0[d0.len - 2..<d0.len] == ".0":
        d0 = d0[0..<d0.len-2]

    if d1[d1.len - 2..<d1.len] == ".0":
        d1 = d1[0..<d1.len-2]

    to_append.append(calculateSpaces() & "    " & register & " = " & d0 & " + " & d1 & ";")
    return to_append

#
vm_transpiler_javascript["SUB"] = proc(d0: string, d1: string, d2: string): string =
    var d0: string = d0
    var d1: string = d1
    var register: string = d2[1..<(d2.len - 1)]
    var to_append: string = ""

    if d0[d0.len - 2..<d0.len] == ".0":
        d0 = d0[0..<d0.len-2]

    if d1[d1.len - 2..<d1.len] == ".0":
        d1 = d1[0..<d1.len-2]

    to_append.append(calculateSpaces() & "    " & register & " = " & d0 & " - " & d1 & ";")
    return to_append

#
vm_transpiler_javascript["MUL"] = proc(d0: string, d1: string, d2: string): string =
    var d0: string = d0
    var d1: string = d1
    var register: string = d2[1..<(d2.len - 1)]
    var to_append: string = ""

    if d0[d0.len - 2..<d0.len] == ".0":
        d0 = d0[0..<d0.len-2]

    if d1[d1.len - 2..<d1.len] == ".0":
        d1 = d1[0..<d1.len-2]

    to_append.append(calculateSpaces() & "    " & register & " = " & d0 & " * " & d1 & ";")
    return to_append

#
vm_transpiler_javascript["DIV"] = proc(d0: string, d1: string, d2: string): string =
    var d0: string = d0
    var d1: string = d1
    var register: string = d2[1..<(d2.len - 1)]
    var to_append: string = ""

    if d0[d0.len - 2..<d0.len] == ".0":
        d0 = d0[0..<d0.len-2]

    if d1[d1.len - 2..<d1.len] == ".0":
        d1 = d1[0..<d1.len-2]

    to_append.append(calculateSpaces() & "    " & register & " = " & d0 & " / " & d1 & ";")
    return to_append

#
vm_transpiler_javascript["EXP"] = proc(d0: string, d1: string, d2: string): string =
    var d0: string = d0
    var d1: string = d1
    var register: string = d2[1..<(d2.len - 1)]
    var to_append: string = ""

    if d0[d0.len - 2..<d0.len] == ".0":
        d0 = d0[0..<d0.len-2]

    if d1[d1.len - 2..<d1.len] == ".0":
        d1 = d1[0..<d1.len-2]

    to_append.append(calculateSpaces() & "    " & register & " = " & d0 & " ^ " & d1 & ";")
    return to_append

#
vm_transpiler_javascript["COPY"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    to_append.append(calculateSpaces() & "    " & d0 & " = " & d1 & ";")
    return to_append

#
vm_transpiler_javascript["LBL"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    if LABELS.len > 0:
        to_append.append("    }")
        LABELS[0] = d0
    else:
        FIRST = d0
        LABELS.add(d0)
    to_append.append(calculateSpaces() & "\n    function " & d0 & "() {")
    return to_append

#
vm_transpiler_javascript["JMP"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    to_append.append(calculateSpaces() & "    " & d0 & "();")
    return to_append


vm_transpiler_javascript["JNZ"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    let spaces: string = calculateSpaces()
    to_append.append(spaces & "    if (sra != 0) {")
    to_append.append(spaces & "        " & d0 & "();")
    to_append.append(spaces & "    }")
    return to_append


vm_transpiler_javascript["JEZ"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    let spaces: string = calculateSpaces()
    to_append.append(spaces & "    if (sra == 0) {")
    to_append.append(spaces & "        " & d0 & "();")
    to_append.append(spaces & "    }")
    return to_append


#
vm_transpiler_javascript["CMP"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    var d0: string = d0
    var d1: string = d1

    case d0[0]:
    of '@':
        d0 = "G" & d0[1..<d0.len]
    of '$':
        d0 = "L" & d0[1..<d0.len]
    of '%':
        d0 = "B" & d0[1..<d0.len]
    of '[':
        echo "WIP"
    else:
        discard

    case d1[0]:
    of '@':
        d1 = "G" & d1[1..<d1.len]
    of '$':
        d1 = "L" & d1[1..<d1.len]
    of '%':
        d1 = "B" & d1[1..<d1.len]
    of '[':
        echo "WIP"
    else:
        discard

    to_append.append(calculateSpaces() & "    compare( " & d0 & ", " & d1 & ")")
    return to_append

#
vm_transpiler_javascript["EXIT"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    to_append.append(calculateSpaces() & "    process.exit(" & d0 & ")")
    return to_append

#
vm_transpiler_javascript["INC"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    var d1: string = d1

    case d0[0]:
    of '@':
        d1 = "G" & d0[1..<d0.len]
    of '$':
        d1 = "L" & d0[1..<d0.len]
    of '%':
        d1 = "B" & d0[1..<d0.len]
    of '[':
        echo "WIP"
    else:
        discard

    to_append.append(calculateSpaces() & "    " & d1 & " = " & d1 & " + 1")
    return to_append

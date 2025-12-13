import tables
import strutils
import ../../../core/memory

var vm_transpiler* = initTable[string, proc(d0: string, d1: string, d2: string): string]()
var labels: Table[string, int] = initTable[string, int]()

# Utility Functions #
proc append(to: var string, data: string): string {.discardable.} =
    to = to & data & "\n"
    return to


# Compiler Boilerplate #
vm_transpiler["__required"] = proc(d0: string, d1: string, d2: string): string =
    return ""

vm_transpiler["__makeTemp"] = proc(d0: string, d1: string, d2: string): string =
    return ""

vm_transpiler["__comment"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    echo "\e[93mDEBUG\e[0m: [" & d1 & "]: " & d2
    return to_append.append("# " & d0)


# Transpiler Functions #
vm_transpiler["NOP"] = proc(d0: string, d1: string, d2: string): string =
    return ""


vm_transpiler["STORE"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    var d1 = d1

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
        to_append.append("    &store(\"G" & d0[1..<d0.len] & "_gravityV\", " & d1 & ");")
        to_append.append("    our $G" & d0[1..<d0.len] & "_gravityV = " & d1 & ";")
    of '$':
        to_append.append("    &store(\"L" & d0[1..<d0.len] & "_gravityV\", " & d1 & ");")
    of '%':
        to_append.append("    &store(\"B" & d0[1..<d0.len] & "_gravityV\", " & d1 & ");")
    of '[':
        let d2: string = d0[1..<d0.len - 1]
        to_append.append("    &setRegister(\"" & d2 & "\", " & d1 & ");")
    else:
        return ""

    return to_append


vm_transpiler["READ"] = proc(d0: string, d1: string, d2: string): string =
    var d0:string = d0
    var to_append: string = ""
    case d0[0]:
    of '@':
        d0 = "G" & d0[1..<d0.len] & "_gravityV"
    of '$':
        d0 = "L" & d0[1..<d0.len] & "_gravityV"
    of '%':
        d0 = "G" & d0[1..<d0.len] & "_gravityV"
    of '[':
        let d1: string = d0[1..<d0.len - 1]
        if REGISTER.hasKey(d1):
            d0 = d0
    else:
        d0 = d0

    to_append.append("    &read(\"" & d0 & "\");")
    return to_append

vm_transpiler["WRITE"] = proc(d0: string, d1: string, d2: string): string =
    var d0: string = d0
    var d1: string = d1
    var d2: string = d2
    var to_append: string = ""

    case d0[0]
    of '@':
        d0 = "\"G" & d0[1..<d0.len] & "_gravityV\""
    of '$':
        d0 = "\"L" & d0[1..<d0.len] & "_gravityV\""
    of '%':
        d0 = "\"B" & d0[1..<d0.len] & "_gravityV\""
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

    to_append.append("    &puts(" & d0 & ");")
    return to_append


vm_transpiler["UPD"] = proc(d0: string, d1: string, d2: string): string =
    var d0: string = d0
    var d1: string = d1
    var to_append: string = ""

    case d0[0]:
    of '@':
        d0 = "\"G" & d0[1..<d0.len] & "_gravityV\""
    of '$':
        d0 = "\"L" & d0[1..<d0.len] & "_gravityV\""
    of '%':
        d0 = "\"B" & d0[1..<d0.len] & "_gravityV\""
    of '[':
        d0 = "\"" & d0[1..<d0.len - 1] & "\""
    else:
        discard

    case d1[0]:
    of '@':
        d1 = "\"G" & d1[1..<d1.len] & "_gravityV\""
    of '$':
        d1 = "\"L" & d1[1..<d1.len] & "_gravityV\""
    of '%':
        d1 = "\"B" & d1[1..<d1.len] & "_gravityV\""
    of '[':
        let d3: string = d1[1..<(d1.len - 1)]
        if REGISTER.hasKey(d3):
            if REGISTER[d3] != "":
                if REGISTER[d3][0] == '[' and REGISTER[d3][REGISTER[d3].len - 1] == ']':
                    d1 = "\"" & REGISTER[d3][1..<REGISTER[d3].len - 1] & "\""
                else:
                    d1 = REGISTER[d3]
        else:
            d1 = "\"" & d3 & "\""
    else:
        discard

    to_append.append("    &update(" & d0 & ", " & d1 & ");")
    return to_append


vm_transpiler["ADD"] = proc(d0: string, d1: string, d2: string): string =
    var d0: string = d0
    var d1: string = d1
    var to_append: string = ""

    if d0[d0.len-2..<d0.len] == ".0":
        d0 = d0[0..<d0.len-2]

    if d1[d1.len-2..<d1.len] == ".0":
        d1 = d1[0..<d1.len-2]

    to_append.append("    &add(" & d0 & ", " & d1 & ", \"" & d2 & "\");")
    if d2 != "sra":
        to_append.append("    &moveRegister(\"sra\", " & d2 & ");")

    return to_append


vm_transpiler["SUB"] = proc(d0: string, d1: string, d2: string): string =
    var d0: string = d0
    var d1: string = d1
    var to_append: string = ""

    if d0[d0.len-2..<d0.len] == ".0":
        d0 = d0[0..<d0.len-2]

    if d1[d1.len-2..<d1.len] == ".0":
        d1 = d1[0..<d1.len-2]

    to_append.append("    &subt(" & d0 & ", " & d1 & ", \"" & d2 & "\");")
    if d2 != "sra":
        to_append.append("    &moveRegister(\"sra\", " & d2 & ");")

    return to_append


vm_transpiler["MUL"] = proc(d0: string, d1: string, d2: string): string =
    var d0: string = d0
    var d1: string = d1
    var to_append: string = ""

    if d0[d0.len-2..<d0.len] == ".0":
        d0 = d0[0..<d0.len-2]

    if d1[d1.len-2..<d1.len] == ".0":
        d1 = d1[0..<d1.len-2]

    to_append.append("    &mul(" & d0 & ", " & d1 & ", \"" & d2 & "\");")
    if d2 != "sra":
        to_append.append("    &moveRegister(\"sra\", " & d2 & ");")

    return to_append


vm_transpiler["DIV"] = proc(d0: string, d1: string, d2: string): string =
    var d0: string = d0
    var d1: string = d1
    var to_append: string = ""

    if d0[d0.len-2..<d0.len] == ".0":
        d0 = d0[0..<d0.len-2]

    if d1[d1.len-2..<d1.len] == ".0":
        d1 = d1[0..<d1.len-2]

    to_append.append("    &div(" & d0 & ", " & d1 & ", \"" & d2 & "\");")
    if d2 != "sra":
        to_append.append("    &moveRegister(\"sra\", " & d2 & ");")

    return to_append


vm_transpiler["EXP"] = proc(d0: string, d1: string, d2: string): string =
    var d0: string = d0
    var d1: string = d1
    var to_append: string = ""

    if d0[d0.len-2..<d0.len] == ".0":
        d0 = d0[0..<d0.len-2]

    if d1[d1.len-2..<d1.len] == ".0":
        d1 = d1[0..<d1.len-2]

    to_append.append("    &exp(" & d0 & ", " & d1 & ", \"" & d2 & "\");")
    if d2 != "sra":
        to_append.append("    &moveRegister(\"sra\", " & d2 & ");")

    return to_append


vm_transpiler["COPY"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    to_append.append("    #InnerShell::copyNode(" & d0 & ", " & d1 & ");")
    return to_append


vm_transpiler["LBL"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    to_append.append("\n    lbl" & d0 & ":")
    return to_append


vm_transpiler["JMP"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    to_append.append("    goto lbl" & d0 & ";")
    return to_append


vm_transpiler["JNZ"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    to_append.append("    goto lbl" & d0 & " if ($REGISTERS{\"sra\"} != 0);")
    return to_append


vm_transpiler["JEZ"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    to_append.append("    goto lbl" & d0 & " if ($REGISTERS{\"sra\"} == 0);")
    return to_append


vm_transpiler["CMP"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    var d0: string = d0
    var d1: string = d1

    case d0[0]:
    of '@':
        d0 = "G" & d0[1..<d0.len] & "_gravityV"
    of '$':
        d0 = "L" & d0[1..<d0.len] & "_gravityV"
    of '%':
        d0 = "B" & d0[1..<d0.len] & "_gravityV"
    of '[':
        echo "WIP"
    else:
        discard

    case d1[0]:
    of '@':
        d1 = "G" & d1[1..<d1.len] & "_gravityV"
    of '$':
        d1 = "L" & d1[1..<d1.len] & "_gravityV"
    of '%':
        d1 = "B" & d1[1..<d1.len] & "_gravityV"
    of '[':
        echo "WIP"
    else:
        discard

    to_append.append("    &compare(\"" & d0 & "\", \"" & d1 & "\", \"sra\");")

    return to_append


vm_transpiler["EXIT"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    to_append.append("    exit " & d0 & ";")
    return to_append


vm_transpiler["INC"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    var d1: string = d1

    case d0[0]:
    of '@':
        d1 = "G" & d0[1..<d0.len] & "_gravityV"
    of '$':
        d1 = "L" & d0[1..<d0.len] & "_gravityV"
    of '%':
        d1 = "B" & d0[1..<d0.len] & "_gravityV"
    of '[':
        echo "WIP"
    else:
        discard

    #to_append.append("    &setRegister(\"srb\", 1);")
    to_append.append("    &add(\"" & d1 & "\", 1, \"sra\");")
    to_append.append("    &store(\"" & d1 & "\", &getRegister(\"sra\"));")
    return to_append

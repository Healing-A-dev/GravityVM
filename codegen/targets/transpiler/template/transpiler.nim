# Immutable Imports [DO NOT CHANGE]
import tables
import strutils
import ../../../../core/memory

# Mutable Imports [Edit as needed]


var vm_transpiler_<LANGUAGE_NAME>* = initTable[string, proc(d0: string, d1: string, d2: string): string]()
var labels: Table[string, int] = initTable[string, int]()

# Utility Functions [Edit as needed]
proc append(to: var string, data: string): string {.discardable.} =
    to = to & data & "\n"
    return to


# Compiler Boilerplate [Edit as needed]
vm_transpiler_<LANGUAGE_NAME>["__required"] = proc(d0: string, d1: string, d2: string): string =
    return ""

vm_transpiler_<LANGUAGE_NAME>["__makeTemp"] = proc(d0: string, d1: string, d2: string): string =
    return ""

vm_transpiler_<LANGUAGE_NAME>["__comment"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    DebugInformation.add("    " & d1 & " => " & d2)
    return to_append.append("# " & d0)

vm_transpiler_<LANGUAGE_NAME>["__finalize"] = proc(d0: string, d1: string, d2: string): string =
    return ""



# Transpiler Intructions Go Here #
vm_transpiler_<LANGUAGE_NAME>["NOP"] = proc(d0: string, d1: string, d2: string): string =
    return ""

vm_transpiler_<LANGUAGE_NAME>["STORE"] = proc(d0: string, d1: string, d2: string): string =
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
        # Create Global Variables [Edit as needed]
        to_append.append("    G" & d0[1..<d0.len] & " ::= " & d1)
    of '$':
        # Create Local Variables [Edit as needed]
        to_append.append("    L" & d0[1..<d0.len] & " ::= " & d1)
    of '%':
        # Create Buffer Variables [Edit as needed]
        to_append.append("    B" & d0[1..<d0.len] & " ::= " & d1)
    of '[':
        # Update Registers [Edit as needed]
        let d2: string = d0[1..<d0.len - 1]
        to_append.append("    " & d2 & " ::= " & d1)
    else:
        return ""

    return to_append

#
vm_transpiler_<LANGUAGE_NAME>["READ"] = proc(d0: string, d1: string, d2: string): string =
    var d0:string = d0
    var to_append: string = ""
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

    # [Edit as needed]
    to_append.append("    " & d0 & " ::= <STDIN>")
    return to_append

#
vm_transpiler_<LANGUAGE_NAME>["WRITE"] = proc(d0: string, d1: string, d2: string): string =
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
                    d0 = REGISTER[d3][1..<REGISTER[d3].len - 1]
                else:
                    d0 = "\"" & REGISTER[d3] & "\""
        else:
            d0 = "\"" & d3 & "\""
    else:
        echo "WIP"
        return ""

    # [Edit as needed]
    to_append.append("    STDOUT(" & d0 & ")")
    return to_append

#
vm_transpiler_<LANGUAGE_NAME>["UPD"] = proc(d0: string, d1: string, d2: string): string =
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

    # [Edit as needed]
    to_append.append("    " & d0 & " ::= " & d1)
    return to_append

#
vm_transpiler_<LANGUAGE_NAME>["ADD"] = proc(d0: string, d1: string, d2: string): string =
    var d0: string = d0
    var d1: string = d1
    var register: string = d2[1..<(d2.len - 1)]
    var to_append: string = ""

    if d0[d0.len - 2..<d0.len] == ".0":
        d0 = d0[0..<d0.len-2]

    if d1[d1.len - 2..<d1.len] == ".0":
        d1 = d1[0..<d1.len-2]

    # [Edit as needed]
    to_append.append("    " & register & " ::= " & d0 & " + " & d1)
    return to_append

#
vm_transpiler_<LANGUAGE_NAME>["SUB"] = proc(d0: string, d1: string, d2: string): string =
    var d0: string = d0
    var d1: string = d1
    var register: string = d2[1..<(d2.len - 1)]
    var to_append: string = ""

    if d0[d0.len - 2..<d0.len] == ".0":
        d0 = d0[0..<d0.len-2]

    if d1[d1.len - 2..<d1.len] == ".0":
        d1 = d1[0..<d1.len-2]

    # [Edit as needed]
    to_append.append("    " & register & " ::= " & d0 & " - " & d1)
    return to_append

#
vm_transpiler_<LANGUAGE_NAME>["MUL"] = proc(d0: string, d1: string, d2: string): string =
    var d0: string = d0
    var d1: string = d1
    var register: string = d2[1..<(d2.len - 1)]
    var to_append: string = ""

    if d0[d0.len - 2..<d0.len] == ".0":
        d0 = d0[0..<d0.len-2]

    if d1[d1.len - 2..<d1.len] == ".0":
        d1 = d1[0..<d1.len-2]

    # [Edit as needed]
    to_append.append("    " & register & " ::= " & d0 & " * " & d1)
    return to_append

#
vm_transpiler_<LANGUAGE_NAME>["DIV"] = proc(d0: string, d1: string, d2: string): string =
    var d0: string = d0
    var d1: string = d1
    var register: string = d2[1..<(d2.len - 1)]
    var to_append: string = ""

    if d0[d0.len - 2..<d0.len] == ".0":
        d0 = d0[0..<d0.len-2]

    if d1[d1.len - 2..<d1.len] == ".0":
        d1 = d1[0..<d1.len-2]

    # [Edit as needed]
    to_append.append("    " & register & " ::= " & d0 & " / " & d1)
    return to_append

#
vm_transpiler_<LANGUAGE_NAME>["EXP"] = proc(d0: string, d1: string, d2: string): string =
    var d0: string = d0
    var d1: string = d1
    var register: string = d2[1..<(d2.len - 1)]
    var to_append: string = ""

    if d0[d0.len - 2..<d0.len] == ".0":
        d0 = d0[0..<d0.len-2]

    if d1[d1.len - 2..<d1.len] == ".0":
        d1 = d1[0..<d1.len-2]

    # [Edit as needed]
    to_append.append("    " & register & " ::= " & d0 & " ^ " & d1)
    return to_append

#
vm_transpiler_<LANGUAGE_NAME>["COPY"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    # [Edit as needed]
    to_append.append("    " & d0 & " ::= " & d1 & "")
    return to_append

#
vm_transpiler_<LANGUAGE_NAME>["LBL"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    # [Edit as needed]
    to_append.append("\n    NEW_LABEL" & d0 & "")
    return to_append

#
vm_transpiler_<LANGUAGE_NAME>["JMP"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    # [Edit as needed]
    to_append.append("    goto " & d0)
    return to_append


vm_transpiler_<LANGUAGE_NAME>["JNZ"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    # [Edit as needed]
    to_append.append("    if (sra != 0) {")
    to_append.append("        goto " & d0)
    to_append.append("    }")
    return to_append


vm_transpiler_<LANGUAGE_NAME>["JEZ"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    # [Edit as needed]
    to_append.append("    if (sra == 0) {")
    to_append.append("        goto " & d0)
    to_append.append("    }")
    return to_append


#
vm_transpiler_<LANGUAGE_NAME>["CMP"] = proc(d0: string, d1: string, d2: string): string =
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

    # [Edit as needed]
    to_append.append("    compare( " & d0 & ", " & d1 & ")")
    return to_append

#
vm_transpiler_<LANGUAGE_NAME>["EXIT"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    # [Edit as needed]
    to_append.append("    exit(" & d0 & ")")
    return to_append

#
vm_transpiler_<LANGUAGE_NAME>["INC"] = proc(d0: string, d1: string, d2: string): string =
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

    # [Edit as needed]
    to_append.append("    " & d1 & " = " & d1 & " + 1")
    return to_append

import tables
import strutils
import ../../../../core/memory

var vm_transpiler_lua* = initTable[string, proc(d0: string, d1: string, d2: string): string]()
var labels: Table[string, int] = initTable[string, int]()

# Utility Functions #
proc append(to: var string, data: string): string {.discardable.} =
    to = to & data & "\n"
    return to


# Compiler Boilerplate #
vm_transpiler_lua["__required"] = proc(d0: string, d1: string, d2: string): string =
    return ""

vm_transpiler_lua["__makeTemp"] = proc(d0: string, d1: string, d2: string): string =
    return ""

vm_transpiler_lua["__comment"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    DebugInformation.add("    " & d1 & " => " & d2)
    return to_append.append("# " & d0)

vm_transpiler_lua["__finalize"] = proc(d0: string, d1: string, d2: string): string =
    return ""


# Transpiler Functions #
vm_transpiler_lua["NOP"] = proc(d0: string, d1: string, d2: string): string =
    return ""

vm_transpiler_lua["STORE"] = proc(d0: string, d1: string, d2: string): string =
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
        to_append.append("    G" & d0[1..<d0.len] & " = " & d1)
    of '$':
        to_append.append("    local L" & d0[1..<d0.len] & " = " & d1)
    of '%':
        to_append.append("    B" & d0[1..<d0.len] & " = " & d1)
    of '[':
        let d2: string = d0[1..<d0.len - 1]
        to_append.append("    " & d2 & " = " & d1)
    else:
        return ""

    return to_append

#
vm_transpiler_lua["READ"] = proc(d0: string, d1: string, d2: string): string =
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

    to_append.append("    " & d0 & " = io.read()")
    return to_append

#
vm_transpiler_lua["WRITE"] = proc(d0: string, d1: string, d2: string): string =
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

    to_append.append("    io.write(" & d0 & ")")
    return to_append

#
vm_transpiler_lua["UPD"] = proc(d0: string, d1: string, d2: string): string =
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

    to_append.append("    " & d0 & " = " & d1)
    return to_append

#
vm_transpiler_lua["ADD"] = proc(d0: string, d1: string, d2: string): string =
    var d0: string = d0
    var d1: string = d1
    var register: string = d2[1..<(d2.len - 1)]
    var to_append: string = ""

    if d0[d0.len - 2..<d0.len] == ".0":
        d0 = d0[0..<d0.len-2]

    if d1[d1.len - 2..<d1.len] == ".0":
        d1 = d1[0..<d1.len-2]

    to_append.append("    " & register & " = " & d0 & " + " & d1)
    return to_append

#
vm_transpiler_lua["SUB"] = proc(d0: string, d1: string, d2: string): string =
    var d0: string = d0
    var d1: string = d1
    var register: string = d2[1..<(d2.len - 1)]
    var to_append: string = ""

    if d0[d0.len - 2..<d0.len] == ".0":
        d0 = d0[0..<d0.len-2]

    if d1[d1.len - 2..<d1.len] == ".0":
        d1 = d1[0..<d1.len-2]

    to_append.append("    " & register & " = " & d0 & " - " & d1)
    return to_append

#
vm_transpiler_lua["MUL"] = proc(d0: string, d1: string, d2: string): string =
    var d0: string = d0
    var d1: string = d1
    var register: string = d2[1..<(d2.len - 1)]
    var to_append: string = ""

    if d0[d0.len - 2..<d0.len] == ".0":
        d0 = d0[0..<d0.len-2]

    if d1[d1.len - 2..<d1.len] == ".0":
        d1 = d1[0..<d1.len-2]

    to_append.append("    " & register & " = " & d0 & " * " & d1)
    return to_append

#
vm_transpiler_lua["DIV"] = proc(d0: string, d1: string, d2: string): string =
    var d0: string = d0
    var d1: string = d1
    var register: string = d2[1..<(d2.len - 1)]
    var to_append: string = ""

    if d0[d0.len - 2..<d0.len] == ".0":
        d0 = d0[0..<d0.len-2]

    if d1[d1.len - 2..<d1.len] == ".0":
        d1 = d1[0..<d1.len-2]

    to_append.append("    " & register & " = " & d0 & " / " & d1)
    return to_append

#
vm_transpiler_lua["EXP"] = proc(d0: string, d1: string, d2: string): string =
    var d0: string = d0
    var d1: string = d1
    var register: string = d2[1..<(d2.len - 1)]
    var to_append: string = ""

    if d0[d0.len - 2..<d0.len] == ".0":
        d0 = d0[0..<d0.len-2]

    if d1[d1.len - 2..<d1.len] == ".0":
        d1 = d1[0..<d1.len-2]

    to_append.append("    " & register & " = " & d0 & " ^ " & d1)
    return to_append

#
vm_transpiler_lua["COPY"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    to_append.append("    " & d0 & " = " & d1 & "")
    return to_append

#
vm_transpiler_lua["LBL"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    to_append.append("\n    ::" & d0 & "::")
    return to_append

#
vm_transpiler_lua["JMP"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    to_append.append("    goto " & d0)
    return to_append


vm_transpiler_lua["JNZ"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    to_append.append("    if sra ~= 0 then")
    to_append.append("        goto " & d0)
    to_append.append("    end")
    return to_append


vm_transpiler_lua["JEZ"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    to_append.append("    if sra == 0 then")
    to_append.append("        goto " & d0)
    to_append.append("    end")
    return to_append


#
vm_transpiler_lua["CMP"] = proc(d0: string, d1: string, d2: string): string =
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

    to_append.append("    compare( " & d0 & ", " & d1 & ")")
    return to_append

#
vm_transpiler_lua["EXIT"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    to_append.append("    os.exit(" & d0 & ")")
    return to_append

#
vm_transpiler_lua["INC"] = proc(d0: string, d1: string, d2: string): string =
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

    #to_append.append("    &setRegister(\"srb\", 1);")
    to_append.append("    " & d1 & " = " & d1 & " + 1")
    return to_append

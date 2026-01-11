import tables
import strutils
import ../../../../core/memory

var vm_transpiler_c* = initTable[string, proc(d0: string, d1: string, d2: string): string]()
var labels: Table[string, int] = initTable[string, int]()

# Utility Functions #
proc append(to: var string, data: string): string {.discardable.} =
    to = to & data & "\n"
    return to



# Compiler Boilerplate #
vm_transpiler_c["__required"] = proc(d0: string, d1: string, d2: string): string =
    return ""

vm_transpiler_c["__makeTemp"] = proc(d0: string, d1: string, d2: string): string =
    return ""

vm_transpiler_c["__comment"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    DebugInformation.add("    " & d1 & " => " & d2)
    return to_append.append("# " & d0)

vm_transpiler_c["__finalize"] = proc(d0: string, d1: string, d2: string): string =
    return ""


# Transpiler Functions #
vm_transpiler_c["NOP"] = proc(d0: string, d1: string, d2: string): string =
    return ""

#
vm_transpiler_c["STORE"] = proc(d0: string, d1: string, d2: string): string =
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
        to_append.append("    let G" & d0[1..<d0.len] & " = " & d1 & ";")
    of '$':
        to_append.append("    let L" & d0[1..<d0.len] & " = " & d1 & ";")
    of '%':
        to_append.append("    let B" & d0[1..<d0.len] & " = " & d1 & ";")
    of '[':
        let d2: string = d0[1..<d0.len - 1]
        to_append.append("    " & d2 & " = " & d1 & ";")
    else:
        return ""

    return to_append

#
vm_transpiler_c["READ"] = proc(d0: string, d1: string, d2: string): string =
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

    to_append.append("    " & d0 & " = prompt()")
    return to_append

#
vm_transpiler_c["WRITE"] = proc(d0: string, d1: string, d2: string): string =
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

    to_append.append("    printf(" & d0 & ");")
    return to_append

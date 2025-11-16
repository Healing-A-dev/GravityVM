import tables
import strutils
import ../../../core/memory

var vm_transpiler* = initTable[string, proc(d0: string, d1: string, d2: string): string]()
var variables*: Table[string, string] = initTable[string, string]()


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
    return to_append.append("-- " & d0)


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
        to_append.append("    our $G" & d0[1..<d0.len] & "_gravityV = " & d1 & ";")
    of '$':
        to_append.append("    my $L" & d0[1..<d0.len] & "_gravityV = " & d1 & ";")
    of '%':
        to_append.append("    my $B" & d0[1..<d0.len] & "_gravityV = " & d1 & ";")
    of '[':
        echo "Working on it"
    else:
        return ""

    return to_append


vm_transpiler["WRITE"] = proc(d0: string, d1: string, d2: string): string =
    var d0: string = d0
    var d1: string = d1
    var d2: string = d2
    var to_append: string = ""

    case d0[0]
    of '@':
        d0 = "$G" & d0[1..<d0.len] & "_gravityV"
    of '$':
        d0 = "$L" & d0[1..<d0.len] & "_gravityV"
    of '%':
        d0 = "$B" & d0[1..<d0.len] & "_gravityV"
    of '[':
        let d3: string = d0[1..<(d0.len - 1)]
        if REGISTER.hasKey(d3):
            if REGISTER[d3] != "":
                d0 = "\"" & REGISTER[d3] & "\""
        else:
            d0 = "\"" & d3 & "\""
    else:
        echo "WIP"
        return ""

    to_append.append("    print(" & d0 & ");")
        

import memory
import tables
import strutils
import math
import ../codegen/codegen

# OPCODES
var OP*: Table[string, proc(args: OPARGUMENTS): int] = initTable[string, proc(args: OPARGUMENTS): int]()
var OPERROR*: string = ""
var OPWARN*: string = "Warning(s):\n"
var instruction_counter*: int = 0

# Instuctions
let Instructions*: Table[string, string] = {
    "00":    "NOP",     # Done
    "01":    "READ",    # Done
    "02":    "WRITE",   # Done
    "03":    "STORE",   # Done
    "04":    "DEL",     # Done
    "05":    "ADD",     # Done
    "06":    "SUB",     # Done
    "07":    "MUL",     # Done
    "08":    "DIV",     #
    "09":    "EXP",     #
    "0A":    "COPY",    # Done
    "0B":    "JMP",     # Done
    "0C":    "JNZ",     # Done
    "0D":    "CMP",     # Done
    "0E":    "INC",     # Done
    "0F":    "DEC",     # Done
    "0G":    "UPD",     # Done
    "0H":    "MALLOC",  # Done
    "0I":    "FREE",    # Done
    "0J":    "LBL",     # Done
    "0K":    "JEZ",     #
    "0L":    "EXIT",    # Done
}.toTable()


# Utility
proc call(memory_pool: ref Table[string, string], address: string, pool_type: string): auto {.discardable.} =
    if memory_pool[].hasKey(address):
        return memory_pool[][address]
    else:
        echo "\e[1mgravity: <\e[91mFATAL-Error\e[0m\e[1m>\e[0m"
        echo "|> Compilation Stopped!"
        echo "|> Reason: Invalid [" & pool_type & "] Memory Address: " & address
        echo "|> Where:"
        echo "|\e[90m--------\e[0m> File: " & c_input
        echo "|\e[90m--------\e[0m> Line: " & $((instruction_counter / 4) + 1)
        quit()


proc getType(data: string): tuple[Type: string, Value: string]=
    var data_type: string = ""
    var data: string = data
    if data[0] == '[':
        data = data[1..data.len-2]
        if data[data.len-2..data.len-1] == ".0":
            data = data[0..data.len-3]
        try:
            # Int
            discard parseInt(data)
            data_type = "int"
        except:
            try:
                # Floats
                discard parseFloat(data)
                data_type = "float"
            except:
                data_type = "string"

    return (Type: data_type, Value: data)



#[ OPERATIONS ]#

# NOP
OP["NOP"] = proc(args: OPARGUMENTS): int =
    C("TEXT", "NOP", "", "", "")
    return 0


# READ
OP["READ"] = proc(args: OPARGUMENTS): int =
    var arg2: string = ""
    var arg3: string = "@STDIN@" & args.memory_address
    case args.memory_address[0]
    of '@':
        arg2 = args.memory_address[1..<args.memory_address.len]
        if not POOL_GLOBAL[].hasKey(arg2):
            OPERROR = "Invalid [Global] Memory Address: '" & arg2 & "'"
            return 3
        POOL_GLOBAL[].Store(arg2, arg3, MAX_SIZE_GLOBAL[])
        C("TEXT", "READ", args.memory_address, "", "")

    of '$':
        arg2 = args.memory_address[1..<args.memory_address.len]
        if not POOL_LOCAL[].hasKey(arg2):
            OPERROR = "Invalid [Local] Memory Address: '" & arg2 & "'"
            return 3
        POOL_LOCAL[].Store(arg2, arg3, MAX_SIZE_LOCAL[])
        C("TEXT", "READ", args.memory_address, "", "")

    of '%':
        arg2 = args.memory_address[1..<args.memory_address.len]
        if not POOL_BUFFER[].hasKey(arg2):
            OPERROR = "Invalid [Buffer] Memory Address: '" & arg2 & "'"
            return 3
        POOL_BUFFER[].Store(arg2, arg3, MAX_SIZE_BUFFER[])
        C("TEXT", "READ", args.memory_address, "", "")

    of '[':
        arg2 = args.memory_address[1..<args.memory_address.len - 1]
        if not REGISTER.hasKey(arg2):
            OPERROR = "Invalid Memory Address Pointer: '" & arg2 & "'"
            return 3
        REGISTER[args.memory_address] = "@STDIN@" & args.memory_address
        C("TEXT", "READ", args.memory_address, "", "")

    else:
        OPERROR = "Invalid Memory Location: '" & args.memory_address & "'"
        return 3

    C("TEXT", "__comment", "    instr_" & $(instruction_counter/4) & ": READ", "READ", args.memory_address)
    return 0


# WRITE
OP["WRITE"] = proc(args: OPARGUMENTS): int =
    # Instance Variables #
    var data: string = ""
    case args.memory_address[0]
    of '@':
        if POOL_GLOBAL.hasKey("" & args.memory_address[1..<args.memory_address.len]):
            data = POOL_GLOBAL[args.memory_address[1..<args.memory_address.len]]
        else:
            OPERROR = "Invalid [Global] Memory Address: '" & args.memory_address[1..<args.memory_address.len] & "'"
            return 3

    of '[':
        data = args.memory_address[1..<(args.memory_address.len - 1)]
        if REGISTER.hasKey(args.memory_address[1..<(args.memory_address.len - 1)]) and REGISTER[args.memory_address[1..<(args.memory_address.len - 1)]] != "":
            data = REGISTER[args.memory_address[1..<(args.memory_address.len - 1)]]

        # Removing '[' and ']'
        if data[0] == '[':
            data = data[1..<(data.len - 1)]

    of '$':
        if POOL_LOCAL.hasKey(args.memory_address[1..<args.memory_address.len]):
            data = POOL_LOCAL[args.memory_address[1..<args.memory_address.len]]
        else:
            OPERROR = "Invalid [Local] Memory Address: '" & args.memory_address[1..<args.memory_address.len] & "'"
            return 3

    of '%':
            if POOL_BUFFER.hasKey(args.memory_address[1..<args.memory_address.len]):
                data = POOL_BUFFER[args.memory_address[1..<args.memory_address.len]]
            else:
                OPERROR = "Invalid [Buffer] Memory Address: '" & args.memory_address[1..<args.memory_address.len] & "'"
                return 3

    else:
        OPERROR = "Invalid Memory Address Pointer: '" & args.memory_address & "'"
        return 3

    C("TEXT", "__comment", "  instr_" & $(instruction_counter/4) & ": WRITE", "WRITE", args.memory_address)
    C("TEXT", "WRITE", args.memory_address, $data.len, $data)
    return 0


# STORE
OP["STORE"] = proc(args: OPARGUMENTS): int =
    # Instance Variables
    var memory_address: string = args.memory_address
    var arg0: string = args.arg0
    var arg1: string = args.arg1

    # Argument
    case arg0[0]
    of '@':
        arg0 = arg0.replace("@", "")
        arg0 = call(POOL_GLOBAL, arg0, "Global")
    of '$':
        arg0 = arg0.replace("$", "")
        arg0 = call(POOL_LOCAL, arg0, "Local")
    of '%':
        arg0 = arg0.replace("%", "")
        arg0 = call(POOL_BUFFER, arg0, "Buffer")
    of '[':
        arg0 = arg0[1..<(arg0.len - 1)]
        if REGISTER.hasKey(arg0) and REGISTER[arg0] != "":
            arg0 = REGISTER[arg0]
    else:
        discard

    case memory_address[0]
    of '@':
        ADDR_BUFFER = memory_address[1..<memory_address.len]
        POOL_GLOBAL[].Store(ADDR_BUFFER, arg0, MAX_SIZE_GLOBAL[])
        ADDR_GLOBAL = ADDR_BUFFER
        ADDR_BUFFER.Zero()
        C("DATA", "__comment", "  instr_" & $(instruction_counter/4) & ": STORE", "STORE", $arg0.replace("\n","\\n") & " -> " & memory_address)
        C("DATA", "STORE", memory_address, arg0, "")
        return 0
    of '$':
        ADDR_BUFFER = memory_address[1..<memory_address.len]
        POOL_LOCAL[].Store(ADDR_BUFFER, arg0, MAX_SIZE_LOCAL[])
        ADDR_LOCAL = ADDR_BUFFER
        ADDR_BUFFER.Zero()
        C("DATA", "__comment", "  instr_" & $(instruction_counter/4) & ": STORE", "STORE", $arg0.replace("\n","\\n") & " -> " & memory_address)
        C("DATA", "STORE", memory_address, arg0, "")
        return 0
    of '%':
        ADDR_BUFFER = memory_address[1..<memory_address.len]
        POOL_BUFFER[].Store(ADDR_BUFFER, arg0, MAX_SIZE_BUFFER[])
        C("DATA", "__comment", "  instr_" & $(instruction_counter/4) & ": STORE", "STORE", $arg0.replace("\n","\\n") & " -> " & memory_address)
        C("DATA", "STORE", memory_address, arg0, "")
        return 0
    of '[':
        let register = memory_address[1..<(memory_address.len - 1)]
        if REGISTER.hasKey(register):
            C("DATA", "__comment", "  instr_" & $(instruction_counter/4) & ": STORE", "STORE", "[" & register & "]")
            REGISTER[register] = arg0
        else:
            OPERROR = "Invalid Register Location: '" & register & "'"
            return 3
    else:
        OPERROR = "Invalid Memory Pointer: '" & memory_address[0] & "'"
        return 3



# DEL
OP["DEL"] = proc(args: OPARGUMENTS): int =
    var memory_address: string = args.memory_address
    case memory_address[0]
    of '@':
        memory_address = memory_address.replace("@", "")
        ADDR_BUFFER = args.memory_address
        POOL_GLOBAL[].Remove(ADDR_BUFFER)
        ADDR_GLOBAL = ADDR_BUFFER
        ADDR_BUFFER.Zero()
        C("VOID", "__comment", "  instr_" & $(instruction_counter/4) & ": DEL", "DEL", "[@" & ADDR_GLOBAL & "]")
    of '$':
        memory_address = memory_address.replace("$", "")
        ADDR_BUFFER = memory_address
        POOL_LOCAL[].Remove(ADDR_BUFFER)
        ADDR_LOCAL = ADDR_BUFFER
        ADDR_BUFFER.Zero()
        C("VOID", "__comment", "  instr_" & $(instruction_counter/4) & ": DEL", "DEL", "[" & ADDR_LOCAL & "]")
    of '%':
        memory_address = memory_address.replace("%", "")
        ADDR_BUFFER = memory_address
        POOL_BUFFER[].Remove(ADDR_BUFFER)
        C("VOID", "__comment", "  instr_" & $(instruction_counter/4) & ": DEL", "DEL", "[" & ADDR_BUFFER & "]")
    else:
        return 3

    return 0


# COPY
OP["COPY"] = proc(args: OPARGUMENTS): int =
    # Instance Variables
    var POOL_0: ref Table[string, string]
    var POOL_1: ref Table[string, string]
    var using_register: bool = false
    var using_mempool: bool = false
    var new_value: bool = false
    var args: tuple = args

    # arg0
    case args.arg0[0]:
    of '@':
        args.arg0 = args.arg0[1..<args.arg0.len]
        POOL_0 = POOL_GLOBAL
        using_mempool = true
    of '$':
        args.arg0 = args.arg0[1..<args.arg0.len]
        POOL_0 = POOL_LOCAL
        using_mempool = true
    of '%':
        args.arg0 = args.arg0[1..<args.arg0.len]
        POOL_0 = POOL_BUFFER
        using_mempool = true
    of '[':
        new_value = true
        args.arg0 = args.arg0[1..<(args.arg0.len - 1)]
        if not REGISTER.hasKey(args.arg0) or REGISTER[args.arg0] == "":
            OPERROR = "INVLIAD OR EMPTY REGISTER ADDRES " & args.arg0
            return 3
        args.arg0 = REGISTER[args.arg0]
    else:
        return 3


    # Update memory address
    case args.memory_address[0]
    of '@':
        if not new_value:
            if POOL_GLOBAL[].hasKey(args.arg0):
                C("VOID", "__comment", "  instr_" & $(instruction_counter/4) & ": COPY", "COPY", "[@" & args.arg0 & " -> @" & args.memory_address[1..<args.memory_address.len] & "]")
                POOL_GLOBAL[][args.memory_address[1..<args.memory_address.len]] = POOL_0[][args.arg0]
            else:
                OPERROR = "Invalid [Global] Memory Address: '" & args.memory_address[1..<args.memory_address.len] & "'"
                return 3
        else:
            C("VOID", "__comment", "  instr_" & $(instruction_counter/4) & ": COPY", "COPY", "[" & $args.arg0.replace("\n","\\n") & " -> @" & args.memory_address[1..<args.memory_address.len] & "]")
            POOL_GLOBAL[][args.memory_address[1..<args.memory_address.len]] = args.arg0
        POOL_1 = POOL_GLOBAL
    of '$':
        if not new_value:
            if POOL_LOCAL[].hasKey(args.arg0):
                C("VOID", "__comment", "  instr_" & $(instruction_counter/4) & ": COPY", "COPY", "[$" & args.arg0 & " -> $" & args.memory_address[1..<args.memory_address.len] & "]")
                POOL_LOCAL[][args.memory_address[1..<args.memory_address.len]] = POOL_0[][args.arg0]
            else:
                OPERROR = "Invalid [Local] Memory Address: '" & args.memory_address[1..<args.memory_address.len] & "'"
                return 3
        else:
            C("VOID", "__comment", "  instr_" & $(instruction_counter/4) & ": COPY", "COPY", "[" & $args.arg0.replace("\n","\\n") & " -> $" & args.memory_address[1..<args.memory_address.len] & "]")
            POOL_LOCAL[][args.memory_address[1..<args.memory_address.len]] = args.arg0
        POOL_1 = POOL_LOCAL
    of '%':
        if not new_value:
            if POOL_BUFFER[].hasKey(args.arg0):
                C("VOID", "__comment", "  instr_" & $(instruction_counter/4) & ": COPY", "COPY", "[%" & args.arg0 & " -> %" & args.memory_address[1..<args.memory_address.len] & "]")
                POOL_BUFFER[][args.memory_address[1..<args.memory_address.len]] = POOL_0[][args.arg0]
            else:
                OPERROR = "Invalid [Buffer] Memory Address: '" & args.memory_address[1..<args.memory_address.len] & "'"
                return 3
        else:
            C("VOID", "__comment", "  instr_" & $(instruction_counter/4) & ": COPY", "COPY", "[" & $args.arg0.replace("\n","\\n") & " -> %" & args.memory_address[1..<args.memory_address.len] & "]")
            POOL_BUFFER[][args.memory_address[1..<args.memory_address.len]] = args.arg0
        POOL_1 = POOL_BUFFER
    of '[':
        if REGISTER.hasKey(args.memory_address[1..<(args.memory_address.len - 1)]):
            C("VOID", "__comment", "  instr_" & $(instruction_counter/4) & ": COPY", "COPY", "[" & args.arg0 & " -> " & args.memory_address[1..<args.memory_address.len] & "]")
            REGISTER[args.memory_address[1..<(args.memory_address.len - 1)]] = args.arg0
        else:
            OPERROR = "Invalid [Register] Location: '" & args.memory_address[1..<args.memory_address.len] & "'"
            return 3
        using_register = true
    else:
        return 3

    if not using_register:
        if new_value:
            if args.arg0[0] == '[' and args.arg0[args.arg0.len - 1] == ']':
                args.arg0 = args.arg0[1..<(args.arg0.len - 1)]
            C("DATA", "__comment", "  instr_" & $(instruction_counter/4) & ": STORE", "STORE", "[" & args.memory_address & "]")
            C("DATA", "STORE", args.memory_address, $args.arg0, "")
            # C("TEXT", "UPD", args.memory_address, $args.arg0, "")
        else:
            C("DATA", "__comment", "  instr_" & $(instruction_counter/4) & ": STORE", "STORE", "[" & args.memory_address & "]")
            C("DATA", "STORE", args.memory_address, $POOL_0[args.arg0], "")
            # C("TEXT", "UPD", args.memory_address, $POOL_0[args.arg0], "")
    else:
         C("TEXT", "STORE REGISTER", args.memory_address, $args.arg0,"")

    return 0


# MALLOC
OP["MALLOC"] = proc(args: OPARGUMENTS): int =
    # Instance Variables
    var MAX_SIZE: ref int
    var POOL_0: ref Table[string, string]
    var current_address: string = ""
    var data: string = ""
    var size_t: int = 0
    var args: tuple = args
    var mem_type: string = ""

    case args.memory_address:
    of "@00":
        current_address = POOL_GLOBAL[].NextAddress()
        POOL_0 = POOL_GLOBAL
        MAX_SIZE = MAX_SIZE_GLOBAL
        mem_type = "GLOBAL"
    of "$00":
        current_address = POOL_LOCAL[].NextAddress()
        POOL_0 = POOL_LOCAL
        MAX_SIZE = MAX_SIZE_LOCAL
        mem_type = "LOCAL"
    of "%00":
        current_address = POOL_BUFFER[].NextAddress()
        POOL_0 = POOL_BUFFER
        MAX_SIZE = MAX_SIZE_BUFFER
        mem_type = "BUFFER"
    else:
        OPERROR = "Invalid Memory Pool Address: '" & args.memory_address & "'"
        return 3

    case args.arg0[0]:
    of '@':
        args.arg0 = args.arg0.replace("@", "")
        args.arg0 = call(POOL_GLOBAL, args.arg0, "Global")
    of '$':
        args.arg0 = args.arg0.replace("$", "")
        args.arg0 = call(POOL_LOCAL, args.arg0, "Local")
    of '%':
        args.arg0 = args.arg0.replace("%", "")
        args.arg0 = call(POOL_BUFFER, args.arg0, "Buffer")
    of '[':
        args.arg0 = args.arg0[1..<(args.arg0.len - 1)]
        args.arg0 = REGISTER[args.arg0]
    else:
        discard

    if parseInt("" & args.arg0[0]) == 0:
        size_t = parseInt("" & args.arg0[0])
    else:
        size_t = parseInt(args.arg0)

    current_address.Decrease()

    for count in 1..size_t+1:
        POOL_0[].Store(current_address, data, 3843)

    MAX_SIZE[] = POOL_0[].len
    C("VOID", "__comment", "  instr_" & $(instruction_counter/4) & ": MALLOC", "MALLOC", "[" & $size_t & " -> " & mem_type & "]")

    return 0


# ADD
OP["ADD"] = proc(args: OPARGUMENTS): int =
    # Instance Variables
    var POOL_0: ref Table[string, string]
    var POOL_1: ref Table[string, string]
    var POOL_2: ref Table[string, string]
    var register00: float = 0.00
    var register10: float = 0.00
    var register0: string = ""
    var register1: string = ""
    var register2: string = ""
    var symbol: char = args.arg1[0]
    var sum: string = ""
    var args: tuple = args

    # Memory Address
    case args.memory_address[0]
    of '@':
        args.memory_address = args.memory_address.replace("@", "")
        POOL_0 = POOL_GLOBAL
    of '$':
        args.memory_address = args.memory_address.replace("$", "")
        POOL_0 = POOL_LOCAL
    of '%':
        args.memory_address = args.memory_address.replace("%", "")
        POOL_0 = POOL_BUFFER
    of '[':
        args.memory_address = args.memory_address[1..<(args.memory_address.len - 1)]
        if REGISTER.hasKey(args.memory_address) and REGISTER[args.memory_address] != "":
            register0 = args.memory_address
        else:
            OPERROR = "Invalid or Empty Register Address: '" & args.memory_address & "'"
            return 3
    else:
        return 3

    # Address to add
    case args.arg0[0]
    of '@':
        args.arg0 = args.arg0.replace("@", "")
        POOL_1 = POOL_GLOBAL
    of '$':
        args.arg0 = args.arg0.replace("$", "")
        POOL_1 = POOL_LOCAL
    of '%':
        args.arg0 = args.arg0.replace("%", "")
        POOL_1 = POOL_BUFFER
    of '[':
        args.arg0 = args.arg0[1..<(args.arg0.len - 1)]
        if REGISTER.hasKey(args.arg0) and REGISTER[args.arg0] != "":
            register1 = args.arg0
        else:
            OPERROR = "Invalid or Empty Memory Address: '" & args.arg0 & "'"
            return 3
    else:
        return 3

    # Return Address/Register
    case args.arg1[0]
    of '@':
        args.arg1 = args.arg1.replace("@", "")
        POOL_2 = POOL_GLOBAL
    of '$':
        args.arg1 = args.arg1.replace("$", "")
        POOL_2 = POOL_LOCAL
    of '%':
        args.arg1 = args.arg1.replace("%", "")
        POOL_2 = POOL_BUFFER
    of '[':
        args.arg1 = args.arg1[1..<(args.arg1.len - 1)]
        if REGISTER.hasKey(args.arg1):
            register2 = args.arg1
        else:
            OPERROR = "Invalid Register Address: '" & args.arg1 & "'"
            return 3
    else:
        register2 = "[sra]"


    # Gathering Address/Register Data Slot0 #
    if register0 == "":
        if POOL_0[].hasKey(args.memory_address):
            try:
                case POOL_0[][args.memory_address][0]
                of '[':
                    var tmp: string = POOL_0[][args.memory_address]
                    tmp = tmp[1..tmp.len-2]
                    register00 = parseFloat(tmp)
                else:
                    register00 = parseFloat(POOL_0[][args.memory_address])
            except ValueError as e:
                OPERROR = "Attempt to perform arithmetic operation on " & $typeof(POOL_0[][args.memory_address]) & " '" & POOL_1[][args.arg0] & "'"
                return 3
        else:
            OPERROR = "Invalid Memeory Address: '" & args.memory_address & "'"
            return 3
    else:
        try:
            register00 = parseFloat(REGISTER[register0])
        except ValueError as e:
            OPERROR = e.msg
            return 3

    # Gathering Address/Register Data Slot1 #
    if register1 == "":
        if POOL_1[].hasKey(args.arg0):
            try:
                case POOL_1[][args.arg0][0]
                of '[':
                    var tmp: string = POOL_1[][args.arg0]
                    tmp = tmp[1..tmp.len-2]
                    register10 = parseFloat(tmp)
                else:
                    register10 = parseFloat(POOL_1[][args.arg0])
            except ValueError as e:
                if not (POOL_1[][args.arg0].contains("@STDIN@") and  POOL_1[][args.arg0].contains(args.arg0)):
                    OPERROR = "Attempt to perform arithmetic operation on " & $typeof(POOL_1[][args.arg0]) & " '" & POOL_1[][args.arg0] & "'"
                    return 3
        else:
            OPERROR = "Invalid Memory Address: '" & args.arg0 & "'"
            return 3
    else:
        try:
            case REGISTER[register1][0]
            of '[':
                var tmp: string = REGISTER[register1]
                tmp = tmp[1..tmp.len-2]
                register10 = parseFloat(tmp)
            else:
                register10 = parseFloat(REGISTER[register1])
        except ValueError as e:
            OPERROR = "Invalid Float '" & REGISTER[register1] & "'"
            return 3

    # Adding Values
    sum = $(register00 + register10)
    OPWARN = OPWARN & "\tIMPLEMENT NEGATIVE NUMBER ADDING\n"
    if sum[sum.len-2..sum.len-1] == ".0":
        sum = sum[0..sum.len-3]
    if sum.len > 2:
        sum = "[" & sum & "]"

    # Storing Data
    if register2 == "":
        var address: string = symbol & args.arg1
        var nop = ""
        if OP["COPY"]((address, sum, nop)) != 0:
            return 3
    else:
        var address: string = register2[1..<(register2.len - 1)]
        REGISTER[address] = sum

    C("VOID", "__comment", "  instr_" & $(instruction_counter/4) & ": ADD", "ADD", "[" & $register00 & " + " & $register10 & "]")
    C("TEXT", "ADD", $register00, $register10, register2)
    return 0


# SUB
OP["SUB"] = proc(args: OPARGUMENTS): int =
    # Instance Variables
    var POOL_0: ref Table[string, string]
    var POOL_1: ref Table[string, string]
    var POOL_2: ref Table[string, string]
    var register00: float = 0.00
    var register10: float = 0.00
    var register0: string = ""
    var register1: string = ""
    var register2: string = ""
    var symbol: char = args.arg1[0]
    var difference: string = ""
    var args: tuple = args

    # Memory Address
    case args.memory_address[0]
    of '@':
        args.memory_address = args.memory_address.replace("@", "")
        POOL_0 = POOL_GLOBAL
    of '$':
        args.memory_address = args.memory_address.replace("$", "")
        POOL_0 = POOL_LOCAL
    of '%':
        args.memory_address = args.memory_address.replace("%", "")
        POOL_0 = POOL_BUFFER
    of '[':
        args.memory_address = args.memory_address[1..<(args.memory_address.len - 1)]
        if REGISTER.hasKey(args.memory_address) and REGISTER[args.memory_address] != "":
            register0 = args.memory_address
        else:
            OPERROR = "Invalid or Empty Register Address: '" & args.memory_address & "'"
            return 3
    else:
        return 3

    # Address to subtract
    case args.arg0[0]
    of '@':
        args.arg0 = args.arg0.replace("@", "")
        POOL_1 = POOL_GLOBAL
    of '$':
        args.arg0 = args.arg0.replace("$", "")
        POOL_1 = POOL_LOCAL
    of '%':
        args.arg0 = args.arg0.replace("%", "")
        POOL_1 = POOL_BUFFER
    of '[':
        args.arg0 = args.arg0[1..<(args.arg0.len - 1)]
        if REGISTER.hasKey(args.arg0) and REGISTER[args.arg0] != "":
            register1 = args.arg0
        else:
            OPERROR = "Invalid or Empty Memory Address: '" & args.arg0 & "'"
            return 3
    else:
        return 3

    # Return Address/Register
    case args.arg1[0]
    of '@':
        args.arg1 = args.arg1.replace("@", "")
        POOL_2 = POOL_GLOBAL
    of '$':
        args.arg1 = args.arg1.replace("$", "")
        POOL_2 = POOL_LOCAL
    of '%':
        args.arg1 = args.arg1.replace("%", "")
        POOL_2 = POOL_BUFFER
    of '[':
        args.arg1 = args.arg1[1..<(args.arg1.len - 1)]
        if REGISTER.hasKey(args.arg1):
            register2 = args.arg1
        else:
            OPERROR = "Invalid Register Address: '" & args.arg1 & "'"
            return 3
    else:
        register2 = "[sra]"


    # Gathering Address/Register Data Slot0 #
    if register0 == "":
        if POOL_0[].hasKey(args.memory_address):
            try:
                case POOL_0[][args.memory_address][0]
                of '[':
                    var tmp: string = POOL_0[][args.memory_address]
                    tmp = tmp[1..tmp.len-2]
                    register00 = parseFloat(tmp)
                else:
                    register00 = parseFloat(POOL_0[][args.memory_address])
            except ValueError as e:
                OPERROR = "Attempt to perform arithmetic operation on " & $typeof(POOL_0[][args.memory_address]) & " '" & POOL_1[][args.arg0] & "'"

                return 3
        else:
            OPERROR = "Invalid Memeory Address: '" & args.memory_address & "'"
            return 3
    else:
        try:
            register00 = parseFloat(REGISTER[register0])
        except ValueError as e:
            OPERROR = e.msg
            return 3

    # Gathering Address/Register Data Slot1 #
    if register1 == "":
        if POOL_1[].hasKey(args.arg0):
            try:
                case POOL_1[][args.arg0][0]
                of '[':
                    var tmp: string = POOL_1[][args.arg0]
                    tmp = tmp[1..tmp.len-2]
                    register10 = parseFloat(tmp)
                else:
                    register10 = parseFloat(POOL_1[][args.arg0])
            except ValueError as e:
                OPERROR = "Attempt to perform arithmetic operation on " & $typeof(POOL_1[][args.arg0]) & " '" & POOL_1[][args.arg0] & "'"
                return 3
        else:
            OPERROR = "Invalid Memory Address: '" & args.arg0 & "'"
            return 3
    else:
        try:
            case REGISTER[register1][0]
            of '[':
                var tmp: string = REGISTER[register1]
                tmp = tmp[1..tmp.len-2]
                register10 = parseFloat(tmp)
            else:
                register10 = parseFloat(REGISTER[register1])
        except ValueError as e:
            OPERROR = "Invalid Float '" & REGISTER[register1] & "'"
            return 3

    # Subtracting Values
    difference = $(register00 - register10)
    OPWARN = OPWARN & "\tIMPLEMENT NEGATIVE NUMBER SUBTRACTING\n"
    if difference[difference.len-2..difference.len-1] == ".0":
        difference = difference[0..difference.len-3]
    if difference.len > 2:
        difference = "[" & difference & "]"

    # Storing Data
    if register2 == "":
        var address: string = symbol & args.arg1
        var nop = ""
        if OP["COPY"]((address, difference, nop)) != 0:
            return 3
    else:
        var address: string = register2[1..<(register2.len - 1)]
        REGISTER[address] = difference

    C("VOID", "__comment", "  instr_" & $(instruction_counter/4) & ": SUB", "SUB", "[" & $register00 & " - " & $register10 & "]")
    C("TEXT", "SUB", $register00, $register10, register2[1..<(register2.len - 1)])
    return 0


# MUL
OP["MUL"] = proc(args: OPARGUMENTS): int =
    # Instance Variables
    var POOL_0: ref Table[string, string]
    var POOL_1: ref Table[string, string]
    var POOL_2: ref Table[string, string]
    var register00: float = 0.00
    var register10: float = 0.00
    var register0: string = ""
    var register1: string = ""
    var register2: string = ""
    var symbol: char = args.arg1[0]
    var product: string = ""
    var args: tuple = args

    # Memory Address
    case args.memory_address[0]
    of '@':
        args.memory_address = args.memory_address.replace("@", "")
        POOL_0 = POOL_GLOBAL
    of '$':
        args.memory_address = args.memory_address.replace("$", "")
        POOL_0 = POOL_LOCAL
    of '%':
        args.memory_address = args.memory_address.replace("%", "")
        POOL_0 = POOL_BUFFER
    of '[':
        args.memory_address = args.memory_address[1..<(args.memory_address.len - 1)]
        if REGISTER.hasKey(args.memory_address) and REGISTER[args.memory_address] != "":
            register0 = args.memory_address
        else:
            OPERROR = "Invalid or Empty Register Address: '" & args.memory_address & "'"
            return 3
    else:
        return 3

    # Address to multiply
    case args.arg0[0]
    of '@':
        args.arg0 = args.arg0.replace("@", "")
        POOL_1 = POOL_GLOBAL
    of '$':
        args.arg0 = args.arg0.replace("$", "")
        POOL_1 = POOL_LOCAL
    of '%':
        args.arg0 = args.arg0.replace("%", "")
        POOL_1 = POOL_BUFFER
    of '[':
        args.arg0 = args.arg0[1..<(args.arg0.len - 1)]
        if REGISTER.hasKey(args.arg0) and REGISTER[args.arg0] != "":
            register1 = args.arg0
        else:
            OPERROR = "Invalid or Empty Memory Address: '" & args.arg0 & "'"
            return 3
    else:
        return 3

    # Return Address/Register
    case args.arg1[0]
    of '@':
        args.arg1 = args.arg1.replace("@", "")
        POOL_2 = POOL_GLOBAL
    of '$':
        args.arg1 = args.arg1.replace("$", "")
        POOL_2 = POOL_LOCAL
    of '%':
        args.arg1 = args.arg1.replace("%", "")
        POOL_2 = POOL_BUFFER
    of '[':
        args.arg1 = args.arg1[1..<(args.arg1.len - 1)]
        if REGISTER.hasKey(args.arg1):
            register2 = args.arg1
        else:
            OPERROR = "Invalid Register Address: '" & args.arg1 & "'"
            return 3
    else:
        register2 = "[sra]"


    # Gathering Address/Register Data Slot0 #
    if register0 == "":
        if POOL_0[].hasKey(args.memory_address):
            try:
                case POOL_0[][args.memory_address][0]
                of '[':
                    var tmp: string = POOL_0[][args.memory_address]
                    tmp = tmp[1..tmp.len-2]
                    register00 = parseFloat(tmp)
                else:
                    register00 = parseFloat(POOL_0[][args.memory_address])
            except ValueError as e:
                OPERROR = "Attempt to perform arithmetic operation on " & $typeof(POOL_0[][args.memory_address]) & " '" & POOL_1[][args.arg0] & "'"

                return 3
        else:
            OPERROR = "Invalid Memeory Address: '" & args.memory_address & "'"
            return 3
    else:
        try:
            register00 = parseFloat(REGISTER[register0])
        except ValueError as e:
            OPERROR = e.msg
            return 3

    # Gathering Address/Register Data Slot1 #
    if register1 == "":
        if POOL_1[].hasKey(args.arg0):
            try:
                case POOL_1[][args.arg0][0]
                of '[':
                    var tmp: string = POOL_1[][args.arg0]
                    tmp = tmp[1..tmp.len-2]
                    register10 = parseFloat(tmp)
                else:
                    register10 = parseFloat(POOL_1[][args.arg0])
            except ValueError as e:
                OPERROR = "Attempt to perform arithmetic operation on " & $typeof(POOL_1[][args.arg0]) & " '" & POOL_1[][args.arg0] & "'"
                return 3
        else:
            OPERROR = "Invalid Memory Address: '" & args.arg0 & "'"
            return 3
    else:
        try:
            case REGISTER[register1][0]
            of '[':
                var tmp: string = REGISTER[register1]
                tmp = tmp[1..tmp.len-2]
                register10 = parseFloat(tmp)
            else:
                register10 = parseFloat(REGISTER[register1])
        except ValueError as e:
            OPERROR = "Invalid Float '" & REGISTER[register1] & "'"
            return 3

    # Multiplying Values
    product = $(register00 * register10)
    OPWARN = OPWARN & "\tIMPLEMENT NEGATIVE NUMBER MULTIPLYING\n"
    if product[product.len-2..product.len-1] == ".0":
        product = product[0..product.len-3]
    if product.len > 2:
        product = "[" & product & "]"

    # Storing Data
    if register2 == "":
        var address: string = symbol & args.arg1
        var nop = ""
        if OP["COPY"]((address, product, nop)) != 0:
            return 3
    else:
        var address: string = register2[1..<(register2.len - 1)]
        REGISTER[address] = product

    C("VOID", "__comment", "  instr_" & $(instruction_counter/4) & ": MUL", "MUL", "[" & $register00 & " * " & $register10 & "]")
    C("TEXT", "MUL", $register00, $register10, register2[1..<(register2.len - 1)])
    return 0


# DIV
OP["DIV"] = proc(args: OPARGUMENTS): int =
    # Instance Variables
    var POOL_0: ref Table[string, string]
    var POOL_1: ref Table[string, string]
    var POOL_2: ref Table[string, string]
    var register00: float = 0.00
    var register10: float = 0.00
    var register0: string = ""
    var register1: string = ""
    var register2: string = ""
    var symbol: char = args.arg1[0]
    var quotient: string = ""
    var args: tuple = args

    # Memory Address
    case args.memory_address[0]
    of '@':
        args.memory_address = args.memory_address.replace("@", "")
        POOL_0 = POOL_GLOBAL
    of '$':
        args.memory_address = args.memory_address.replace("$", "")
        POOL_0 = POOL_LOCAL
    of '%':
        args.memory_address = args.memory_address.replace("%", "")
        POOL_0 = POOL_BUFFER
    of '[':
        args.memory_address = args.memory_address[1..<(args.memory_address.len - 1)]
        if REGISTER.hasKey(args.memory_address) and REGISTER[args.memory_address] != "":
            register0 = args.memory_address
        else:
            OPERROR = "Invalid or Empty Register Address: '" & args.memory_address & "'"
            return 3
    else:
        return 3

    # Address to divide
    case args.arg0[0]
    of '@':
        args.arg0 = args.arg0.replace("@", "")
        POOL_1 = POOL_GLOBAL
    of '$':
        args.arg0 = args.arg0.replace("$", "")
        POOL_1 = POOL_LOCAL
    of '%':
        args.arg0 = args.arg0.replace("%", "")
        POOL_1 = POOL_BUFFER
    of '[':
        args.arg0 = args.arg0[1..<(args.arg0.len - 1)]
        if REGISTER.hasKey(args.arg0) and REGISTER[args.arg0] != "":
            register1 = args.arg0
        else:
            OPERROR = "Invalid or Empty Memory Address: '" & args.arg0 & "'"
            return 3
    else:
        return 3

    # Return Address/Register
    case args.arg1[0]
    of '@':
        args.arg1 = args.arg1.replace("@", "")
        POOL_2 = POOL_GLOBAL
    of '$':
        args.arg1 = args.arg1.replace("$", "")
        POOL_2 = POOL_LOCAL
    of '%':
        args.arg1 = args.arg1.replace("%", "")
        POOL_2 = POOL_BUFFER
    of '[':
        args.arg1 = args.arg1[1..<(args.arg1.len - 1)]
        if REGISTER.hasKey(args.arg1):
            register2 = args.arg1
        else:
            OPERROR = "Invalid Register Address: '" & args.arg1 & "'"
            return 3
    else:
        register2 = "[sra]"


    # Gathering Address/Register Data Slot0 #
    if register0 == "":
        if POOL_0[].hasKey(args.memory_address):
            try:
                case POOL_0[][args.memory_address][0]
                of '[':
                    var tmp: string = POOL_0[][args.memory_address]
                    tmp = tmp[1..tmp.len-2]
                    register00 = parseFloat(tmp)
                else:
                    register00 = parseFloat(POOL_0[][args.memory_address])
            except ValueError as e:
                OPERROR = "Attempt to perform arithmetic operation on " & $typeof(POOL_0[][args.memory_address]) & " '" & POOL_1[][args.arg0] & "'"

                return 3
        else:
            OPERROR = "Invalid Memeory Address: '" & args.memory_address & "'"
            return 3
    else:
        try:
            register00 = parseFloat(REGISTER[register0])
        except ValueError as e:
            OPERROR = e.msg
            return 3

    # Gathering Address/Register Data Slot1 #
    if register1 == "":
        if POOL_1[].hasKey(args.arg0):
            try:
                case POOL_1[][args.arg0][0]
                of '[':
                    var tmp: string = POOL_1[][args.arg0]
                    tmp = tmp[1..tmp.len-2]
                    register10 = parseFloat(tmp)
                else:
                    register10 = parseFloat(POOL_1[][args.arg0])
            except ValueError as e:
                OPERROR = "Attempt to perform arithmetic operation on " & $typeof(POOL_1[][args.arg0]) & " '" & POOL_1[][args.arg0] & "'"
                return 3
        else:
            OPERROR = "Invalid Memory Address: '" & args.arg0 & "'"
            return 3
    else:
        try:
            case REGISTER[register1][0]
            of '[':
                var tmp: string = REGISTER[register1]
                tmp = tmp[1..tmp.len-2]
                register10 = parseFloat(tmp)
            else:
                register10 = parseFloat(REGISTER[register1])
        except ValueError as e:
            OPERROR = "Invalid Float '" & REGISTER[register1] & "'"
            return 3

    # Dividing Values
    quotient = $(register00 / register10)
    OPWARN = OPWARN & "\tIMPLEMENT NEGATIVE NUMBER DIVIDING\n"
    if quotient[quotient.len-2..quotient.len-1] == ".0":
        quotient = quotient[0..quotient.len-3]
    if quotient.len > 2:
        quotient = "[" & quotient & "]"

    # Storing Data
    if register2 == "":
        var address: string = symbol & args.arg1
        var nop = ""
        if OP["COPY"]((address, quotient, nop)) != 0:
            return 3
    else:
        var address: string = register2[1..<(register2.len - 1)]
        REGISTER[address] = quotient

    C("VOID", "__comment", "  instr_" & $(instruction_counter/4) & ": DIV", "DIV", "[" & $register00 & " / " & $register10 & "]")
    C("TEXT", "DIV", $register00, $register10, register2[1..<(register2.len - 1)])
    return 0


# EXP
OP["DIV"] = proc(args: OPARGUMENTS): int =
    # Instance Variables
    var POOL_0: ref Table[string, string]
    var POOL_1: ref Table[string, string]
    var POOL_2: ref Table[string, string]
    var register00: float = 0.00
    var register10: float = 0.00
    var register0: string = ""
    var register1: string = ""
    var register2: string = ""
    var symbol: char = args.arg1[0]
    var power: string = ""
    var args: tuple = args

    # Memory Address
    case args.memory_address[0]
    of '@':
        args.memory_address = args.memory_address.replace("@", "")
        POOL_0 = POOL_GLOBAL
    of '$':
        args.memory_address = args.memory_address.replace("$", "")
        POOL_0 = POOL_LOCAL
    of '%':
        args.memory_address = args.memory_address.replace("%", "")
        POOL_0 = POOL_BUFFER
    of '[':
        args.memory_address = args.memory_address[1..<(args.memory_address.len - 1)]
        if REGISTER.hasKey(args.memory_address) and REGISTER[args.memory_address] != "":
            register0 = args.memory_address
        else:
            OPERROR = "Invalid or Empty Register Address: '" & args.memory_address & "'"
            return 3
    else:
        return 3

    # Address to do exponent stuff....
    case args.arg0[0]
    of '@':
        args.arg0 = args.arg0.replace("@", "")
        POOL_1 = POOL_GLOBAL
    of '$':
        args.arg0 = args.arg0.replace("$", "")
        POOL_1 = POOL_LOCAL
    of '%':
        args.arg0 = args.arg0.replace("%", "")
        POOL_1 = POOL_BUFFER
    of '[':
        args.arg0 = args.arg0[1..<(args.arg0.len - 1)]
        if REGISTER.hasKey(args.arg0) and REGISTER[args.arg0] != "":
            register1 = args.arg0
        else:
            OPERROR = "Invalid or Empty Memory Address: '" & args.arg0 & "'"
            return 3
    else:
        return 3

    # Return Address/Register
    case args.arg1[0]
    of '@':
        args.arg1 = args.arg1.replace("@", "")
        POOL_2 = POOL_GLOBAL
    of '$':
        args.arg1 = args.arg1.replace("$", "")
        POOL_2 = POOL_LOCAL
    of '%':
        args.arg1 = args.arg1.replace("%", "")
        POOL_2 = POOL_BUFFER
    of '[':
        args.arg1 = args.arg1[1..<(args.arg1.len - 1)]
        if REGISTER.hasKey(args.arg1):
            register2 = args.arg1
        else:
            OPERROR = "Invalid Register Address: '" & args.arg1 & "'"
            return 3
    else:
        register2 = "[sra]"


    # Gathering Address/Register Data Slot0 #
    if register0 == "":
        if POOL_0[].hasKey(args.memory_address):
            try:
                case POOL_0[][args.memory_address][0]
                of '[':
                    var tmp: string = POOL_0[][args.memory_address]
                    tmp = tmp[1..tmp.len-2]
                    register00 = parseFloat(tmp)
                else:
                    register00 = parseFloat(POOL_0[][args.memory_address])
            except ValueError as e:
                OPERROR = "Attempt to perform arithmetic operation on " & $typeof(POOL_0[][args.memory_address]) & " '" & POOL_1[][args.arg0] & "'"

                return 3
        else:
            OPERROR = "Invalid Memeory Address: '" & args.memory_address & "'"
            return 3
    else:
        try:
            register00 = parseFloat(REGISTER[register0])
        except ValueError as e:
            OPERROR = e.msg
            return 3

    # Gathering Address/Register Data Slot1 #
    if register1 == "":
        if POOL_1[].hasKey(args.arg0):
            try:
                case POOL_1[][args.arg0][0]
                of '[':
                    var tmp: string = POOL_1[][args.arg0]
                    tmp = tmp[1..tmp.len-2]
                    register10 = parseFloat(tmp)
                else:
                    register10 = parseFloat(POOL_1[][args.arg0])
            except ValueError as e:
                OPERROR = "Attempt to perform arithmetic operation on " & $typeof(POOL_1[][args.arg0]) & " '" & POOL_1[][args.arg0] & "'"
                return 3
        else:
            OPERROR = "Invalid Memory Address: '" & args.arg0 & "'"
            return 3
    else:
        try:
            case REGISTER[register1][0]
            of '[':
                var tmp: string = REGISTER[register1]
                tmp = tmp[1..tmp.len-2]
                register10 = parseFloat(tmp)
            else:
                register10 = parseFloat(REGISTER[register1])
        except ValueError as e:
            OPERROR = "Invalid Float '" & REGISTER[register1] & "'"
            return 3

    # Dividing Values
    power = $(register00 ^ register10)
    OPWARN = OPWARN & "\tIMPLEMENT NEGATIVE NUMBER EXPONENTS\n"
    if power[power.len-2..power.len-1] == ".0":
        power = power[0..power.len-3]
    if power.len > 2:
        power = "[" & power & "]"

    # Storing Data
    if register2 == "":
        var address: string = symbol & args.arg1
        var nop = ""
        if OP["COPY"]((address, power, nop)) != 0:
            return 3
    else:
        var address: string = register2[1..<(register2.len - 1)]
        REGISTER[address] = power

    C("VOID", "__comment", "  instr_" & $(instruction_counter/4) & ": EXP", "EXP", "[" & $register00 & " ^ " & $register10 & "]")
    C("TEXT", "EXP", $register00, $register10, register2[1..<(register2.len - 1)])
    return 0


# INC
OP["INC"] = proc(args: OPARGUMENTS): int =
    # Instance Variables
    var value: string = ""
    var num_value: float = 0
    var nop: string = "00"
    var args: tuple = args
    #if OP["ADD"](memory_address, num, nop) != 0:
        #return 3
    case args.memory_address[0]
    of '@':
        value = call(POOL_GLOBAL, args.memory_address[1..<args.memory_address.len], "Global")
    of '$':
        value = call(POOL_LOCAL, args.memory_address[1..<args.memory_address.len], "Local")
    of '%':
        value = call(POOL_BUFFER, args.memory_address[1..<args.memory_address.len], "Buffer")
    of '[':
        if REGISTER.hasKey(args.memory_address[1..<args.memory_address.len - 1]):
            value = REGISTER[args.memory_address[1..<args.memory_address.len - 1]]
    else:
        OPERROR = "Invalid Memory Address: '" & args.memory_address & "'"
        return 3

    try:
        num_value = parseFloat(value)
    except ValueError as e:
        OPERROR = e.msg
        return 3

    num_value = num_value + 1
    value = $num_value

    if value[value.len-2..<value.len] == ".0":
        value = value[0..<value.len - 2]


    # discard OP["STORE"]((args.memory_address, value, nop))
    C("TEXT", "__comment", "INC", "INC", args.memory_address)
    C("TEXT", "INC", args.memory_address, "", "")

    return 0


# DEC
OP["DEC"] = proc(args: OPARGUMENTS): int =
    # Instance Variables
    var num: string = "[srb]"
    var nop: string = "00"
    var args: tuple = args
    if OP["SUB"]((args.memory_address, num, nop)) != 0:
        return 3

    return 0


# FREE
OP["FREE"] = proc(args: OPARGUMENTS): int =
    var args: tuple = args
    case args.memory_address
    of "@00":
        C("VOID", "__comment", "  instr_" & $(instruction_counter/4) & ": FREE", "FREE", "[GLOBAL]")
        POOL_GLOBAL[].Free()
        ADDR_GLOBAL.Zero()
    of "$00":
        C("VOID", "__comment", "  instr_" & $(instruction_counter/4) & ": FREE", "FREE", "[LOCAL]")
        POOL_LOCAL[].Free()
        ADDR_LOCAL.Zero()
    of "%00":
        C("VOID", "__comment", "  instr_" & $(instruction_counter/4) & ": FREE", "FREE", "[BUFFER]")
        POOL_BUFFER[].Free()
        ADDR_BUFFER.Zero()
    else:
        OPERROR = "INVALID MEMORY POOL ADDRESS: " & args.memory_address
        return 3

    #C("TEXT", "FREE", "", "", "")

    return 0


OP["UPD"] = proc(args: OPARGUMENTS): int =
    # Instance Variables
    var POOL_0: ref Table[string, string]
    var POOL_1: ref Table[string, string]
    var register0: string = ""
    var args: tuple = args

    # Memory Address
    case args.memory_address[0]
    of '@':
        POOL_0 = POOL_GLOBAL
    of '$':
        POOL_0 = POOL_LOCAL
    of '%':
        POOL_0 = POOL_BUFFER
    of '[':
        let arg3 = args.memory_address[1..<(args.memory_address.len - 1)]
        if REGISTER.hasKey(arg3):
            register0 = arg3
        else:
            OPERROR = "INVALID: " & args.memory_address
            return 3
    else:
        return 3

    # echo "UPDATE " & arg0
    C("VOID", "__comment", "UPD", "UPD", args.arg0 & " -> " & args.memory_address)
    C("TEXT", "UPD", args.memory_address, args.arg0, "")
    return 0


# LABEL
OP["LBL"] = proc(args: OPARGUMENTS): int =
    var memory_address: string = args.memory_address
    case memory_address[0]
    of '@':
        memory_address = call(POOL_GLOBAL, memory_address[1..<memory_address.len], "Global")
    of '$':
        memory_address = call(POOL_LOCAL, memory_address[1..<memory_address.len], "Local")
    of '%':
        memory_address = call(POOL_BUFFER, memory_address[1..<memory_address.len], "Buffer")
    of '[':
        let arg3: string = memory_address[1..<memory_address.len - 1]
        if REGISTER.hasKey(arg3):
            memory_address = REGISTER[arg3]
        else:
            memory_address = memory_address[1..<memory_address.len - 1]
    else:
        OPERROR = "Invalid Memory Location: '" & memory_address & "'"
        return 3

    if memory_address == "":
        OPERROR = "Value expected, got: " & memory_address
        return 3
    elif $(typeof(memory_address)) != "string":
        OPERROR = "String value expected, got: " & $(typeof(memory_address))
        return 3

    if LABELS.hasKey(memory_address):
        OPERROR = "Redefinition of label: '" & memory_address & "'"
        return 3

    C("TEXT", "__comment", "LBL", "LBL", memory_address)
    C("TEXT", "LBL", memory_address, "", "")
    LABELS[memory_address] = 0
    return 0


# JUMP
OP["JMP"] = proc(args: OPARGUMENTS): int =
    var memory_address: string = args.memory_address
    case memory_address[0]
    of '@':
        memory_address = call(POOL_GLOBAL, memory_address[1..<memory_address.len], "Global")
    of '$':
        memory_address = call(POOL_LOCAL, memory_address[1..<memory_address.len], "Local")
    of '%':
        memory_address = call(POOL_BUFFER, memory_address[1..<memory_address.len], "Buffer")
    of '[':
        let arg3: string = memory_address[1..<memory_address.len - 1]
        if REGISTER.hasKey(arg3):
            memory_address = REGISTER[arg3]
        else:
            memory_address = memory_address[1..<memory_address.len - 1]
    else:
        OPERROR = "Invalid Memory Location: '" & memory_address & "'"
        return 3

    if memory_address == "":
        OPERROR = "Value expected, got: " & memory_address
        return 3
    elif $(typeof(memory_address)) != "string":
        OPERROR = "String value expected, got: " & $(typeof(memory_address))
        return 3

    C("TEXT", "__comment", "JMP", "JMP", memory_address)
    C("TEXT", "JMP", memory_address, "", "")
    return 0


# JUMP IF NOT ZERO
OP["JNZ"] = proc(args: OPARGUMENTS): int =
    var memory_address: string = args.memory_address
    case memory_address[0]
    of '@':
        memory_address = call(POOL_GLOBAL, memory_address[1..<memory_address.len], "Global")
    of '$':
        memory_address = call(POOL_LOCAL, memory_address[1..<memory_address.len], "Local")
    of '%':
        memory_address = call(POOL_BUFFER, memory_address[1..<memory_address.len], "Buffer")
    of '[':
        let arg3: string = memory_address[1..<memory_address.len - 1]
        if REGISTER.hasKey(arg3):
            memory_address = REGISTER[arg3]
        else:
            memory_address = memory_address[1..<memory_address.len - 1]
    else:
        OPERROR = "Invalid Memory Location: '" & memory_address & "'"
        return 3

    if memory_address == "":
        OPERROR = "Value expected, got: " & memory_address
        return 3
    elif $(typeof(memory_address)) != "string":
        OPERROR = "String value expected, got: " & $(typeof(memory_address))
        return 3

    C("TEXT", "__comment", "JNZ", "JNZ", memory_address)
    C("TEXT", "JNZ", memory_address, "", "")
    return 0


# JUMP IF ZERO
OP["JEZ"] = proc(args: OPARGUMENTS): int =
    var memory_address: string = args.memory_address
    case memory_address[0]
    of '@':
        memory_address = call(POOL_GLOBAL, memory_address[1..<memory_address.len], "Global")
    of '$':
        memory_address = call(POOL_LOCAL, memory_address[1..<memory_address.len], "Local")
    of '%':
        memory_address = call(POOL_BUFFER, memory_address[1..<memory_address.len], "Buffer")
    of '[':
        let arg3: string = memory_address[1..<memory_address.len - 1]
        if REGISTER.hasKey(arg3):
            memory_address = REGISTER[arg3]
        else:
            memory_address = memory_address[1..<memory_address.len - 1]
    else:
        OPERROR = "Invalid Memory Location: '" & memory_address & "'"
        return 3

    if memory_address == "":
        OPERROR = "Value expected, got: " & memory_address
        return 3
    elif $(typeof(memory_address)) != "string":
        OPERROR = "String value expected, got: " & $(typeof(memory_address))
        return 3

    C("TEXT", "__comment", "JEZ", "JEZ", memory_address)
    C("TEXT", "JEZ", memory_address, "", "")
    return 0


# COMPARE
OP["CMP"] = proc(args: OPARGUMENTS): int =
    case args.memory_address[0]:
    of '@':
        call(POOL_GLOBAL, args.memory_address[1..<args.memory_address.len], "Global")
    of '$':
        call(POOL_LOCAL, args.memory_address[1..<args.memory_address.len], "Local")
    of '%':
        call(POOL_BUFFER, args.memory_address[1..<args.memory_address.len], "Buffer")
    of '[':
        if not REGISTER.hasKey(args.memory_address[1..<args.memory_address.len - 1]):
            OPERROR = "Invalid Register Address: '" & args.memory_address[1..<args.memory_address.len - 1] & "'"
            return 3
    else:
        OPERROR = "Invalid Memory Location: '" & args.memory_address & "'"
        return 3

    case args.arg0[0]:
    of '@':
        call(POOL_GLOBAL, args.arg0[1..<args.arg0.len], "Global")
    of '$':
        call(POOL_LOCAL, args.arg0[1..<args.arg0.len], "Local")
    of '%':
        call(POOL_BUFFER, args.arg0[1..<args.arg0.len], "Buffer")
    of '[':
        if not REGISTER.hasKey(args.arg0[1..<args.arg0.len - 1]):
            OPERROR = "Invalid Register Address: '" & args.arg0[1..<args.arg0.len - 1] & "'"
            return 3
    else:
        OPERROR = "Invalid Memory Location: '" & args.arg0 & "'"
        return 3

    C("TEXT", "__comment", "CMP", "CMP", args.memory_address & " == " & args.arg0)
    C("TEXT", "CMP", args.memory_address, args.arg0, "")
    return 0


# EXIT
OP["EXIT"] = proc(args: OPARGUMENTS): int =
    var errcode: string = ""
    case args.memory_address[0]:
    of '@':
        errcode = call(POOL_GLOBAL, args.memory_address[1..<args.memory_address.len], "Global")
    of '$':
        errcode = call(POOL_LOCAL, args.memory_address[1..<args.memory_address.len], "Local")
    of '%':
        errcode = call(POOL_BUFFER, args.memory_address[1..<args.memory_address.len], "Buffer")
    of '[':
        if REGISTER.hasKey(args.memory_address[1..<args.memory_address.len - 1]):
            if REGISTER[args.memory_address[1..<args.memory_address.len - 1]] != "":
                errcode = REGISTER[args.memory_address[1..<args.memory_address.len - 1]]
            else:
                errcode = args.memory_address[1..<args.memory_address.len - 1]
        else:
            errcode = args.memory_address[1..<args.memory_address.len - 1]
    else:
        errcode = args.memory_address

    try:
        discard parseInt(errcode)
    except ValueError as e:
        OPERROR = e.msg
        return 3

    C("TEXT", "__comment", "EXIT", "EXIT", args.memory_address)
    C("TEXT", "EXIT", errcode, "", "")

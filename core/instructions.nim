import tables
import memory
import strutils
import math
import ../codegen/codegen
    
# OPCODES
var OP* = initTable[string, proc(memory_address: var string, arg0: var string, arg1: var string): int]()
var OPERROR*: string = ""
var OPWARN*: string = "Warning(s):\n"
var instruction_counter*: int = 0
    
# Instuctions
let Instructions*: Table[string, string] = {
    "00":    "NOP",     # Done
    "01":    "READ",    # 
    "02":    "WRITE",   # Done
    "03":    "STORE",   # Done
    "04":    "DEL",     # Done
    "05":    "ADD",     # Done
    "06":    "SUB",     # Done
    "07":    "MUL",     # Done
    "08":    "DIV",     # Done
    "09":    "EXP",     # Done
    "0A":    "COPY",    # Done
    "0B":    "JMP",     #
    "0C":    "JNE",     #
    "0D":    "CMP",     #
    "0E":    "INC",     # Done
    "0F":    "DEC",     # Done
    "0G":    "UPD",     #
    "0H":    "MALLOC",  # Done
    "0I":    "FREE",    # Done
    "0J":    "LBL",     #
}.toTable()


# Utility
proc call(memory_pool: ref Table[string, string], address: string, pool_type: string): auto =
    if memory_pool[].hasKey(address):
        return memory_pool[][address]
    else:
        echo "INVALID [" & pool_type & "] MEMORY ADDRESS: " & address
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
OP["NOP"] = proc(memory_address: var string, arg0: var string, arg1: var string): int =
    C("TEXT", "NOP", "", "", "")
    return 0


# READ
OP["READ"] = proc(memory_address: var string, arg0: var string = "", arg1: var string = ""): int =
    OPERROR = "IMPLEMENT OP READ"
    return 1


# WRITE
OP["WRITE"] = proc(memory_address: var string, arg0: var string = "", arg1: var string = ""): int =
    # Instance Variables #
    var data: string = ""
    case memory_address[0]
    of '@':
        if POOL_GLOBAL.hasKey("" & memory_address[1..<memory_address.len]):
            data = POOL_GLOBAL[memory_address[1..<memory_address.len]]
        else:
            OPERROR = "Invalid [Global] Memory Address: '" & memory_address[1..<memory_address.len] & "'"
            return 1

    of '[':
        data = memory_address[1..<(memory_address.len - 1)]
        if REGISTER.hasKey(memory_address[1..<(memory_address.len - 1)]) and REGISTER[memory_address[1..<(memory_address.len - 1)]] != "":
            data = REGISTER[memory_address[1..<(memory_address.len - 1)]]

        # Removing '[' and ']'
        if data[0] == '[':
            data = data[1..<(data.len - 1)]

    of '$':
        if POOL_LOCAL.hasKey(memory_address[1..<memory_address.len]):
            data = POOL_LOCAL[memory_address[1..<memory_address.len]]
        else:
            OPERROR = "Invalid [Local] Memory Address: '" & memory_address[1..<memory_address.len] & "'"
            return 1

    of '%':
            if POOL_BUFFER.hasKey(memory_address[1..<memory_address.len]):
                data = POOL_BUFFER[memory_address[1..<memory_address.len]]
            else:
                OPERROR = "Invalid [Buffer] Memory Address: '" & memory_address[1..<memory_address.len] & "'"
                return 1

    else:
        OPERROR = "Invalid Memory Address Pointer: '" & memory_address & "'"
        return 1

    C("TEXT", "__comment", "  instr_" & $(instruction_counter/4) & ": WRITE", "WRITE", memory_address)
    C("TEXT", "WRITE", memory_address, $data.len, $data)
    return 0


# STORE
OP["STORE"] = proc(memory_address: var string, arg0: var string, arg1: var string): int =
    # Instance Variables
    var memory_address: string = memory_address
    var arg0: string = arg0
    var arg1: string = arg1

    # Argument
    case arg0[0]
    of '@':
        arg0 = arg0.replace("@", "")
        arg0 = call(POOL_GLOBAL, arg0, "GLOBAL")
    of '$':
        arg0 = arg0.replace("$", "")
        arg0 = call(POOL_LOCAL, arg0, "LOCAL")
    of '%':
        arg0 = arg0.replace("%", "")
        arg0 = call(POOL_BUFFER, arg0, "BUFFER")
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
            return 1
    else:
        OPERROR = "Invalid Memory Pointer: '" & memory_address[0] & "'"
        return 1



# DEL
OP["DEL"] = proc(memory_address: var string, arg0: var string, arg1: var string): int =
    case memory_address[0]
    of '@':
        memory_address = memory_address.replace("@", "")
        ADDR_BUFFER = memory_address
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
        return 1
        
    return 0


# COPY
OP["COPY"] = proc(memory_address: var string, arg0: var string, arg1: var string = ""): int =
    # Instance Variables
    var POOL_0: ref Table[string, string]
    var POOL_1: ref Table[string, string]
    var using_register: bool = false
    var using_mempool: bool = false
    var new_value: bool = false

    # arg0
    case arg0[0]:
    of '@':
        arg0 = arg0[1..<arg0.len]
        POOL_0 = POOL_GLOBAL
        using_mempool = true
    of '$':
        arg0 = arg0[1..<arg0.len]
        POOL_0 = POOL_LOCAL
        using_mempool = true
    of '%':
        arg0 = arg0[1..<arg0.len]
        POOL_0 = POOL_BUFFER
        using_mempool = true
    of '[':
        new_value = true
        arg0 = arg0[1..<(arg0.len - 1)]
        if not REGISTER.hasKey(arg0) or REGISTER[arg0] == "":
            OPERROR = "INVLIAD OR EMPTY REGISTER ADDRES " & arg0
            return 1
        arg0 = REGISTER[arg0]
    else:
        return 1


    # Update memory address
    case memory_address[0]
    of '@':
        if not new_value:
            if POOL_GLOBAL[].hasKey(arg0):
                C("VOID", "__comment", "  instr_" & $(instruction_counter/4) & ": COPY", "COPY", "[@" & arg0 & " -> @" & memory_address[1..<memory_address.len] & "]")
                POOL_GLOBAL[][memory_address[1..<memory_address.len]] = POOL_0[][arg0]
            else:
                OPERROR = "Invalid [Global] Memory Address: '" & memory_address[1..<memory_address.len] & "'"
                return 1
        else:
            C("VOID", "__comment", "  instr_" & $(instruction_counter/4) & ": COPY", "COPY", "[" & $arg0.replace("\n","\\n") & " -> @" & memory_address[1..<memory_address.len] & "]")
            POOL_GLOBAL[][memory_address[1..<memory_address.len]] = arg0
        POOL_1 = POOL_GLOBAL
    of '$':
        if not new_value:
            if POOL_LOCAL[].hasKey(arg0):
                C("VOID", "__comment", "  instr_" & $(instruction_counter/4) & ": COPY", "COPY", "[$" & arg0 & " -> $" & memory_address[1..<memory_address.len] & "]")
                POOL_LOCAL[][memory_address[1..<memory_address.len]] = POOL_0[][arg0]
            else:
                OPERROR = "Invalid [Local] Memory Address: '" & memory_address[1..<memory_address.len] & "'"
                return 1
        else:
            C("VOID", "__comment", "  instr_" & $(instruction_counter/4) & ": COPY", "COPY", "[" & $arg0.replace("\n","\\n") & " -> $" & memory_address[1..<memory_address.len] & "]")
            POOL_LOCAL[][memory_address[1..<memory_address.len]] = arg0
        POOL_1 = POOL_LOCAL
    of '%':
        if not new_value:
            if POOL_BUFFER[].hasKey(arg0):
                C("VOID", "__comment", "  instr_" & $(instruction_counter/4) & ": COPY", "COPY", "[%" & arg0 & " -> %" & memory_address[1..<memory_address.len] & "]")
                POOL_BUFFER[][memory_address[1..<memory_address.len]] = POOL_0[][arg0]
            else:
                OPERROR = "Invalid [Buffer] Memory Address: '" & memory_address[1..<memory_address.len] & "'"
                return 1
        else:
            C("VOID", "__comment", "  instr_" & $(instruction_counter/4) & ": COPY", "COPY", "[" & $arg0.replace("\n","\\n") & " -> %" & memory_address[1..<memory_address.len] & "]")
            POOL_BUFFER[][memory_address[1..<memory_address.len]] = arg0
        POOL_1 = POOL_BUFFER
    of '[':
        if REGISTER.hasKey(memory_address[1..<(memory_address.len - 1)]):
            C("VOID", "__comment", "  instr_" & $(instruction_counter/4) & ": COPY", "COPY", "[" & arg0 & " -> " & memory_address[1..<memory_address.len] & "]")
            REGISTER[memory_address[1..<(memory_address.len - 1)]] = arg0
        else:
            OPERROR = "Invalid [Register] Location: '" & memory_address[1..<memory_address.len] & "'"
            return 1
        using_register = true
    else:
        return 1

    if not using_register:
        if new_value:
            if arg0[0] == '[' and arg0[arg0.len - 1] == ']':
                arg0 = arg0[1..<(arg0.len - 1)]
            C("DATA", "__comment", "  instr_" & $(instruction_counter/4) & ": STORE", "STORE", "[" & memory_address & "]")
            C("DATA", "STORE", memory_address, $arg0, "")
        else:
            C("DATA", "__comment", "  instr_" & $(instruction_counter/4) & ": STORE", "STORE", "[" & memory_address & "]")  
            C("DATA", "STORE", memory_address, $POOL_0[arg0], "")
    else:
         C("TEXT", "STORE REGISTER", memory_address, $arg0,"")
        
    return 0


# MALLOC
OP["MALLOC"] = proc(memory_address: var string, arg0: var string, arg1: var string): int =
    # Instance Variables
    var MAX_SIZE: ref int
    var POOL_0: ref Table[string, string]
    var current_address: string = ""
    var data: string = ""
    var size_t: int = 0

    case memory_address:
    of "@00":
        current_address = POOL_GLOBAL[].NextAddress()
        POOL_0 = POOL_GLOBAL
        MAX_SIZE = MAX_SIZE_GLOBAL
    of "$00":
        current_address = POOL_LOCAL[].NextAddress()
        POOL_0 = POOL_LOCAL
        MAX_SIZE = MAX_SIZE_LOCAL
    of "%00":
        current_address = POOL_BUFFER[].NextAddress()
        POOL_0 = POOL_BUFFER
        MAX_SIZE = MAX_SIZE_BUFFER
    else:
        OPERROR = "Invalid Memory Pool Address: '" & memory_address & "'"
        return 1

    case arg0[0]:
    of '@':
        arg0 = arg0.replace("@", "")
        arg0 = call(POOL_GLOBAL, arg0, "GLOBAL")
    of '$':
        arg0 = arg0.replace("$", "")
        arg0 = call(POOL_LOCAL, arg0, "LOCAL")
    of '%':
        arg0 = arg0.replace("%", "")
        arg0 = call(POOL_BUFFER, arg0, "BUFFER")
    of '[':
        arg0 = arg0[1..<(arg0.len - 1)]
        arg0 = REGISTER[arg0]
    else:
        discard

    if parseInt("" & arg0[0]) == 0:
        size_t = parseInt("" & arg0[1])
    else:
        size_t = parseInt(arg0)

    current_address.Decrease()
    
    for count in 1..size_t+1:
        POOL_0[].Store(current_address, data, 3843)
        
    MAX_SIZE[] = POOL_0[].len
    C("VOID", "__comment", "  instr_" & $(instruction_counter/4) & ": MALLOC", "MALLOC", "[" & $size_t & " -> " & memory_address & "]")  

    return 0


# ADD
OP["ADD"] = proc(memory_address: var string, arg0: var string, arg1: var string): int =
    # Instance Variables
    var POOL_0: ref Table[string, string]
    var POOL_1: ref Table[string, string]
    var POOL_2: ref Table[string, string]
    var register00: float = 0.00
    var register10: float = 0.00
    var register0: string = ""
    var register1: string = ""
    var register2: string = ""
    var symbol: char = arg1[0]
    var sum: string = ""

    # Memory Address
    case memory_address[0]
    of '@':
        memory_address = memory_address.replace("@", "")
        POOL_0 = POOL_GLOBAL
    of '$':
        memory_address = memory_address.replace("$", "")
        POOL_0 = POOL_LOCAL
    of '%':
        memory_address = memory_address.replace("%", "")
        POOL_0 = POOL_BUFFER
    of '[':
        memory_address = memory_address[1..<(memory_address.len - 1)]
        if REGISTER.hasKey(memory_address) and REGISTER[memory_address] != "":
            register0 = memory_address
        else:
            OPERROR = "Invalid or Empty Register Address: '" & memory_address & "'"
            return 1
    else:
        return 1

    # Address to add
    case arg0[0]
    of '@':
        arg0 = arg0.replace("@", "")
        POOL_1 = POOL_GLOBAL
    of '$':
        arg0 = arg0.replace("$", "")
        POOL_1 = POOL_LOCAL
    of '%':
        arg0 = arg0.replace("%", "")
        POOL_1 = POOL_BUFFER
    of '[':
        arg0 = arg0[1..<(arg0.len - 1)]
        if REGISTER.hasKey(arg0) and REGISTER[arg0] != "":
            register1 = arg0
        else:
            OPERROR = "Invalid or Empty Memory Address: '" & arg0 & "'"
            return 1
    else:
        return 1

    # Return Address/Register
    case arg1[0]
    of '@':
        arg1 = arg1.replace("@", "")
        POOL_2 = POOL_GLOBAL
    of '$':
        arg1 = arg1.replace("$", "")
        POOL_2 = POOL_LOCAL
    of '%':
        arg1 = arg1.replace("%", "")
        POOL_2 = POOL_BUFFER
    of '[':
        arg1 = arg1[1..<(arg1.len - 1)]
        if REGISTER.hasKey(arg1):
            register2 = arg1
        else:
            OPERROR = "Invalid Register Address: '" & arg1 & "'"
            return 1
    else:
        register2 = "[sra]"


    # Gathering Address/Register Data Slot0 #
    if register0 == "":
        if POOL_0[].hasKey(memory_address):
            try:
                case POOL_0[][memory_address][0]
                of '[':
                    var tmp: string = POOL_0[][memory_address]
                    tmp = tmp[1..tmp.len-2]
                    register00 = parseFloat(tmp)
                else:
                    register00 = parseFloat(POOL_0[][memory_address])
            except ValueError as e:
                OPERROR = "Attempt to perform arithmetic operation on " & $typeof(POOL_0[][memory_address]) & " '" & POOL_1[][arg0] & "'"
                
                return 1
        else:
            OPERROR = "Invalid Memeory Address: '" & memory_address & "'"
            return 1
    else:
        try:
            register00 = parseFloat(REGISTER[register0])
        except ValueError as e:
            OPERROR = e.msg
            return 1

    # Gathering Address/Register Data Slot1 #
    if register1 == "":
        if POOL_1[].hasKey(arg0):
            try:
                case POOL_1[][arg0][0]
                of '[':
                    var tmp: string = POOL_1[][arg0]
                    tmp = tmp[1..tmp.len-2]
                    register10 = parseFloat(tmp)
                else:
                    register10 = parseFloat(POOL_1[][arg0])
            except ValueError as e:
                OPERROR = "Attempt to perform arithmetic operation on " & $typeof(POOL_1[][arg0]) & " '" & POOL_1[][arg0] & "'"
                return 1
        else:
            OPERROR = "Invalid Memory Address: '" & arg0 & "'"
            return 1
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
            return 1

    # Adding Values
    sum = $(register00 + register10)
    OPWARN = OPWARN & "\tIMPLEMENT NEGATIVE NUMBER ADDING\n"
    if sum[sum.len-2..sum.len-1] == ".0":
        sum = sum[0..sum.len-3]
    if sum.len > 2:
        sum = "[" & sum & "]"

    # Storing Data
    if register2 == "":
        var address: string = symbol & arg1
        var nop = ""
        if OP["COPY"](address, sum, nop) != 0:
            return 1
    else:
        var address: string = register2[1..<(register2.len - 1)]
        REGISTER[address] = sum

    C("VOID", "__comment", "  instr_" & $(instruction_counter/4) & ": ADD", "ADD", "[" & $register00 & " + " & $register10 & "]")
    return 0


# SUB
OP["SUB"] = proc(memory_address: var string, arg0: var string, arg1: var string): int =
    # Instance Variables
    var POOL_0: ref Table[string, string]
    var POOL_1: ref Table[string, string]
    var POOL_2: ref Table[string, string]
    var register00: float = 0.00
    var register10: float = 0.00
    var register0: string = ""
    var register1: string = ""
    var register2: string = ""
    var symbol: char = arg1[0]
    var difference: string = ""

    # Memory Address
    case memory_address[0]
    of '@':
        memory_address = memory_address.replace("@", "")
        POOL_0 = POOL_GLOBAL
    of '$':
        memory_address = memory_address.replace("$", "")
        POOL_0 = POOL_LOCAL
    of '%':
        memory_address = memory_address.replace("%", "")
        POOL_0 = POOL_BUFFER
    of '[':
        memory_address = memory_address[1..<(memory_address.len - 1)]
        if REGISTER.hasKey(memory_address) and REGISTER[memory_address] != "":
            register0 = memory_address
        else:
            OPERROR = "Invalid or Empty Register Address: '" & memory_address & "'"
            return 1
    else:
        return 1

    # Address to add
    case arg0[0]
    of '@':
        arg0 = arg0.replace("@", "")
        POOL_1 = POOL_GLOBAL
    of '$':
        arg0 = arg0.replace("$", "")
        POOL_1 = POOL_LOCAL
    of '%':
        arg0 = arg0.replace("%", "")
        POOL_1 = POOL_BUFFER
    of '[':
        arg0 = arg0[1..<(arg0.len - 1)]
        if REGISTER.hasKey(arg0) and REGISTER[arg0] != "":
            register1 = arg0
        else:
            OPERROR = "Invalid or Empty Memory Address: '" & arg0 & "'"
            return 1
    else:
        return 1

    # Return Address/Register
    case arg1[0]
    of '@':
        arg1 = arg1.replace("@", "")
        POOL_2 = POOL_GLOBAL
    of '$':
        arg1 = arg1.replace("$", "")
        POOL_2 = POOL_LOCAL
    of '%':
        arg1 = arg1.replace("%", "")
        POOL_2 = POOL_BUFFER
    of '[':
        arg1 = arg1[1..<(arg1.len - 1)]
        if REGISTER.hasKey(arg1):
            register2 = arg1
        else:
            OPERROR = "Invalid Register Address: '" & arg1 & "'"
            return 1
    else:
        register2 = "[sra]"


    # Gathering Address/Register Data Slot0 #
    if register0 == "":
        if POOL_0[].hasKey(memory_address):
            try:
                case POOL_0[][memory_address][0]
                of '[':
                    var tmp: string = POOL_0[][memory_address]
                    tmp = tmp[1..tmp.len-2]
                    register00 = parseFloat(tmp)
                else:
                    register00 = parseFloat(POOL_0[][memory_address])
            except ValueError as e:
                OPERROR = "Attempt to perform arithmetic operation on " & $typeof(POOL_0[][memory_address]) & " '" & POOL_1[][arg0] & "'"
                
                return 1
        else:
            OPERROR = "Invalid Memeory Address: '" & memory_address & "'"
            return 1
    else:
        try:
            register00 = parseFloat(REGISTER[register0])
        except ValueError as e:
            OPERROR = e.msg
            return 1

    # Gathering Address/Register Data Slot1 #
    if register1 == "":
        if POOL_1[].hasKey(arg0):
            try:
                case POOL_1[][arg0][0]
                of '[':
                    var tmp: string = POOL_1[][arg0]
                    tmp = tmp[1..tmp.len-2]
                    register10 = parseFloat(tmp)
                else:
                    register10 = parseFloat(POOL_1[][arg0])
            except ValueError as e:
                OPERROR = "Attempt to perform arithmetic operation on " & $typeof(POOL_1[][arg0]) & " '" & POOL_1[][arg0] & "'"
                return 1
        else:
            OPERROR = "Invalid Memory Address: '" & arg0 & "'"
            return 1
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
            return 1

    # Subtracting Values
    difference = $(register00 + register10)
    OPWARN = OPWARN & "\tIMPLEMENT NEGATIVE NUMBER ADDING\n"
    if difference[difference.len-2..difference.len-1] == ".0":
        difference = difference[0..difference.len-3]
    if difference.len > 2:
        difference = "[" & difference & "]"

    # Storing Data
    if register2 == "":
        var address: string = symbol & arg1
        var nop = ""
        if OP["COPY"](address, difference, nop) != 0:
            return 1
    else:
        var address: string = register2[1..<(register2.len - 1)]
        REGISTER[address] = difference

    C("VOID", "__comment", "  instr_" & $(instruction_counter/4) & ": SUB", "SUB", "[" & $register00 & " + " & $register10 & "]")
    return 0


# MUL
OP["MUL"] = proc(memory_address: var string, arg0: var string, arg1: var string): int =
    # Instance Variables
    var POOL_0: ref Table[string, string]
    var POOL_1: ref Table[string, string]
    var POOL_2: ref Table[string, string]
    var register00: float = 0.00
    var register10: float = 0.00
    var register0: string = ""
    var register1: string = ""
    var register2: string = ""
    var symbol: char = arg1[0]
    var product: string = ""

    # Memory Address
    case memory_address[0]
    of '@':
        memory_address = memory_address.replace("@", "")
        POOL_0 = POOL_GLOBAL
    of '$':
        memory_address = memory_address.replace("$", "")
        POOL_0 = POOL_LOCAL
    of '%':
        memory_address = memory_address.replace("%", "")
        POOL_0 = POOL_BUFFER
    of '[':
        memory_address = memory_address[1..<(memory_address.len - 1)]
        if REGISTER.hasKey(memory_address) and REGISTER[memory_address] != "":
            register0 = memory_address
        else:
            OPERROR = "INVALID OR EMPTY REGISTER ADDRESS: " & memory_address
            return 1
    else:
        return 1

    # Address to add
    case arg0[0]
    of '@':
        arg0 = arg0.replace("@", "")
        POOL_1 = POOL_GLOBAL
    of '$':
        arg0 = arg0.replace("$", "")
        POOL_1 = POOL_LOCAL
    of '%':
        arg0 = arg0.replace("%", "")
        POOL_1 = POOL_BUFFER
    of '[':
        arg0 = arg0[1..<(arg0.len - 1)]
        if REGISTER.hasKey(arg0) and REGISTER[arg0] != "":
            register1 = arg0
        else:
            OPERROR = "INVALID OR EMPTY MEMORY ADDRESS: " & arg0
            return 1
    else:
        return 1

    # Return Address/Register
    case arg1[0]
    of '@':
        arg1 = arg1.replace("@", "")
        POOL_2 = POOL_GLOBAL
    of '$':
        arg1 = arg1.replace("$", "")
        POOL_2 = POOL_LOCAL
    of '%':
        arg1 = arg1.replace("%", "")
        POOL_2 = POOL_BUFFER
    of '[':
        arg1 = arg1[1..<(arg1.len - 1)]
        if REGISTER.hasKey(arg1):
            register2 = arg1
        else:
            OPERROR = "INVALID REGISTER ADDRES: " & arg1
            return 1
    else:
        register2 = "[sra]"


    # Gathering Address/Register Data Slot0 #
    if register0 == "":
        if POOL_0[].hasKey(memory_address):
            try:
                register00 = parseFloat(POOL_0[][memory_address])
            except ValueError as e:
                OPERROR = e.msg
                return 1
        else:
            OPERROR = "INVALID MEMORY ADDRESS: " & memory_address
            return 1
    else:
        try:
            register00 = parseFloat(REGISTER[register0])
        except ValueError as e:
            OPERROR = e.msg
            return 1

    # Gathering Address/Register Data Slot1 #
    if register1 == "":
        if POOL_1[].hasKey(arg0):
            try:
                register10 = parseFloat(POOL_1[][arg0])
            except ValueError as e:
                OPERROR = e.msg
                return 1
        else:
            OPERROR = "INVALID MEMORY ADDRESS: " & arg0
            return 1
    else:
        try:
            register10 = parseFloat(REGISTER[register1])
        except ValueError as e:
            OPERROR = e.msg
            return 1

    # Adding Values
    product = $(register00 * register10)
    OPWARN = OPWARN & "\tIMPLEMENT NEGATIVE NUMBER ADDING\n"
    if product.len > 2:
        product = "[" & product & "]"

    # Storing Data
    if register2 == "":
        var address: string = symbol & arg1
        var nop = ""
        if OP["COPY"](address, product, nop) != 0:
            return 1
    else:
        var address: string = register2[1..<(register2.len - 1)]
        REGISTER[address] = product

    C("VOID", "__comment", "  instr_" & $(instruction_counter/4) & ": MUL", "MUL", "[" & $register00 & " * " & $register10 & "]")
    return 0


# DIV
OP["DIV"] = proc(memory_address: var string, arg0: var string, arg1: var string): int =
    # Instance Variables
    var POOL_0: ref Table[string, string]
    var POOL_1: ref Table[string, string]
    var POOL_2: ref Table[string, string]
    var register00: float = 0.00
    var register10: float = 0.00
    var register0: string = ""
    var register1: string = ""
    var register2: string = ""
    var symbol: char = arg1[0]
    var quotient: string = ""

    # Memory Address
    case memory_address[0]
    of '@':
        memory_address = memory_address.replace("@", "")
        POOL_0 = POOL_GLOBAL
    of '$':
        memory_address = memory_address.replace("$", "")
        POOL_0 = POOL_LOCAL
    of '%':
        memory_address = memory_address.replace("%", "")
        POOL_0 = POOL_BUFFER
    of '[':
        memory_address = memory_address[1..<(memory_address.len - 1)]
        if REGISTER.hasKey(memory_address) and REGISTER[memory_address] != "":
            register0 = memory_address
        else:
            OPERROR = "INVALID OR EMPTY REGISTER ADDRESS: " & memory_address
            return 1
    else:
        return 1

    # Address to add
    case arg0[0]
    of '@':
        arg0 = arg0.replace("@", "")
        POOL_1 = POOL_GLOBAL
    of '$':
        arg0 = arg0.replace("$", "")
        POOL_1 = POOL_LOCAL
    of '%':
        arg0 = arg0.replace("%", "")
        POOL_1 = POOL_BUFFER
    of '[':
        arg0 = arg0[1..<(arg0.len - 1)]
        if REGISTER.hasKey(arg0) and REGISTER[arg0] != "":
            register1 = arg0
        else:
            OPERROR = "INVALID OR EMPTY MEMORY ADDRESS: " & arg0
            return 1
    else:
        return 1

    # Return Address/Register
    case arg1[0]
    of '@':
        arg1 = arg1.replace("@", "")
        POOL_2 = POOL_GLOBAL
    of '$':
        arg1 = arg1.replace("$", "")
        POOL_2 = POOL_LOCAL
    of '%':
        arg1 = arg1.replace("%", "")
        POOL_2 = POOL_BUFFER
    of '[':
        arg1 = arg1[1..<(arg1.len - 1)]
        if REGISTER.hasKey(arg1):
            register2 = arg1
        else:
            OPERROR = "INVALID REGISTER ADDRES: " & arg1
            return 1
    else:
        register2 = "[sra]"


    # Gathering Address/Register Data Slot0 #
    if register0 == "":
        if POOL_0[].hasKey(memory_address):
            try:
                register00 = parseFloat(POOL_0[][memory_address])
            except ValueError as e:
                OPERROR = e.msg
                return 1
        else:
            OPERROR = "INVALID MEMORY ADDRESS: " & memory_address
            return 1
    else:
        try:
            register00 = parseFloat(REGISTER[register0])
        except ValueError as e:
            OPERROR = e.msg
            return 1

    # Gathering Address/Register Data Slot1 #
    if register1 == "":
        if POOL_1[].hasKey(arg0):
            try:
                register10 = parseFloat(POOL_1[][arg0])
            except ValueError as e:
                OPERROR = e.msg
                return 1
        else:
            OPERROR = "INVALID MEMORY ADDRESS: " & arg0
            return 1
    else:
        try:
            register10 = parseFloat(REGISTER[register1])
        except ValueError as e:
            OPERROR = e.msg
            return 1

    # Adding Values
    quotient = $(register00 / register10)
    OPWARN = OPWARN & "\tIMPLEMENT NEGATIVE NUMBER ADDING\n"
    if quotient.len > 2:
        quotient = "[" & quotient & "]"

    # Storing Data
    if register2 == "":
        var address: string = symbol & arg1
        var nop = ""
        if OP["COPY"](address, quotient, nop) != 0:
            return 1
    else:
        var address: string = register2[1..<(register2.len - 1)]
        REGISTER[address] = quotient
        
    C("VOID", "__comment", "  instr_" & $(instruction_counter/4) & ": DIV", "DIV", "[" & $register00 & " / " & $register10 & "]")
    return 0


# EXP
OP["EXP"] = proc(memory_address: var string, arg0: var string, arg1: var string): int =
    # Instance Variables
    var POOL_0: ref Table[string, string]
    var POOL_1: ref Table[string, string]
    var POOL_2: ref Table[string, string]
    var register00: float = 0.00
    var register10: float = 0.00
    var register0: string = ""
    var register1: string = ""
    var register2: string = ""
    var symbol: char = arg1[0]
    var power: string = ""

    # Memory Address
    case memory_address[0]
    of '@':
        memory_address = memory_address.replace("@", "")
        POOL_0 = POOL_GLOBAL
    of '$':
        memory_address = memory_address.replace("$", "")
        POOL_0 = POOL_LOCAL
    of '%':
        memory_address = memory_address.replace("%", "")
        POOL_0 = POOL_BUFFER
    of '[':
        memory_address = memory_address[1..<(memory_address.len - 1)]
        if REGISTER.hasKey(memory_address) and REGISTER[memory_address] != "":
            register0 = memory_address
        else:
            OPERROR = "INVALID OR EMPTY REGISTER ADDRESS: " & memory_address
            return 1
    else:
        return 1

    # Address to add
    case arg0[0]
    of '@':
        arg0 = arg0.replace("@", "")
        POOL_1 = POOL_GLOBAL
    of '$':
        arg0 = arg0.replace("$", "")
        POOL_1 = POOL_LOCAL
    of '%':
        arg0 = arg0.replace("%", "")
        POOL_1 = POOL_BUFFER
    of '[':
        arg0 = arg0[1..<(arg0.len - 1)]
        if REGISTER.hasKey(arg0) and REGISTER[arg0] != "":
            register1 = arg0
        else:
            OPERROR = "INVALID OR EMPTY MEMORY ADDRESS: " & arg0
            return 1
    else:
        return 1

    # Return Address/Register
    case arg1[0]
    of '@':
        arg1 = arg1.replace("@", "")
        POOL_2 = POOL_GLOBAL
    of '$':
        arg1 = arg1.replace("$", "")
        POOL_2 = POOL_LOCAL
    of '%':
        arg1 = arg1.replace("%", "")
        POOL_2 = POOL_BUFFER
    of '[':
        arg1 = arg1[1..<(arg1.len - 1)]
        if REGISTER.hasKey(arg1):
            register2 = arg1
        else:
            OPERROR = "INVALID REGISTER ADDRES: " & arg1
            return 1
    else:
        register2 = "[sra]"


    # Gathering Address/Register Data Slot0 #
    if register0 == "":
        if POOL_0[].hasKey(memory_address):
            try:
                register00 = parseFloat(POOL_0[][memory_address])
            except ValueError as e:
                OPERROR = e.msg
                return 1
        else:
            OPERROR = "INVALID MEMORY ADDRESS: " & memory_address
            return 1
    else:
        try:
            register00 = parseFloat(REGISTER[register0])
        except ValueError as e:
            OPERROR = e.msg
            return 1

    # Gathering Address/Register Data Slot1 #
    if register1 == "":
        if POOL_1[].hasKey(arg0):
            try:
                register10 = parseFloat(POOL_1[][arg0])
            except ValueError as e:
                OPERROR = e.msg
                return 1
        else:
            OPERROR = "INVALID MEMORY ADDRESS: " & arg0
            return 1
    else:
        try:
            register10 = parseFloat(REGISTER[register1])
        except ValueError as e:
            OPERROR = e.msg
            return 1

    # Adding Values
    power = $(register00 ^ register10)
    OPWARN = OPWARN & "\tIMPLEMENT NEGATIVE NUMBER ADDING\n"
    if power.len > 2:
        power = "[" & power & "]"

    # Storing Data
    if register2 == "":
        var address: string = symbol & arg1
        var nop = ""
        if OP["COPY"](address, power, nop) != 0:
            return 1
    else:
        var address: string = register2[1..<(register2.len - 1)]
        REGISTER[address] = power
        
    C("VOID", "__comment", "  instr_" & $(instruction_counter/4) & ": EXP", "EXP", "[" & $register00 & " ^ " & $register10 & "]")
    return 0


# INC
OP["INC"] = proc(memory_address: var string, arg0: var string, arg1: var string): int =
    # Instance Variables
    var num: string = "1"
    var nop: string = "00"

    if OP["ADD"](memory_address, num, nop) != 0:
        return 1

    return 0


# DEC
OP["DEC"] = proc(memory_address: var string, arg0: var string, arg1: var string): int =
    # Instance Variables
    var num: string = "1"
    var nop: string = "00"

    if OP["SUB"](memory_address, num, nop) != 0:
        return 1 

    return 0


OP["FREE"] = proc(memory_address: var string, arg0: var string, arg1: var string): int =
# FREE
    case memory_address
    of "@00":
        C("VOID", "__comment", "  instr_" & $(instruction_counter/4) & ": FREE", "FREE", "[GLOBAL]")
        POOL_GLOBAL[].Free()
    of "$00":
        C("VOID", "__comment", "  instr_" & $(instruction_counter/4) & ": FREE", "FREE", "[LOCAL]")
        POOL_LOCAL[].Free()
    of "%00":
        C("VOID", "__comment", "  instr_" & $(instruction_counter/4) & ": FREE", "FREE", "[BUFFER]")
        POOL_BUFFER[].Free()
    else:
        OPERROR = "INVALID MEMORY POOL ADDRESS: " & memory_address
        return 1


    return 0


OP["UPD"] = proc(memory_address: var string, arg0: var string, arg1: var string): int =
    # Instance Variables
    var POOL_0: ref Table[string, string]
    var POOL_1: ref Table[string, string]
    var register0: string = ""

    # Memory Address
    case memory_address[0]
    of '@':
        memory_address = memory_address.replace("@", "")
        POOL_0 = POOL_GLOBAL
    of '$':
        memory_address = memory_address.replace("$", "")
        POOL_0 = POOL_LOCAL
    of '%':
        memory_address = memory_address.replace("%", "")
        POOL_0 = POOL_BUFFER
    of '[':
        memory_address = memory_address[1..<(memory_address.len - 1)]
        if REGISTER.hasKey(memory_address):
            register0 = memory_address
        else:
            OPERROR = "INVALID: " & memory_address
            return 1
    else:
        return 1

    #echo getType(POOL_0[][memory_address]).Type
    #echo POOL_0[][memory_address]

        
    return 0

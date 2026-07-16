import memory
import tables
import strutils
import math
import ../codegen/codegen

# --- CONFIGURATION ---
# Set to TRUE for Compiler (Newton -> ASM)
# Set to FALSE for Interpreter (Gravity VM direct execution)
var COMPILE_MODE*: bool = true

# OPCODES
var OP*: Table[string, proc(args: OPARGUMENTS): int] = initTable[string, proc(args: OPARGUMENTS): int]()
var OPERROR*: string = ""
var OPWARN*: string = "Warning(s):\n"
var instruction_counter*: int = 0

# --- VM STATE (Used mainly for Function Stack Tracking) ---
var STACK*: seq[string] = @[]
var FRAME_PTR*: int = 0
var CALL_STACK*: seq[tuple[ip: int, fp: int, dest: string]] = @[]
var HEAP_MAPS*: Table[string, Table[string, string]] = initTable[string, Table[string, string]]()
var map_counter: int = 0

# Instructions Table
let Instructions*: Table[string, string] = {
    "00":    "NOP",
    "01":    "READ",
    "02":    "WRITE",
    "03":    "STORE",
    "04":    "DEL",
    "05":    "ADD",
    "06":    "SUB",
    "07":    "MUL",
    "08":    "DIV",
    "09":    "EXP",
    "0A":    "COPY",
    "0B":    "JMP",
    "0C":    "JNZ",
    "0D":    "CMP",
    "0E":    "INC",
    "0F":    "DEC",
    "0G":    "UPD",
    "0H":    "MALLOC",
    "0I":    "FREE",
    "0J":    "LBL",
    "0K":    "JNZ",
    "0L":    "EXIT",
    "0M":    "LT",
    "0N":    "GT",
    "0P":    "JF",

    # Type Handling #
    "0O":    "ITS",
    "0T":    "TYPEOF",

    # Function Handling #
    "1A":    "PUSH",
    "1B":    "CALL",
    "1C":    "RET",
    "1D":    "GETARG",
    "1E":    "STR",
    "1F":    "WRITES",
    "1G":    "CALLD",
    "1H":    "EXPO",
    "1I":    "ETRN",

    # Maps #
    "20":    "NEWMAP",
    "21":    "MSET",
    "22":    "MGET",
    "23":    "MLEN",
    "24":    "MHEAD",
    "25":    "MKEY",
    "26":    "MVAL",
    "27":    "MNEXT",

    # Arrays #
    "30":    "NEWARR",

    # File IO #
    "28":    "FOPEN",
    "29":    "FWRITE",
    "2A":    "FREAD",
    "2B":    "FCLOSE",
    "2E":    "READF",

    # ENV ARGS #
    "2C":    "ARGV",
    "2D":    "CAT",

    # Floats #
    "3A":    "MOVSD",
    "3B":    "FSTORE",

    # Register Handling #
    "40":    "MOV",
    "41":    "NSUB",
    "42":    "NADD",

    # Networking #
    "50":    "NET_SOCKET",
    "51":    "NET_BIND",
    "52":    "NET_LISTEN",
    "53":    "NET_ACCEPT",
    "54":    "NET_WRITE",
    "55":    "NET_CLOSE",
    "56":    "NET_RECV",
}.toTable()

# --- HELPERS ---

# In Compile Mode, VM memory updates are largely ignored,
# but I'll keep the structure valid so the interpreter logic remains intact if needed.
proc storeResult(target: string, value: string): int =
    if not COMPILE_MODE:
        var dest = target
        if dest == "00": dest = "[sra]"
        case dest[0]
        of '[': REGISTER[dest[1..^2]] = value
        of '$': POOL_LOCAL[][dest[1..^1]] = value
        of '@': POOL_GLOBAL[][dest[1..^1]] = value
        of '%': POOL_BUFFER[][dest[1..^1]] = value
        else: return 3
    return 0

proc getValue(loc: string): string =
    if loc == "": return "0"
    if not COMPILE_MODE:
        if loc.startsWith("[") and loc.endsWith("]"):
            let reg = loc[1..^2]
            if REGISTER.hasKey(reg): return REGISTER[reg]
    return loc

# --- OPCODES ---

# NOP
OP["NOP"] = proc(args: OPARGUMENTS): int =
    C("TEXT", "__comment", "NOP", "NOP", "NOP")
    C("TEXT", "NOP", "", "", "")
    return 0

# READ
OP["READ"] = proc(args: OPARGUMENTS): int =
    C("TEXT", "__comment", "READ", "READ", args.memory_address)
    C("TEXT", "READ", args.memory_address, "00", "")
    return 0

# WRITE
OP["WRITE"] = proc(args: OPARGUMENTS): int =
    var data: string = "0"
    var rawAddr = args.memory_address

    if rawAddr.startsWith("[\"") and rawAddr.endsWith("\"]"):
        data = rawAddr[2..^3].replace("\\n", "\n")
        C("TEXT", "__comment", "WRITE", "WRITE", data)
        C("TEXT", "WRITE", args.memory_address, $data.len, data)
        return 0

    C("TEXT", "__comment", "WRITE", "WRITE", args.memory_address)
    C("TEXT", "WRITE", args.memory_address, "8", "")
    return 0

# STORE
OP["STORE"] = proc(args: OPARGUMENTS): int =
    var dest = args.memory_address
    var src = args.arg0

    if src.startsWith("[") and src.endsWith("]"):
        src = src[1..^2]
        if REGISTER.hasKey(src): src = REGISTER[src]
        else: src = "[" & src & "]"

    if dest.contains("(%rbp)"):
        C("VOID", "__comment", "STORE", "STORE", src & " => " & dest)
        C("TEXT", "STORE", dest, src, "")
        return 0

    if dest.startsWith("!"):
        C("VOID", "__comment", "STORE", "STORE", src & " => " & dest)
        C("TEXT", "STORE", dest, src, "")
        return 0

    if dest.startsWith("@") or dest.startsWith("$") or dest.startsWith("%"):
        case dest[0]
        of '@':
          ADDR_BUFFER = dest[1..<dest.len]
          POOL_GLOBAL[].Store(ADDR_BUFFER, src, MAX_SIZE_GLOBAL[])
          ADDR_GLOBAL = ADDR_BUFFER
          ADDR_BUFFER.Zero()
        of '$':
          ADDR_BUFFER = dest[1..<dest.len]
          POOL_LOCAL[].Store(ADDR_BUFFER, src, MAX_SIZE_LOCAL[])
          ADDR_LOCAL = ADDR_BUFFER
          ADDR_BUFFER.Zero()
        of '%':
          ADDR_BUFFER = dest[1..<dest.len]
          POOL_BUFFER[].Store(ADDR_BUFFER, src, MAX_SIZE_BUFFER[])
        else: discard

        # This goes to DATA section
        C("VOID", "__comment", "STORE", "STORE", src & " => " & dest)
        C("DATA", "STORE", dest, src, "")
    else:
        # Register assignment fallback
        C("VOID", "__comment", "STORE", "STORE REGISTER", src & " => " & dest)
        C("TEXT", "STORE REGISTER", dest, src, "")
    return 0

# UPD (UPDATE)
OP["UPD"] = proc(args: OPARGUMENTS): int =
    C("VOID", "__comment", "UPDATE", "UPDATE", args.arg0 & " => " & args.memory_address)
    C("TEXT", "UPD", args.memory_address, args.arg0, "")
    return 0

# --- MATH (Pass-through to Assembly) ---
OP["ADD"] = proc(args: OPARGUMENTS): int =
    C("TEXT", "__comment", "ADD", "ADD", args.memory_address & " + " & args.arg0)
    C("TEXT", "ADD", args.memory_address, args.arg0, args.arg1); return 0
OP["SUB"] = proc(args: OPARGUMENTS): int =
    C("TEXT", "__comment", "SUB", "SUB", args.memory_address & " - " & args.arg0)
    C("TEXT", "SUB", args.memory_address, args.arg0, args.arg1); return 0
OP["MUL"] = proc(args: OPARGUMENTS): int =
    C("TEXT", "__comment", "MUL", "MUL", args.memory_address & " * " & args.arg0)
    C("TEXT", "MUL", args.memory_address, args.arg0, args.arg1); return 0
OP["DIV"] = proc(args: OPARGUMENTS): int =
    C("TEXT", "__comment", "DIV", "DIV", args.memory_address & " / " & args.arg0)
    C("TEXT", "DIV", args.memory_address, args.arg0, args.arg1); return 0
OP["EXP"] = proc(args: OPARGUMENTS): int =
    C("TEXT", "__comment", "EXP", "EXP", args.memory_address & " ^ " & args.arg0)
    C("TEXT", "EXP", args.memory_address, args.arg0, args.arg1); return 0
OP["INC"] = proc(args: OPARGUMENTS): int =
    C("TEXT", "__comment", "INC", "INC", args.memory_address)
    C("TEXT", "INC", args.memory_address, "", ""); return 0
OP["DEC"] = proc(args: OPARGUMENTS): int =
    C("TEXT", "__comment", "DEC", "DEC", args.memory_address)
    C("TEXT", "DEC", args.memory_address, "", ""); return 0

# --- MEMORY MGMT ---
OP["DEL"] = proc(args: OPARGUMENTS): int =
    C("VOID", "DEL", "", "", ""); return 0
OP["COPY"] = proc(args: OPARGUMENTS): int =
    C("VOID", "__comment", "COPY", "COPY", args.memory_address & " => " & args.arg0)
    C("TEXT", "COPY", args.memory_address, args.arg0, args.arg1)
    return 0

OP["MALLOC"] = proc(args: OPARGUMENTS): int =
    # Keep track of sizes for debugging, but C() does the work
    var size_t = 1
    try: size_t = parseInt(args.arg0)
    except: discard
    if args.memory_address.startsWith("@"):
      var maddr: string = POOL_GLOBAL[].NextAddress()
      maddr.Decrease()
      POOL_GLOBAL[].Alloc(maddr, size_t, "global")
      C("VOID", "__comment", "", "MALLOC", $size_t & " <GLOBAL>")
    elif args.memory_address.startsWith("$"):
      var maddr: string = POOL_LOCAL[].NextAddress()
      maddr.Decrease()
      POOL_LOCAL[].Alloc(maddr, size_t, "local")
      C("VOID", "__comment", "", "MALLOC", $size_t & " <LOCAL>")
    elif args.memory_address.startsWith("%"):
      var maddr: string = POOL_BUFFER[].NextAddress()
      maddr.Decrease()
      POOL_BUFFER[].Alloc(maddr, size_t, "buffer")
      C("VOID", "__comment", "", "MALLOC", $size_t & " <BUFFER>")
    C("VOID", "MALLOC", "", "", ""); return 0

OP["FREE"] = proc(args: OPARGUMENTS): int =
    C("VOID", "__comment", "FREE", "FREE", args.memory_address)
    C("VOID", "FREE", args.memory_address, "", ""); return 0


# --- CONTROL FLOW & LOGIC ---

OP["CMP"] = proc(args: OPARGUMENTS): int =
    C("TEXT", "__comment", "CMP", "CMP", args.memory_address & " with " & args.arg0)
    C("TEXT", "CMP", args.memory_address, args.arg0, ""); return 0
OP["LT"] = proc(args: OPARGUMENTS): int =
    C("TEXT", "__comment", "LT", "LESS THAN", args.memory_address & " < " & args.arg0)
    C("TEXT", "LT", args.memory_address, args.arg0, args.arg1); return 0
OP["GT"] = proc(args: OPARGUMENTS): int =
    C("TEXT", "__comment", "GT", "GREATER THAN", args.memory_address & " > " & args.arg0)
    C("TEXT", "GT", args.memory_address, args.arg0, args.arg1); return 0

OP["LBL"] = proc(args: OPARGUMENTS): int =
    C("TEXT", "__comment", "LBL", "LABEL", args.memory_address)
    C("TEXT", "LBL", args.memory_address, "", "")
    if not COMPILE_MODE:
        LABELS[args.memory_address] = instruction_counter
    return 0

OP["JMP"] = proc(args: OPARGUMENTS): int =
    C("TEXT", "__comment", "JMP", "JUMP", args.memory_address)
    C("TEXT", "JMP", args.memory_address, "", "")
    if not COMPILE_MODE and LABELS.hasKey(args.memory_address):
        instruction_counter = LABELS[args.memory_address] - 4
    return 0

OP["JNZ"] = proc(args: OPARGUMENTS): int =
    C("TEXT", "__comment", "JNZ", "JUMP_NOT_ZERO", args.memory_address)
    C("TEXT", "JNZ", args.memory_address, "", "")
    if not COMPILE_MODE:
        if REGISTER.hasKey("sra") and REGISTER["sra"] != "0":
             if LABELS.hasKey(args.memory_address):
                instruction_counter = LABELS[args.memory_address] - 4
    return 0

OP["JEZ"] = proc(args: OPARGUMENTS): int =
    C("TEXT", "__comment", "JEZ", "JUMP_EQUAL_ZERO", args.memory_address)
    C("TEXT", "JEZ", args.memory_address, "", "")
    if not COMPILE_MODE:
        if REGISTER.hasKey("sra") and REGISTER["sra"] == "0":
             if LABELS.hasKey(args.memory_address):
                instruction_counter = LABELS[args.memory_address] - 4
    return 0

# --- FUNCTION STACK OPS ---

OP["PUSH"] = proc(args: OPARGUMENTS): int =
    C("TEXT", "__comment", "PUSH", "PUSH", args.memory_address)
    C("TEXT", "PUSH", args.memory_address, "", "")
    if not COMPILE_MODE:
        let val = getValue(args.memory_address)
        STACK.add(val)
    return 0

OP["CALL"] = proc(args: OPARGUMENTS): int =
    C("TEXT", "__comment", "CALL", "CALL", args.memory_address)
    C("TEXT", "CALL", args.memory_address, args.arg0, args.arg1)
    if not COMPILE_MODE:
        let label = args.memory_address.replace("[", "").replace("]", "")
        let argCount = parseInt(args.arg0)
        if LABELS.hasKey(label):
            CALL_STACK.add((instruction_counter, FRAME_PTR, args.arg1))
            FRAME_PTR = STACK.len - argCount
            if FRAME_PTR < 0: FRAME_PTR = 0
            instruction_counter = LABELS[label] - 4
    return 0

OP["CALLD"] = proc(args: OPARGUMENTS): int =
    C("TEXT", "__comment", "CALLD", "CALL_DYNAMIC", args.arg1)
    C("TEXT", "CALLD", args.arg1, args.memory_address, args.arg0)

    if not COMPILE_MODE:
        echo "Runtime Error: Dynamic Function Calls (Higher Order Functions) require Compilation."
        quit(1)

    return 0

OP["EXPO"] = proc(args: OPARGUMENTS): int =
    C("TEXT", "__comment", "EXPO", "EXPOSE", args.memory_address)
    C("TEXT", "EXPO", args.memory_address, args.arg0, args.arg1)
    return 0

OP["ETRN"] = proc(args: OPARGUMENTS): int =
    C("TEXT", "__comment", "ETRN", "Call extern", args.memory_address)
    C("TEXT", "ETRN", args.memory_address, args.arg0, args.arg1)
    return 0

OP["RET"] = proc(args: OPARGUMENTS): int =
    C("TEXT", "__comment", "RET", "RET", args.memory_address)
    C("TEXT", "RET", args.memory_address, "", "")
    if not COMPILE_MODE:
        if CALL_STACK.len > 0:
            let state = CALL_STACK.pop()
            instruction_counter = state.ip
            if STACK.len >= FRAME_PTR: STACK.setLen(FRAME_PTR)
            FRAME_PTR = state.fp
            if state.dest != "00": discard storeResult(state.dest, getValue(args.memory_address))
        else:
            quit(0)
    return 0

OP["GETARG"] = proc(args: OPARGUMENTS): int =
    C("TEXT", "__comment", "GETARG", "GETARG", args.memory_address)
    C("TEXT", "GETARG", args.memory_address, args.arg0, "")
    if not COMPILE_MODE:
        try:
            let idx = parseInt(args.arg0)
            if FRAME_PTR + idx < STACK.len:
                discard storeResult(args.memory_address, STACK[FRAME_PTR + idx])
        except: discard
    return 0

OP["EXIT"] = proc(args: OPARGUMENTS): int =
    C("TEXT", "__comment", "EXIT", "EXIT", args.memory_address)
    C("TEXT", "EXIT", args.memory_address, "", "")
    if not COMPILE_MODE:
        C("TEXT", "EXIT", args.memory_address, "", "")
    return 0

# --- STRINGS ---
OP["STR"] = proc(args: OPARGUMENTS): int =
    C("DATA", "__comment", "STR", "STR", args.arg0 & " => " & args.memory_address)
    C("DATA", "STR", args.memory_address, args.arg0[1..(args.arg0.len - 2)], "")
    return 0

OP["WRITES"] = proc(args: OPARGUMENTS): int =
    C("TEXT", "__comment", "WRITES", "WRITE", args.memory_address)
    C("TEXT", "WRITES", args.memory_address, "00", "")
    return 0


# --- MAP OPERATIONS ---

# NEWMAP
OP["NEWMAP"] = proc(args: OPARGUMENTS): int =
    C("TEXT", "__comment", "NEWMAP", "NEWMAP", args.memory_address)
    C("TEXT", "NEWMAP", args.memory_address, "", "")

    if not COMPILE_MODE:
        map_counter.inc()
        let mapId = "MAP_" & $map_counter

        HEAP_MAPS[mapId] = initTable[string, string]()
        discard storeResult(args.memory_address, mapId)

    return 0

# MSET
OP["MSET"] = proc(args: OPARGUMENTS): int =
    C("TEXT", "__comment", "MSET", "MSET", args.memory_address & " => (Key = " & args.arg0 & ", Value = " & args.arg1 & ")")
    C("TEXT", "MSET", args.memory_address, args.arg0, args.arg1)

    if not COMPILE_MODE:
        let mapRef = getValue(args.memory_address)
        let key = getValue(args.arg0)
        let val = getValue(args.arg1)

        if HEAP_MAPS.hasKey(mapRef):
            HEAP_MAPS[mapRef][key] = val
        else:
            OPWARN.add("Runtime Error: MSET attempted on invalid map reference: " & mapRef & "\n")

    return 0

# MGET
OP["MGET"] = proc(args: OPARGUMENTS): int =
    C("TEXT", "MGET", args.memory_address, args.arg0, args.arg1)

    if not COMPILE_MODE:
        let mapRef = getValue(args.arg0)
        let key = getValue(args.arg1)

        if HEAP_MAPS.hasKey(mapRef):
            let theMap = HEAP_MAPS[mapRef]
            if theMap.hasKey(key):
                discard storeResult(args.memory_address, theMap[key])
            else:
                # Key not found: Return "0" or "nil"
                discard storeResult(args.memory_address, "0")
        else:
            # Map not found: Return "0"
            discard storeResult(args.memory_address, "0")
            OPWARN.add("Runtime Error: MGET attempted on invalid map reference: " & mapRef & "\n")

    return 0

OP["MLEN"] = proc(args: OPARGUMENTS): int =
    C("TEXT", "MLEN", args.memory_address, args.arg0, "")
    # Interpreter logic:
    if not COMPILE_MODE:
        let mapRef = getValue(args.arg0)
        if HEAP_MAPS.hasKey(mapRef):
             # Convert int length to string for storage
            discard storeResult(args.memory_address, $HEAP_MAPS[mapRef].len)
        else:
            discard storeResult(args.memory_address, "0")
    return 0

OP["MHEAD"] = proc(args: OPARGUMENTS): int =
    C("TEXT", "MHEAD", args.memory_address, args.arg0, "")
    return 0

OP["MKEY"] = proc(args: OPARGUMENTS): int =
    C("TEXT", "MKEY", args.memory_address, args.arg0, "")
    return 0

OP["MVAL"] = proc(args: OPARGUMENTS): int =
    C("TEXT", "MVAL", args.memory_address, args.arg0, "")
    return 0

OP["MNEXT"] = proc(args: OPARGUMENTS): int =
    C("TEXT", "MNEXT", args.memory_address, args.arg0, "")
    return 0

OP["DEL"] = proc(args: OPARGUMENTS): int =
    C("TEXT", "DEL", args.memory_address, args.arg0, "")
    return 0

# --- FILE I/O OPERATIONS ----
OP["FOPEN"] = proc(args: OPARGUMENTS): int =
    C("TEXT", "FOPEN", args.memory_address, args.arg0, args.arg1)
    return 0

OP["FWRITE"] = proc(args: OPARGUMENTS): int =
    C("TEXT", "FWRITE", args.memory_address, args.arg0, "")
    return 0

OP["FREAD"] = proc(args: OPARGUMENTS): int =
    C("TEXT", "FREAD", args.memory_address, args.arg0, args.arg1)
    return 0

# Read entire file
OP["READF"] = proc(args: OPARGUMENTS): int =
    C("TEXT", "READF", args.memory_address, args.arg0, args.arg1)
    return 0

OP["FCLOSE"] = proc(args: OPARGUMENTS): int =
    C("TEXT", "FCLOSE", args.memory_address, "", "")
    return 0

# ---COMMAND LINE ARGUEMNTS ---
OP["ARGV"] = proc(args: OPARGUMENTS): int =
    C("TEXT", "ARGV", args.memory_address, args.arg0, "")
    return 0

OP["CAT"] = proc(args: OPARGUMENTS): int =
    C("TEXT", "CAT", args.memory_address, args.arg0, args.arg1)
    return 0

# --- TYPEOF ---
OP["TYPEOF"] = proc(args: OPARGUMENTS): int =
    C("TEXT", "TYPEOF", args.memory_address, args.arg0, args.arg1)
    return 0

OP["ITS"] = proc(args: OPARGUMENTS): int =
    C("TEXT", "ITS", args.memory_address, args.arg0, args.arg1)
    return 0

# --- ARRAYS ---
OP["NEWARR"] = proc(args: OPARGUMENTS): int =
    C("VOID", "__comment", "NEWARR", "NEWARR", args.memory_address)
    C("TEXT", "NEWARR", args.memory_address, args.arg0, args.arg1)
    return 0

OP["JF"] = proc(args: OPARGUMENTS): int =
    C("VOID", "__comment", "JF", "JUMP_FALSE", args.memory_address)
    C("TEXT", "JF", args.memory_address, args.arg0, args.arg1)


# --- FLOATS ---
OP["MOVSD"] = proc(args: OPARGUMENTS): int =
    C("VOID", "__comment", "MOVSD", "MOVSD", args.memory_address)
    C("TEXT", "MOVSD", args.memory_address, args.arg0, args.arg1)

OP["FSTORE"] = proc(args: OPARGUMENTS): int =
    C("VOID", "__comment", "FSTORE", "STORE_FLOST", args.memory_address & " => " & args.arg0)
    C("DATA", "FSTORE", args.memory_address, args.arg0, args.arg1)

OP["MOV"] = proc(args: OPARGUMENTS): int =
    C("VOID", "__comment", "MOV", "MOV", args.memory_address & " => " & args.arg0)
    C("TEXT", "MOV", args.memory_address, args.arg0, args.arg1)

OP["NSUB"] = proc(args: OPARGUMENTS): int =
    C("VOID", "__comment", "SUB", "NSUB", args.memory_address & " => " & args.arg0)
    C("TEXT", "NSUB", args.memory_address, args.arg0, args.arg1)

OP["NADD"] = proc(args: OPARGUMENTS): int =
    C("VOID", "__comment", "ADD", "NADD", args.memory_address & " => " & args.arg0)
    C("TEXT", "NADD", args.memory_address, args.arg0, args.arg1)


# ---- NETWORKING ---- #
OP["NET_SOCKET"] = proc(args: OPARGUMENTS): int =
    C("VOID", "__comment", "NET_SOCKET", "NET_SOCKET", "")
    C("TEXT", "NET_SOCKET", args.memory_address, args.arg0, args.arg1)

OP["NET_BIND"] = proc(args: OPARGUMENTS): int =
    C("VOID", "__comment", "NET_BIND", "NET_BIND", "")
    C("TEXT", "NET_BIND", args.memory_address, args.arg0, args.arg1)

OP["NET_LISTEN"] = proc(args: OPARGUMENTS): int =
    C("VOID", "__comment", "NET_LISTEN", "NET_LISTEN", "")
    C("TEXT", "NET_LISTEN", args.memory_address, args.arg0, args.arg1)

OP["NET_ACCEPT"] = proc(args: OPARGUMENTS): int =
    C("VOID", "__comment", "NET_ACCEPT", "NET_ACCEPT", "")
    C("TEXT", "NET_ACCEPT", args.memory_address, args.arg0, args.arg1)

OP["NET_WRITE"] = proc(args: OPARGUMENTS): int =
    C("VOID", "__comment", "NET_WRITE", "NET_WRITE", "")
    C("TEXT", "NET_WRITE", args.memory_address, args.arg0, args.arg1)

OP["NET_CLOSE"] = proc(args: OPARGUMENTS): int =
    C("VOID", "__comment", "NET_CLOSE", "NET_CLOSE", "")
    C("TEXT", "NET_CLOSE", args.memory_address, args.arg0, args.arg1)

OP["NET_RECV"] = proc(args: OPARGUMENTS): int =
    C("VOID", "__comment", "NET_RECV", "NET_RECV", "")
    C("TEXT", "NET_RECV", args.memory_address, args.arg0, args.arg1)

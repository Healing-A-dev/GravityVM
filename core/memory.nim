import tables

# Virtual Memory Pools #
var POOL_LOCAL*: ref Table[string, string]  = new(Table[string, string])
var POOL_GLOBAL*: ref Table[string, string] = new(Table[string, string])
var POOL_BUFFER*: ref Table[string, string] = new(Table[string, string])

var MAX_SIZE_GLOBAL*: ref int
var MAX_SIZE_LOCAL*: ref int
var MAX_SIZE_BUFFER*:  ref int

POOL_LOCAL[] = initTable[string, string]()
POOL_GLOBAL[] = initTable[string, string]()
POOL_BUFFER[] = initTable[string, string]()

new(MAX_SIZE_GLOBAL)
new(MAX_SIZE_LOCAL)
new(MAX_SIZE_BUFFER)

# Memory Addresses #
var ADDR_LOCAL*:string  = "00"
var ADDR_GLOBAL*:string = "00"
var ADDR_BUFFER*:string = "00"

# Speical Registers #
var REGISTER*: Table[string, auto] = {
    "sra": "",
    "srb": "",
    "src": "",
    "srd": "",
    "sre": "",
    "fhr": "",  # Not accessable threw normal means (internal for internal useage only)
    "srnl": "\\n", # Not accessable threw normal means (internal for internal useage only)
}.toTable()

# Labels #
var LABELS*: Table[string, int] = initTable[string, int]()

#[ MEMORY POOL MANAGMENT ]#


# Incrementing Memory Addess #
proc Increase*(T: var string, MAX: int = 122): bool {.discardable.} =
    var p0: int = T[0].ord()
    var p1: int = T[1].ord()

    if p0 == MAX and p1 == MAX:
        return false
    p1.inc()

    if p1 == 58:
        p1 = 65
    elif p1 == 91:
        p1 = 97
    elif p1 == 123:
        p0.inc()
        p1 = 48

    if p0 == 58:
        p0 = 65
    elif p0 == 91:
        p0 = 97

    T[0] = p0.chr()
    T[1] = p1.chr()
    return true


# Decrementing Memory Address
proc Decrease*(T: var string, MIN: int = 0): bool {.discardable.} =
    var p0: int = T[0].ord()
    var p1: int = T[1].ord()

    if p0 == MIN and p1 == MIN:
        return false
    p1.dec()

    if p1 == 96:
        p1 = 90
    elif p1 == 64:
        p1 = 57
    elif p1 == 47:
        p0.dec()
        p1 = 122

    if p0 == 96:
        p0 = 90
    elif p0 == 64:
        p0 = 57

    T[0] = p0.chr()
    T[1] = p1.chr()
    return true


# Size of a Memory Pool
proc Size*(MEM_POOL: Table[string, string]): int =
    return MEM_POOL.len


# Storing Value
proc Store*(MEM_POOL: var Table[string, string], ADDR: var string, DATA: var string, MAX_SIZE: int): string {.discardable.} =
    if DATA.len >= 2 and DATA[0] == '[':
        DATA = DATA[1..<(DATA.len - 1)]
    MEM_POOL[ADDR] = DATA

    if not ADDR.Increase() or MEM_POOL.len > MAX_SIZE:
        echo "\e[1mgravity: <\e[91mOVERFLOW-Error\e[0m\e[1m>\e[0m"
        echo "|> Reason: Maximum memory pool size exceeded"
        echo "|\e[90m--------\e[0m> Maximum size: " & $MAX_SIZE
        echo "|\e[90m--------\e[0m> Current size: " & $MEM_POOL.len
        quit()
    return ADDR


# Removing Value
proc Remove*(MEM_POOL: var Table[string, string], ADDR: var string): string {.discardable.} =
    if MEM_POOL.Size() == 0 or ADDR == "00":
        echo "MEMORY UNDERFLOW"
        quit()
    MEM_POOL.del(ADDR)
    ADDR.Decrease()
    return ADDR


# Clearing Mem. Pool
proc Free*(MEM_POOL: var Table[string, string]): void =
    MEM_POOL = initTable[string, string]()


# Zeroing Address Pointer
proc Zero*(ADDR: var string): void =
    ADDR = "00"


# Collect Next Available Memory Location
proc NextAddress*(MEM_POOL: Table[string, string]): string =
    var ADDR = "01"
    while MEM_POOL.hasKey(ADDR) and MEM_POOL[ADDR] != "":
        if not ADDR.Increase():
            return ADDR # Maximum capcity reached
    return ADDR

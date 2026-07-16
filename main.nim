import std/os
import std/tables
import core/cli
import core/generation
import core/cache
import core/memory
import codegen/codegen

# --- Argument Parsing --- #
let commands: seq[string] = commandLineParams()
parseArgs(commands.len, commands)

# --- Instruction Generation --- #
let program: seq[string] = generateInstructions(vm_file_in)
var valid: int = validateInstructions(program)
if valid != 0: quit(valid)

# --- Cache Comparison --- #
loadCacheConfig()
generateData(vm_file_in, program)
let recompile: int = compareCache(vm_file_in)
if recompile == 1 or vm_recompile or vm_debug:
    valid = processInstructions(program, vm_file_in)
    if valid != 0: quit(valid)

# --- Compilation --- #
let status: tuple = C_buildProgram(program, recompile)
if status.ERRCODE == 0: writeCache(vm_file_in)
if status.ERRCODE == 0 and status.Run:
    quit(C_run())

# --- Debugging --- #
if vm_debug:
    let instruction_count: string = $(program.len / 4)
    var
        used_storage: tuple[Local: int, Global: int, Buffer: int] = (Local: 0, Global: 0, Buffer: 0)
        global_data: seq[string] = @[]
        local_data: seq[string] = @[]
        buffer_data: seq[string] = @[]

    # --- Collecting Memory --- #
    for location, data in POOL_GLOBAL[].pairs():
        if data != "":
            inc used_storage.Global
            global_data.add(location & " => " & data)

    for location, data in POOL_LOCAL[].pairs():
        if data != "":
            inc used_storage.Local
            local_data.add(location & " => " & data)

    for location, data in POOL_BUFFER[].pairs():
        if data != "":
            inc used_storage.Buffer
            buffer_data.add(location & " => " & data)

    # --- Displaying Debug Information --- #
    echo "Filename: " & vm_file_in & "\n"

    echo "-------------------------"
    echo "Instruction Count: " & instruction_count[0..<(instruction_count.len - 2)]
    echo "Virtual Storage Reserved: " & $(POOL_GLOBAL[].len + POOL_LOCAL[].len + POOL_BUFFER[].len)
    echo "Virtual Storage Used: " & $(used_storage.Global + used_storage.Local + used_storage.Buffer) & "\n"

    echo "-------------------------"
    echo "Instructions: "
    for information in DebugInformation:
        echo information

    echo "\n-------------------------"
    echo "Data:"
    echo "    Global:"
    for data in global_data:
        echo "        " & data
    echo "    Local:"
    for data in local_data:
        echo "        " & data
    echo "    Buffer:"
    for data in buffer_data:
        echo "        " & data

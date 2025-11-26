import std/os
import core/cli
import core/generation
import core/cache
import codegen/codegen

# Argument Parsing #
let commands: seq[string] = commandLineParams()
parseArgs(commands.len, commands)

# Instruction Generation #
let program: seq[string] = generateInstructions(vm_file_in)
var valid: int = validateInstructions(program)
if valid != 0: quit(valid)

# Cache Comparison #
generateData(vm_file_in, program)
let recompile: int = compareCache(vm_file_in)
if recompile == 1 or vm_recompile or vm_debug:
    valid = processInstructions(program, vm_file_in)
    if valid != 0: quit(valid)

# Compilation #
let status: tuple = C_buildProgram(program, recompile)
if status.ERRCODE == 0: writeCache(vm_file_in)
if status.ERRCODE == 0 and status.Run:
    C_run()

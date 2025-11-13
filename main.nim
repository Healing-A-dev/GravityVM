import std/os
import std/strutils
import std/tables
import codegen/codegen
import core/instructions
import core/cli
import core/cache

# Instance Variables
var str_buffer: seq[string] = @[]
var cmd: int = 0
var warn: bool = false

# ARGV parsing
let commands: seq[string] = commandLineParams()
parseArgs(commands.len, commands)

proc generateInstructions(file: string): seq[string] = 
    let input: seq[string] = readFile(file).splitLines()
    var instructions: seq[string] = @[]
    var tmp: seq[string] = @[]
    
    for s in 0..input.len-1:
        for instr in input[s].split():
            var instruction: string = instr
            if instruction == "":
                instruction = "|"
            case instruction[0]
            of '[':
                if instruction[instruction.len-1] != ']':
                    tmp.add(instruction)
                else:
                    instructions.add(instruction)
            else:
                if tmp.len > 0 and instruction[instruction.len-1] != ']':
                    tmp.add(" ")
                    tmp.add(instruction)
                elif tmp.len > 0 and instruction[instruction.len-1] == ']':
                    tmp.add(" ")
                    tmp.add(instruction)
                    instruction = tmp.join()
                    instructions.add(instruction)
                    tmp = @[]
                else:
                    if instruction != "|":
                        instructions.add(instruction)
    return instructions
                        

proc expectedLen(length: int): string = 
    var str: string = ""
    let remainder: int = length mod 4
    if 4 - remainder == 2:
        str = str & $(length+2) & " or " & $(length-2)
    else:
        str = str & $(length+(4-remainder))
    
    return str


let pInstr: seq[string] = generateInstructions(vm_file_in)

if pInstr.len mod 4 != 0:
    echo "\e[1mgravity: <\e[91mFORMAT-Error\e[0m\e[1m>\e[0m"
    echo "|> Reason: Invalid bytecode length"
    echo "|\e[90m--------\e[0m> Length: " & $(pInstr.len)
    echo "|\e[90m--------\e[0m> Expected length: " & $(expectedLen(pInstr.len))
    quit()

discard generateData(vm_file_in, pInstr)
let recompile: int = compareCache(vm_file_in)

if recompile == 1 or vm_recompile:
    while instruction_counter < pInstr.len-1:
        var instruction: string = pInstr[instruction_counter]
        if Instructions.hasKey(instruction) and instruction_counter == cmd:
            var OPCODE: string = Instructions[instruction]
            var OPARGS: seq[string] = @[]
            var instruction_counter_next: int = instruction_counter
    
            while OPARGS.len < 3:
                OPARGS.add(pInstr[instruction_counter_next + 1])
                instruction_counter_next.inc()
    
            # Failed Instruction
            if OP[OPCODE](OPARGS[0], OPARGS[1], OPARGS[2]) != 0:
                echo "\e[1mgravity: <\e[91mFATAL-Error\e[0m\e[1m>\e[0m"
                echo "|> Compilation Stopped!"
                echo "|> Reason: " & OPERROR
                echo "|\e[90m--------\e[0m> Intruction: " & instruction & ", " & OPCODE & ""
                echo "|> Where:"
                echo "|\e[90m-------\e[0m> File: " & vm_file_in
                echo "|\e[90m-------\e[0m> Line: " & $((instruction_counter/4) + 1)
                quit()
    
            cmd = cmd + 4
        elif not Instructions.hasKey(instruction) and instruction_counter == cmd:
            echo "\e[1mgravity: <\e[91mFATAL-Error\e[0m\e[1m>\e[0m"
            echo "|> Compilation Stopped!"
            echo "|> Reason: Invalid instruction '" & instruction & "'"
            echo "|> Where:"
            echo "|\e[90m-------\e[0m> File: " & vm_file_in
            echo "|\e[90m-------\e[0m> Line: " & $((instruction_counter/4) + 1)
            quit()
    
        instruction_counter.inc()


    if OPWARN != "Warning(s):\n" and warn:
        echo OPWARN

if not vm_debug and vm_build:
    if recompile == 0 and not vm_recompile:
        if vm_run:
            C_run()
    else:
        C_generateASM()
        let status: int = C_compile()
        let write_status: int = writeCache(vm_file_in)
        if vm_run and status == 0:
            C_run()

import strutils
import tables
import instructions

proc generateInstructions*(file: string): seq[string] =
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


proc validateInstructions*(instructions: seq[string]): int =
    var str: string = ""
    let remainder: int = instructions.len mod 4
    if 4 - remainder == 2:
        str = $(instructions.len - 2) & " or " & $(instructions.len + 2)
    else:
        str = $(instructions.len + (4 - remainder))

    if instructions.len mod 4 != 0:
        echo "\e[1mgravity: <\e[91mFORMAT-Error\e[0m\e[1m>\e[0m"
        echo "|> Reason: Invalid bytecode length"
        echo "|\e[90m--------\e[0m> Length: " & $(instructions.len)
        echo "|\e[90m--------\e[0m> Expected length: " & str
        return 1

    return 0


proc processInstructions*(instructions: seq[string], file: string): int =
    var COMMAND: int = 0
    while instruction_counter < instructions.len - 1:
        var instruction: string = instructions[instruction_counter]
        if Instructions.hasKey(instruction) and instruction_counter == COMMAND:
            var OPCODE: string = Instructions[instruction]
            var OPARGS: seq[string] = @[]
            var next: int = instruction_counter

            while OPARGS.len < 3:
                OPARGS.add(instructions[next + 1])
                next.inc()

            # Instruction Failure
            if OP[OPCODE]((OPARGS[0], OPARGS[1], OPARGS[2])) != 0:
                echo "\e[1mgravity: <\e[91mFATAL-Error\e[0m\e[1m>\e[0m"
                echo "|> Compilation Stopped!"
                echo "|> Reason: " & OPERROR
                echo "|\e[90m---------\e[0m> Instruction: " & instruction & ", " & OPCODE
                echo "|> Where:"
                echo "|\e[90m--------\e[0m> File: " & file
                echo "|\e[90m--------\e[0m> Instruction #: " & $((instruction_counter / 4) + 1)
                return 2

            COMMAND.inc(4)
        elif not Instructions.hasKey(instruction) and instruction_counter == COMMAND:
            echo "\e[1mgravity: <\e[91mFATAL-Error\e[0m\e[1m>\e[0m"
            echo "|> Compilation Stopped!"
            echo "|> Reason: Invalid instruction: " & instruction
            echo "|> Where:"
            echo "|\e[90m--------\e[0m> File: " & file
            echo "|\e[90m--------\e[0m> Instruction #: " & $((instruction_counter / 4) + 1)
            return 2

        instruction_counter.inc()

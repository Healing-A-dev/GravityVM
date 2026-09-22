import strutils
import tables
import instructions
import cli
import memory
import streams

proc decodeOpcode(val: uint8): string =
  var v = int(val)
  var res = ""
  if v == 0:
      return "00"

  while v > 0:
    let rem = v mod 36
    if rem < 10: res.add(chr(rem + ord('0')))
    else: res.add(chr(rem - 10 + ord('A')))
    v = v div 36

  for i in 0 ..< res.len div 2:
    swap(res[i], res[res.len - 1 - i])

  while res.len < 2:
    res = "0" & res
  return res

proc collectProperInstructionSize(size: int): string =
    let diff_size: int = size mod 4
    return $(size-diff_size)

proc generateInstructions*(file: string): seq[string] =
    var instructions: seq[string] = @[]
    var strm = newFileStream(file, fmRead)

    if strm.isNil:
        echo "\e[1mgravity: <\e[91mFATAL-Error\e[0m\e[1m>\e[0m"
        echo "|> Reason: Could not file <", file, ">"
        quit(1)

    defer: strm.close()

    let magic = strm.readStr(3)
    let version = strm.readUint8()

    if magic != "GVM":
        echo "\e[1mgravity: <\e[91mFATAL-Error\e[0m\e[1m>\e[0m"
        echo "|> Reason: Not a valid GravityVM binary."
        quit(1)

    let instructionCount = strm.readUint32()

    for i in 0 ..< int(instructionCount):
        let opByte = strm.readUint8()
        instructions.add(decodeOpcode(opByte))

        for argIdx in 0 .. 2:
            let argLen = strm.readUint8()
            let argStr = strm.readStr(int(argLen))
            instructions.add(argStr)

    return instructions

proc validateInstructions*(instructions: seq[string]): int =
    if instructions.len mod 4 != 0:
        echo "\e[1mgravity: <\e[91mFATAL-Error\e[0m\e[1m>\e[0m"
        echo "|> Reason: Invalid bytecode length <" & $instructions.len & ">"
        echo "|\e[90m---------\e[0m> Expected length: " & collectProperInstructionSize(instructions.len)
        return 1
    return 0

proc processInstructions*(instructions: seq[string], file: string): int =
    if vm_debug:
        type OPARGUMENTS = tuple[memory_address: string, arg0: string, arg1: string]
        OP["FREE"] = proc(args: OPARGUMENTS): int = return 0

    LABELS.clear()
    instruction_counter = 0

    var scan_idx = 0
    while scan_idx < instructions.len:
        let opCode = instructions[scan_idx]

        if Instructions.hasKey(opCode) and Instructions[opCode] == "LBL":
             if scan_idx + 1 < instructions.len:
                 let labelRaw = instructions[scan_idx + 1]
                 let labelName = labelRaw.replace("[", "").replace("]", "")
                 LABELS[labelName] = scan_idx

        scan_idx.inc(4)

    var COMMAND: int = 0
    instruction_counter = 0

    while instruction_counter < instructions.len - 1:
        var instruction: string = instructions[instruction_counter]

        if Instructions.hasKey(instruction) and instruction_counter == COMMAND:
            var OPCODE: string = Instructions[instruction]
            var OPARGS: seq[string] = @[]
            var next: int = instruction_counter

            while OPARGS.len < 3:
                if next + 1 < instructions.len:
                    OPARGS.add(instructions[next + 1])
                else:
                    OPARGS.add("00")
                next.inc()

            if OP[OPCODE]((OPARGS[0], OPARGS[1], OPARGS[2])) != 0:
                let instruction_number: string = $((instruction_counter / 4) + 1)
                echo "\e[1mgravity: <\e[91mFATAL-Error\e[0m\e[1m>\e[0m"
                echo "|> Compilation Stopped!"
                echo "|> Reason: " & OPERROR
                echo "|\e[90m---------\e[0m> Opcode: " & instruction & ", " & OPCODE
                echo "|\e[90m--------\e[0m> Location: " & instruction_number
                return 2
            COMMAND = instruction_counter + 4
            instruction_counter = COMMAND
        else:
             instruction_counter.inc()
             COMMAND = instruction_counter
    return 0

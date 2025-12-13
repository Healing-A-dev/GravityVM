# Static modules
import tables
import strutils
import osproc
import os
import targets/target
import targets/transpiler/packaging
import ../core/pattern

# Instance Variables
const c_version*: string = "0.0.1+12"
type OPARGUMENTS* = tuple[memory_address: string, arg0: string, arg1: string]
var
    c_cmds: Table[string, proc(d0: string, d1: string, d2: string): string] = vm_getTarget()
    c_rodata: seq[string] = @[]
    c_text: seq[string] = @[]
    c_data: seq[string] = @[]
    c_void: seq[string] = @[]
    c_bss: seq[string] = @[]
    c_debug: bool = true
    c_clean: bool = true
    c_input*: string = ""
    c_output*: string = ""
    c_recompile: bool = false
    c_transpile: bool = false
    c_tmp: string = "out"
    c_build: bool = false
    c_run: bool = false


# Directory Stripper
proc stripDir(file_path: string): string =
    var directory: seq[char] = @[]
    var tmp: seq[char] = @[]

    if not c_output.contains("/"):
        return file_path

    directory.add(file_path[file_path.len - 1])
    while directory[directory.len - 1] != '/':
        directory.add(file_path[file_path.len - 1 - (directory.len - 1)])

    var s: int = directory.len - 2
    while s > 0:
        tmp.add(directory[s])
        s.dec()

    return tmp.join("")


proc C*(location: string, CMD: string, d0: string, d1: string, d2: string): int {.discardable.} =
    if not c_cmds.hasKey(CMD):
        let commands: string = commandLineParams().join(" ") & " -f:perl"
        echo "\e[31mSEVERE:\e[0m Invalid or unimplemented opcode '" & CMD & "', falling back to perl transpilation."
        echo "\e[92mHint:\e[0m ./gravity " & commands & " \e[96m[Fallback]\e[0m"
        discard execCmd("./gravity " & commands)
        quit()

    case location
    of "TEXT":
        c_text.add(c_cmds[CMD](d0, d1, d2))
    of "BSS":
        c_bss.add(c_cmds[CMD](d0, d1, d2))
    of "DATA":
        c_data.add(c_cmds[CMD](d0, d1, d2))
    else:
        c_void.add(c_cmds[CMD](d0, d1, d2))

    return 0


# VM Accessors #
proc C_setOutputFile*(file: string): string =
    c_output = file
    return file

proc C_setInputFile*(file: string): string =
    c_input = file
    return file

proc C_setTranspile*(state: bool = false): void =
    c_cmds = vm_getTarget("transpiler", "transpiler")
    c_transpile = true

proc C_setDebug*(state: bool, init: bool = true): bool =
    if not state and not init:
        c_debug = state
        c_cmds["__comment"] = proc(d0: string, d1: string, d2: string): string =
            return ""
    return state

proc C_setState*(c_type: string, state: bool = false): bool {.discardable.} =
    case c_type
    of "build":
        c_build = state
    of "run":
        c_run = state
    of "recompile":
        c_recompile = state
    of "cleanup":
        c_clean = state
    else:
        echo "INVALID COMPILER VARIABLE: " & c_type
        quit()
    return state


# ASM Generator
proc C_generateASM*(): void =
    # Adding to Buffer
    c_rodata.add(c_cmds["__makeTemp"]("","",""))

    # Temporary EXIT (to avoid address boundary error)
    c_text.add("    mov $60, %rax\n")
    c_text.add("    mov $0, %rdi\n")
    c_text.add("    syscall\n")

    # Creating Buffers (If Necessary)
    let required_buffers: string = c_cmds["__required"]("", "", "")
    if required_buffers.contains("int: true"):
        c_bss.add("B_GIB:\n")
        c_bss.add("    .skip 128\n")
    if required_buffers.contains("str: true"):
        c_bss.add("B_GSB:\n")
        c_bss.add("    .skip 128\n")
    if required_buffers.contains("dot: true"):
        c_rodata.add("G_GDOTV:\n")
        c_rodata.add("    .ascii \".\"\n")
        c_rodata.add("G_GB10:\n")
        c_rodata.add("    .double 10.0\n")

    c_tmp = c_tmp & ".s"
    let c_out = open(c_tmp, fmWrite)
    defer: c_out.close()

    # Writing To File
    c_out.writeLine("    .file \"" & c_input & "\"")
    c_out.writeLine("    .text")
    c_out.writeLine("    .global _start\n")
    if c_bss.len > 0:
        c_out.writeLine("    .section .bss")
        c_out.writeLine(c_bss.join(""))
    if c_data.len > 0:
        c_out.writeLine("    .section .data")
        c_out.writeLine(c_data.join(""))
    c_out.writeLine("    .section .text")
    c_out.writeLine("_start:")
    c_out.writeLine(c_text.join(""))
    if c_rodata.len > 0:
        c_out.writeLine("    .section .rodata")
        c_out.writeLine(c_rodata.join(""))


# Perl Generator
proc C_generatePERL*(): void =
    c_tmp = c_output
    let c_out: File = open(c_tmp, fmWrite)
    defer: c_out.close()

    # Writing to file
    c_out.writeLine("#!/usr/bin/env perl\n")
    c_out.writeLine(innershell)
    c_out.writeLine(outershell)
    c_out.writeLine("#---| File: " & c_input)
    c_out.writeLine("sub _begin {")
    if c_data.len > 0:
        c_out.writeLine(c_data.join(""))
    c_out.writeLine(c_text.join(""))
    c_out.writeLine("}\n&_begin();")


proc C_compile*(): int =
    var files: seq[string] = @[c_tmp, c_output, c_output&".o"]
    var exit_code:int = 0
    var status: string = " \e[96m[" & $exit_code & "]\e[0m"

    # Assembly
    exit_code = execCmd("as -o " & files[2] & " " & files[0])
    if exit_code != 0:
        status = " \e[91m[" & $exit_code & "]\e[0m"
    echo "\e[92mHint:\e[0m as -o " & files[2] & " " & files[0] & status

    # Linking
    if exit_code == 0:
        exit_code = execCmd("ld -o " & files[1] & " " & files[2])
        if exit_code != 0:
                status = " \e[91m[" & $exit_code & "]\e[0m"
        echo "\e[92mHint:\e[0m ld -o " & files[1] & " " & files[2] & status

    # Cleanup
    if c_clean:
        files[1] = ""
        status = "\e[96m[Cleanup]\e[0m"
        exit_code = execCmd("rm " & files.join(" "))
        if exit_code != 0:
            status = "\e[91m[Cleanup]\e[0m"
        echo "\e[92mHint:\e[0m rm " & files.join(" ") & " " & status

    return exit_code


proc C_run*(): void =
    if vm_target[] == "transpiler":
        var end_of_path: int = (c_output <?> stripDir(c_output)).Region[0] - 1
        var packaging_location: string = c_output[0..end_of_path]

        if end_of_path < 0:
            end_of_path = c_output.len - 1

        if packaging_location == c_output:
            packaging_location = ""

        echo "\e[92mHint:\e[0m ./" & c_tmp & " \e[96m[Exec]\e[0m"
        discard execCmd("./" & c_tmp)
        return

    echo "\e[92mHint:\e[0m ./" & c_output & " \e[96m[Exec]\e[0m"
    discard execCmd("./" & c_output)


proc C_buildProgram*(instructions: seq[string], recompile: int = 1): tuple[ERRCODE: int, Run: bool] =
    if c_transpile:
        if not c_debug and c_build:
            C_generatePERL()
            discard execCmd("chmod +x " & c_output)
            if c_run:
                C_run()
    else:
        if not c_debug and c_build:
            if recompile == 0 and not c_recompile:
                if c_run:
                    C_run()
            else:
                C_generateASM()
                let status: int = C_compile()
                return (ERRCODE: status, Run: c_run)

# Static modules
import tables
import strutils
import osproc
import os
import targets/target
import ../core/pattern

# Language Packaging
import targets/transpiler/lua/packaging
import targets/transpiler/c/packaging
import targets/transpiler/javascript/packaging

# Instance Variables
const c_version*: string = "0.0.3+20"
type OPARGUMENTS* = tuple[memory_address: string, arg0: string, arg1: string]
var
    c_cmds: Table[string, proc(d0: string, d1: string, d2: string): string] =  vm_getTarget()
    c_rodata: seq[string] = @[]
    c_text: seq[string] = @[]
    c_data: seq[string] = @[]
    c_void: seq[string] = @[]
    c_bss: seq[string] = @[]
    c_linkerfiles*: seq[string] = @[]
    c_debug: bool = true
    c_clean: bool = true
    c_input*: string = ""
    c_output*: string = ""
    c_recompile: bool = false
    c_transpile: bool = false
    c_verbose*: bool = false
    c_tmp: string = "out"
    c_build: bool = false
    c_run: bool = false
    c_lang*: string = "native"
    c_backup*: string = ""
    c_c: string = ""
    c_generateObjectFile*: bool = false


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


proc fancyError(): void =
    for pos, item in vm_languages[].pairs():
        if vm_languages[][pos] == c_lang:
            vm_languages[][pos] = "\e[91m\e[9m" & c_lang & "\e[0m"



# Compiler OPCODE runner
# Runs the given OPCODE and compiles it to given format
proc C*(location: string, CMD: string, d0: string, d1: string, d2: string): int {.discardable.} =
    if not c_cmds.hasKey(CMD):
        var commands: seq[string] = commandLineParams()
        var to_run: bool = false
        for pos, _ in commands.pairs():
            if commands[pos].contains("-f:"):
                to_run = true
                commands[pos] = "-b:" & c_backup
            elif commands[pos].contains("-b:"):
                commands[pos] = ""
        if to_run:
            discard execCmd("gvm " & commands.join(" "))
            quit()

        fancyError()
        echo "\e[1mgravity: <\e[91mCOMPILE-Error\e[0m\e[1m>\e[0m"
        echo "|> Reason: Invalid, unimplemented, or unsupported opcode '\e[91m" & CMD & "\e[0m'"
        echo "|> Try -b: [" & vm_languages[].join(", ") & "] to build with a different backend"
        echo "|> Try -f: [" & vm_languages[].join(", ") & "] to add a fallback backend"
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

proc C_setTranspile*(state: bool = false, language: string = "c"): void =
    c_cmds = vm_getTarget("transpiler", "transpiler", language)
    c_transpile = true
    c_lang = language

proc C_setDebug*(state: bool, init: bool = true): bool =
    if not state and not init:
        c_debug = state
        c_cmds["__comment"] = proc(d0: string, d1: string, d2: string): string =
            return ""
    return state

proc C_setPlatform*(arch: string, target: string): void =
    c_cmds = vm_getTarget(arch, target)

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
    if c_bss.len > 0:
        c_out.writeLine("    .section .bss")
        c_out.writeLine(c_bss.join(""))
    if c_data.len > 0:
        c_out.writeLine("    .section .data")
        c_out.writeLine(c_data.join(""))
    c_out.writeLine(c_text.join(""))
    if c_rodata.len > 0:
        c_out.writeLine(c_rodata.join(""))

# Transpiler Code Generator
proc C_transpile*(): void =
    var setup: string = ""
    var comment_char: string = ""
    var entry_start: string = ""
    var entry_end: string = ""
    var entry_call: string = ""
    c_tmp = c_output

    # Setting up transpiler environment
    case c_lang
    of "lua":
        setup = lua_setup
        comment_char = lua_comment_char
        entry_start = lua_entry_start
        entry_end = lua_entry_end
        entry_call = lua_entry_call
    of "c":
        setup = c_setup
        comment_char = c_comment_char
        entry_start = c_entry_start
        entry_end = c_entry_end
        entry_call = c_entry_call
        c_tmp = c_tmp & ".c"
        c_c = c_compiler
    of "javascript":
        setup = js_setup
        comment_char = js_comment_char
        entry_start = js_entry_start
        entry_end = js_entry_end
        entry_call = js_entry_call
        c_lang = "node"
    else:
        discard

    # Generating output file
    let c_out: File = open(c_tmp, fmWrite)
    defer: c_out.close()

    # Writing shebang
    case c_lang
    of "c":
        discard
    else:
        c_out.writeLine("#!/usr/bin/env " & c_lang & "\n")

    # Writing to file
    c_out.writeLine(setup)
    c_out.writeLine(comment_char & "--| File: " & c_input & " |--" & comment_char)
    c_out.writeLine(entry_start)
    if c_data.len > 0:
        c_out.writeLine(c_data.join(""))
    c_out.writeLine(c_text.join(""))
    c_out.writeLine(c_cmds["__finalize"]("", "", ""))
    c_out.writeLine(entry_end)

    # Writing entrypoint function call
    case c_lang:
    of "c":
        discard
    else:
        c_out.writeLine("")
        c_out.writeLine(comment_char & "--| Entrypoint Call |--" & comment_char)
        c_out.writeLine(entry_call)


proc C_compile*(): int =
    var files: seq[string] = @[c_tmp, c_output, c_output & ".o"]
    var exit_code:int = 0
    var status: string = " \e[96m[" & $exit_code & "]\e[0m"

    # Win64 Compilation (Cross Platform Compilation | ie. Linux -> Windows)
    if vm_isWin64_CPC[]:

      exit_code = execCmd("x86_64-w64-mingw32-as -o " & files[2] & " " & files[0])
      if exit_code != 0:
        status = " \e[91m[" & $exit_code & "]\e[0m"
      if c_verbose:
        echo "x86_64-w64-mingw32-as -o " & files[2] & " " & files[0] & status

      # Linking (mingw32-gcc)
      if exit_code == 0 and not c_generateObjectFile:
        exit_code = execCmd("x86_64-w64-mingw32-gcc " & files[2] & " -o " & files[1] & ".exe " & c_linkerfiles.join(" ") & " -nostdlib -lkernel32 -lws2_32 -lbcrypt -lmswsock")
        status = "\e[96m[Link]\e[0m"
        if exit_code != 0:
          status = " \e[91m[Link]\e[0m"
        if c_verbose:
          echo "x86_64-w64-mingw32-gcc " & files[2] & " -o " & files[1] & ".exe " & c_linkerfiles.join(" ") & " -nostdlib -lkernel32 -lws2_32"

    # Win64 Compilation (Same Platform Compilation | ie. Windows -> Windows)
    elif not vm_isWin64_CPC[] and vm_target[] == "windows":

      exit_code = execCmd("as -o " & files[2] & " " & files[0])
      if exit_code != 0:
        status = " \e[91m[" & $exit_code & "]\e[0m"
      if c_verbose:
        echo "as -o " & files[2] & " " & files[0] & status

      # Linking (gcc)
      if exit_code == 0 and not c_generateObjectFile:
        exit_code = execCmd("gcc " & files[2] & " -o " & files[1] & ".exe " & c_linkerfiles.join(" ") & " -nostdlib -lkernel32 -lws2_32")
        status = "\e[96m[Link]\e[0m"
        if exit_code != 0:
          status = " \e[91m[Link]\e[0m"
        if c_verbose:
          echo "gcc " & files[2] & " -o " & files[1] & ".exe " & c_linkerfiles.join(" ") & " -nostdlib -lkernel32 -lws2_32"

    # Linux/MacOS
    else:
      if c_generateObjectFile: files[2] = "_" & files[2]
      exit_code = execCmd("as -o " & files[2] & " " & files[0])
      if exit_code != 0:
          status = " \e[91m[" & $exit_code & "]\e[0m"
      if c_verbose:
          echo "as -o " & files[2] & " " & files[0] & status

      # Linking
      if exit_code == 0 and not c_generateObjectFile:
          exit_code = execCmd("ld -o " & files[1] & " " & files[2] & " " & c_linkerfiles.join(" "))
          status = "\e[96m[Link]\e[0m"
          if exit_code != 0:
              status = " \e[91m[Link]\e[0m"
          if c_verbose:
              echo "ld -o " & files[1] & " " & files[2] & " " & c_linkerfiles.join(" ") & " " & status

      if exit_code == 0 and c_generateObjectFile:
        exit_code = execCmd("ld -r -o " & files[1] & ".o " & files[2] & " " & c_linkerfiles.join(" "))
        status = "\e[96m[Link->Object]\e[0m"
        if exit_code != 0:
            status = " \e[91m[Link->Object]\e[0m"
        if c_verbose:
            echo "ld -r -o " & files[1] & ".o " & files[2] & " " & c_linkerfiles.join(" ") & " " & status

    # Cleanup
    if c_clean:
        if c_generateObjectFile:
            files[2] = ""
        files[1] = ""
        status = "\e[96m[Cleanup]\e[0m"
        exit_code = execCmd("rm " & files.join(" "))
        if exit_code != 0:
            status = "\e[91m[Cleanup]\e[0m"

        if c_verbose:
            echo "rm " & files.join(" ") & " " & status

    return exit_code


proc C_run*(): int =
    if vm_target[] == "transpiler":
        var end_of_path: int = (c_output <?> stripDir(c_output)).Region[0] - 1
        var packaging_location: string = c_output[0..end_of_path]

        if end_of_path < 0:
            end_of_path = c_output.len - 1

        if packaging_location == c_output:
            packaging_location = ""
            
        if c_verbose:
            echo "./" & c_tmp & " \e[96m[Exec]\e[0m"
        discard execCmd("./" & c_tmp)
        return
    if c_verbose:
        echo "./" & c_output & " \e[96m[Exec]\e[0m"
    return execCmd("./" & c_output)


proc buildC(compiler: string, output_command: string = "-o"): void =
    if c_c == "":
        return

    var status: int = execCmd(compiler & " " & output_command & " " & c_output & " " & c_tmp)
    var tag: string = "\e[96m[" & c_c & "]\e[0m"
    if status != 0:
        tag = "\e[91m[" & c_c & "]\e[0m"

    if c_verbose:
        echo compiler & " " & output_command & " " & c_output & " " & c_tmp & " " & tag

    if c_clean:
        tag = "\e[96m[Cleanup]\e[0m"
        status = execCmd("rm " & c_tmp)
        if status != 0:
            tag = "\e[91m[Cleanup]\e[0m"

        if c_verbose:
            echo "rm " & c_tmp & " " & tag

    c_tmp = c_tmp[0..<(c_tmp.len - 2)]



proc C_buildProgram*(instructions: seq[string], recompile: int = 1): tuple[ERRCODE: int, Run: bool] =
    if c_transpile:
        if not c_debug and c_build:
            if recompile != 0:
                C_transpile()
                buildC(c_c)
                discard execCmd("chmod +x " & c_output)
            else:
                c_tmp = c_output

            if c_run:
                quit(C_run())
    else:
        if not c_debug and c_build:
            if recompile == 0 and not c_recompile:
                if c_run:
                    quit(C_run())
            else:
                C_generateASM()
                let status: int = C_compile()
                return (ERRCODE: status, Run: c_run)

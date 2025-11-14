# Static modules
import targets/target
import tables
import strutils
import osproc

# Instance Variables
var c_cmds: Table[string, proc(d0: string, d1: string, d2: string): string] = vm_getTarget()
var c_rodata: seq[string] = @[]
var c_text: seq[string] = @[]
var c_data: seq[string] = @[]
var c_void: seq[string] = @[]
var c_bss: seq[string] = @[]
var c_clean: bool = true
var c_input: string = ""
var c_output: string = ""
const c_tmp: string = "out.s"


proc C*(location: string, CMD: string, d0: string, d1: string, d2: string): int {.discardable.} =
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


proc C_setDebug*(state: bool, init: bool = true): bool =
    if not state and not init:
        c_cmds["__comment"] = proc(d0: string, d1: string, d2: string): string =
            return ""
    return state


proc C_setOutputFile*(file: string): string =
    c_output = file
    return file

proc C_setInputFile*(file: string): string =
    c_input = file
    return file

proc C_setCleanup*(state: bool = true): void =
    c_clean = state
    


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

        
proc C_compile*(): int =
    var files: seq[string] = @[c_tmp, c_output, c_output&".o"]
    var exit_code:int = 0
    var status: string = " \e[96m[" & $exit_code & "]\e[0m"
    
    exit_code = execCmd("as -o " & files[2] & " " & files[0])
    
    if exit_code != 0:
        status = " \e[91m[" & $exit_code & "]\e[0m"
        
    echo "\e[92mHint:\e[0m as -o " & files[2] & " " & files[0] & status

    if exit_code == 0:
        exit_code = execCmd("ld -o " & files[1] & " " & files[2])
        if exit_code != 0:
                status = " \e[91m[" & $exit_code & "]\e[0m"
                
        echo "\e[92mHint:\e[0m ld -o " & files[1] & " " & files[2] & status

    # cleanup
    if c_clean:
        files[1] = "" 
        discard execCmd("rm " & files.join(" "))

    return exit_code

proc C_run*(): void =
    echo "\e[92mHint:\e[0m ./" & c_output & " \e[96m[Exec]\e[0m"
    discard execCmd("./" & c_output)

# Library Imports
import std/[tables, osproc, strutils]
import x86_64/[linux, win64, darwin]
import aarch64/[linux, win64, darwin]

# Language Transpilers
import transpiler/lua/transpiler
import transpiler/c/transpiler
import transpiler/javascript/trasnpiler_new

# --------------------- #

var vm_target*: ref string
var vm_system*: ref string
var vm_isWin64_CPC*: ref bool
var vm_architecture*: ref string
var vm_languages*: ref seq[string]

new(vm_target)
new(vm_system)
new(vm_isWin64_CPC)
new(vm_architecture)
new(vm_languages)

# Creating the table to store the intructions for each architure and OS type
var vm_c = initTable[string, Table[string, Table[string, proc(d0: string, d1: string, d2: string): string]]]()
var vm_t = initTable[string, proc(d0: string, d1: string, d2: string): string]()

vm_c["amd64"] = initTable[string, Table[string, proc(d0: string, d1: string, d2:string): string]]()
vm_c["aarch64"] = initTable[string, Table[string, proc(d0: string, d1: string, d2:string): string]]()

vm_c["amd64"]["linux"] = x86_64_linux
vm_c["amd64"]["win64"] = x86_64_win64
vm_c["amd64"]["darwin"]  = x86_64_darwin

vm_c["aarch64"]["linux"] = aarch64_linux
vm_c["aarch64"]["win64"] = aarch64_win64
vm_c["aarch64"]["darwin"] = aarch64_darwin

vm_languages[] = @["native", "c", "js", "web-asm"]
vm_isWin64_CPC[] = false


proc vm_getTarget*(architecture: string = "", target: string = "", language: string = "lua"): Table[string, proc(d0: string, d1: string, d2: string): string] =
    # Collecting information about the system
    const hostSystem: string = hostOS
    vm_target[] = hostOS
    vm_system[] = execCmdEx("uname -o").output
    vm_architecture[] = hostCPU


    # User defined compilation target/architecture
    if target != "":
        vm_target[] = target
    elif architecture != "":
        vm_architecture[] = architecture

    vm_target[].stripLineEnd()
    vm_system[].stripLineEnd()
    vm_architecture[].stripLineEnd()

    vm_target[] = vm_target[].toLower()
    vm_system[] = vm_system[].toLower()
    vm_architecture[] = vm_architecture[].toLower()

    if vm_c.hasKey(vm_architecture[]):
        if vm_c[vm_architecture[]].hasKey(vm_target[]):
            if vm_target[] == "win64" or vm_target[] == "win32":
                if vm_target[] != hostSystem:
                    vm_isWin64_CPC[] = true
            return vm_c[vm_architecture[]][vm_target[]]

    # Transpiler languages
    case language
    of "lua":
        vm_t = vm_transpiler_lua
    of "javascript":
        vm_t = vm_transpiler_javascript
    of "c":
        vm_t = vm_transpiler_c
    else:
        discard

    return vm_t

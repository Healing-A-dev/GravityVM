# Library Imports
import std/[tables, strutils]
import x86_64/[linux, win64, darwin]
import aarch64/[linux, win64, darwin]

# Language Transpilers
import transpiler/lua/transpiler
import transpiler/c/transpiler
import transpiler/javascript/transpiler
import transpiler/python/transpiler

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

# Creating the table to store the instructions for each architecture and OS type
var vm_c = initTable[string, Table[string, Table[string, proc(d0: string, d1: string, d2: string): string]]]()
var vm_t = initTable[string, proc(d0: string, d1: string, d2: string): string]()

vm_c["amd64"] = initTable[string, Table[string, proc(d0: string, d1: string, d2: string): string]]()
vm_c["aarch64"] = initTable[string, Table[string, proc(d0: string, d1: string, d2: string): string]]()

vm_c["amd64"]["linux"] = x86_64_linux
vm_c["amd64"]["win64"] = x86_64_win64
vm_c["amd64"]["darwin"] = x86_64_darwin

vm_c["aarch64"]["linux"] = aarch64_linux
vm_c["aarch64"]["win64"] = aarch64_win64
vm_c["aarch64"]["darwin"] = aarch64_darwin

vm_languages[] = @["native", "c", "lua", "javascript", "python"]
vm_isWin64_CPC[] = false

proc normalizeArch*(arch: string): string =
    var a = arch.toLowerAscii().strip()
    if a in ["amd64", "x86_64", "x64"]: return "amd64"
    if a in ["aarch64", "arm64"]: return "aarch64"
    return a

proc normalizePlatform*(plat: string): string =
    var p = plat.toLowerAscii().strip()
    if p in ["linux", "linux64"]: return "linux"
    if p in ["win64", "windows", "win32"]: return "win64"
    if p in ["darwin", "macos", "osx"]: return "darwin"
    return p

proc vm_getTarget*(architecture: string = "", target: string = "", language: string = "lua"): Table[string, proc(d0: string, d1: string, d2: string): string] =
    # Collecting information about the system
    const hostSystem: string = hostOS
    vm_target[] = normalizePlatform(hostOS)
    vm_system[] = normalizePlatform(hostSystem)
    vm_architecture[] = normalizeArch(hostCPU)

    # User defined compilation target/architecture
    if target != "":
        vm_target[] = normalizePlatform(target)
    if architecture != "":
        vm_architecture[] = normalizeArch(architecture)

    if vm_target[] == "win64":
        if vm_system[] != "win64":
            vm_isWin64_CPC[] = true

    if vm_c.hasKey(vm_architecture[]):
        if vm_c[vm_architecture[]].hasKey(vm_target[]):
            return vm_c[vm_architecture[]][vm_target[]]

    # Transpiler languages
    case language.toLowerAscii()
    of "lua":
        vm_t = vm_transpiler_lua
    of "javascript", "js":
        vm_t = vm_transpiler_javascript
    of "c":
        vm_t = vm_transpiler_c
    of "python", "py":
        vm_t = vm_transpiler_python
    else:
        discard

    return vm_t

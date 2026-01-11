# Adding Language Support
------
### To add another language backend to gravity:

1) Create a directory within <**codegen/targets/transpiler**> with the language name you wish to support
2) Inside the newly created directory, copy the <**template/packaging.nim**> and <**template/transpiler.nim**> to a <**packaging.nim**> and <**transpiler.nim**> file respectivly, and edit each file as needed.
3) In <**codgen/targets/target.nim**> file, import the transpiler file you created within the new language folder:
```nim
# Language Transpilers
import transpiler/lua/transpiler
import transpiler/c/transpiler
import transpiler/javascript/transpiler
import transpiler/<LANGUAGE_NAME>/transpiler
```
_____
4) In <**codgen/targets/target.nim**> file, add the language to the case statement, and set **vm_t** to the name of the transpiler within the new transpiler file:
```nim
proc vm_getTarget*(architecture: string = "", target: string = "", language: string = "c"): Table[string, proc(d0: string, d1: string, d2: string): string] =
    # ...
    case language
    of "lua":
        vm_t = vm_transpiler_lua
    of "javascript":
        vm_t = vm_transpiler_javascript
    of "c":
        vm_t = vm_transpiler_c
    
    # Example Below
    #[
    of <LANGUAGE_NAME>:
        vm_t = vm_transpiler_<LANGUAGE_NAME>
    ]#

    # Leave the below unchanged
    else:
        discard
    # ...

```
-----
5) In <**codegen/codgen.nim**>, underneath the **<# Language Packaging>**, import that packaging file you created within the new language folder:
```nim
# Language Packaging
import targets/transpiler/lua/packaging
import targets/transpiler/c/packaging
import targets/transpiler/javascript/packaging
import targets/trasnpiler/<LANGUAGE_NAME>/packaging
```
-----
6) In <**codegen/codegen.nim**>, within the **C_transpile** function, add the name of the language your adding to the case statement, and set each variable to the respective variable defined in the **packaging.nim** file. (Any other such as the name of the output file *c_tmp*, name of the shebang environment  *c_lang*, or the compiler type (for compiled languages) *c_compiler* can be changed here aswell):
```nim
proc C_transpile*(): void =
    # ...
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
    of "javascript":
        setup = js_setup
        comment_char = js_comment_char
        entry_start = js_entry_start
        entry_end = js_entry_end
        entry_call = js_entry_call
        c_lang = "node"
    
    # Example Below
    #[
    of <LANGUAGE_NAME>:
        setup = <LANGUAGE_NAME>_setup
        comment_char = <LANGUAGE_NAME>_comment_char
        entry_start = <LANGUAGE_NAME>_entry_start
        entry_end = <LANGUAGE_NAME>_entry_end
        entry_call = <LANGUAGE_NAME>_entry_call
    
        # OPTIONALS #
        c_c = <LANGUAGE_NAME>_compiler (ie. gcc, cc, rust, nim)
        c_lang = <ENV> (#!/bin/env <ENV>)
        c_tmp = c_tmp & ".<FILE_EXTENSION>"
    ]#
    
    # Leave the below unchanged
    else:
        discard
    # ...
```
-------
7) (If the language supports running with shebang, this step can (and should) be ignored) In <**codegen/codegen.nim**>, within the **C_transpile** function, add the language to the case statement to prevent a shebang from being generated:
```nim
proc C_transpile*(): void =
    # ...
    case c_lang
    of "c" <LANGUAGE_NAME>:
        discard
    else # Leave unchanged
        c_out.writeLine("#!/usr/bin/env " & c_lang & "\n")
    # ...

# OR

proc C_transpile*(): void =
    # ...
    case c_lang
    of "c":
        discard
    of <LANGUAGE_NAME>:
        discard
    else # Leave unchanged
        c_out.writeLine("#!/usr/bin/env " & c_lang & "\n")
    # ...

```
-------
8) (If the language automatically calls the entrypoint function, this step can (and should) be ignored) In <**codegen/codegen.nim**>, within the **C_transpile** function, add the language to the case statement to prevent a the entrypoint function from being called from within the language itself:
```nim
proc C_transpile*(): void =
    # ...
    case c_lang:
    of "c" <LANGUAGE_NAME>:
        discard
    else: 
        # Leave unchanged
        c_out.writeLine("")
        c_out.writeLine(comment_char & "--| Entrypoint Call |--" & comment_char)
        c_out.writeLine(entry_call)
    
# OR

proc C_transpile*(): void =
    # ...
    case c_lang:
    of "c":
        discard
    of <LANGUAGE_NAME>:
        discard
    else:
        # Leave unchanged
        c_out.writeLine("")
        c_out.writeLine(comment_char & "--| Entrypoint Call |--" & comment_char)
        c_out.writeLine(entry_call)
```
--------
9) In <**core/cli.nim**>, within the **parseArgs** function, add a way for the language to be called as a backend (ie. rs, rust, nim, etc):
```nim 
proc parseArgs*(argc: int, argv: seq[string]): void =
    # ...
    elif (arg[0..1] == "b:"):
        if arg.len < 3:
            echo "\e[1mgravity: <\e[91mCLI-Error\e[0m\e[1m>\e[0m"
            echo "|> Reason: Language argument expected after -b:"
            quit()
        case arg[2..<(arg.len)]
        of "native":
            vm_recompile = C_setState("recompile", true)
            vm_execTarget = "native"
        of "c":
            vm_recompile = C_setState("recompile", true)
            vm_execTarget = "c"
            C_setTranspile(true, "c")
        of "lua":
            vm_recompile = C_setState("recompile", true)
            vm_execTarget = "lua"
            C_setTranspile(true, "lua")
        of "js":
            vm_recompile = C_setState("recompile", true)
            vm_execTarget = "javascript"
            C_setTranspile(true, "javascript")
        # Example
        #[
        of <LANGUAGE_NAME/SHORTHAND>:
            vm_recompile = C_setState("recompile", true)
            vm_execTarget = <LANGUAGE_NAME>
            C_setTranspile(true, <LANGUAGE_NAME>)
        ]#
        else:
            echo "\e[1mgravity: <\e[91mCLI-Error\e[0m\e[1m>\e[0m"
            echo "|> Reason: Unsupported Language: " & arg[2..<(arg.len)]
            quit()
    # ...
```
--------
10) In <**core/cli.nim**>, within the **parseArgs** function, add a way for the language to be called as a fallback:
```nim
proc parseArgs*(argc: int, argv: seq[string]): void =
    # ...
    elif (arg[0..1] == "f:"):
        if arg.len < 3:
            echo "\e[1mgravity: <\e[91mCLI-Error\e[0m\e[1m>\e[0m"
            echo "|> Reason: Language argument expected after -f:"
            quit()
        case arg[2..<(arg.len)]
        of "native":
            c_backup = "native"
        of "c":
            c_backup = "c"
        of "lua":
            c_backup = "lua"
        of "js":
            c_backup = "js"
        # Example
        #[
        of <LANGUAGE_SHORTHAND (SAME AS BACKEND NAME)>:
            c_backup = <LANGUAGE_SHORTHAND (SAME AS BACKEND NAME)>
        ]#
        else:
            echo "\e[1mgravity: <\e[91mCLI-Error\e[0m\e[1m>\e[0m"
            echo "|> Reason: Unsupported Language: " & arg[2..<(arg.len)]
            quit()
    # ...
```

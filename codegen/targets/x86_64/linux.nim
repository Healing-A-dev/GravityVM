import tables
import strutils
import ../../../core/memory

# Global Varibles #
var x86_64_linux* = initTable[string, proc(d0: string, d1: string, d2:string): string]()
var variables*: Table[string, string] = initTable[string, string]()

# Instance Varibles #
var needIntBuffer: bool = false
var needStrBuffer: bool = false
var needDotGlobal: bool = true
var variable_loop_counter: Table[string, int] = initTable[string, int]() 
var write_storage: Table[string, string] = initTable[string, string]()


# Utiliy Functions #
proc append(to: var string, data: string): string {.discardable.} =
    to = to & data & "\n"
    return to


proc variable_exists(var_name: string): bool =
    return variables.hasKey(var_name)


proc add_or_increment(var_name: string): int =
    if not variable_loop_counter.hasKey(var_name):
        variable_loop_counter[var_name] = 0
    else:
        variable_loop_counter[var_name].inc()
    return variable_loop_counter[var_name]


# Compiler Functions #       
x86_64_linux["__required"] = proc(d0: string, d1: string, d2: string): string =
    return "int: " & $needIntBuffer & "\nstr: " & $needStrBuffer & "\ndot: " & $needDotGlobal 


x86_64_linux["__makeTemp"] = proc(d0: string, d1: string, d2: string): string =
    var tmp: string = ""
    if write_storage.len > 0:
        for key, item in write_storage.pairs():
            tmp = tmp & item & "\n"
    return tmp


x86_64_linux["__comment"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    echo "\e[93mDEBUG\e[0m: [" & d1 & "]: " & d2
    return to_append.append("# " & d0)


x86_64_linux["NOP"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    return to_append.append("    nop")


x86_64_linux["STORE"] = proc(d0: string, d1: string, d2:string): string =
    var to_append: string = ""
    var d1 = d1

    case d0[0]
    of '@':
        to_append.append("G" & d0[1..<d0.len] & "_gravityV: ")
    of '$':
        to_append.append("L" & d0[1..<d0.len] & "_gravityV: ")
    of '%':
        to_append.append("B" & d0[1..<d0.len] & "_gravityV: ")
    of '[':
        echo "Working on it"
    else:
        return ""
        
    try:
        # Integers
        discard parseInt(d1)
        to_append.append("    .quad " & d1)
        variables[d0] = "integer"
    except:
        try:
            # Floats
            discard parseFloat(d1)
            to_append.append("    .double " & d1)
            variables[d0] = "double"
        except:
            # Strings
            d1 = d1.replace("\n", "\\n")
            if d1.contains('"'):
                d1 = "'" & d1 & "'"
                echo "WORK IN PROGRESS {STRINGS CONTAINING '\"'}!!!"
                quit()
                # to_append.append("    .ascii " & d1)
            else:
                to_append.append("    .ascii \"" & d1 & "\"")
            
            to_append.append("    .byte 0")
            variables[d0] = "string"
        
    return to_append


x86_64_linux["WRITE"] = proc(d0: string, d1: string, d2: string = ""): string =
    var d0: string = d0
    var d1: string = d1
    var d2: string = d2
    var to_append: string = ""

    case d0[0]
    of '@':
        d0 = "G" & d0[1..<d0.len] & "_gravityV"
    of '$':
        d0 = "L" & d0[1..<d0.len] & "_gravityV"
    of '%':
        d0 = "B" & d0[1..<d0.len] & "_gravityV"
    of '[':
        let d3: string = d0[1..<(d0.len - 1)]
        if REGISTER.hasKey(d3):
            if REGISTER[d3] != "":
                let count: int = write_storage.len
                let variable_name: string = "T" & $count & "_gravityV"
                try:
                    # Integers
                    discard parseInt(REGISTER[d3])
                    write_storage[variable_name] = variable_name & ":\n    .quad " & REGISTER[d3]
                except:
                    try:
                        # Floats
                        discard parseFloat(REGISTER[d3])
                        write_storage[variable_name] = variable_name & ":\n    .double " & REGISTER[d3]
                    except:
                        # Strings
                        write_storage[variable_name] = variable_name & ":\n    .ascii \"" & REGISTER[d3] & "\"\n    .byte 0" 
                d2 = REGISTER[d3]
                d0 = variable_name
            else:
                let count: int = write_storage.len
                let variable_name: string = "T" & $count & "_gravityV"
                try:
                    # Integers
                    discard parseInt(d3)
                    write_storage[variable_name] = variable_name & ":\n    .quad " & REGISTER[d3]
                except:
                    try:
                        # Floats
                        discard parseFloat(d3)
                        write_storage[variable_name] = variable_name & ":\n    .double " & d3
                    except:
                        # Strings
                        write_storage[variable_name] = variable_name & ":\n    .ascii \"" & d3 & "\"\n    .byte 0" 
                d2 = d3
                d0 = variable_name
                d1 = $d3.len
        else:
            let count: int = write_storage.len
            let variable_name: string = "T" & $count & "_gravityV"
            try:
                # Integers
                discard parseInt(d3)
                write_storage[variable_name] = variable_name & ":\n    .quad " & d3
            except:
                try:
                    # Floats
                    discard parseFloat(d3)
                    write_storage[variable_name] = variable_name & ":\n    .double " & d3
                except:
                    # Strings
                    write_storage[variable_name] = variable_name & ":\n    .ascii \"" & d3 & "\"\n    .byte 0" 
            d2 = d3
            d0 = variable_name
            d1 = $d3.len 
    else:
        echo "WIP"
        return ""

    try:
        if d2[0] == '[' and d2[d2.len - 1] == ']':
            d2 = d2[1..<(d2.len - 1)]
            
        # Integers
        discard parseInt(d2)
        needIntBuffer = true
        let loop_count: int = add_or_increment(d0)
        let iteration: string = "_" & $loop_count
        
        to_append.append("    mov " & d0 & "(%rip), %rax")
        to_append.append("    mov $10, %rcx")
        to_append.append("    lea B_GIB + 32(%rip), %rsi")
        to_append.append("    mov %rsi, %r8")
        to_append.append(".displayInt" & d0 & iteration & ":")
        to_append.append("    xor %rdx, %rdx")
        to_append.append("    div %rcx")
        to_append.append("    add $'0', %dl")
        to_append.append("    dec %rsi")
        to_append.append("    mov %dl, (%rsi)")
        to_append.append("    test %rax, %rax")
        to_append.append("    jnz .displayInt" & d0 & iteration)
        to_append.append("    mov $1, %rax")
        to_append.append("    mov $1, %rdi")
        to_append.append("    mov %r8, %rdx")
        to_append.append("    sub %rsi, %rdx")
        to_append.append("    syscall\n")
    except:
        try:
            if d2[0] == '[' and d2[d2.len - 1] == ']':
                d2 = d2[1..<(d2.len - 1)]
                
            # Floats
            discard parseFloat(d2)
            needStrBuffer = true
            needDotGlobal = true
            let size_d:int = d2[d2.find(".") + 1..<d2.len].len
            let loop_count: int = add_or_increment(d0)
            let iteration: string = "_" & $loop_count
            
            to_append.append("    movsd " & d0 & "(%rip), %xmm0")
            to_append.append("    cvttsd2si %xmm0, %rax")
            to_append.append("    mov %rax, %rbx")
            to_append.append("    lea B_GSB+64(%rip), %rsi")
            to_append.append("    movb $0, (%rsi)")
            to_append.append(".displayInt" & d0 & iteration & ":")
            to_append.append("    xor %rdx, %rdx")
            to_append.append("    mov $10, %rcx")
            to_append.append("    div %rcx")
            to_append.append("    add $'0', %dl")
            to_append.append("    dec %rsi")
            to_append.append("    mov %dl, (%rsi)")
            to_append.append("    test %rax, %rax")
            to_append.append("    jnz .displayInt" & d0 & iteration )
            to_append.append("    mov $1, %rax")
            to_append.append("    mov $1, %rdi")
            to_append.append("    lea B_GSB+64(%rip), %rdx")
            to_append.append("    sub %rsi, %rdx")
            to_append.append("    syscall")
            to_append.append("")
            to_append.append("    mov $1, %rax")
            to_append.append("    mov $1, %rdi")
            to_append.append("    lea G_GDOTV(%rip), %rsi")
            to_append.append("    mov $1, %rdx")
            to_append.append("    syscall")
            to_append.append("")
            to_append.append("    movsd " & d0 & "(%rip), %xmm0")
            to_append.append("    cvtsi2sd %rbx, %xmm1")
            to_append.append("    subsd %xmm1, %xmm0")
            to_append.append("    mov $" & $size_d & ", %rcx")
            to_append.append("    lea B_GSB(%rip), %rsi")
            to_append.append(".displayDecimal" & d0 & iteration & ":")
            to_append.append("    mulsd G_GB10(%rip), %xmm0")
            to_append.append("    cvttsd2si %xmm0, %rax")
            to_append.append("    add $'0', %al")
            to_append.append("    mov %al, (%rsi)")
            to_append.append("    inc %rsi")
            to_append.append("    cvtsi2sd %rax, %xmm1")
            to_append.append("    subsd %xmm1, %xmm0")
            to_append.append("    dec %rcx")
            to_append.append("    jnz .displayDecimal" & d0 & iteration)
            to_append.append("    mov $1, %rax")
            to_append.append("    mov $1, %rdi")
            to_append.append("    lea B_GSB(%rip), %rsi")
            to_append.append("    mov $" & $size_d & ", %rdx")
            to_append.append("    syscall")
            to_append.append("")
        except:
            # Strings
            to_append.append("    mov $1, %rax")
            to_append.append("    mov $1, %rdi")
            to_append.append("    mov $" & d0 & ", %rsi")
            to_append.append("    mov $" & d1 & ", %rdx")
            to_append.append("    syscall")
            to_append.append("")
    
    return to_append


x86_64_linux["COPY"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""

    echo d0
    echo d1
    echo d2

    
    return to_append


x86_64_linux["STORE REGISTER"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    
    echo d0
    echo d1
    echo d2
    
    return to_append


x86_64_linux["UPD"] = proc(d0: string, d1: string, d2: string): string =
    var to_append: string = ""
    var typing0: string = ""
    var typing1: string = ""
    var POOL_0: ref Table[string, string]
    var POOL_1: ref Table[string, string]
    var d0: string = d0
    var d1: string = d1

    case d0[0]
    of '@':
        try:
            discard parseInt(POOL_GLOBAL[][d0[1..<d0.len]])
            typing0 = "number"
        except:
            typing0 = "string"
        d0 = "G" & d0[1..<d0.len] & "_gravityV"
        POOL_0 = POOL_GLOBAL
    of '$':
        try:
            discard parseInt(POOL_LOCAL[][d0[1..<d0.len]])
            typing0 = "number"
        except:
            typing0 = "string"
        d0 = "L" & d0[1..<d0.len] & "_gravityV"
        POOL_0 = POOL_LOCAL
    of '%':
        try:
            discard parseInt(POOL_BUFFER[][d0[1..<d0.len]])
            typing0 = "number"
        except:
            typing0 = "string"
        d0 = "B" & d0[1..<d0.len] & "_gravityV"
        POOL_0 = POOL_BUFFER
    else:
        return ""

    case d1[0]
        of '@':
            try:
                discard parseInt(POOL_GLOBAL[][d1[1..<d1.len]])
                typing1 = "number"
            except:
                typing1 = "string"
            d1 = "G" & d1[1..<d1.len] & "_gravityV"
            POOL_1 = POOL_GLOBAL
        of '$':
            try:
                discard parseInt(POOL_LOCAL[][d1[1..<d1.len]])
                typing1 = "number"
            except:
                typing1 = "string"
            d1 = "L" & d1[1..<d1.len] & "_gravityV"
            POOL_1 = POOL_LOCAL
        of '%':
            try:
                discard parseInt(POOL_BUFFER[][d1[1..<d1.len]])
                typing1 = "number"
            except:
                typing1 = "string"
            d1 = "B" & d1[1..<d1.len] & "_gravityV"
            POOL_1 = POOL_BUFFER
        else:
            try:
                discard parseInt(POOL_BUFFER[][d1[1..<d1.len]])
                typing1 = "number"
            except:
                typing1 = "string"
                needStrBuffer = true   

    if typing1 == typing0:
        case typing0:
        of "string":
            if not needStrBuffer:
                to_append.append("    mov $" & d1 & ", %rsi")  
                to_append.append("    mov $" & d0 & " + 0, %rdi")
                to_append.append("    mov $" & $(POOL_1[][d1].len) & ", %rcx")   
                to_append.append("    cld")
                to_append.append("    resp movsb")
            else:
                echo "TODO: IMPLEMENT STR BUFFER STRING UPDATES"
                quit()
        of "number":
            var number: float = parseFloat(d1)
            var to_match: float = 0
            
            if POOL_1[].hasKey(d1):
                number = parseFloat(POOL_1[d1])
                
            to_append.append("    mov $" & $number & ", $[" & d0 & "]")
    else:
        echo "TODO: IMPLEMENT: " & typing0 & " -> " & typing1 & "UPDATES"
        quit()
        
    return to_append

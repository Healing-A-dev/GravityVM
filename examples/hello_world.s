    .file "examples/hello_world.gravity"
    .text
    .global _start

    .section .data
G01_gravityV: 
    .ascii "This was written in gravity :>\n"
    .byte 0

    .section .text
_start:
    mov $1, %rax
    mov $1, %rdi
    mov $T0_gravityV, %rsi
    mov $14, %rdx
    syscall

    mov $1, %rax
    mov $1, %rdi
    mov $T1_gravityV, %rsi
    mov $39, %rdx
    syscall

    mov $1, %rax
    mov $1, %rdi
    mov $T2_gravityV, %rsi
    mov $2, %rdx
    syscall

    mov $1, %rax
    mov $1, %rdi
    mov $G01_gravityV, %rsi
    mov $32, %rdx
    syscall

    mov $60, %rax
    mov $0, %rdi
    syscall

    .section .rodata
T0_gravityV:
    .ascii "Hello, World\n"
    .byte 0
T1_gravityV:
    .ascii "This was compiled using the GravityVM\n"
    .byte 0
T2_gravityV:
    .ascii "\n"
    .byte 0
G_GDOTV:
    .ascii "."
G_GB10:
    .double 10.0


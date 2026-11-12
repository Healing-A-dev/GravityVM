# GravityVM Architecture

GravityVM is a high-performance **Bring-Your-Own-Backend (BYOB)** compiler platform and intermediate virtual machine. While originally developed alongside the **Newton** programming language, GravityVM is fully decoupled and capable of serving as the compilation backend for any custom programming language compiler.

GravityVM transforms structured bytecode (`.gvt`) into optimized native machine code (x86_64, AArch64) or clean, self-contained scripts across multiple transpilation targets (C, Lua, Python, JavaScript).

```
   +-----------------------------+     +-----------------------------+
   |   Newton Source (.nt)       |     |   Custom Language (.lang)   |
   +-----------------------------+     +-----------------------------+
                 |                                    |
                 v (Newton Compiler)                  v (Custom Compiler Frontend)
   +-----------------------------------------------------------------+
   |                    Gravity Bytecode (.gvt)                      |
   +-----------------------------------------------------------------+
                                    |
                           +--------+--------+
                           |  GravityVM CLI  |
                           |  Caching Engine |
                           +--------+--------+
                                    |
                          +---------+---------+
                          |                   |
                          v                   v
   +------------------------------+    +-----------------------------------------------+
   | Native Target (x86_64 / ARM) |    | Transpilation Targets                         |
   |   Requires: -l:runtime.o     |    |   Self-Contained Embedded Runtimes:           |
   |   - as / ld                  |    |   - C (Clang/GCC + SysV ABI)                  |
   |   - Clang                    |    |   - Lua 5.4 (Native GOTO + Return Trampoline) |
   |   - MinGW                    |    |   - Python 3 (Block-Linear CFG State Machine) |
   +------------------------------+    |   - JavaScript (V8 / Node Switch Machine)     |
                                       +-----------------------------------------------+
```

> [!NOTE]
> **Runtime Library Boundary**:
> GravityVM does not bundle `libnewton.o`. Native machine code outputs link against whichever language runtime object is provided via the `-l:` flag. Conversely, script transpilers (Lua, Python, JavaScript) automatically synthesize a complete, self-contained runtime into the output file.

---

## 1. Instruction Set Architecture (ISA) & Bytecode Specification

GravityVM operates on a fixed 4-tuple bytecode layout:
```
OPCODE  ARG0  ARG1  ARG2
```

### 1.1 Binary Container Format (`.gvt`)
GravityVM bytecode files start with an 8-byte header followed by a sequence of instructions:

| Offset | Size | Type | Description |
|---|---|---|---|
| `0x00` | 3 bytes | ASCII | Magic identifier: `"GVM"` |
| `0x03` | 1 byte  | uint8 | Bytecode container version (`1` = Stack VM, `2` = Register VM) |
| `0x04` | 4 bytes | uint32 (LE) | Total instruction count in the stream |
| `0x08` | Variable | Stream | Sequence of instructions |

GravityVM provides 100% backward compatibility via dual-mode execution: container version 1 files (classic stack/accumulator mode) and version 2 files (16-register 3-address mode) are both automatically recognized and executed across all native and transpiled targets.

### 1.2 Base36 Opcode Table
Opcodes are mapped to mnemonic instructions:
- `00`: `NOP` — No operation
- `01`: `READ` — Read line from standard input
- `02`: `WRITE` — Write string / register to standard output
- `03`: `STORE` — Store value into memory location or stack offset
- `04`: `DEL` — Delete collection entry
- `05`: `ADD` — Tagged integer addition (3-address: `SRC1, SRC2, R_DEST`)
- `06`: `SUB` — Tagged integer subtraction (3-address: `SRC1, SRC2, R_DEST`)
- `07`: `MUL` — Tagged integer multiplication (3-address: `SRC1, SRC2, R_DEST`)
- `08`: `DIV` — Tagged integer division (3-address: `SRC1, SRC2, R_DEST`)
- `09`: `EXP` — Exponentiation
- `0A`: `COPY` — Move value between operands
- `0B`: `JMP` — Unconditional jump to label
- `0C`/`0K`: `JNZ` — Jump if `sra` / `r0 != 0`
- `0D`: `CMP` — Compare two operands
- `0E`: `INC` — Increment tagged integer by 2
- `0F`: `DEC` — Decrement tagged integer by 2
- `0J`: `LBL` — Define code label
- `0L`: `EXIT` — Program termination / entrypoint dispatch
- `0M`: `LT` — Less than comparison
- `0N`: `GT` — Greater than comparison
- `0P`: `JF` — Jump if false
- `0O`: `ITS` — Convert integer to string representation
- `0T`: `TYPEOF` — Query runtime type identifier
- `17`: `IADD` — Raw 64-bit integer addition (`0x93` / decimal 43)
- `18`: `ISUB` — Raw 64-bit integer subtraction (`0x94` / decimal 44)
- `19`: `IMUL` — Raw 64-bit integer multiplication (`0x95` / decimal 45)
- `1A`: `IDIV` / `PUSH` — Raw 64-bit integer division (`0x96` / decimal 46) / Call stack push
- `1B`: `CALL` — Call function / runtime procedure
- `1C`: `RET` — Return from current function frame
- `1D`: `GETARG` — Load parameter from caller stack frame
- `1E`: `STR` — Define constant string literal in data pool
- `1F`: `WRITES` — Print string
- `20`: `NEWMAP` — Instantiate a key-value hash map
- `21`: `MSET` — Assign key-value pair in collection
- `22`: `MGET` — Retrieve value by key from collection
- `23`: `MLEN` — Retrieve collection element count / string length
- `30`: `NEWARR` — Instantiate an indexed dynamic list
- `28`-`2E`: File I/O operations (`FOPEN`, `FWRITE`, `FREAD`, `FCLOSE`, `READF`)
- `3A`-`42`: Register / Stack manipulation (`MOVSD`, `FSTORE`, `MOV`, `NSUB`, `NADD`)

---

## 2. Register & Memory Architecture

GravityVM 2.0 introduces a modern 16-register virtual machine architecture (`r0`..`r15`) operating in 3-address mode (`OP SRC1, SRC2, R_DEST`), providing dramatic speed increases over pure stack/memory execution.

### 2.1 The Register File (`r0`..`r15`)

| Register | Role / Convention | x86_64 Mapping | AArch64 Mapping | Transpiler Target Mapping |
|---|---|---|---|---|
| `r0` (`sra`) | Primary Accumulator & Function Return | `%rax` | `x0` | `r0` / `sra` |
| `r1` | General scratch / Argument 1 | `%rdi` | `x1` | `r1` |
| `r2` | General scratch / Argument 2 | `%rsi` | `x2` | `r2` |
| `r3` | General scratch / Argument 3 | `%rdx` | `x3` | `r3` |
| `r4` | General scratch / Argument 4 | `%rcx` | `x4` | `r4` |
| `r5` | General scratch / Argument 5 | `%r8` | `x5` | `r5` |
| `r6` | General scratch / Argument 6 | `%r9` | `x6` | `r6` |
| `r7`..`r8` | Caller-saved scratch | `%r10`, `%r11` | `x7`, `x8` | `r7`, `r8` |
| `r9`..`r13` | Callee-saved registers | `%rbx`, `%r12`..`%r15` | `x9`..`x13` | `r9`..`r13` |
| `r14`..`r15` | Spill slots / Frame registers | `-8(%rbp)`, `-16(%rbp)` | `x14`, `x15` | `r14`, `r15` |

#### Callee Preservation & Function Boundaries
On function prologue (`LBL [F_*]`), native targets save callee registers `r9`..`r13` (`%rbx`, `%r12`..`%r15`) and allocate stack space for `r14`..`r15`. On epilogue (`RET`), these registers are restored prior to returning to the caller.

### 2.2 3-Address Instruction Model
In GVM 2.0, arithmetic instructions accept an explicit destination operand:
```
ADD   r1, r2, r3      # r3 = r1 + r2 (tagged)
IADD  r1, r2, r3      # r3 = r1 + r2 (raw 64-bit int)
SUB   r1, r2, r0      # r0 = r1 - r2
MOV   r1, $42, 00     # r1 = 42
```
If the 3rd argument is omitted, `"00"`, or `"sra"`, GVM defaults destination storage to `r0` (`sra`), ensuring seamless execution of legacy 2-address code.

### 2.3 Tagged Integers vs. Raw Integers
GravityVM supports both polymorphic dynamic runtimes and raw unboxed numeric performance:

- **Tagged Integers (`ADD`, `SUB`, `MUL`, `DIV`)**:
  $$\text{TAG}(x) = (x \times 2) + 1$$
  $$\text{UNTAG}(y) = \lfloor y / 2 \rfloor$$
  Tagged representations allow runtime reflection without pointer boxing.

- **Raw 64-bit Integers (`IADD`, `ISUB`, `IMUL`, `IDIV`)**:
  Bypasses bit shifts and masks, directly issuing hardware arithmetic instructions (`addq`, `subq`, `imulq`, `idivq` / `add`, `sub`, `mul`, `sdiv`).

### 2.4 Memory Pools
In addition to the register file, GravityVM maintains memory regions for static and dynamic data:
- **Global Pool (`@00`..`@zz`)**: Static variables surviving function lifetimes.
- **Local Pool (`$00`..`$zz`)**: Frame-local scratch variables.
- **Buffer Pool (`%00`..`%zz`)**: Temporary register spills and intermediate calculation buffers.
- **Constant Registers**:
  - `srnl`: Constant newline string (`\n`)

---

## 3. Native Compilation Engine

For native compilation, GravityVM translates bytecode into assembly code (`.s`) and invokes system toolchains:

1. **Host Linux x86_64**:
   - Assembler: GNU `as -O2`
   - Linker: GNU `ld` with standard runtime libraries (`libnewton.o`)
2. **Apple Silicon & Intel Darwin (`darwin`)**:
   - Cross-target compilation via LLVM `clang -target arm64-apple-darwin` or `x86_64-apple-darwin`
3. **Linux AArch64 (`aarch64`)**:
   - Assembled and linked via `clang -target aarch64-linux-gnu`
4. **Windows x64 (`win64`)**:
   - Cross-compiled via MinGW (`x86_64-w64-mingw32-as` & `x86_64-w64-mingw32-gcc`)

---

## 4. Transpilation & Control Flow Normalization

High-level transpilation targets emulate low-level stack frames and arbitrary jumps:

### 4.1 C Transpiler
- Translates bytecode basic blocks into linear C functions.
- Uses GCC/Clang label addresses (`&&LABEL`) for dispatch tables.
- Directly links against `libnewton.o` via SysV AMD64 register passing (`%rdi`, `%rsi`, `%rdx`, `%rcx`, `%r8`, `%r9`).

### 4.2 Script CFG State Machine (Lua, Python, JavaScript)
High-level languages lacking unstructured gotos or arbitrary stack unwinding use a normalized **Control Flow Graph (CFG) State Machine**:

```
+------------------------------------------------+
| let pc = "ENTRY"                               |
| while (pc !== null) {                          |
|     switch (pc) {                              |
|         case "ENTRY":                          |
|             pc = "L500"; break;                |
|         case "F_main":                         |
|             stack[--rsp] = rbp; rbp = rsp;     |
|             ...                                |
|             pc = "L1157"; break;               |
|         case "RET_ADDR_X":                     |
|             process.exit(UNTAG(0));            |
|     }                                          |
| }                                              |
+------------------------------------------------+
```

- **Lua 5.4**: Uses native labels and `goto` statements with an indirect trampoline table (`::DISPATCH::`) for function return addresses.
- **Python 3**: Uses a `while pc is not None:` loop with linearized `if pc == "LABEL":` blocks and string state pointers.
- **JavaScript (Node)**: Uses a `while (pc !== null)` loop containing a jump switch.

---

## 5. Caching System Architecture

GravityVM includes an automated hashing cache to avoid redundant compilations:
- When a file is compiled, its contents and compiler parameters are hashed using SHA-256.
- Cached signatures and intermediate object outputs are stored in `~/.cache/GravityVM/entries`.
- If neither the input bytecode nor the target architecture has changed, compilation completes in under 1 millisecond.
- Invalidation can be triggered manually via `gvm clean-cache` or automatically when bytecode content changes.

---

## 6. In-Process Bytecode Interpreter & V1 Lowering

GravityVM features an in-process bytecode execution engine (`gvm interpret`, `-b:interp`, `--interpret`) and an automated V1-to-Register lowering pass:

### 6.1 Direct In-Process Interpreter
- **Zero-Dependency Execution**: Directly executes `.gvt` bytecode in-memory without invoking clang, gcc, as, or ld, and without requiring external runtime objects like `libnewton.o`.
- **16-Register VM State**: Maintains state for `r0`..`r15`, local stack frames (`-N(%rbp)`), call stack, argument stack, heap maps, and heap arrays.
- **16-Byte Aligned Heap Allocation**: Every allocated heap object (strings, arrays, maps) is aligned to 16 bytes, ensuring tag bit masking (`and (not 7)`) accurately recovers the original object pointer without bit distortion.
- **cdecl Call Frame Convention**: Respects the standard cdecl calling convention where arguments pushed right-to-left are indexed starting from the top of the call stack frame down to the base.
- **Built-In Standard Runtime Procedures**: Emulates arithmetic (`runtime_add`, `runtime_sub`, `runtime_mul`, `runtime_div`), comparisons (`runtime_lt`, `runtime_gt`, `runtime_eq`, `runtime_neq`), auto-unwrapping of `["ok", val]` result tuples (`runtime_auto_unwrap`), collection routines (`collection_set`, `collection_get`, `collection_get_key`), string operators (`string_substring`, `string_char`, `string_ord`), and size queries (`newton_sizeof`).

### 6.2 V1-to-Register Lowering Pass (`core/v1_reg_mapper.nim`)
- **Dual-Mode Compatibility**: GravityVM detects container version 1 bytecode (`gvm_bytecode_version == 1`) and automatically executes the lowering pass before interpretation and compilation.
- **3-Address Promotion**: Promotes legacy 2-address instructions (`ADD`, `SUB`, `MUL`, `DIV`, `LT`, `GT`, `CMP`, etc.) into explicit 3-address form targeting `r0`.
- **Register Normalization**: Maps legacy register aliases (`%rax`, `sra`, `%rdi`, `%rsi`, `%rdx`, `%rcx`) into virtual registers `r0`..`r4`.
- **Peephole Optimization**: Eliminates redundant stack spills, rewriting adjacent `MOV -N(%rbp), r0` and `PUSH -N(%rbp)` patterns into direct register pushes `PUSH r0`.



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
| `0x03` | 1 byte  | uint8 | Bytecode container version (currently `1`) |
| `0x04` | 4 bytes | uint32 (LE) | Total instruction count in the stream |
| `0x08` | Variable | Stream | Sequence of instructions |

Each instruction is encoded as:
- `1 byte`: Opcode ID (converted to a 2-character Base36 representation `00`..`56`)
- `3` Argument tuples, each consisting of:
  - `1 byte`: Length of argument string $N$
  - $N$ bytes: ASCII string of the operand

### 1.2 Base36 Opcode Table
Opcodes are mapped to mnemonic instructions:
- `00`: `NOP` — No operation
- `01`: `READ` — Read line from standard input
- `02`: `WRITE` — Write string / register to standard output
- `03`: `STORE` — Store value into memory location or stack offset
- `04`: `DEL` — Delete collection entry
- `05`: `ADD` — Tagged integer addition
- `06`: `SUB` — Tagged integer subtraction
- `07`: `MUL` — Tagged integer multiplication
- `08`: `DIV` — Tagged integer division
- `09`: `EXP` — Exponentiation
- `0A`: `COPY` — Move value between operands
- `0B`: `JMP` — Unconditional jump to label
- `0C`/`0K`: `JNZ` — Jump if `sra != 0`
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
- `1A`: `PUSH` — Push value onto the call stack
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

## 2. Memory Architecture & Value Representation

GravityVM uses a unified tagged-value representation compatible with 64-bit architectures and dynamic runtimes.

### 2.1 Tagged Integers
To support polymorphic operations without heap allocation for scalars, integers are tagged using the least significant bit (LSB):
$$\text{TAG}(x) = (x \times 2) + 1$$
$$\text{UNTAG}(y) = \lfloor y / 2 \rfloor$$

- `1` encodes integer `0` (and boolean `false`)
- `3` encodes integer `1` (and boolean `true`)
- Arithmetic operations (`ADD`, `SUB`, `MUL`, `DIV`) untag inputs, perform the integer arithmetic, and re-tag the result.

### 2.2 Heap Objects & Collections
Strings and compound collections are stored on the virtual heap:
- **Strings**: Pointers to contiguous byte buffers prefixed by an 8-byte aligned length quadword.
- **Maps**: Dynamic key-value mappings indexed by tagged keys.
- **Arrays**: 0-indexed dynamic dense arrays tracked with size and capacity metadata.

### 2.3 Memory Pools
GravityVM defines 3 dedicated memory regions alongside the call stack:
- **Global Pool (`@00`..`@zz`)**: Static variables surviving function lifetimes.
- **Local Pool (`$00`..`$zz`)**: Frame-local scratch variables.
- **Buffer Pool (`%00`..`%zz`)**: Temporary register spills and intermediate calculation buffers.
- **Special Registers**:
  - `sra`: Accumulator / Return value register (mirrors `%rax`)
  - `srb`, `src`, `srd`, `sre`: General-purpose virtual registers
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
- Cached signatures and intermediate object outputs are stored in `.g_cache/`.
- If neither the input bytecode nor the target architecture has changed, compilation completes in under 1 millisecond.
- Invalidation can be triggered manually via `gvm clean-cache` or automatically when bytecode content changes.


# GravityVM: Bring-Your-Own-Backend (BYOB) Compiler Guide

**GravityVM (GVM)** is a **Bring-Your-Own-Backend (BYOB)** compiler platform and intermediate virtual machine. While originally designed alongside the Newton programming language, GravityVM was architected from the ground up as a general-purpose, modular compiler target.

Any programming language author or compiler engineer can write a frontend that emits GravityVM Bytecode (`.gvt`) and instantly take advantage of:
- **Native Machine Code Generation**: Optimized x86_64 and AArch64 machine code across Linux, macOS, and Windows.
- **Multiple Production Transpilers**: C, Lua, Python, and JavaScript without writing backend generators for each.
- **SHA-256 Incremental Caching Engine**: High-speed incremental build cache that skips unchanged compilation units.

---

## 1. The BYOB Philosophy & Runtime Architecture

> [!IMPORTANT]
> **GravityVM Does NOT Ship With Language-Specific Runtimes (`libnewton.o`)**:
> When compiling to native machine code (`-b:native`) or C (`-b:c`), GravityVM generates raw assembly and object code that references primitive runtime functions (such as `runtime_add`, `collection_set`, etc.).
> 
> - **In Newton**, these procedures are implemented in `libnewton.o` (which is supplied at build time via the `-l:` linker flag).
> - **For your custom language**, you must **bring your own runtime library** (written in C, Nim, Rust, or Assembly) and link it using `./gvm build -i:prog.gvt -l:path/to/my_runtime.o`.
> - **For Script Transpilation Targets (Lua, Python, JavaScript)**, GravityVM automatically generates a **complete, self-contained runtime environment** directly into the generated script file, requiring no external `.o` files.

---

## 2. Bytecode Container Specification (`.gvt`)

GravityVM bytecode is a compact binary format composed of an 8-byte file header followed by a sequence of 4-tuple instruction records:

```
+---------------------------------------------------------------+
| Bytes 0..2  | Magic Header: "GVM" (ASCII)                     |
| Byte 3      | Container Version: 0x01 (uint8)                 |
| Bytes 4..7  | Instruction Count: uint32 (Little-Endian)       |
+---------------------------------------------------------------+
| Instruction Records (repeated `Count` times):                 |
|   1 byte    | Opcode Byte (uint8, Base36 decoded)             |
|   1 byte    | Arg 0 Length N0 (uint8)                         |
|   N0 bytes  | Arg 0 String (ASCII)                            |
|   1 byte    | Arg 1 Length N1 (uint8)                         |
|   N1 bytes  | Arg 1 String (ASCII)                            |
|   1 byte    | Arg 2 Length N2 (uint8)                         |
|   N2 bytes  | Arg 2 String (ASCII)                            |
+---------------------------------------------------------------+
```

### 2.1 Opcode Encoding
The single opcode byte is decoded by GravityVM as a 2-character Base36 string (`0`..`9`, `A`..`Z`):
$$\text{Opcode Byte} = (\text{Base36Char}_0 \times 36) + \text{Base36Char}_1$$

Common Base36 opcodes and their byte values:
- `00` (`0x00`, 0): `NOP`
- `01` (`0x01`, 1): `READ`
- `02` (`0x02`, 2): `WRITE`
- `03` (`0x03`, 3): `STORE`
- `04` (`0x04`, 4): `DEL`
- `05` (`0x05`, 5): `ADD`
- `06` (`0x06`, 6): `SUB`
- `07` (`0x07`, 7): `MUL`
- `08` (`0x08`, 8): `DIV`
- `0A` (`0x0A`, 10): `COPY`
- `0B` (`0x0B`, 11): `JMP`
- `0C` (`0x0C`, 12): `JNZ`
- `0D` (`0x0D`, 13): `CMP`
- `0E` (`0x0E`, 14): `INC`
- `0F` (`0x0F`, 15): `DEC`
- `0J` (`0x13`, 19): `LBL`
- `0L` (`0x15`, 21): `EXIT`
- `0M` (`0x16`, 22): `LT`
- `0N` (`0x17`, 23): `GT`
- `0P` (`0x19`, 25): `JF`
- `1A` (`0x2E`, 46): `PUSH`
- `1B` (`0x2F`, 47): `CALL`
- `1C` (`0x30`, 48): `RET`
- `1D` (`0x31`, 49): `GETARG`
- `1E` (`0x32`, 50): `STR`
- `1F` (`0x33`, 51): `WRITES`
- `20` (`0x48`, 72): `NEWMAP`
- `21` (`0x49`, 73): `MSET`
- `22` (`0x4A`, 74): `MGET`
- `23` (`0x4B`, 75): `MLEN`
- `30` (`0x6C`, 108): `NEWARR`
- `40` (`0x90`, 144): `MOV`
- `41` (`0x91`, 145): `NSUB`
- `42` (`0x92`, 146): `NADD`

### 2.2 Operands & Memory Representation
Every instruction requires exactly 3 operands (unused operands should be set to `"00"` or `"0"`):

- **Literals**: Prefix with `$` (e.g., `$10`, `$55`).
- **Global Variables**: Prefix with `@` (e.g., `@01`, `@my_var`).
- **Stack Offsets**: Standard SysV base-pointer offsets (e.g., `$-8(%rbp)`, `$-16(%rbp)`).
- **Virtual Stack Push / Pop Offsets**: `528`, `48` (byte counts div 8).
- **Registers**: Standard virtual registers (`sra`, `srb`, `src`, `srd`, `sre`, `srnl`) or architecture registers (`%rdi`, `%rsi`, `%rax`).
- **Labels**: Wrapped in brackets (e.g., `[ENTRY]`, `[L500]`, `[F_main]`).

---

## 3. How to Write a Compiler Frontend Targeting GravityVM

### 3.1 Python Implementation: `gvm_emitter.py`
Below is a complete, self-contained Python emitter module that generates valid `.gvt` files:

```python
#!/usr/bin/env python3
"""
GravityVM Bytecode Emitter for custom compiler frontends.
Generates compliant binary .gvt bytecode files for GravityVM.
"""
import struct

# Base36 Opcode Table
OPCODES = {
    "NOP": 0, "READ": 1, "WRITE": 2, "STORE": 3, "DEL": 4,
    "ADD": 5, "SUB": 6, "MUL": 7, "DIV": 8, "EXP": 9,
    "COPY": 10, "JMP": 11, "JNZ": 12, "CMP": 13, "INC": 14, "DEC": 15,
    "UPD": 16, "MALLOC": 17, "FREE": 18, "LBL": 19, "EXIT": 21,
    "LT": 22, "GT": 23, "ITS": 24, "JF": 25, "TYPEOF": 29,
    "PUSH": 46, "CALL": 47, "RET": 48, "GETARG": 49, "STR": 50,
    "WRITES": 51, "NEWMAP": 72, "MSET": 73, "MGET": 74, "MLEN": 75,
    "NEWARR": 108, "MOV": 144, "NSUB": 145, "NADD": 146
}

class GvmEmitter:
    def __init__(self):
        self.instructions = []

    def emit(self, opcode: str, arg0: str = "00", arg1: str = "00", arg2: str = "00"):
        """Emit a single 4-tuple instruction."""
        if opcode not in OPCODES:
            raise ValueError(f"Unknown GravityVM opcode: {opcode}")
        self.instructions.append((OPCODES[opcode], str(arg0), str(arg1), str(arg2)))

    def tag(self, val: int) -> int:
        """Tag an integer: (val * 2) + 1."""
        return (val * 2) + 1

    def label(self, name: str):
        self.emit("LBL", f"[{name}]")

    def jump(self, label: str):
        self.emit("JMP", f"[{label}]")

    def call(self, func_label: str, arg_count: int = 0, dest: str = "00"):
        self.emit("CALL", f"[{func_label}]", str(arg_count), dest)

    def write_file(self, filename: str):
        """Serializes bytecode into the binary GVM container format."""
        with open(filename, "wb") as f:
            # 1. Magic Header "GVM" + Version 1
            f.write(b"GVM")
            f.write(struct.pack("B", 1))

            # 2. Instruction Count (uint32 Little-Endian)
            f.write(struct.pack("<I", len(self.instructions)))

            # 3. Instruction Stream
            for op, a0, a1, a2 in self.instructions:
                f.write(struct.pack("B", op))
                for arg in (a0, a1, a2):
                    b_arg = arg.encode("ascii")
                    f.write(struct.pack("B", len(b_arg)))
                    f.write(b_arg)
        print(f"Successfully generated {filename} ({len(self.instructions)} instructions)")
```

### 3.2 Complete Example: Emitting a Working Program

Here is an example program that defines an entrypoint, stores variables, performs tagged arithmetic, and exits:

```python
def generate_sample_program():
    gvm = GvmEmitter()

    # Reserve initial memory pools (local, global, buffer)
    gvm.emit("MALLOC", "$00", "128", "00")
    gvm.emit("MALLOC", "@00", "128", "00")
    gvm.emit("MALLOC", "%00", "128", "00")

    # Program entrypoint label
    gvm.label("ENTRY")
    gvm.jump("L500")

    # Start main function
    gvm.label("F_main")
    # Store tagged integer 10 (tagged as 21) into global @01
    gvm.emit("STORE", "@01", str(gvm.tag(10)))

    # Store tagged integer 45 (tagged as 91) into global @02
    gvm.emit("STORE", "@02", str(gvm.tag(45)))

    # Perform tagged addition: sra = @01 + @02
    gvm.emit("ADD", "@01", "@02", "sra")

    # Write output to STDOUT
    gvm.emit("WRITE", "[sra]", "00", "00")
    gvm.emit("WRITE", "[srnl]", "00", "00")

    # Return from F_main
    gvm.emit("RET", "00", "00", "00")

    # Startup sequence (L500)
    gvm.label("L500")
    # EXIT dispatches to F_main, then terminates with exit code 0
    gvm.emit("EXIT", "$0", "00", "00")

    gvm.write_file("hello_byob.gvt")

if __name__ == "__main__":
    generate_sample_program()
```

### 3.3 Compiling and Running Your Custom Bytecode

Once your compiler has output `hello_byob.gvt`:

```bash
# Compile and run natively
./gvm run -i:hello_byob.gvt

# Or transpile to any of the supported languages:
./gvm build -b:lua -i:hello_byob.gvt -o:prog.lua && lua prog.lua
./gvm build -b:python -i:hello_byob.gvt -o:prog.py && python3 prog.py
./gvm build -b:javascript -i:hello_byob.gvt -o:prog.js && node prog.js
```

---

## 4. Nim Implementation: `gvm_emitter.nim`

For high-performance compilers written in Nim:

```nim
import streams, tables

type GvmEmitter* = ref object
  instructions: seq[tuple[op: uint8, a0, a1, a2: string]]

proc newGvmEmitter*(): GvmEmitter =
  GvmEmitter(instructions: @[])

proc emit*(self: GvmEmitter, op: uint8, a0 = "00", a1 = "00", a2 = "00") =
  self.instructions.add((op, a0, a1, a2))

proc writeGvt*(self: GvmEmitter, filename: string) =
  var strm = newFileStream(filename, fmWrite)
  defer: strm.close()

  # Write Header
  strm.write("GVM")
  strm.write(uint8(1))
  strm.write(uint32(self.instructions.len))

  # Write Instructions
  for inst in self.instructions:
    strm.write(inst.op)
    for arg in [inst.a0, inst.a1, inst.a2]:
      strm.write(uint8(arg.len))
      strm.write(arg)
```

---

## 5. Summary Checklist for Frontend Authors

1. **Emit Header**: Always start with `GVM` + `\x01` + `uint32(count)`.
2. **Setup Entrypoint**: Emit `[ENTRY]` -> `[L500]` -> `[F_main]`.
3. **Use Tagged Arithmetic**: For integers, use `(x * 2) + 1` so GravityVM's runtime functions can distinguish scalars from pointers without boxing.
4. **Link Native Runtimes When Necessary**: If your language requires custom heap objects, IO procedures, or external C bindings, compile them into an object file (`.o`) and pass `-l:/path/to/my_runtime.o` when compiling natively.

# GravityVM CLI Reference

The `gvm` command-line utility provides compilation, execution, disassembly, and cache management for GravityVM bytecode programs.

```bash
gvm <command> [options] [flags]
```

---

## 1. Commands

| Command | Description |
|---|---|
| `build` | Compiles the input `.gvt` bytecode file to the designated target output. |
| `run` | Compiles and immediately executes the target binary or script. |
| `generate-object` | Compiles the bytecode into a relocatable machine object file (`.o`). |
| `disassemble` | Decodes the binary bytecode container and prints human-readable instructions. |
| `clean-cache` | Flushes all cached compilation artifacts from the `.g_cache/` directory. |

---

## 2. Options

### `-i:<file>` (Required)
Specifies the input `.gvt` bytecode file.
```bash
./gvm build -i:main.gvt
```

### `-o:<file>` (Optional)
Specifies the destination output file name. If omitted, defaults to the base name of the input file.
```bash
./gvm build -i:main.gvt -o:my_app
```

### `-b:<target>` (Optional, Default: `native`)
Selects the compilation backend or transpilation target:
- `native`: Compiles directly to native host assembly (x86_64 or AArch64).
- `c`: Transpiles to optimized C source and compiles via Clang/GCC.
- `lua`: Transpiles to standalone Lua 5.4 script.
- `python` / `py`: Transpiles to standalone Python 3 script.
- `javascript` / `js`: Transpiles to standalone Node.js script.

```bash
./gvm build -b:lua -i:main.gvt -o:app.lua
```

### `-f:<target>` (Optional)
Specifies a fallback compilation backend if the primary backend encounters unsupported opcodes.
```bash
./gvm build -b:native -f:c -i:main.gvt
```

### `-l:<path>` (Repeatable)
Specifies an object file (`.o`), static archive (`.a`), or linker flag to link with the executable.

> [!NOTE]
> GravityVM does not bundle `libnewton.o`. If your language frontend relies on runtime primitives that require an external implementation, pass your runtime object here (e.g. `-l:path/to/my_runtime.o`). Script transpilers (`-b:lua`, `-b:py`, `-b:js`) embed their runtimes automatically and do not require this flag.

```bash
./gvm build -i:main.gvt -l:path/to/my_runtime.o -l:-lm
```

### `-p:<platform>` (Optional, Default: host OS)
Specifies the target operating system platform:
- `linux`: Standard ELF binary
- `darwin`: macOS Mach-O binary (Universal / Apple Silicon / Intel)
- `win64`: Windows PE-COFF executable (`.exe`)

```bash
./gvm build -i:main.gvt -p:win64 -o:app.exe
```

### `-arch:<architecture>` (Optional, Default: host architecture)
Specifies the target processor architecture:
- `amd64` / `x86_64`: 64-bit Intel/AMD
- `aarch64` / `arm64`: 64-bit ARM

```bash
./gvm build -i:main.gvt -arch:aarch64 -p:linux
```

### `-a:<arg>` (Repeatable)
Passes command-line arguments to the target program when running with `run`:
```bash
./gvm run -i:main.gvt -a:input.txt -a:--verbose
```

### `-verbose:<true|false>` (Default: `false`)
Prints full shell commands executed by GravityVM (assembly, compilation, linking commands).
```bash
./gvm build -i:main.gvt -verbose:true
```

### `-intermediates:<true|false>` (Default: `false`)
Preserves intermediate generated files (such as `.s` assembly, `.c`, `.o`) in the output directory for debugging.
```bash
./gvm build -b:c -i:main.gvt -intermediates:true
```

### `-w:<true|false>` (Default: `true`)
Enables or suppresses compiler warning messages.

---

## 3. Informational Flags

| Flag | Description |
|---|---|
| `--help` | Prints the synopsis and command help summary. |
| `--version` | Displays the active GravityVM version. |
| `--targets` | Lists all available compilation and transpilation backends. |
| `--platforms` | Lists supported operating systems. |
| `--archs` | Lists supported processor architectures. |

---

## 4. Examples

### Building a Native Executable with a Custom Runtime Library
```bash
./gvm build -i:main.gvt -l:path/to/my_runtime.o -o:my_native_app
./my_native_app
```

### Transpiling to C
```bash
./gvm build -b:c -i:main.gvt -l:path/to/my_runtime.o -o:my_c_app
./my_c_app
```

### Transpiling to Lua
```bash
./gvm build -b:lua -i:main.gvt -o:app.lua
lua app.lua
```

### Transpiling to Python
```bash
./gvm build -b:python -i:main.gvt -o:app.py
python3 app.py
```

### Transpiling to JavaScript
```bash
./gvm build -b:javascript -i:main.gvt -o:app.js
node app.js
```

### Disassembling Bytecode
```bash
./gvm disassemble -i:main.gvt
```


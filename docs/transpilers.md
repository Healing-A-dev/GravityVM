# GravityVM Transpiler Subsystems

GravityVM includes four high-performance transpilers designed to emit portable source code from `.gvt` bytecode:
- **C** (Clang / GCC / MSVC)
- **Lua** (Lua 5.4 / LuaJIT)
- **Python** (Python 3.8+)
- **JavaScript** (Node.js / V8 / Bun / Deno)

Unlike simple bytecode interpreters, GravityVM transpilers perform **static control-flow normalization** and **register-stack lowering**, allowing generated programs to execute natively on host language engines without a secondary VM interpreter layer.

---

## 1. C Transpiler (`-b:c`)

The C transpiler targets ISO C99 / GNU C, generating a standalone `.c` compilation unit. When compiling to a binary, it links with an external language runtime library (such as `libnewton.o` for Newton, or your own language runtime for custom compilers) via `-l:path/to/runtime.o`.

### 1.1 Architecture & Calling Convention
- **Computed Gotos**: Basic blocks are emitted as C labels (`L500:`, `F_main:`), with function returns dispatched via stack-pushed address pointers:
  ```c
  stack[--rsp] = (long long)&&RET_ADDR_123;
  goto F_some_function;
  RET_ADDR_123:
  ```
- **SysV Register Passing**: Emulated registers (`reg_rdi`, `reg_rsi`, `reg_rdx`, `reg_rcx`, `reg_r8`, `reg_r9`) are loaded before runtime calls and forwarded directly to external C runtime procedures:
  ```c
  extern long long runtime_sub(long long, long long, long long, long long, long long, long long);
  sra = runtime_sub(reg_rdi, reg_rsi, srd, src, reg_r8, reg_r9);
  ```
- **Quadword Aligned String Literals**: Newton standard library functions expect 8-byte aligned string descriptors with a quadword length header:
  ```c
  struct { long long header; char data[23]; } _str_362 __attribute__((aligned(8))) = { 1, "Result of fib(10): {}" };
  #define str_362 (_str_362.data)
  ```
- **GC Stack Base Symbol**: A weak stack anchor prevents segfaults during runtime garbage collection sweeps:
  ```c
  __attribute__((weak)) void* __sys_stack_base = (void*)1;
  ```

---

## 2. Lua Transpiler (`-b:lua`)

The Lua transpiler targets Lua 5.4, utilizing Lua's native unstructured `goto` and label semantics to mirror assembly branch instructions.

### 2.1 Control Flow & Trampoline Dispatch
- Basic blocks and function entries are translated to labels (`::L500::`, `::F_main::`).
- Function calls push a return address token onto `stack`:
  ```lua
  rsp = rsp - 1; stack[rsp] = "RET_ADDR_42"
  goto F_my_func
  ::RET_ADDR_42::
  ```
- Function returns (`RET`) pop the destination label into `ret_target` and jump to a centralized `::DISPATCH::` trampoline:
  ```lua
  ::DISPATCH::
      if ret_target == "RET_ADDR_1" then goto RET_ADDR_1
      elseif ret_target == "RET_ADDR_42" then goto RET_ADDR_42
      end
  ```

### 2.2 Heap Collections & Builtins
The Lua transpiler embeds a complete runtime environment in the script header:
- `maps`: Central table storing heap-allocated maps and arrays.
- `TAG(x)` / `UNTAG(x)`: Implements Newton's tagged integer representation.
- `newton_sizeof`: Queries map count or string length without confusing array identifiers with string constants.

---

## 3. Python Transpiler (`-b:python`)

Because Python does not provide unstructured `goto` statements, GravityVM implements an optimized **Block-Linear CFG State Machine**.

### 3.1 State Machine Loop
Every label becomes a branch in a top-level dispatch loop:
```python
pc = "ENTRY"
while pc is not None:
    if pc == "ENTRY":
        pc = "L500"; continue
    elif pc == "F_main":
        rsp -= 1; stack[rsp] = rbp; rbp = rsp
        rsp -= 6
        pc = "L1157"; continue
    elif pc == "RET_ADDR_1":
        stack[rbp - 2] = sra
        ...
    else:
        break
```

### 3.2 Block Fallthrough Preservation
To preserve native fallthrough semantics between sequential blocks without conditional jumps, the transpiler emits `pc = next_label; continue` before consecutive label headers.

### 3.3 Zero Overhead String Dispatch
Dispatch states use direct string labels (`"L500"`, `"F_main"`), eliminating dictionary lookups or numeric mapping tables.

---

## 4. JavaScript Transpiler (`-b:javascript`)

The JavaScript transpiler generates high-performance code for Node.js, Bun, Deno, and modern browser runtimes.

### 4.1 Switch Case State Machine
Like the Python backend, JavaScript uses a state machine driving a `switch` statement:
```javascript
function main() {
    // Data declarations and string literals
    const str_0 = "map";

    let pc = "ENTRY";
    while (pc !== null) {
        switch (pc) {
            case "ENTRY":
                pc = "L500"; break;
            case "F_main":
                stack[--rsp] = rbp; rbp = rsp;
                rsp -= 6;
                pc = "L1157"; break;
            case "RET_ADDR_1":
                stack[rbp - 2] = sra;
                ...
                break;
            default:
                pc = null;
                break;
        }
    }
}
main();
```

---

## 5. Unified Runtime Builtins Specification

All transpiler runtimes implement the standard GravityVM / Newton primitive interface:

| Builtin Function | Signature / Registers | Semantics |
|---|---|---|
| `runtime_add` | `Brdi`, `Brsi` | Returns $\text{TAG}(\text{UNTAG}(\text{Brdi}) + \text{UNTAG}(\text{Brsi}))$ |
| `runtime_sub` | `Brdi`, `Brsi` | Returns $\text{TAG}(\text{UNTAG}(\text{Brdi}) - \text{UNTAG}(\text{Brsi}))$ |
| `runtime_mul` | `Brdi`, `Brsi` | Returns $\text{TAG}(\text{UNTAG}(\text{Brdi}) \times \text{UNTAG}(\text{Brsi}))$ |
| `runtime_div` | `Brdi`, `Brsi` | Returns $\text{TAG}(\lfloor \text{UNTAG}(\text{Brdi}) / \text{UNTAG}(\text{Brsi}) \rfloor)$ |
| `runtime_lt` | `Brdi`, `Brsi` | Returns `3` (`true`) if $\text{Brdi} < \text{Brsi}$, else `1` (`false`) |
| `runtime_gt` | `Brdi`, `Brsi` | Returns `3` (`true`) if $\text{Brdi} > \text{Brsi}$, else `1` (`false`) |
| `runtime_eq` | `Brdi`, `Brsi` | Returns `3` (`true`) if $\text{Brdi} == \text{Brsi}$, else `1` (`false`) |
| `runtime_auto_unwrap` | `Brdi` | Extracts primary value (`vals[1]` or `vals[3]`) from a collection box |
| `newton_sizeof` | `Brdi` | Returns element count for collections or length for strings |
| `new_array` | None | Instantiates a dynamic indexed array |
| `new_map` | None | Instantiates a key-value hash map |
| `collection_set` | `Brdi`, `Brsi`, `Brdx`/`srd` | Sets `map[UNTAG(Brsi)] = value` |
| `collection_get` | `Brdi`, `Brsi` | Retrieves value at `map[UNTAG(Brsi)]` |
| `get_type_str` | `Brdi` | Returns `"map"`, `"list"`, `"string"`, or `"number"` |
| `runtime_to_string` | `Brdi` | Converts tagged integer or object to human-readable string |


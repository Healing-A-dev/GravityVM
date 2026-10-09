# Adding Language Backend Support in GravityVM

GravityVM is designed with a **Bring-Your-Own-Backend (BYOB)** modular architecture. Adding a new transpilation target (such as Go, Ruby, Rust, WebAssembly, or Swift) is straightforward and requires modifying only three core registration points in the compiler.

---

## Overview of Steps

To add a new language backend `<lang>`:
1. Create `codegen/targets/transpiler/<lang>/`
2. Populate `packaging.nim` and `transpiler.nim` from the templates
3. Register the transpiler in `codegen/targets/target.nim`
4. Register the packager in `codegen/codegen.nim`
5. Add CLI flag support in `core/cli.nim`

---

## Step 1: Create the Language Directory

Create a directory named after your target language inside `codegen/targets/transpiler/`:
```bash
mkdir -p codegen/targets/transpiler/<lang>
```

Copy the modern template files from `template/`:
```bash
cp codegen/targets/transpiler/template/packaging.nim codegen/targets/transpiler/<lang>/packaging.nim
cp codegen/targets/transpiler/template/transpiler.nim codegen/targets/transpiler/<lang>/transpiler.nim
```

---

## Step 2: Customize `packaging.nim` and `transpiler.nim`

In your new `packaging.nim` and `transpiler.nim`:
1. Rename all instances of `<LANGUAGE_NAME>` to your language identifier (e.g., `ruby`, `go`, `rust`).
2. Decide on your **Control Flow Strategy**:
   - **Languages with Native Goto (e.g. C, Lua, Perl)**: Translate `LBL` to label definitions and `JMP` to `goto`. Emit a return trampoline (`DISPATCH`) in `__finalize`.
   - **Languages without Goto (e.g. Python, JS, Go, Ruby)**: Use a **Linear CFG State Machine**:
     ```
     let pc = "ENTRY"
     while (pc !== null) {
         switch (pc) { ... }
     }
     ```
3. Implement the standard primitive functions in `<lang>_setup` (`TAG`, `UNTAG`, `newton_sizeof`, `new_array`, `new_map`, `collection_set`, `collection_get`).

---

## Step 3: Register in `codegen/targets/target.nim`

Open `codegen/targets/target.nim`:

1. **Import your transpiler** near the top of the file:
   ```nim
   # Language Transpilers
   import transpiler/lua/transpiler
   import transpiler/c/transpiler
   import transpiler/javascript/transpiler
   import transpiler/python/transpiler
   import transpiler/<lang>/transpiler
   ```

2. **Add to the active language list**:
   ```nim
   vm_languages[] = @["native", "c", "lua", "javascript", "python", "<lang>"]
   ```

3. **Add to the dispatch case statement** in `vm_getTarget`:
   ```nim
   case language.toLowerAscii()
   of "lua":
       vm_t = vm_transpiler_lua
   of "c":
       vm_t = vm_transpiler_c
   of "<lang>", "<shorthand>":
       vm_t = vm_transpiler_<lang>
   ```

---

## Step 4: Register in `codegen/codegen.nim`

Open `codegen/codegen.nim`:

1. **Import your packaging module**:
   ```nim
   # Language Packaging
   import targets/transpiler/lua/packaging
   import targets/transpiler/c/packaging
   import targets/transpiler/javascript/packaging
   import targets/transpiler/python/packaging
   import targets/transpiler/<lang>/packaging
   ```

2. **Configure your transpilation environment** inside `C_transpile()`:
   ```nim
   proc C_transpile*(): void =
       case c_lang
       # ...
       of "<lang>", "<shorthand>":
           setup = <lang>_setup
           comment_char = <lang>_comment_char
           entry_start = <lang>_entry_start
           entry_end = <lang>_entry_end
           entry_call = <lang>_entry_call
           c_lang = "<lang_executable_name>" # For shebang: #!/usr/bin/env <executable>
           if not c_tmp.endsWith(".<extension>"):
               c_tmp = c_tmp & ".<extension>"
   ```

---

## Step 5: Register in `core/cli.nim`

Open `core/cli.nim` to connect CLI flags:

1. **In `parseArgs` under `-b:` (Backend Selection)**:
   ```nim
   case bLang
   # ...
   of "<lang>", "<shorthand>":
       vm_recompile = C_setState("recompile", true)
       vm_execTarget = "<lang>"
       C_setTranspile(true, "<lang>")
   ```

2. **In `parseArgs` under `-f:` (Fallback Selection)**:
   ```nim
   case fLang
   # ...
   of "<lang>", "<shorthand>":
       c_backup = "<lang>"
   ```

---

## Step 6: Build & Test Your Target

Recompile GravityVM and test your target:
```bash
make build
./gvm build -b:<lang> -i:main.gvt -o:output_file
```

Inspect the generated file to ensure clean syntax and complete control-flow dispatch!

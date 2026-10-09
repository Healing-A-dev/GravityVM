# ==============================================================================
# GravityVM Transpiler Template: packaging.nim
# Replace <LANGUAGE_NAME> with your backend identifier (e.g. ruby, rust, go)
# ==============================================================================

# This string defines the runtime header prepended to the generated output.
# It should define registers, tagged integer helpers, the call stack, and
# primitive runtime procedure implementations.
const <LANGUAGE_NAME>_setup*: string = """
--| Runtime Registers & Stack Setup |--
-- Define tagged value helpers:
-- TAG(x) = (x * 2) + 1
-- UNTAG(y) = y // 2

-- Define virtual registers:
-- sra = 0 (accumulator/return), srb = 0, src = 0, srd = 0, sre = 0, srnl = "\n"
-- Brdi = 0, Brsi = 0, Brdx = 0, Brcx = 0, Br8 = 0, Br9 = 0

-- Define virtual call stack:
-- stack = Array of 1048576 slots
-- rsp = 1048575, rbp = 1048575

-- Define collection storage:
-- maps = {}

-- Define runtime procedure table:
-- runtime_eq(a, b), runtime_neq(a, b)
-- runtime_add(a, b), runtime_sub(a, b), runtime_mul(a, b), runtime_div(a, b)
-- runtime_lt(a, b), runtime_gt(a, b), runtime_le(a, b), runtime_ge(a, b)
-- runtime_auto_unwrap(val)
-- newton_sizeof(collection_or_str)
-- new_array(), new_map()
-- collection_set(map_id, key, val)
-- collection_get(map_id, key)
-- collection_get_key(map_id, idx)
-- collection_delete(map_id, key)
-- print_string(val), gvm_str_cat(a, b)
"""

# The single-line comment character for the language (e.g. "//", "#", "--")
const <LANGUAGE_NAME>_comment_char*: string = "//"

# The header emitted before the program code (e.g. function definition or module start)
# For state-machine based targets: "function main() {"
const <LANGUAGE_NAME>_entry_start*: string = "function main() {"

# The footer emitted after the program code to close the entrypoint function
# For curly-brace languages: "}"
# For indentation-based languages (Python): ""
# For Lua/Ruby: "end"
const <LANGUAGE_NAME>_entry_end*: string = "}"

# The invocation to trigger execution of the entrypoint
# e.g. "main();" or "if __name__ == '__main__': main()"
const <LANGUAGE_NAME>_entry_call*: string = "main();"

# For compiled transpilation targets (e.g. C, Go, Rust), the compiler command line
# e.g. "clang", "gcc", "go build", "rustc". Leave empty for interpreted script targets.
const <LANGUAGE_NAME>_compiler*: string = ""

const python_setup*: string = """
import sys, os, math

sra = 0
srb = 0
src = 0
srd = 0
sre = 0
srnl = "\n"

Brdi = 0
Brsi = 0
Brdx = 0
Brcx = 0
Br8 = 0
Br9 = 0

G_01 = 0; G_02 = 0; G_03 = 0; G_04 = 0; G_05 = 0; G_06 = 0
G01 = 0; G02 = 0; G03 = 0; G04 = 0; G05 = 0; G06 = 0

stack = [0] * 1048576
rsp = 1048575
rbp = 1048575

def TAG(x): return math.floor(int(x) * 2 + 1)
def UNTAG(x): return math.floor(int(x) // 2)

def print_string(val):
    if isinstance(val, str):
        sys.stdout.write(val)
    elif isinstance(val, int):
        if (val % 2) == 1:
            sys.stdout.write(str(val // 2))
        else:
            sys.stdout.write(str(val))
    else:
        sys.stdout.write(str(val) if val is not None else "")
    sys.stdout.flush()

def gvm_str_cat(a, b):
    return str(a if a is not None else "") + str(b if b is not None else "")

maps = {}
map_counter = 0

class GvmMap:
    def __init__(self, is_map=False):
        self.keys = []
        self.vals = {}
        self.count = 0
        self.is_map = is_map

gvm_runtime = {
    "runtime_eq": lambda: 3 if (Brdi == Brsi) else 1,
    "runtime_neq": lambda: 3 if (Brdi != Brsi) else 1,
    "runtime_sub": lambda: TAG(UNTAG(Brdi) - UNTAG(Brsi)),
    "runtime_add": lambda: TAG(UNTAG(Brdi) + UNTAG(Brsi)),
    "runtime_mul": lambda: TAG(UNTAG(Brdi) * UNTAG(Brsi)),
    "runtime_div": lambda: TAG(UNTAG(Brdi) // UNTAG(Brsi)) if UNTAG(Brsi) != 0 else TAG(0),
    "runtime_lt": lambda: 3 if (UNTAG(Brdi) < UNTAG(Brsi)) else 1,
    "runtime_gt": lambda: 3 if (UNTAG(Brdi) > UNTAG(Brsi)) else 1,
    "runtime_le": lambda: 3 if (UNTAG(Brdi) <= UNTAG(Brsi)) else 1,
    "runtime_ge": lambda: 3 if (UNTAG(Brdi) >= UNTAG(Brsi)) else 1,
    "runtime_and": lambda: 3 if (Brdi == 3 and Brsi == 3) else 1,
    "runtime_or": lambda: 3 if (Brdi == 3 or Brsi == 3) else 1,
    "runtime_not": lambda: 1 if (Brdi == 3) else 3,
    "newton_inc": lambda: Brdi + 2,
    "sys_argc": lambda: TAG(len(sys.argv)),
    "sys_argv": lambda: 0,
    "exit_program": lambda: sys.exit(UNTAG(Brdi)),
}

def _runtime_auto_unwrap():
    if Brdi in maps:
        m = maps[Brdi]
        v = m.vals.get(1, m.vals.get(3))
        if v is not None: return v
        return 0
    return Brdi
gvm_runtime["runtime_auto_unwrap"] = _runtime_auto_unwrap

def _newton_sizeof():
    if Brdi in maps: return TAG(maps[Brdi].count)
    if isinstance(Brdi, str): return TAG(len(Brdi))
    return TAG(0)
gvm_runtime["newton_sizeof"] = _newton_sizeof

def _new_array():
    global map_counter
    map_counter += 1
    mid = f"arr_{map_counter}"
    maps[mid] = GvmMap(is_map=False)
    return mid
gvm_runtime["new_array"] = _new_array

def _new_map():
    global map_counter
    map_counter += 1
    mid = f"map_{map_counter}"
    maps[mid] = GvmMap(is_map=True)
    return mid
gvm_runtime["new_map"] = _new_map

def _collection_set():
    if Brdi in maps:
        m = maps[Brdi]
        k = UNTAG(Brsi)
        if k not in m.vals:
            m.count += 1
            m.keys.append(k)
        m.vals[k] = srd if srd is not None else Brdx
    return 0
gvm_runtime["collection_set"] = _collection_set

def _collection_get():
    if Brdi in maps:
        m = maps[Brdi]
        k = UNTAG(Brsi)
        return m.vals.get(k, 0)
    return 0
gvm_runtime["collection_get"] = _collection_get

def _collection_get_key():
    if Brdi in maps:
        idx = UNTAG(Brsi)
        if 0 <= idx < len(maps[Brdi].keys):
            return TAG(maps[Brdi].keys[idx])
    return 1
gvm_runtime["collection_get_key"] = _collection_get_key

def _collection_delete():
    if Brdi in maps:
        m = maps[Brdi]
        k = UNTAG(Brsi)
        if k in m.vals:
            del m.vals[k]
            m.count -= 1
    return 0
gvm_runtime["collection_delete"] = _collection_delete

def _get_type_str(v=None):
    val = v if v is not None else Brdi
    if val in maps:
        return "map" if maps[val].is_map else "list"
    if isinstance(val, str): return "string"
    return "number"
gvm_runtime["get_type_str"] = _get_type_str

def _runtime_to_string(v=None):
    val = v if v is not None else Brdi
    if isinstance(val, str): return val
    if isinstance(val, int):
        if (val % 2) == 1: return str(val // 2)
        return str(val)
    return str(val if val is not None else "")
gvm_runtime["runtime_to_string"] = _runtime_to_string

def _string_substring():
    s = str(Brdi if Brdi is not None else "")
    st = UNTAG(Brsi)
    ln = UNTAG(srd if srd is not None else 0)
    return s[st:st + ln]
gvm_runtime["string_substring"] = _string_substring

def _string_concat():
    return str(Brdi if Brdi is not None else "") + str(Brsi if Brsi is not None else "")
gvm_runtime["string_concat"] = _string_concat
"""

const python_comment_char*: string = "#"
const python_entry_start*: string = "def main():\n    global sra, srb, src, srd, sre, Brdi, Brsi, Brdx, Brcx, Br8, Br9, G_01, G_02, G_03, G_04, G_05, G_06, G01, G02, G03, G04, G05, G06, rsp, rbp"
const python_entry_end*: string = ""
const python_entry_call*: string = "if __name__ == '__main__':\n    main()"
const python_compiler*: string = ""

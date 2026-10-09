const js_setup*: string = """
//---| Required Modules & Variables |---//
const fs = require('fs');

let sra = 0, srb = 0, src = 0, srd = 0, sre = 0;
let srnl = "\n";
let Brdi = 0, Brsi = 0, Brdx = 0, Brcx = 0, Br8 = 0, Br9 = 0;
let G_01 = 0, G_02 = 0, G_03 = 0, G_04 = 0, G_05 = 0, G_06 = 0;

const stack = new Array(1048576).fill(0);
let rsp = 1048575, rbp = 1048575;

function TAG(x) { return Math.floor(Number(x) * 2 + 1); }
function UNTAG(x) { return Math.floor(Number(x) / 2); }

function print_string(val) {
    if (typeof val === "string") {
        process.stdout.write(val);
    } else if (typeof val === "number") {
        if ((val % 2) === 1) {
            process.stdout.write(String(Math.floor(val / 2)));
        } else {
            process.stdout.write(String(val));
        }
    } else {
        process.stdout.write(String(val ?? ""));
    }
}

function gvm_str_cat(a, b) {
    return String(a ?? '') + String(b ?? '');
}

const maps = {};
let map_counter = 0;

const gvm_runtime = {
    runtime_eq: () => (Brdi === Brsi ? 3 : 1),
    runtime_neq: () => (Brdi !== Brsi ? 3 : 1),
    runtime_sub: () => TAG(UNTAG(Brdi) - UNTAG(Brsi)),
    runtime_add: () => TAG(UNTAG(Brdi) + UNTAG(Brsi)),
    runtime_mul: () => TAG(UNTAG(Brdi) * UNTAG(Brsi)),
    runtime_div: () => (UNTAG(Brsi) !== 0 ? TAG(Math.floor(UNTAG(Brdi) / UNTAG(Brsi))) : TAG(0)),
    runtime_lt: () => (UNTAG(Brdi) < UNTAG(Brsi) ? 3 : 1),
    runtime_gt: () => (UNTAG(Brdi) > UNTAG(Brsi) ? 3 : 1),
    runtime_le: () => (UNTAG(Brdi) <= UNTAG(Brsi) ? 3 : 1),
    runtime_ge: () => (UNTAG(Brdi) >= UNTAG(Brsi) ? 3 : 1),
    runtime_and: () => (Brdi === 3 && Brsi === 3 ? 3 : 1),
    runtime_or: () => (Brdi === 3 || Brsi === 3 ? 3 : 1),
    runtime_not: () => (Brdi === 3 ? 1 : 3),
    runtime_auto_unwrap: () => {
        const m = maps[Brdi];
        if (m) {
            const v = (m.vals[1] !== undefined ? m.vals[1] : m.vals[3]);
            if (v !== undefined) return v;
            return 0;
        }
        return Brdi;
    },
    newton_inc: () => Brdi + 2,
    newton_sizeof: () => {
        if (maps[Brdi]) return TAG(maps[Brdi].count);
        if (typeof Brdi === "string") return TAG(Brdi.length);
        return TAG(0);
    },
    new_array: () => {
        map_counter++;
        const id = "arr_" + map_counter;
        maps[id] = { keys: [], vals: {}, count: 0, is_map: false };
        return id;
    },
    new_map: () => {
        map_counter++;
        const id = "map_" + map_counter;
        maps[id] = { keys: [], vals: {}, count: 0, is_map: true };
        return id;
    },
    collection_set: () => {
        const m = maps[Brdi];
        if (m) {
            const k = UNTAG(Brsi);
            if (m.vals[k] === undefined) {
                m.count++;
                m.keys.push(k);
            }
            m.vals[k] = (srd !== undefined ? srd : Brdx);
        }
        return 0;
    },
    collection_get: () => {
        const m = maps[Brdi];
        if (m) {
            const k = UNTAG(Brsi);
            return (m.vals[k] !== undefined ? m.vals[k] : 0);
        }
        return 0;
    },
    collection_get_key: () => {
        const m = maps[Brdi];
        if (m) {
            const idx = UNTAG(Brsi);
            if (idx >= 0 && idx < m.keys.length) return TAG(m.keys[idx]);
        }
        return 1;
    },
    collection_delete: () => {
        const m = maps[Brdi];
        if (m) {
            const k = UNTAG(Brsi);
            if (m.vals[k] !== undefined) {
                delete m.vals[k];
                m.count--;
            }
        }
        return 0;
    },
    get_type_str: (v) => {
        const val = (v !== undefined ? v : Brdi);
        if (maps[val]) return maps[val].is_map ? "map" : "list";
        if (typeof val === "string") return "string";
        return "number";
    },
    runtime_to_string: (v) => {
        const val = (v !== undefined ? v : Brdi);
        if (typeof val === "string") return val;
        if (typeof val === "number") {
            if ((val % 2) === 1) return String(Math.floor(val / 2));
            return String(val);
        }
        return String(val ?? "");
    },
    string_substring: () => {
        const s = String(Brdi ?? "");
        const st = UNTAG(Brsi);
        const ln = UNTAG(srd ?? 0);
        return s.substring(st, st + ln);
    },
    string_concat: () => String(Brdi ?? "") + String(Brsi ?? ""),
    exit_program: () => process.exit(UNTAG(Brdi)),
    sys_argc: () => TAG(process.argv.length),
    sys_argv: () => 0,
};
"""

const js_comment_char*: string = "//"
const js_entry_start*: string = "function main() {"
const js_entry_end*: string = "}"
const js_entry_call*: string = "main();"
const js_compiler*: string = ""

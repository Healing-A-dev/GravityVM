const js_setup*: string = """
//---| Required Modules |---//
const prompt = require('prompt-sync')({sigint: true});

//---| Required Function & Variables |---//
let sra = 0;
let srb = 0;
let src = 0;
let srd = 0;
let sre = 0;
let srnl = "\n"

function compare(x, y) {
    if (x == y) {
        sra = 0;
    } else if (x > y) {
        sra = 1;
    } else {
        sra = 2;
    }
}
"""

const js_comment_char*: string = "//"
const js_entry_start*: string = "function main() {"
const js_entry_end*: string = "}"
const js_entry_call*: string = "main()"
const js_compiler*: string = ""

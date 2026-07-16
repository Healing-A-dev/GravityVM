# This is were any setup code needed for the program to run properly will go
const <LANGUAGE_NAME>_setup*: string = """
sra ::= 0
srb ::= 0
src ::= 0
srd ::= 0
sre ::= 0

function compare(x ::= value, y ::= value) ::= void {
    if (x == y)
        sra ::= 0
    else
        sra ::= 1
}
"""

# The single line comment character for the language
const <LANGUAGE_NAME>_comment_char*: string = ""

# The entry or main function to define the entry point of the program
# ie. function main() {
# (NOTE: SET THIS VALUE TO ONLY THE VERY FIRST FUNCTION LINE (ie. fn main() {))
const <LANGUAGE_NAME>_entry_start*: string = "" # OPTIONAL

# The end character for functions in the given language
# ie. [end, }, etc]
const <LANGUAGE_NAME>_entry_end*: string = "" # OPTIONAL [unless entry_start is defined]

# The function call to the entrypoint function defined earlier
# ie. main()
const <LANGUAGE_NAME>_entry_call*: string = "" # OPTIONAL [unless entry_start is defined]

# The compiler/runtime name to build the language of choice
# ie. clang, lua, perl, gcc, rustc, go build
const <LANGUAGE_NAME>_compiler*: string = ""

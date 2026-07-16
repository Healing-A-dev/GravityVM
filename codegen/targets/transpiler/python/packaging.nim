# This is were any setup code needed for the program to run properly will go
const python_setup*: string = """
sra = 0
srb = 0
src = 0
srd = 0
sre = 0

def compare(x, y):
    global sra
    if (x == y):
        sra = 0
    else:
        sra = 1

"""

# The single line comment character for the language
const python_comment_char*: string = "#"

# The entry or main function to define the entry point of the program
# ie. function main() {
# (NOTE: SET THIS VALUE TO ONLY THE VERY FIRST FUNCTION LINE (ie. fn main() {))
const python_entry_start*: string = "def main():" # OPTIONAL

# The end character for functions in the given language
# ie. [end, }, etc]
const python_entry_end*: string = "" # OPTIONAL [unless entry_start is defined]

# The function call to the entrypoint function defined earlier
# ie. main()
const python_entry_call*: string = "if __name__ == \"__main__\":\n    main()" # OPTIONAL [unless entry_start is defined]

const python_compiler*: string = ""

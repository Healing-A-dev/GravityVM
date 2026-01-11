const c_setup*: string = """
#include <stdio.h>
#include <string.h>

int sra = 0;
int srb = 0;
int src = 0;
int srd = 0;
int sre = 0;
"""

const c_comment_char*: string = "//"
const c_entry_start*: string = "int main(void) {"
const c_entry_end*: string = "}"
const c_entry_call*: string = "main()"
const c_compiler*: string = "cc"

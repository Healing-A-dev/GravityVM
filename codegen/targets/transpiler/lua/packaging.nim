const lua_setup*: string = """
---| Required Functions & Variables |---
local sra = 0
local srb = 0
local src = 0
local srd = 0
local sre = 0

local function compare(x, y)
    if x == y then
        sra = 0
    else
        sra = 1
    end
end
"""

const lua_comment_char*: string = "--"
const lua_entry_start*: string = "function main()"
const lua_entry_end*: string = "end"
const lua_entry_call*: string = "main()"
const lua_compiler*: string = ""

const lua_setup*: string = """
---| Required Functions & Variables |---
local sra = 0
local srb = 0
local src = 0
local srd = 0
local sre = 0
local srnl = "\n"

local stack = {}
local rsp = 1048576
local rbp = 1048576
local ret_target = nil

local function TAG(x) return math.floor((x * 2) + 1) end
local function UNTAG(x) return math.floor(x / 2) end

local lua_type = type
local function print_string(val)
    if lua_type(val) == "string" then
        io.write(val)
    elseif lua_type(val) == "number" then
        if (val % 2) == 1 then
            io.write(tostring(math.floor(val / 2)))
        else
            io.write(tostring(val))
        end
    else
        io.write(tostring(val or ""))
    end
end

local function gvm_str_cat(s1, s2)
    return tostring(s1 or "") .. tostring(s2 or "")
end

local maps = {}
local map_counter = 0

local Brdi = 0
local Brsi = 0
local Brdx = 0
local Brcx = 0
local Br8 = 0
local Br9 = 0

local gvm_runtime = {
    runtime_eq = function() return (Brdi == Brsi) and 3 or 1 end,
    runtime_neq = function() return (Brdi ~= Brsi) and 3 or 1 end,
    runtime_sub = function() return TAG(UNTAG(Brdi) - UNTAG(Brsi)) end,
    runtime_add = function() return TAG(UNTAG(Brdi) + UNTAG(Brsi)) end,
    runtime_mul = function() return TAG(UNTAG(Brdi) * UNTAG(Brsi)) end,
    runtime_div = function() return TAG(math.floor(UNTAG(Brdi) / UNTAG(Brsi))) end,
    runtime_lt = function() return (UNTAG(Brdi) < UNTAG(Brsi)) and 3 or 1 end,
    runtime_gt = function() return (UNTAG(Brdi) > UNTAG(Brsi)) and 3 or 1 end,
    runtime_le = function() return (UNTAG(Brdi) <= UNTAG(Brsi)) and 3 or 1 end,
    runtime_ge = function() return (UNTAG(Brdi) >= UNTAG(Brsi)) and 3 or 1 end,
    runtime_and = function() return (Brdi == 3 and Brsi == 3) and 3 or 1 end,
    runtime_or = function() return (Brdi == 3 or Brsi == 3) and 3 or 1 end,
    runtime_auto_unwrap = function()
        local m = maps[Brdi]
        if m then
            local v = m.vals[1] or m.vals[3]
            if v ~= nil then return v end
            return 0
        end
        return Brdi
    end,
    newton_inc = function() return Brdi + 2 end,
    newton_sizeof = function()
        if maps[Brdi] then return TAG(maps[Brdi].count)
        elseif lua_type(Brdi) == "string" then return TAG(#Brdi)
        else return TAG(0) end
    end,
    new_array = function()
        map_counter = map_counter + 1
        local id = "arr_" .. map_counter
        maps[id] = { keys = {}, vals = {}, count = 0 }
        return id
    end,
    new_map = function()
        map_counter = map_counter + 1
        local id = "map_" .. map_counter
        maps[id] = { keys = {}, vals = {}, count = 0, is_map = true }
        return id
    end,
    collection_set = function()
        local m = maps[Brdi]
        if m then
            local k = UNTAG(Brsi)
            if m.vals[k] == nil then
                m.count = m.count + 1
                table.insert(m.keys, k)
            end
            m.vals[k] = (srd ~= nil and srd or Brdx)
        end
        return 0
    end,
    collection_get = function()
        local m = maps[Brdi]
        if m then
            local k = UNTAG(Brsi)
            if m.vals[k] ~= nil then return m.vals[k] end
        end
        return 0
    end,
    collection_get_key = function()
        local m = maps[Brdi]
        if m then
            local idx = UNTAG(Brsi) + 1
            if m.keys[idx] ~= nil then return TAG(m.keys[idx]) end
        end
        return 0
    end,
    collection_delete = function()
        local m = maps[Brdi]
        if m then
            local k = UNTAG(Brsi)
            if m.vals[k] ~= nil then
                m.vals[k] = nil
                m.count = m.count - 1
            end
        end
        return 0
    end,
    get_type_str = function(v)
        local val = (v ~= nil and v or Brdi)
        if maps[val] then
            if maps[val].is_map then return "map" else return "list" end
        elseif lua_type(val) == "string" then
            return "string"
        else
            return "number"
        end
    end,
    runtime_to_string = function(v)
        local val = (v ~= nil and v or Brdi)
        if lua_type(val) == "string" then return val
        elseif lua_type(val) == "number" and (val % 2) == 1 then return tostring(UNTAG(val))
        else return tostring(val) end
    end,
    string_substring = function()
        local s = tostring(Brdi or "")
        local st = UNTAG(Brsi) + 1
        local ln = UNTAG(srd or 0)
        return s:sub(st, st + ln - 1)
    end,
    string_concat = function()
        return tostring(Brdi or "") .. tostring(Brsi or "")
    end,
    exit_program = function() os.exit(UNTAG(Brdi)) end,
    sys_argc = function() return TAG(1) end,
    sys_argv = function() return 0 end,
}
setmetatable(gvm_runtime, { __index = function(_, _) return function() return 0 end end })
"""

const lua_comment_char*: string = "--"
const lua_entry_start*: string = "function main()"
const lua_entry_end*: string = "end"
const lua_entry_call*: string = "main()"
const lua_compiler*: string = ""

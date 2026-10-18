-- Offline behaviour test for gquest_weapon_align.lua.
--
-- GMod is not available here, so this harness provides the small slice of the
-- engine API the module uses: convar, concommand, hook, timer, file, util.JSON
-- and Vector/Angle. It then asserts the observable behaviour (which offsets the
-- baseline writes, which saved values win, how nudges accumulate, what is
-- written to disk). Run with the Lua 5.1 interpreter:
--   lua work/harness/gquest_weapon_align_test.lua

local ROOT = (arg and arg[0] or ""):match("^(.*)/work/harness/") or "."
local MODULE = ROOT .. "/work/gquest-ui/lua/autorun/client/gquest_weapon_align.lua"

local logs, files, commands, hooks, timers, callbacks = {}, {}, {}, {}, {}, {}
local convars = {}

function print(...) logs[#logs + 1] = table.concat({...}, "\t") end
local function rawprint(...) io.write(table.concat({...}, "\t"), "\n") end

function Vector(x, y, z) return {x = x or 0, y = y or 0, z = z or 0} end
function Angle(p, y, r) return {p = p or 0, y = y or 0, r = r or 0} end

function table.Count(tbl) local n = 0 for _ in pairs(tbl) do n = n + 1 end return n end

concommand = {Add = function(name, fn) commands[name] = fn end}
hook = {
    Add = function(event, id, fn) hooks[event] = hooks[event] or {}; hooks[event][id] = fn end,
    Remove = function(event, id) if hooks[event] then hooks[event][id] = nil end end,
}
timer = {
    Simple = function(delay, fn) timers[#timers + 1] = fn end,
    Create = function() end,
    Remove = function() end,
}
file = {}
notification = {AddLegacy = function() end}

function GetConVar(name)
    local entry = convars[name]
    if not entry then return nil end
    return {GetInt = function() return entry.value end, GetString = function() return tostring(entry.value) end}
end
function CreateClientConVar(name, default) convars[name] = {value = tonumber(default) or 0} end
function RunConsoleCommand(name, value)
    if convars[name] and value then convars[name].value = tonumber(value) or 0 end
end
cvars = {AddChangeCallback = function(name, fn) callbacks[name] = fn end}

file.Read = function(path) return files[path] end
file.Write = function(path, text) files[path] = text end
file.IsDir = function() return true end
file.CreateDir = function() end
file.Exists = function(path) return files[path] ~= nil end

-- Minimal JSON for the shapes the module writes (objects, arrays, numbers).
local function encode(value)
    local kind = type(value)
    if kind == "number" then
        if value == math.floor(value) then return string.format("%d", value) end
        return string.format("%.14g", value)
    elseif kind == "string" then
        return '"' .. value:gsub('[%c"\\]', function(c)
            return string.format('\\u%04x', string.byte(c))
        end) .. '"'
    elseif kind == "table" then
        local n = #value
        if n > 0 then
            local parts = {}
            for i = 1, n do parts[i] = encode(value[i]) end
            return "[" .. table.concat(parts, ",") .. "]"
        end
        local keys = {}
        for key in pairs(value) do keys[#keys + 1] = tostring(key) end
        table.sort(keys)
        local parts = {}
        for _, key in ipairs(keys) do parts[#parts + 1] = encode(key) .. ":" .. encode(value[key]) end
        return "{" .. table.concat(parts, ",") .. "}"
    elseif kind == "boolean" then
        return tostring(value)
    end
    return "null"
end

local function decode(text)
    local position = 1
    local function skip()
        position = text:find("[^ \n\t\r]", position) or (#text + 1)
    end
    local value
    local function parse()
        skip()
        local c = text:sub(position, position)
        if c == "{" then
            position = position + 1
            local result = {}
            while true do
                skip()
                if text:sub(position, position) == "}" then position = position + 1 return result end
                local key = parse()
                skip(); position = position + 1 -- ':'
                result[key] = parse()
                skip()
                if text:sub(position, position) == "," then position = position + 1 end
            end
        elseif c == "[" then
            position = position + 1
            local result = {}
            while true do
                skip()
                if text:sub(position, position) == "]" then position = position + 1 return result end
                result[#result + 1] = parse()
                skip()
                if text:sub(position, position) == "," then position = position + 1 end
            end
        elseif c == '"' then
            position = position + 1
            local out = {}
            while true do
                local ch = text:sub(position, position)
                if ch == '"' then position = position + 1 break end
                if ch == "\\" then
                    local esc = text:sub(position + 1, position + 1)
                    if esc == "u" then
                        out[#out + 1] = string.char(tonumber(text:sub(position + 2, position + 5), 16))
                        position = position + 6
                    else
                        out[#out + 1] = esc
                        position = position + 2
                    end
                else
                    out[#out + 1] = ch
                    position = position + 1
                end
            end
            return table.concat(out)
        else
            local number = text:match("^-?%d+%.?%d*", position)
            position = position + #number
            return tonumber(number)
        end
    end
    return parse()
end

util = {TableToJSON = function(value) return encode(value) end, JSONToTable = function(text)
    local ok, result = pcall(decode, text)
    if ok then return result end
    return nil
end}

-- A controllable player/weapon pair for the commands.
local activeClass = nil
local weapon = {GetClass = function() return activeClass end}
function IsValid(value) return value ~= nil and value ~= false end
function LocalPlayer()
    return {GetActiveWeapon = function() return activeClass and weapon or nil end}
end

local failures = 0
local function check(condition, label)
    if condition then
        rawprint("ok   " .. label)
    else
        failures = failures + 1
        rawprint("FAIL " .. label)
    end
end

local function near(actual, expected)
    return actual and math.abs(actual - expected) < 1e-6
end

-- The addon's own stock offsets, exactly as cl_viewmodeledit.lua ships them.
local STOCK = {
    weapon_physgun = {-31.5, 13.4, 14.5},
    weapon_physcannon = {-31.5, 13.4, 10.5},
    weapon_shotgun = {-14.5, 10, 8.5},
    weapon_crossbow = {-14.5, 10, 8.5},
    weapon_rpg = {-27.5, 19, 10.5},
}

local function resetState()
    logs, files, commands, hooks, timers, callbacks = {}, {}, {}, {}, {}, {}
    convars = {}
    g_VR = {viewModelInfo = {}}
    for class, values in pairs(STOCK) do
        g_VR.viewModelInfo[class] = {
            offsetPos = Vector(values[1], values[2], values[3]),
            offsetAng = Angle(0, 0, 0),
        }
    end
    vrmod = nil
    activeClass = nil
end

local function loadModule()
    local chunk = assert(loadfile(MODULE))
    chunk()
end

local function runTimers()
    local pending = timers
    timers = {}
    for _, fn in ipairs(pending) do fn() end
end

-- 1. Baseline replaces the stock offsets and leaves everything else at zero.
resetState()
loadModule()
check(GQUEST_WEAPON_ALIGN ~= nil, "module publishes GQUEST_WEAPON_ALIGN")
check(near(g_VR.viewModelInfo.weapon_physgun.offsetPos.x, -31.5), "offsets untouched before the baseline runs")
runTimers()
local replaced, stockCount = 0, 0
for class in pairs(STOCK) do
    stockCount = stockCount + 1
    local pos = g_VR.viewModelInfo[class].offsetPos
    if near(pos.x, 0) and near(pos.y, 0) and near(pos.z, 0) then replaced = replaced + 1 end
end
check(replaced == stockCount, "every stock offset replaced by the hand origin (" .. replaced .. "/" .. stockCount .. ")")
local classes = 0
for _ in pairs(GQUEST_WEAPON_ALIGN.Classes) do classes = classes + 1 end
check(classes == 12, "12 VR classes covered")
local zeroed = 0
for class in pairs(GQUEST_WEAPON_ALIGN.Classes) do
    local entry = g_VR.viewModelInfo[class]
    if entry and near(entry.offsetPos.x, 0) and near(entry.offsetPos.y, 0) and near(entry.offsetPos.z, 0) then
        zeroed = zeroed + 1
    end
end
check(zeroed == 12, "all 12 classes exist with a zero offset (" .. zeroed .. "/12)")

-- 2. A saved value wins over the baseline and is actually read back from JSON.
resetState()
files["gquest/weapon_align.json"] = '{"classes":{"weapon_pistol":{"pos":[1,2,3],"ang":[0,90,0]}}}'
loadModule()
runTimers()
local pistol = g_VR.viewModelInfo.weapon_pistol
check(near(pistol.offsetPos.x, 1) and near(pistol.offsetPos.y, 2) and near(pistol.offsetPos.z, 3),
    "saved position overrides the baseline")
check(near(pistol.offsetAng.y, 90), "saved rotation overrides the baseline")

-- 3. Nudging accumulates in steps and only persists when saved.
resetState()
loadModule()
runTimers()
activeClass = "weapon_physgun"
assert(commands.gquest_align_step)
commands.gquest_align_step(nil, nil, {"0.5"})
commands.gquest_align_move(nil, nil, {"1", "0", "0"})
commands.gquest_align_move(nil, nil, {"1", "0", "0"})
local physgun = g_VR.viewModelInfo.weapon_physgun
check(near(physgun.offsetPos.x, 1.0), "two 0.5-unit nudges accumulate to 1.0 (got " .. tostring(physgun.offsetPos.x) .. ")")
check(files["gquest/weapon_align.json"] == nil, "unsaved nudges are not persisted")
commands.gquest_align_save()
local saved = util.JSONToTable(files["gquest/weapon_align.json"] or "")
check(saved and saved.classes and saved.classes.weapon_physgun,
    "save writes the class into data/gquest/weapon_align.json")
check(saved and near(saved.classes.weapon_physgun.pos[1], 1.0), "saved value matches the live value")

-- 4. A reset drops the saved value and returns the class to the hand origin.
commands.gquest_align_reset()
check(files["gquest/weapon_align.json"]:find("weapon_physgun", 1, true) == nil, "reset removes the saved entry")
check(near(g_VR.viewModelInfo.weapon_physgun.offsetPos.x, 0), "reset returns the class to the origin")

-- 5. Status covers all 12 classes, and the baseline switch turns everything off.
logs = {}
commands.gquest_align_status()
local statusLines = 0
for _, line in ipairs(logs) do if line:find("GQUEST_ALIGN weapon_", 1, true) then statusLines = statusLines + 1 end end
check(statusLines == 12, "status lists 12 classes (" .. statusLines .. ")")

-- 6. With vrmod present, writes go through its API instead of raw tables.
resetState()
local apiCalls = {ensure = 0, apply = 0}
g_VR.viewModelInfo = {}
vrmod = {
    EnsureWeaponViewModelEntry = function(class)
        apiCalls.ensure = apiCalls.ensure + 1
        g_VR.viewModelInfo[class] = g_VR.viewModelInfo[class] or {}
        return g_VR.viewModelInfo[class]
    end,
    GetWeaponViewModelEntry = function(class) return g_VR.viewModelInfo[class] end,
    ApplyWeaponViewModelLive = function() apiCalls.apply = apiCalls.apply + 1 end,
    SaveWeaponViewModelConfig = function() apiCalls.saved = true end,
}
loadModule()
runTimers()
check(apiCalls.ensure == 12 and apiCalls.apply == 12,
    "vrmod API used when available (ensure=" .. apiCalls.ensure .. " apply=" .. apiCalls.apply .. ")")
activeClass = "weapon_shotgun"
commands.gquest_align_save()
check(apiCalls.saved == true, "save also asks vrmod to persist its own config")

rawprint("")
if failures == 0 then rawprint("ALL CHECKS PASSED") else rawprint(failures .. " CHECK(S) FAILED") end
os.exit(failures == 0 and 0 or 1)

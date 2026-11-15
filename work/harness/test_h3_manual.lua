-- Offline boundary check for gquest_h3_manual.lua.
--
-- The module is driven here by fixed hand poses, so this proves the state
-- machine (grab latch, pull distance, eject pulse, seat lock, refill once,
-- rack, left-handed mirroring, menu/tracking gates, calibration round trip),
-- not the behaviour of a real headset.
--   lua work/harness/test_h3_manual.lua

local ROOT = (arg and arg[0] or ""):match("^(.*)/work/harness/") or "."
local MODULE = ROOT .. "/work/gquest-ui/lua/autorun/client/gquest_h3_manual.lua"

-- Vector/Angle with the Source axis convention used by the module.
local VectorMeta = {}
VectorMeta.__index = VectorMeta
function Vector(x, y, z) return setmetatable({x = x or 0, y = y or 0, z = z or 0}, VectorMeta) end
function VectorMeta.__add(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
function VectorMeta.__sub(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
function VectorMeta.__mul(a, b)
    if type(b) == "number" then return Vector(a.x * b, a.y * b, a.z * b) end
    return Vector(a.x * b.x, a.y * b.y, a.z * b.z)
end
function VectorMeta:Length() return math.sqrt(self.x ^ 2 + self.y ^ 2 + self.z ^ 2) end
function VectorMeta:Dot(other) return self.x * other.x + self.y * other.y + self.z * other.z end

local AngleMeta = {}
AngleMeta.__index = AngleMeta
function Angle(p, y, r) return setmetatable({p = p or 0, y = y or 0, r = r or 0}, AngleMeta) end
function AngleMeta:Forward() return Vector(1, 0, 0) end
function AngleMeta:Right() return Vector(0, -1, 0) end
function AngleMeta:Up() return Vector(0, 0, 1) end

-- Engine stubs.
local convars, hooks, commands, events, haptics = {}, {}, {}, {}, {}
local files = {}
local now = 0
function RealTime() return now end
local function convar(name, default, _, _, _, minimum, maximum)
    local entry = {value = tonumber(default) or 0, minimum = minimum, maximum = maximum}
    convars[name] = entry
    return {
        GetFloat = function() return entry.value end,
        GetBool = function() return entry.value ~= 0 end,
        GetInt = function() return math.floor(entry.value) end,
    }
end
function CreateClientConVar(name, default, _, _, _, minimum, maximum)
    return convar(name, default, minimum, maximum)
end
function GetConVar(name)
    local entry = convars[name]
    if not entry then return nil end
    return {GetFloat = function() return entry.value end,
        GetBool = function() return entry.value ~= 0 end}
end
function RunConsoleCommand(name, value) events[#events + 1] = {name = name, value = value} end
hook = {Add = function(event, id, fn) hooks[event] = hooks[event] or {}; hooks[event][id] = fn end,
    Remove = function() end}
concommand = {Add = function(name, fn) commands[name] = fn end}
file = {
    Read = function(path) return files[path] end,
    Write = function(path, text) files[path] = text end,
    IsDir = function() return true end,
    CreateDir = function() end,
}
util = {
    TableToJSON = function(value)
        local copy = {}
        for class, offset in pairs(value) do
            copy[class] = {f = offset.f, r = offset.r, u = offset.u}
        end
        return copy
    end,
    JSONToTable = function(value) return value end,
}
gui = {IsGameUIVisible = function() return gui.menu end}
vgui = {CursorVisible = function() return false end}

local weapon = {class = "hlvr_weapon_pistol", clip = 17, ammo = 4, maxClip = 17}
function weapon:GetClass() return self.class end
function weapon:Clip1() return self.clip end
function weapon:GetPrimaryAmmoType() return self.ammo end
function weapon:GetMaxClip1() return self.maxClip end
local player = {
    Alive = function() return true end,
    Health = function() return 100 end,
    GetActiveWeapon = function() return weapon end,
    GetAmmoCount = function() return 100 end,
}
function LocalPlayer() return player end
function IsValid(value) return value ~= nil and value ~= false end

local gripDown = false
local primary = 1
vr = {
    IsActive = function() return true end,
    GetPrimaryHand = function() return primary end,
    GetDigital = function(name, hand)
        if name == "grab" then return gripDown, false, true end
        return false, false, false
    end,
    GetAnalog = function() return 0, 0, false end,
    TriggerHaptic = function(hand, seconds, frequency, amplitude)
        haptics[#haptics + 1] = {hand = hand, amplitude = amplitude}
    end,
}

assert(loadfile(MODULE))()
-- Kept so the real session gate can be exercised after pose() replaces the reader.
local defaultReadHands = GquestH3.ReadHands

local failures = 0
local function check(condition, label)
    if condition then io.write("ok   " .. label .. "\n")
    else failures = failures + 1; io.write("FAIL " .. label .. "\n") end
end

-- Hand pose in the weapon hand's frame: f -> +x, r -> -y, u -> +z.
local function pose(f, r, u)
    GquestH3.ReadHands = function()
        return {
            primary = primary,
            support = 1 - primary,
            weaponPos = Vector(0, 0, 0),
            weaponAng = Angle(0, 0, 0),
            handPos = Vector(f, -r, u),
            handAng = Angle(0, 0, 0),
        }
    end
end

local function think() hooks.Think.GquestH3Manual() end
local function reset()
    now = 0
    gripDown = false
    primary = 1
    weapon.class = "hlvr_weapon_pistol"
    weapon.clip = 17
    gui.menu = false
    state = GquestH3.State
    state.magOut = false
    state.grabbed = false
    state.armed = false
    state.ejectUntil = nil
    state.seatLockUntil = 0
    state.class = "weapon_pistol"
    events, haptics = {}, {}
    convars.gquest_h3_manual.value = 1
    convars.gquest_h3_assisted.value = 1
end

local function count(name)
    local total = 0
    for _, event in ipairs(events) do if event.name == name then total = total + 1 end end
    return total
end

-- 1. The pistol well sits at f0.6 / r-1.2 / u-3.0 for a right-handed player.
reset()
pose(0.6, -1.2, -3.0)
gripDown = true
think()
check(state.grabbed, "support hand at the well with grip grabs the magazine")
check(count("+eject") == 0, "grabbing alone does not eject")

-- 2. Downward travel below the threshold does nothing.
pose(0.6, -1.2, -3.0 - 4)
think()
check(count("+eject") == 0, "4 units of travel are below the 6-unit pull")

-- 3. Enough travel ejects once, even while the hand keeps going.
pose(0.6, -1.2, -3.0 - 7)
think()
check(count("+eject") == 1, "7 units of travel pulls the magazine out")
check(state.magOut, "the magazine is tracked as out")
think()
think()
check(count("+eject") == 1, "a held pull ejects only once")

-- 4. The native pulse is released by time, not by the gesture.
now = 0.1
think()
check(count("-eject") == 0, "the eject pulse is still held at 0.1s")
now = 0.2
think()
check(count("-eject") == 1, "the eject pulse is released after 0.18s")

-- 5. Seating inside the seat lock window is refused.
pose(0.6, -1.2, -3.0)
now = 0.25
think()
check(count("gquest_reload_refill") == 0, "a magazine cannot seat inside the 0.35s lock")

-- 6. Seating after the lock refills exactly once.
now = 0.5
think()
check(count("gquest_reload_refill") == 1, "seating the magazine refills from the reserve")
check(not state.magOut, "the magazine is tracked as seated")
think()
think()
check(count("gquest_reload_refill") == 1, "a seated magazine does not refill again")
check(#haptics == 2, "eject and seat each fire one haptic pulse")

-- 7. With assistance off, seating still works but moves no ammunition.
reset()
pose(0.6, -1.2, -3.0)
gripDown = true
think()
pose(0.6, -1.2, -3.0 - 7)
think()
now = 0.2
think()
convars.gquest_h3_assisted.value = 0
pose(0.6, -1.2, -3.0)
now = 0.6
think()
check(count("gquest_reload_refill") == 0, "assisted off: seating does not refill")
check(not state.magOut, "assisted off: the magazine is still seated")

-- 8. Racking an empty seated weapon loads it; a loaded one only clicks.
reset()
weapon.clip = 0
pose(1.0, -0.6, 0.4)
gripDown = true
think()
check(state.armed, "support hand at the slide arms the rack")
pose(1.0 - 4, -0.6, 0.4)
think()
check(count("gquest_reload_refill") == 1, "racking an empty weapon loads one magazine from the reserve")
check(#haptics == 1, "the rack clicks once")
think()
check(count("gquest_reload_refill") == 1, "holding the rack does not load twice")

reset()
weapon.clip = 12
pose(1.0, -0.6, 0.4)
gripDown = true
think()
pose(1.0 - 5, -0.6, 0.4)
think()
check(count("gquest_reload_refill") == 0, "racking a loaded weapon moves no ammunition")

-- 9. Releasing the grip disarms both gestures.
reset()
pose(0.6, -1.2, -3.0)
gripDown = true
think()
gripDown = false
think()
check(not state.grabbed and not state.armed, "releasing the grip clears grab and rack")

-- 10. A left-handed player mirrors the sideways offset.
reset()
primary = 0
pose(0.6, 1.2, -3.0)
gripDown = true
think()
check(state.grabbed, "left-handed: mirrored well is grabbed")
check(vr.GetDigital("grab", 0) ~= nil, "left-handed: the support hand is queried")
primary = 1

-- 11. The menu, a missing session and a disabled module all suppress handling.
reset()
pose(0.6, -1.2, -3.0)
gripDown = true
gui.menu = true
think()
check(not state.grabbed, "an open menu suppresses the grab")
gui.menu = false
convars.gquest_h3_manual.value = 0
think()
check(not state.grabbed, "gquest_h3_manual 0 suppresses the grab")
convars.gquest_h3_manual.value = 1

reset()
GquestH3.ReadHands = defaultReadHands
vr.IsActive = function() return false end
gripDown = true
think()
check(not state.grabbed, "an inactive VR session suppresses the grab")
vr.IsActive = function() return true end

-- 12. Losing the pose resets the gesture instead of leaving it latched.
reset()
pose(0.6, -1.2, -3.0)
gripDown = true
think()
GquestH3.ReadHands = function() return nil end
think()
check(not state.grabbed, "lost tracking clears the grab")
check(not state.armed, "lost tracking clears the rack")

-- 13. Switching to a weapon without a magazine drops the magazine state.
reset()
pose(0.6, -1.2, -3.0)
gripDown = true
think()
pose(0.6, -1.2, -3.0 - 7)
think()
check(state.magOut, "magazine ejected before the switch")
weapon.class = "hlvr_weapon_crowbar"
think()
check(not state.magOut, "a magazineless weapon clears the ejected state")
count("gquest_reload_refill")
weapon.class = "hlvr_weapon_pistol"

-- 14. Calibration: the offset command changes the well the gesture uses.
reset()
pose(2, 2, -1)
gripDown = true
commands.gquest_h3_offset(nil, nil, {"2", "2", "-1", "weapon_pistol"})
think()
check(state.grabbed, "the calibration offset becomes the new well")
commands.gquest_h3_save()
check(files["gquest/h3_manual.json"] ~= nil, "the offset was written to data/gquest/h3_manual.json")
GquestH3.State.class = "weapon_pistol"
commands.gquest_h3_reset()
check(files["gquest/h3_manual.json"] ~= nil, "reset also writes the (now empty) file")

-- 15. The calibration sampler averages a held pose and can apply it.
reset()
GquestH3.ReadHands = nil
pose(1.5, -2.0, -2.5)
commands.gquest_h3_sample(nil, nil, {"0", "1", "apply"})
think()
now = 0.5
think()
pose(1.7, -1.9, -2.6)
now = 0.9
think()
now = 1.1
think()
local sampled = GquestH3.Context()
check(sampled ~= nil, "the held weapon is still resolvable after sampling")
if sampled then
    check(math.abs(sampled.mag.x - 1.5667) < 0.01 and math.abs(sampled.mag.y + 1.9667) < 0.01
        and math.abs(sampled.mag.z + 2.5333) < 0.01, "the sampler applied the averaged well")
end
check(files["gquest/h3_manual.json"] ~= nil, "the sampled offset was saved")

-- 16. The sampler refuses a weapon without a magazine instead of guessing.
reset()
weapon.class = "hlvr_weapon_crowbar"
commands.gquest_h3_sample(nil, nil, {"0", "1", "apply"})
think()
check(not state.grabbed, "a magazineless weapon arms no sampler and no gesture")
weapon.class = "hlvr_weapon_pistol"

-- 17. The status report carries the live clip and reserve for acceptance runs.
reset()
pose(0.6, -1.2, -3.0)
local printed = {}
local realPrint = print
print = function(...)
    local parts = {}
    for index = 1, select("#", ...) do parts[#parts + 1] = tostring(select(index, ...)) end
    printed[#printed + 1] = table.concat(parts, " ")
end
commands.gquest_h3_status()
print = realPrint
local joined = table.concat(printed, "\n")
check(joined:find("clip=17", 1, true) ~= nil, "status reports the live clip")
check(joined:find("reserve=100", 1, true) ~= nil, "status reports the live reserve")
check(joined:find("distance=", 1, true) ~= nil, "status reports the measured distance")

-- 18. The console surface exists.
for _, name in ipairs({"gquest_h3_status", "gquest_h3_report", "gquest_h3_offset",
    "gquest_h3_save", "gquest_h3_reset"}) do
    check(commands[name] ~= nil, "command registered: " .. name)
end
check(commands.gquest_h3_sample ~= nil, "command registered: gquest_h3_sample")

-- 16. A closed hand curl is accepted when no digital grab action is active.
reset()
pose(0.6, -1.2, -3.0)
vr.GetDigital = function() return false, false, false end
vr.GetAnalog = function(name, hand)
    if name == "hand_curl" then return 0.7, 0, true end
    return 0, 0, false
end
think()
check(state.grabbed, "analog hand_curl 0.7 counts as a grab")
vr.GetAnalog = function() return 0, 0, false end
think()
check(not state.grabbed, "an inactive curl does not count as a grab")

io.write("\n")
if failures == 0 then io.write("ALL CHECKS PASSED\n")
else io.write(failures .. " CHECK(S) FAILED\n") end
os.exit(failures == 0 and 0 or 1)

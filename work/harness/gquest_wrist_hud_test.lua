-- Offline check for the wrist HUD anchor in gquest_wrist_hud.lua.
--
-- Proves that the panel is offset along the hand's own right/up axes (not the
-- head's) and that side/up 0 reproduces the old "1.4 units towards the eye"
-- placement. Direction on the real glove still needs the headset; the numbers
-- here only pin the arithmetic.
--   lua work/harness/gquest_wrist_hud_test.lua

local ROOT = (arg and arg[0] or ""):match("^(.*)/work/harness/") or "."
local MODULE = ROOT .. "/work/gquest-ui/lua/autorun/client/gquest_wrist_hud.lua"

-- Vector/Angle with the Source axis convention (Angle(pitch, yaw, roll)).
local VectorMeta = {}
VectorMeta.__index = VectorMeta
function Vector(x, y, z)
    return setmetatable({x = x or 0, y = y or 0, z = z or 0}, VectorMeta)
end
function VectorMeta.__add(a, b) return Vector(a.x + b.x, a.y + b.y, a.z + b.z) end
function VectorMeta.__sub(a, b) return Vector(a.x - b.x, a.y - b.y, a.z - b.z) end
function VectorMeta.__mul(a, b)
    if type(b) == "number" then return Vector(a.x * b, a.y * b, a.z * b) end
    return Vector(a.x * b.x, a.y * b.y, a.z * b.z)
end
function VectorMeta:Length() return math.sqrt(self.x ^ 2 + self.y ^ 2 + self.z ^ 2) end
function VectorMeta:Normalize()
    local length = self:Length()
    if length == 0 then return self end
    self.x, self.y, self.z = self.x / length, self.y / length, self.z / length
    return self
end

local AngleMeta = {}
AngleMeta.__index = AngleMeta
function Angle(p, y, r) return setmetatable({p = p or 0, y = y or 0, r = r or 0}, AngleMeta) end
local function radians(degrees) return degrees * math.pi / 180 end
function AngleMeta:Forward()
    local p, y = radians(self.p), radians(self.y)
    return Vector(math.cos(p) * math.cos(y), math.cos(p) * math.sin(y), -math.sin(p))
end
function AngleMeta:Right()
    local p, y, r = radians(self.p), radians(self.y), radians(self.r)
    return Vector(-math.sin(r) * math.sin(p) * math.cos(y) + math.cos(r) * math.sin(y),
        -math.sin(r) * math.sin(p) * math.sin(y) - math.cos(r) * math.cos(y),
        -math.sin(r) * math.cos(p))
end
function AngleMeta:Up()
    local p, y, r = radians(self.p), radians(self.y), radians(self.r)
    return Vector(math.cos(r) * math.sin(p) * math.cos(y) + math.sin(r) * math.sin(y),
        math.cos(r) * math.sin(p) * math.sin(y) - math.sin(r) * math.cos(y),
        math.cos(r) * math.cos(p))
end
function AngleMeta:RotateAroundAxis(axis, degrees) return self end

function Color(r, g, b, a) return {r = r, g = g, b = b, a = a} end

function math.Clamp(value, minimum, maximum)
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

function math.AngleDifference(a, b)
    local difference = math.fmod(a - b, 360)
    if difference > 180 then difference = difference - 360 end
    if difference < -180 then difference = difference + 360 end
    return difference
end

-- Engine stubs: only what the module touches at load and while painting.
local convars, hooks, commands = {}, {}, {}
local function convar(name, default, minimum, maximum)
    local entry = {value = tonumber(default) or 0, minimum = minimum, maximum = maximum}
    convars[name] = entry
    return {
        GetFloat = function() return entry.value end,
        GetBool = function() return entry.value ~= 0 end,
        GetInt = function() return math.floor(entry.value) end,
    }
end
function CreateClientConVar(name, default, _, _, _, minimum, maximum) return convar(name, default, minimum, maximum) end
function GetConVar(name)
    local entry = convars[name]
    if not entry then return nil end
    return {GetFloat = function() return entry.value end, GetBool = function() return entry.value ~= 0 end,
        GetInt = function() return math.floor(entry.value) end}
end
function RunConsoleCommand(name, value)
    if convars[name] and value then convars[name].value = tonumber(value) or 0 end
end
local function SetConVar(name, value) convars[name].value = value end

hook = {
    Add = function(event, id, fn) hooks[event] = hooks[event] or {}; hooks[event][id] = fn end,
    Remove = function() end,
}
concommand = {Add = function(name, fn) commands[name] = fn end}
surface = {CreateFont = function() end, SetDrawColor = function() end, DrawOutlinedRect = function() end,
    DrawPoly = function() end, DrawRect = function() end}
draw = {RoundedBox = function() end, SimpleText = function() end, NoTexture = function() end}

local captured
cam = {
    Start3D2D = function(position, angle, scale) captured = {position = position, angle = angle, scale = scale} end,
    End3D2D = function() end,
}

local player = {
    Alive = function() return true end,
    Health = function() return 74 end,
    GetMaxHealth = function() return 100 end,
    Armor = function() return 32 end,
    GetActiveWeapon = function() return nil end,
    EyePos = function() return Vector(0, 0, 64) end,
    EyeAngles = function() return Angle(0, 0, 0) end,
}
function LocalPlayer() return player end
function IsValid(value) return value ~= nil and value ~= false end

assert(loadfile(MODULE))()

local failures = 0
local function check(condition, label)
    if condition then io.write("ok   " .. label .. "\n")
    else failures = failures + 1; io.write("FAIL " .. label .. "\n") end
end

-- Known tracking: hand 10 units below and 20 in front of the head, no rotation.
local handPosition = Vector(0, 0, 40)
GquestXR.GetWorldTracking = function()
    return {
        hmd = {pos = Vector(0, 0, 64), ang = Angle(0, 0, 0)},
        pose_lefthand = {pos = handPosition, ang = Angle(0, 0, 0)},
    }
end

local function render()
    captured = nil
    hooks.PostDrawTranslucentRenderables.GquestWristHUD(false, false)
    return captured
end

-- 1. Defaults: panel leaves the glove along the hand's right/up axes.
SetConVar("gquest_wrist_hud_offset_side", 4.5)
SetConVar("gquest_wrist_hud_offset_up", 5)
SetConVar("gquest_wrist_hud_offset_forward", 1.4)
local frame = render()
check(frame ~= nil, "panel rendered")
if frame then
    local direction = (Vector(0, 0, 64) - handPosition):Normalize() -- towards the eye
    local expected = handPosition + direction * 1.4
        + Angle(0, 0, 0):Right() * 4.5 + Angle(0, 0, 0):Up() * 5
    local delta = frame.position - expected
    check(delta:Length() < 1e-6, "default offsets land on hand + 1.4*eye + 4.5*right + 5*up")
    local fromHand = frame.position - handPosition
    check(math.abs(fromHand:Length() - (expected - handPosition):Length()) < 1e-6,
        "panel distance from the hand matches the composed offset")
end

-- 2. side/up 0 reproduces the old placement exactly (regression guard).
SetConVar("gquest_wrist_hud_offset_side", 0)
SetConVar("gquest_wrist_hud_offset_up", 0)
frame = render()
if frame then
    local old = handPosition + (Vector(0, 0, 64) - handPosition):Normalize() * 1.4
    check((frame.position - old):Length() < 1e-6, "zero side/up matches the previous 1.4-unit anchor")
end

-- 3. Offsets follow the hand, not the head: with the hand yawed 90 degrees the
--    offsets stay in hand space.
GquestXR.GetWorldTracking = function()
    return {
        hmd = {pos = Vector(0, 0, 64), ang = Angle(0, 0, 0)},
        pose_lefthand = {pos = handPosition, ang = Angle(0, 90, 0)},
    }
end
SetConVar("gquest_wrist_hud_offset_side", 3)
SetConVar("gquest_wrist_hud_offset_up", 0)
SetConVar("gquest_wrist_hud_offset_forward", 0)
frame = render()
if frame then
    local expected = handPosition + Angle(0, 90, 0):Right() * 3
    check((frame.position - expected):Length() < 1e-6, "offsets rotate with the hand (yaw 90)")
    check(math.abs(frame.position.y - handPosition.y) < 1e-6 and math.abs(frame.position.x - handPosition.x - 3) < 1e-6,
        "yawed hand puts the 3-unit sideways offset along world +x")
end

-- 4. Hidden while the hand is up at the face, with hysteresis so it cannot
--    flicker around the threshold.
local headPos = Vector(0, 0, 64)
local function poseAt(distance)
    GquestXR.GetWorldTracking = function()
        return {hmd = {pos = headPos, ang = Angle(0, 0, 0)},
            pose_lefthand = {pos = Vector(0, 0, 64 - distance), ang = Angle(0, 0, 0)}}
    end
end
SetConVar("gquest_wrist_hud_offset_side", 4.5)
SetConVar("gquest_wrist_hud_offset_up", 5)
SetConVar("gquest_wrist_hud_offset_forward", 1.4)
SetConVar("gquest_wrist_hud_near_hide", 14)
poseAt(20)
check(render() ~= nil, "shown while the hand is down (20 units from the head)")
poseAt(12)
check(render() == nil, "hidden at 12 units from the head")
poseAt(15)
check(render() == nil, "stays hidden at 15 units (hysteresis band)")
poseAt(20)
check(render() ~= nil, "shown again beyond the hysteresis band")

-- 5. The near test can be switched off entirely.
SetConVar("gquest_wrist_hud_near_hide", 0)
poseAt(8)
check(render() ~= nil, "near test disabled: visible even at 8 units")

-- 6. Hidden while aiming (two-handed grip), and switchable.
SetConVar("gquest_wrist_hud_hide_aim", 1)
vrmod = {IsForegripActive = function() return true end}
poseAt(20)
check(render() == nil, "hidden while the foregrip reports aiming")
vrmod.IsForegripActive = function() return false end
check(render() ~= nil, "visible again once the grip is released")
vrmod = nil
g_VR = {foregripActive = true}
check(render() == nil, "hidden when the mod's foregrip flag is set")
g_VR = nil
check(render() ~= nil, "visible with no aim state at all")
SetConVar("gquest_wrist_hud_hide_aim", 0)
vrmod = {IsForegripActive = function() return true end}
check(render() ~= nil, "aim test disabled: visible while aiming")
vrmod = nil

-- 7. The console report exists and prints the offset length.
check(commands.gquest_wrist_report ~= nil, "gquest_wrist_report command registered")
check(commands.gquest_wrist_offset ~= nil, "gquest_wrist_offset command registered")

io.write("\n")
if failures == 0 then io.write("ALL CHECKS PASSED\n") else io.write(failures .. " CHECK(S) FAILED\n") end
os.exit(failures == 0 and 0 or 1)

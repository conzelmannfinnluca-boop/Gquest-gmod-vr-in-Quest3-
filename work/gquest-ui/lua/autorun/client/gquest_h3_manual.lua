-- Gquest: H3VR-style manual weapon handling on the tracked support hand.
--
-- The native HL2/HLVR weapons own the real state: clip, reserve, magazine
-- entity, drop animation and sounds. This module adds the H3VR-style *manual*
-- step in front of that state, driven by where the support hand actually is
-- instead of by a key:
--
--   1. grab the magazine at its well and pull it down/out
--      -> the native eject pulse (+eject / -eject, the same pulse the reviewed
--         button reload in gquest_reload.lua uses),
--   2. bring the fresh magazine back into the well and seat it
--      -> the assisted refill, capped by the player's own reserve,
--   3. with a seated magazine, rack the slide / charging handle rearwards
--      -> a rack click, plus a refill when the weapon still reads empty.
--
-- Every step needs a real support-hand pose from vr.GetHandPose. Without
-- tracking, with gquest_h3_manual 0, in a menu, or on a weapon without a
-- magazine nothing runs and the existing button path stays exactly as it is.
-- This file never invents ammunition and never writes clip or reserve values.
--
-- Offsets are per weapon class, expressed in the weapon hand's own frame
-- (f = along the hand, r = to the hand's right, u = hand up). They are starting
-- values only: gquest_h3_report prints the measured hand position next to the
-- assumed well so they can be corrected on the device with gquest_h3_offset,
-- and gquest_h3_save keeps the result in data/gquest/h3_manual.json.

GquestH3 = GquestH3 or {}

local enabled = CreateClientConVar("gquest_h3_manual", "1", true, false,
    "H3VR-style manual magazine handling on the tracked support hand")
local assisted = CreateClientConVar("gquest_h3_assisted", "1", true, false,
    "Seating a magazine refills it from the player's own reserve")
local grabRadius = CreateClientConVar("gquest_h3_grab_radius", "5.5", true, false,
    "How close the support hand must be to grab the magazine or slide", 1, 15)
local seatRadius = CreateClientConVar("gquest_h3_seat_radius", "2.5", true, false,
    "How close the magazine must come to the well to seat", 0.5, 10)
local pullDistance = CreateClientConVar("gquest_h3_mag_pull", "6", true, false,
    "Downward support-hand travel that pulls the magazine out", 1, 20)
local rackDistance = CreateClientConVar("gquest_h3_rack_pull", "4", true, false,
    "Rearward support-hand travel that racks the slide", 1, 20)

-- Class names are the plain HL2 classes; the port's converted entities are
-- hlvr_weapon_* and are mapped back by baseClass().
local CLASSES = {
    weapon_pistol = {
        mag = {f = 0.6, r = -1.2, u = -3.0},
        rack = {f = 1.0, r = -0.6, u = 0.4},
    },
    weapon_357 = {
        mag = {f = 0.6, r = -1.2, u = -3.4},
        rack = {f = 1.2, r = -0.6, u = 0.4},
    },
    weapon_smg1 = {
        mag = {f = 3.0, r = -1.0, u = -4.4},
        rack = {f = 1.4, r = -0.8, u = 0.6},
    },
    weapon_ar2 = {
        mag = {f = 2.6, r = -0.8, u = -5.8},
        rack = {f = 1.2, r = -0.6, u = 1.0},
    },
}

local overrides = {}

local function baseClass(name)
    if type(name) ~= "string" then return nil end
    if string.sub(name, 1, 5) == "hlvr_" then return string.sub(name, 6) end
    return name
end

-- One mirror factor per primary hand: with a left-handed player every sideways
-- offset flips so the same table keeps meaning "toward the weapon hand's right".
local function offsetVector(offset, side)
    return Vector(offset.f, offset.r * side, offset.u)
end

local function localPoint(position, origin, angle)
    local relative = position - origin
    return Vector(relative:Dot(angle:Forward()), relative:Dot(angle:Right()),
        relative:Dot(angle:Up()))
end

-- Same Axis conversion the wrist HUD already uses on the device: the native
-- binding returns XR-axis Euler angles, the positions in Source units.
local function sourceAngle(raw)
    if not raw then return end
    local rotation = Angle(raw.p, raw.y, raw.r)
    local forward, up = Vector(0, 0, -1), Vector(0, 1, 0)
    forward:Rotate(rotation)
    up:Rotate(rotation)
    forward = Vector(forward.x, -forward.z, forward.y)
    up = Vector(up.x, -up.z, up.y)
    return forward:AngleEx(up)
end

local function readHands()
    if not vr or not vr.GetHandPose or not vr.IsActive then return nil end
    local okActive, active = pcall(vr.IsActive)
    if not okActive or active ~= true then return nil end
    local primary = 0
    if vr.GetPrimaryHand then
        local okPrimary, value = pcall(vr.GetPrimaryHand)
        if okPrimary and (value == 0 or value == 1) then primary = value end
    end
    local support = 1 - primary
    local okWeapon, weaponPosition, weaponAngle, weaponValid =
        pcall(vr.GetHandPose, primary)
    if not okWeapon or weaponValid ~= true then return nil end
    local okSupport, handPosition, handAngle, handValid =
        pcall(vr.GetHandPose, support)
    if not okSupport or handValid ~= true then return nil end
    return {
        primary = primary,
        support = support,
        weaponPos = Vector(weaponPosition.x, weaponPosition.y, weaponPosition.z),
        weaponAng = sourceAngle(weaponAngle),
        handPos = Vector(handPosition.x, handPosition.y, handPosition.z),
        handAng = sourceAngle(handAngle),
    }
end

-- Replaceable for the offline harness; the shipped path is readHands.
GquestH3.ReadHands = readHands

-- The real grab is whichever supplied action this port actually exposes as
-- active; the order prefers a dedicated grab over the trigger fallback.
local DIGITAL_GRAB = {"grab", "grip", "hand_grab", "use"}
local function supportGrip(hand)
    if not vr then return false end
    if vr.GetDigital then
        for _, name in ipairs(DIGITAL_GRAB) do
            local ok, down, _, active = pcall(vr.GetDigital, name, hand)
            if ok and active == true and type(down) == "boolean" then return down end
        end
    end
    -- No digital grab action is active on this runtime: accept a real closed
    -- hand curl, verified to exist as an analog action in libvrxr.
    if vr.GetAnalog then
        local ok, value, _, active = pcall(vr.GetAnalog, "hand_curl", hand)
        if ok and active == true and type(value) == "number" and value == value then
            return value >= 0.55
        end
    end
    return false
end

GquestH3.Grip = supportGrip

local function menuVisible()
    if gui and gui.IsGameUIVisible and gui.IsGameUIVisible() then return true end
    if vgui and vgui.CursorVisible and vgui.CursorVisible() then return true end
    if IsValid and IsValid(g_SpawnMenu) and g_SpawnMenu:IsVisible() then return true end
    local ui = _G.GquestUI
    if type(ui) == "table" and type(ui.IsMenuVisible) == "function" then
        local ok, visible = pcall(ui.IsMenuVisible)
        if ok and visible then return true end
    end
    return false
end

local function clipState(weapon, player)
    local clip = 0
    if weapon.Clip1 then
        local value = weapon:Clip1()
        if type(value) == "number" and value > 0 then clip = value end
    end
    local reserve = 0
    local ammo = weapon.GetPrimaryAmmoType and weapon:GetPrimaryAmmoType() or -1
    if ammo >= 0 and player.GetAmmoCount then
        local count = player:GetAmmoCount(ammo)
        if type(count) == "number" and count > 0 then reserve = count end
    end
    return clip, reserve
end

local state = {
    class = nil,
    grabbed = false,
    grabHeight = 0,
    magOut = false,
    armed = false,
    armedForward = 0,
    ejectUntil = nil,
    seatLockUntil = 0,
}
GquestH3.State = state

local function haptic(hand, seconds, frequency, amplitude)
    if vr and vr.TriggerHaptic then
        pcall(vr.TriggerHaptic, hand, seconds, frequency, amplitude)
    end
end

local function context()
    if not enabled:GetBool() then return nil end
    local player = LocalPlayer()
    if not IsValid(player) or not player:Alive() then return nil end
    local weapon = player:GetActiveWeapon()
    if not IsValid(weapon) then return nil end
    local class = baseClass(weapon:GetClass())
    local config = class and CLASSES[class]
    if not config then return nil end
    if menuVisible() then return nil end
    local hands = GquestH3.ReadHands()
    if not hands then return nil end
    local side = hands.primary == 0 and -1 or 1
    local override = overrides[class]
    return {
        player = player,
        weapon = weapon,
        class = class,
        support = hands.support,
        mag = offsetVector(override or config.mag, side),
        rack = offsetVector(config.rack, side),
        hand = localPoint(hands.handPos, hands.weaponPos, hands.weaponAng),
        hands = hands,
    }
end
GquestH3.Context = context

local function ejectRequest(ctx)
    if state.ejectUntil then return end
    RunConsoleCommand("+eject")
    state.ejectUntil = RealTime() + 0.18
    state.seatLockUntil = RealTime() + 0.35
    state.magOut = true
    state.grabbed = false
    state.armed = false
    haptic(ctx.support, 0.12, 90, 0.6)
    print(string.format("GQUEST_H3 mag_out class=%s hand=%d", ctx.class, ctx.support))
end

local function seatRequest(ctx)
    state.magOut = false
    state.grabbed = false
    state.armed = false
    haptic(ctx.support, 0.08, 150, 0.5)
    if assisted:GetBool() then RunConsoleCommand("gquest_reload_refill") end
    print(string.format("GQUEST_H3 mag_seated class=%s refill=%s", ctx.class,
        tostring(assisted:GetBool())))
end

local function rackRequest(ctx)
    state.armed = false
    haptic(ctx.support, 0.1, 120, 0.5)
    local clip, reserve = clipState(ctx.weapon, ctx.player)
    -- A seated magazine that the native path left empty is filled on the rack,
    -- which is the step H3VR uses to chamber. Never more than the reserve holds.
    if assisted:GetBool() and clip <= 0 and reserve > 0 then
        RunConsoleCommand("gquest_reload_refill")
    end
    print(string.format("GQUEST_H3 racked class=%s clip=%d reserve=%d", ctx.class, clip, reserve))
end

-- The calibration sampler needs saveOverrides, which is defined further down;
-- both are declared here so think() closes over the real functions.
local sampleThink, sampleFinish

local function currentMagazineClass()
    local player = LocalPlayer()
    local weapon = IsValid(player) and player:GetActiveWeapon() or nil
    if not IsValid(weapon) or not weapon.GetClass then return nil end
    local class = baseClass(weapon:GetClass())
    if class and CLASSES[class] then return class end
    return nil
end
GquestH3.CurrentClass = currentMagazineClass

local function think()
    -- Release a pending eject pulse even if the gesture or tracking drops.
    if state.ejectUntil and RealTime() >= state.ejectUntil then
        RunConsoleCommand("-eject")
        state.ejectUntil = nil
    end
    if sampleFinish then sampleFinish() end
    local ctx = context()
    if not ctx then
        state.grabbed = false
        state.armed = false
        -- Only a weapon without a magazine clears the magazine state. A menu or
        -- a lost pose frame must not silently seat an ejected magazine again.
        if not currentMagazineClass() then
            state.class = nil
            state.magOut = false
        end
        return
    end
    if state.class ~= ctx.class then
        state.class = ctx.class
        state.magOut = false
        state.grabbed = false
        state.armed = false
        print("GQUEST_H3 class=" .. ctx.class)
    end
    if sampleThink then sampleThink(ctx) end
    local grip = supportGrip(ctx.support)
    local magDistance = (ctx.hand - ctx.mag):Length()
    local rackDistanceNow = (ctx.hand - ctx.rack):Length()

    -- Step 2 first: an ejected magazine is seated by returning it to the well.
    if state.magOut then
        if grip and magDistance <= seatRadius:GetFloat() and RealTime() >= state.seatLockUntil then
            seatRequest(ctx)
        end
        return
    end

    -- Step 1: grab at the well, then deliberate downward travel pulls it out.
    -- The grab is latched: the travel is usually longer than the grab radius,
    -- so the pull must keep counting after the hand has left that radius.
    if grip then
        if not state.grabbed and magDistance <= grabRadius:GetFloat() then
            state.grabbed = true
            state.grabHeight = ctx.hand.z
        end
        if state.grabbed and state.grabHeight - ctx.hand.z >= pullDistance:GetFloat() then
            ejectRequest(ctx)
            return
        end
    else
        state.grabbed = false
    end

    -- Step 3: rack the slide / charging handle with rearward travel.
    if grip then
        if not state.armed and rackDistanceNow <= grabRadius:GetFloat() then
            state.armed = true
            state.armedForward = ctx.hand.x
        end
        if state.armed and state.armedForward - ctx.hand.x >= rackDistance:GetFloat() then
            rackRequest(ctx)
        end
    else
        state.armed = false
    end
end

GquestH3.Think = think

local OVERRIDE_PATH = "gquest/h3_manual.json"
local function loadOverrides()
    local text = file.Read(OVERRIDE_PATH, "DATA")
    if not text then return end
    local data = util.JSONToTable(text)
    if type(data) ~= "table" then return end
    for class, values in pairs(data) do
        if CLASSES[class] and type(values) == "table"
            and type(values.f) == "number" and type(values.r) == "number"
            and type(values.u) == "number" then
            overrides[class] = {f = values.f, r = values.r, u = values.u}
        end
    end
end

local function saveOverrides()
    if not file.IsDir("gquest", "DATA") then file.CreateDir("gquest") end
    file.Write(OVERRIDE_PATH, util.TableToJSON(overrides, true) or "{}")
end

loadOverrides()

-- Calibration sampler. The support hand has to stay in the grab pose while the
-- command runs, so the sample starts after a delay and averages every frame of
-- its window. Values are the same hand-frame numbers gquest_h3_report prints;
-- the "apply" mode stores the average as this class's well and saves it.
local sample
function sampleThink(ctx)
    if not sample or ctx.class ~= sample.class then return end
    local now = RealTime()
    if now < sample.startAt or now > sample.endAt then return end
    sample.count = sample.count + 1
    sample.f = sample.f + ctx.hand.x
    sample.r = sample.r + ctx.hand.y
    sample.u = sample.u + ctx.hand.z
    if sample.count == 1 then
        sample.min = {f = ctx.hand.x, r = ctx.hand.y, u = ctx.hand.z}
        sample.max = {f = ctx.hand.x, r = ctx.hand.y, u = ctx.hand.z}
    else
        sample.min.f = math.min(sample.min.f, ctx.hand.x)
        sample.min.r = math.min(sample.min.r, ctx.hand.y)
        sample.min.u = math.min(sample.min.u, ctx.hand.z)
        sample.max.f = math.max(sample.max.f, ctx.hand.x)
        sample.max.r = math.max(sample.max.r, ctx.hand.y)
        sample.max.u = math.max(sample.max.u, ctx.hand.z)
    end
end

function sampleFinish()
    if not sample or RealTime() < sample.endAt then return end
    local finished = sample
    sample = nil
    if finished.count < 1 then
        print("GQUEST_H3 sample: no frames captured (tracking lost?)")
        return
    end
    local n = finished.count
    local average = {f = finished.f / n, r = finished.r / n, u = finished.u / n}
    local spread = math.max(
        finished.max.f - finished.min.f,
        finished.max.r - finished.min.r,
        finished.max.u - finished.min.u)
    print(string.format("GQUEST_H3 sample class=%s frames=%d avg=%.2f,%.2f,%.2f spread=%.2f",
        finished.class, n, average.f, average.r, average.u, spread))
    if finished.apply then
        overrides[finished.class] = average
        saveOverrides()
        state.grabbed = false
        state.armed = false
        print(string.format("GQUEST_H3 sample applied and saved %s", finished.class))
    else
        print(string.format(
            "GQUEST_H3 sample: apply with gquest_h3_offset %.2f %.2f %.2f %s",
            average.f, average.r, average.u, finished.class))
    end
end

concommand.Add("gquest_h3_sample", function(_, _, arguments)
    local delay = tonumber(arguments and arguments[1] or "") or 5
    local window = tonumber(arguments and arguments[2] or "") or 2
    local mode = arguments and arguments[3] or ""
    local class = currentMagazineClass() or state.class
    if not class then
        print("GQUEST_H3 sample: hold a magazine weapon first")
        return
    end
    if delay < 0 then delay = 0 end
    if window < 0.2 then window = 0.2 end
    local startAt = RealTime() + delay
    sample = {class = class, startAt = startAt, endAt = startAt + window,
        apply = mode == "apply", count = 0, f = 0, r = 0, u = 0}
    print(string.format("GQUEST_H3 sample armed class=%s delay=%.1fs window=%.1fs apply=%s",
        class, delay, window, tostring(sample.apply)))
end)

concommand.Add("gquest_h3_status", function()
    local ctx = context()
    local override = ctx and overrides[ctx.class] or nil
    print(string.format(
        "GQUEST_H3 status enabled=%s assisted=%s class=%s mag_out=%s grabbed=%s racked=%s",
        tostring(enabled:GetBool()), tostring(assisted:GetBool()),
        tostring(ctx and ctx.class or state.class), tostring(state.magOut),
        tostring(state.grabbed), tostring(state.armed)))
    print(string.format(
        "GQUEST_H3 status grab_radius=%.2f seat_radius=%.2f mag_pull=%.2f rack_pull=%.2f override=%s",
        grabRadius:GetFloat(), seatRadius:GetFloat(), pullDistance:GetFloat(),
        rackDistance:GetFloat(),
        override and string.format("%.2f/%.2f/%.2f", override.f, override.r, override.u) or "none"))
    if ctx then
        print(string.format(
            "GQUEST_H3 status measured hand=%.2f,%.2f,%.2f well=%.2f,%.2f,%.2f distance=%.2f",
            ctx.hand.x, ctx.hand.y, ctx.hand.z, ctx.mag.x, ctx.mag.y, ctx.mag.z,
            (ctx.hand - ctx.mag):Length()))
        local clip, reserve = clipState(ctx.weapon, ctx.player)
        print(string.format("GQUEST_H3 status clip=%d reserve=%d", clip, reserve))
    end
end)

-- Calibration aid: where is the support hand, in the weapon hand's own frame,
-- right now? These are the numbers to copy into the class table.
concommand.Add("gquest_h3_report", function()
    local hands = GquestH3.ReadHands()
    if not hands then
        print("GQUEST_H3 report: no active VR hand pose")
        return
    end
    local player = LocalPlayer()
    local weapon = IsValid(player) and player:GetActiveWeapon() or nil
    local class = IsValid(weapon) and baseClass(weapon:GetClass()) or nil
    local hand = localPoint(hands.handPos, hands.weaponPos, hands.weaponAng)
    local side = hands.primary == 0 and -1 or 1
    local config = class and CLASSES[class] or nil
    local override = class and overrides[class] or nil
    local assumed = config and offsetVector(override or config.mag, side) or nil
    print(string.format(
        "GQUEST_H3 report primary=%d support=%d class=%s grip=%s hand=%.2f,%.2f,%.2f",
        hands.primary, hands.support, tostring(class), tostring(supportGrip(hands.support)),
        hand.x, hand.y, hand.z))
    if assumed then
        print(string.format(
            "GQUEST_H3 report well=%.2f,%.2f,%.2f distance=%.2f (adjust with gquest_h3_offset f r u)",
            assumed.x, assumed.y, assumed.z, (hand - assumed):Length()))
    else
        print("GQUEST_H3 report: no magazine class held; values above are the raw hand frame")
    end
end)

concommand.Add("gquest_h3_offset", function(_, _, arguments)
    local f = tonumber(arguments and arguments[1] or "")
    local r = tonumber(arguments and arguments[2] or "")
    local u = tonumber(arguments and arguments[3] or "")
    local class = arguments and arguments[4] or state.class
    if not CLASSES[class] then
        print("GQUEST_H3 offset: unknown class " .. tostring(class))
        return
    end
    if not f or not r or not u then
        print("GQUEST_H3 offset: usage gquest_h3_offset f r u [class]")
        return
    end
    overrides[class] = {f = f, r = r, u = u}
    print(string.format("GQUEST_H3 offset %s = %.2f/%.2f/%.2f (unsaved)", class, f, r, u))
end)

concommand.Add("gquest_h3_save", function()
    saveOverrides()
    print("GQUEST_H3 saved " .. OVERRIDE_PATH)
end)

concommand.Add("gquest_h3_reset", function()
    if overrides[state.class] then
        overrides[state.class] = nil
    else
        overrides = {}
    end
    saveOverrides()
    print("GQUEST_H3 offsets reset")
end)

hook.Add("Think", "GquestH3Manual", think)
hook.Add("ShutDown", "GquestH3Manual", function()
    if state.ejectUntil then
        RunConsoleCommand("-eject")
        state.ejectUntil = nil
    end
end)

print("GQUEST_H3 ready: manual magazine, seat and rack on the support hand")

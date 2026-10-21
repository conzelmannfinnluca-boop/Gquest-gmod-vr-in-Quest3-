-- Gquest assisted HL2/HLVR reload.
--
-- The native VR path ejects the magazine and offers a fresh one. Measured on
-- the Quest (files/diagnostics/session-1792582512.log): every native magazine
-- entity is created with 0 rounds in reserve ("offered with 45 round(s), 0 to
-- reserve"), so the assisted reload finishes on an empty magazine while the
-- player's own reserve stays untouched -- the weapon reads 0 after reloading.
-- This module keeps the native eject (visual, magazine drop, sounds) and then
-- asks the server to move rounds from the player's reserve into the weapon. It
-- never creates ammunition: the transfer is capped by the weapon's own clip
-- size and by the reserve actually present, and it is a no-op when the native
-- path already filled the magazine.
GquestReload=GquestReload or {}
local assisted=CreateClientConVar("gquest_reload_assisted","1",true,false,
    "Assisted HL2 reload: native eject, then refill the magazine from the player's own reserve")
local releaseAt,refillAt
local function release()
    if releaseAt then RunConsoleCommand("-eject");releaseAt=nil end
end
local function refill()
    refillAt=nil
    RunConsoleCommand("gquest_reload_refill")
end
local function applyMode()
    if GetConVar("hlvr_quick_reload") then
        RunConsoleCommand("hlvr_quick_reload",assisted:GetBool() and "1" or "0")
    end
end
hook.Add("InitPostEntity","GquestReloadMode",applyMode)
cvars.AddChangeCallback("gquest_reload_assisted",applyMode,"GquestReloadMode")
function GquestReload.Request()
    local p=LocalPlayer()
    if not IsValid(p) or not p:Alive() then return end
    local w=p:GetActiveWeapon()
    if not IsValid(w) then return end
    applyMode()
    RunConsoleCommand("+eject")
    releaseAt=RealTime()+0.18
    -- The refill runs after the eject pulse has been released, so the native
    -- path gets the full gesture before Lua tops the magazine up.
    if assisted:GetBool() then refillAt=RealTime()+0.45 end
    if chat and chat.AddText then chat.AddText("HL2: Magazin ausgeworfen; Munition kommt aus dem eigenen Vorrat.") end
    print("GQUEST_RELOAD requested="..w:GetClass().." assisted="..tostring(assisted:GetBool()))
end
concommand.Add("gquest_reload",GquestReload.Request)
concommand.Add("gquest_reload_state",function() RunConsoleCommand("gquest_reload_state_sv") end)
hook.Add("Think","GquestReloadRelease",function()
    if releaseAt and RealTime()>=releaseAt then release() end
    if refillAt and RealTime()>=refillAt then refill() end
end)
hook.Add("ShutDown","GquestReloadRelease",function() release();refillAt=nil end)
print("GQUEST_RELOAD ready: native eject plus own-reserve refill")

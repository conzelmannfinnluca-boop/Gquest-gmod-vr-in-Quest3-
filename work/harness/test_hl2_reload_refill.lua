-- Boundary harness for the server-side assisted reload refill.
-- The refill must only move rounds the player already owns.
local commands={}
concommand={Add=function(key,fn) commands[key]=fn end}
function IsValid(v) return type(v)=="table" end
game={SinglePlayer=function() return true end}
ents={GetAll=function() return {} end}
util={TableToJSON=function(t) return "{}" end}
local cvars={hlvr_quick_reload={GetString=function() return "1" end}}
function GetConVar(name) return cvars[name] end
AddCSLuaFile=function() end
timer={Simple=function(_,fn) fn() end}
player={GetHumans=function() return {} end}
dofile("work/gquest-ui/lua/autorun/server/gquest_hl2_equipment.lua")

local function makeWeapon(clip,maxClip,ammoType)
    return {GetClass=function() return "hlvr_weapon_smg1" end,
        GetModel=function() return "models/weapons/vr_smg.mdl" end,
        Clip1=function() return clip end,SetClip1=function(_,v) clip=v end,
        GetMaxClip1=function() return maxClip end,
        GetPrimaryAmmoType=function() return ammoType end,
        GetOwner=function() return nil end}
end
local function makePlayer(weapon,reserve,alive)
    local counts={}
    local p={Alive=function() return alive~=false end,
        GetActiveWeapon=function() return weapon end,
        GetAmmoCount=function(_,t) return counts[t] or reserve end,
        RemoveAmmo=function(_,n,t) counts[t]=(counts[t] or reserve)-n end,
        GetWeapon=function() return weapon end}
    return p
end

-- Partial magazine: only the missing rounds move.
local w=makeWeapon(10,45,4)
local p=makePlayer(w,100)
commands.gquest_reload_refill(p)
assert(w.Clip1()==45,"magazine must fill to its own maximum")
assert(p:GetAmmoCount(4)==65,"exactly 35 rounds leave the reserve")

-- Reserve smaller than the gap: never invents ammunition.
w=makeWeapon(0,45,4);p=makePlayer(w,7)
commands.gquest_reload_refill(p)
assert(w.Clip1()==7,"clip must stop at the reserve actually held")
assert(p:GetAmmoCount(4)==0,"reserve must not go negative")

-- Empty reserve is a no-op.
w=makeWeapon(0,45,4);p=makePlayer(w,0)
commands.gquest_reload_refill(p)
assert(w.Clip1()==0 and p:GetAmmoCount(4)==0,"empty reserve must change nothing")

-- Already full is a no-op.
w=makeWeapon(45,45,4);p=makePlayer(w,100)
commands.gquest_reload_refill(p)
assert(w.Clip1()==45 and p:GetAmmoCount(4)==100,"full magazine must not consume reserve")

-- Weapons without a magazine (crowbar, physgun, grenade) stay untouched.
w=makeWeapon(0,0,0);p=makePlayer(w,50)
commands.gquest_reload_refill(p)
assert(w.Clip1()==0 and p:GetAmmoCount(0)==50,"magazineless weapon must be left alone")

-- Dead player and missing weapon are refused.
w=makeWeapon(0,45,4);p=makePlayer(w,100,false)
commands.gquest_reload_refill(p)
assert(w.Clip1()==0,"dead player must not be refilled")
commands.gquest_reload_refill({Alive=function() return true end,GetActiveWeapon=function() return nil end})

print("PASS assisted reload refill: clip cap, reserve cap, empty reserve, full magazine, magazineless weapon, dead player")

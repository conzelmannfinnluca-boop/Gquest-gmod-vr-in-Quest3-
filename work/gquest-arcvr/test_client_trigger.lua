-- Runs the real adapted client Think. Engine/API boundaries are mocked only.
SERVER=false;CLIENT=true;SWEP={}
function AddCSLuaFile() end
function CreateClientConVar() return {GetBool=function() return true end} end
math.Clamp=function(x,a,b) return math.max(a,math.min(b,x)) end
function IsValid(v) return type(v)=="table" and v.valid~=false end
local state={session=true,digital=false,digitalActive=false,analog=0,analogActive=false,menu=false}
vr={IsActive=function() return state.session end,
    GetDigital=function(action,hand)
        assert(action=="attack" and hand==1)
        if state.digitalThrows then error("unavailable digital action") end
        return state.digital,false,state.digitalActive
    end,
    GetAnalog=function(action,hand)
        assert(action=="trigger_pull" and hand==1)
        return state.analog,0,state.analogActive
    end}
gui={IsGameUIVisible=function() return state.menu end}
vgui={CursorVisible=function() return false end}
hook={Add=function() end}
local shots=0
local pos={isvector=true};local ang={isangle=true}
function isvector(v) return v and v.isvector end
function isangle(v) return v and v.isangle end
net={Receive=function() end,Start=function(name) assert(name=="gquest_arcvr_shot") end,
    WriteVector=function(v) assert(v==pos) end,WriteAngle=function(v) assert(v==ang) end,
    SendToServer=function() shots=shots+1 end}
assert(loadfile("work/gquest-arcvr/content/lua/weapons/gquest_arcvr_aniv_glock/shared.lua"))()
local player={};local weapon=setmetatable({}, {__index=SWEP})
function LocalPlayer() return player end
function player:GetActiveWeapon() return weapon end
function weapon:GetOwner() return player end
function weapon:GetArcLoaded() return 16 end
function weapon:GetArcChambered() return 1 end
function weapon:GetArcMagazine() return true end
-- Match the real MDL attachment name; its bone is separately named "muzzle".
function weapon:LookupAttachment(name) assert(name=="1");return 1 end
function weapon:GetAttachment(index) assert(index==1);return {Pos=pos,Ang=ang} end
local function tick(value,active,expected,label)
    state.analog=value;state.analogActive=active
    weapon:Think()
    assert(shots==expected,label..": expected "..expected.." requests, got "..shots)
end
tick(1,false,0,"inactive physical input cannot shoot")
tick(0,true,0,"released active analog")
tick(0.54,true,0,"below press threshold")
tick(0.55,true,1,"active analog rising threshold with inactive digital")
tick(1,true,1,"hold cannot repeat")
tick(0.51,true,1,"hysteresis noise stays held")
tick(0.46,true,1,"above release threshold remains held")
tick(0.45,true,1,"release threshold")
tick(0.50,true,1,"between thresholds remains released")
tick(0.56,true,2,"fresh physical repress")
tick(0,true,2,"release")
state.menu=true
tick(1,true,2,"menu suppresses physical press")
state.menu=false
tick(1,true,2,"closing menu while held cannot fire")
tick(0,true,2,"release after menu")
tick(1,true,3,"new press after menu closes")
state.session=false
tick(1,true,3,"inactive VR session blocks genuine analog")
state.session=true
tick(0,true,3,"release on session restoration")
tick(0/0,true,3,"NaN input cannot shoot")
tick(math.huge,true,3,"nonfinite input cannot shoot")
state.digitalActive=true;state.digital=false
tick(1,true,3,"valid digital released takes priority over analog")
state.digital=true
tick(0,true,4,"valid digital fresh press")
tick(0,true,4,"digital hold cannot repeat")
state.digital=false
tick(0,true,4,"digital release")
state.digitalThrows=true
tick(1,true,5,"throwing digital API falls back to genuine active analog")
state.digitalThrows=false;state.digitalActive=false
tick(0,true,5,"release before missing digital API")
vr.GetDigital=nil
tick(1,true,6,"missing digital API falls back to genuine active analog")
print("PASS actual client Think: inactive input/session, analog hysteresis, hold/repress, menu suppression, digital priority/fallback; 6 requests")

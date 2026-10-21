-- Execute the real client reload dispatcher; native command boundary is mocked.
local hooks,commands,callbacks={},{},{}
local now=0
local mode=true
local events={}
local player={Alive=function() return true end}
local weapon={GetClass=function() return "hlvr_weapon_smg1" end}
function player:GetActiveWeapon() return weapon end
function LocalPlayer() return player end
function IsValid(v) return type(v)=="table" end
function CreateClientConVar() return {GetBool=function() return mode end} end
function GetConVar(name) assert(name=="hlvr_quick_reload");return {} end
function RealTime() return now end
function RunConsoleCommand(name,value) events[#events+1]={name,value} end
hook={Add=function(event,key,fn)
 local old=hooks[event]
 hooks[event]=old and function() old();fn() end or fn
end}
concommand={Add=function(key,fn) commands[key]=fn end}
cvars={AddChangeCallback=function(key,fn) callbacks[key]=fn end}
dofile("work/gquest-ui/lua/autorun/client/gquest_reload.lua")
hooks.InitPostEntity();assert(events[#events][1]=="hlvr_quick_reload" and events[#events][2]=="1")
commands.gquest_reload();assert(events[#events][1]=="+eject")
-- The refill must not run before the eject pulse is released.
now=0.1;hooks.Think();assert(events[#events][1]=="+eject")
now=0.2;hooks.Think();assert(events[#events][1]=="-eject")
now=0.3;hooks.Think();assert(events[#events][1]=="-eject","refill ran before its delay")
now=0.5;hooks.Think();assert(events[#events][1]=="gquest_reload_refill")
local afterRefill=#events;hooks.Think();assert(#events==afterRefill,"refill must fire once")
-- Assisted mode off keeps the plain native path: no refill is ever queued.
mode=false;callbacks.gquest_reload_assisted();assert(events[#events][2]=="0")
commands.gquest_reload();now=1;hooks.Think();now=1.3;hooks.Think()
assert(events[#events][1]=="-eject","unassisted path must not refill")
mode=true;callbacks.gquest_reload_assisted()
-- Shutdown releases a pending eject and drops a pending refill.
commands.gquest_reload();hooks.ShutDown();assert(events[#events][1]=="-eject")
local afterShutdown=#events;now=9;hooks.Think();assert(#events==afterShutdown,"shutdown must drop the pending refill")
player.Alive=function() return false end
local count=#events;commands.gquest_reload();assert(#events==count)
print("PASS client reload: native eject pulse/release, delayed own-reserve refill, assisted-off path, shutdown drop, alive gate")

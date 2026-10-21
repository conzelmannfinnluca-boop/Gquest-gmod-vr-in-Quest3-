RealTime=function() return 0 end
util={TableToJSON=function() return "{}" end}
local tick,writes,active,class,alive,side=nil,{},true,"hlvr_weapon_smg1",true,1
file={Write=function(path,text) writes[#writes+1]=text end}
hook={Add=function(_,_,fn) tick=fn end}
function IsValid(x) return type(x)=="table" end
local weapon={GetClass=function() return class end}
local player={Alive=function() return alive end,GetActiveWeapon=function() return weapon end}
function LocalPlayer() return player end
vr={IsActive=function() return active end,GetPrimaryHand=function() return side end}
dofile("work/gquest-ui/lua/autorun/client/gquest_native_weapon_pose.lua")
assert(writes[1]=="none\n")
tick();assert(writes[#writes]=="weapon_smg1\n")
local count=#writes;tick();assert(#writes==count,"must not rewrite unchanged class every frame")
class="gquest_arcvr_aniv_m9";tick();assert(writes[#writes]=="none\n","retired ArcVR class accepted")
side=0;tick();assert(writes[#writes]=="none\n","left primary must not receive right pose")
side=1;class="weapon_physgun";tick();assert(writes[#writes]==class.."\n")
class="gmod_camera";tick();assert(writes[#writes]=="none\n","no fabricated camera grip")
class="weapon_pistol";alive=false;tick();assert(writes[#writes]=="none\n")
alive=true;active=false;tick();assert(writes[#writes]=="none\n")
active=true;tick();assert(writes[#writes]=="weapon_pistol\n")
print("PASS native pose writer: HLVR aliases, allowlist, left-primary/session/death gates, change-only writes")

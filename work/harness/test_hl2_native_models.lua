local hooks,pending={},{}
function AddCSLuaFile() end
local single=true
game={SinglePlayer=function() return single end}
function IsValid(v) return type(v)=="table" and v.valid~=false end
local exists=true
file={Exists=function(path,scope) assert(scope=="GAME");return exists end}
timer={Simple=function(_,fn) pending[#pending+1]=fn end}
hook={Add=function(event,_,fn) hooks[event]=fn end}
local owner={Alive=function() return true end,IsPlayer=function() return true end}
local w={class="hlvr_weapon_pistol",model="w_pistol",changes=0}
function w:GetClass() return self.class end;function w:GetOwner() return owner end
function w:GetModel() return self.model end
function w:SetModel(path) self.model=path;self.changes=self.changes+1 end
local function flush() local q=pending;pending={};for _,fn in ipairs(q) do fn() end end
assert(loadfile("work/gquest-ui/lua/autorun/server/gquest_hl2_models.lua"))()
hooks.PlayerSwitchWeapon(owner,nil,w)
assert(w.model=="w_pistol","must defer until Deploy finishes")
flush();assert(w.model=="models/weapons/vr_pistol.mdl")
local n=w.changes;GquestHL2Models.Apply(w);assert(w.changes==n,"idle unchanged model should not be reassigned")
w.class="gmod_tool";w.model="tool";assert(not GquestHL2Models.Apply(w) and w.model=="tool")
w.class="weapon_pistol";assert(not GquestHL2Models.Apply(w),"desktop weapon class modified")
w.class="hlvr_weapon_pistol";single=false;assert(not GquestHL2Models.Apply(w),"multiplayer changed")
single=true;exists=false;assert(not GquestHL2Models.Apply(w),"missing model substituted")
exists=true;owner.Alive=function() return false end;assert(not GquestHL2Models.Apply(w),"dead owner changed")
owner.Alive=function() return true end
owner.IsPlayer=function() return false end;assert(not GquestHL2Models.Apply(w),"NPC changed")
owner.IsPlayer=function() return true end
for class,stem in pairs({smg1="smg",ar2="irifle",shotgun="shotgun",crossbow="crossbow",rpg="rocket_launcher",crowbar="crowbar",frag="grenade",bugbait="bugbait",physcannon="physcannon",["357"]="357"}) do
 w.class="hlvr_weapon_"..class;w.model="retail"
 assert(GquestHL2Models.Apply(w) and w.model=="models/weapons/vr_"..stem..".mdl")
end
print("PASS native HL2 model policy: eleven classes, after-Deploy assignment, no idle rewrite, desktop/mod/NPC/MP/dead/missing-model guards")

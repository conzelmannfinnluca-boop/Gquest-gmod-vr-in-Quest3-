local commands={}
function AddCSLuaFile() end
function IsValid(x) return type(x)=="table" and x.valid~=false end
concommand={Add=function(k,v) commands[k]=v end}
local singleplayer=true
game={SinglePlayer=function() return singleplayer end}
local player={alive=true,owned={},given=0,selected=nil}
function player:Alive() return self.alive end
function player:GetWeapon(c) return self.owned[c] end
function player:Give(c)
    self.given=self.given+1
    self.owned[c]={GetModel=function() return "native-vr-model" end,GetClass=function() return c end}
    return self.owned[c]
end
function player:SelectWeapon(c) self.selected=c end
dofile("work/gquest-ui/lua/autorun/server/gquest_hl2_equipment.lua")
local equip=commands.gquest_hl2_equip
equip(player,nil,{"weapon_smg1"});assert(player.selected=="weapon_smg1" and player.given==1)
equip(player,nil,{"weapon_smg1"});assert(player.given==1,"selection must not give/refill again")
equip(player,nil,{"arbitrary_entity"});assert(player.given==1)
equip(player,nil,{});equip(player,nil,nil);assert(player.given==1)
singleplayer=false;equip(player,nil,{"weapon_ar2"});assert(player.given==1)
singleplayer=true;player.alive=false;equip(player,nil,{"weapon_ar2"});assert(player.given==1)
equip(nil,nil,{"weapon_ar2"})
player.alive=true
for _,c in ipairs({"weapon_pistol","weapon_357","weapon_ar2","weapon_shotgun",
    "weapon_crossbow","weapon_rpg","weapon_crowbar","weapon_frag","weapon_physcannon","weapon_physgun"}) do
    equip(player,nil,{c});assert(player.selected==c)
end
assert(player.given==11)
local alias={GetClass=function() return "hlvr_weapon_pistol" end,GetModel=function() return "vr_pistol" end}
player.owned.weapon_pistol=nil;player.owned.hlvr_weapon_pistol=alias
local before=player.given
equip(player,nil,{"weapon_pistol"})
assert(player.selected=="hlvr_weapon_pistol" and player.given==before,"existing HLVR alias must not give a duplicate or refill ammo")
print("HL2 equipment: eleven classes, persistent ammo, allowlist, missing args, SP/alive guards passed")

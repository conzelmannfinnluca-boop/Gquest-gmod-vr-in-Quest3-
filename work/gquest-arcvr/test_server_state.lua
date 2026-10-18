-- Runs actual adapted SWEP server methods with a small engine boundary harness.
SERVER=true CLIENT=false SWEP={} CHAN_WEAPON=1
function AddCSLuaFile() end
function IsValid(value) return type(value)=="table" and value.valid~=false end
util={AddNetworkString=function() end}
local receivers,commands={},{ }
net={Receive=function(name,callback) receivers[name]=callback end,
    Start=function() end,WriteEntity=function() end,Send=function() end}
concommand={Add=function(name,callback) commands[name]=callback end}
local single=true
game={SinglePlayer=function() return single end}
local now=0
function CurTime() return now end
local angleMeta={}
function angleMeta.__add(a,b) return setmetatable({p=a.p+b.p,y=a.y+b.y,r=a.r+b.r},angleMeta) end
function angleMeta.__mul(a,b) return setmetatable({p=a.p*b,y=a.y*b,r=a.r*b},angleMeta) end
function angleMeta.__index(_,key) if key=="Forward" then return function() return {x=1,y=0,z=0} end end end
function AngleRand() return setmetatable({p=1,y=1,r=1},angleMeta) end
local src={x=0,y=0,z=0,DistToSqr=function(self,eye)
    return (self.x-eye.x)^2+(self.y-eye.y)^2+(self.z-eye.z)^2
end}
local angle=setmetatable({p=0,y=0,r=0},angleMeta)
net.ReadVector=function() return src end
net.ReadAngle=function() return angle end
dofile("work/gquest-arcvr/content/lua/weapons/gquest_arcvr_aniv_glock/shared.lua")
local weapon=setmetatable({}, {__index=SWEP})
local state={loaded=0,chamber=0,mag=false,clip=0}
function weapon:SetHoldType() end
function weapon:SetArcLoaded(n) state.loaded=n end
function weapon:GetArcLoaded() return state.loaded end
function weapon:SetArcChambered(n) state.chamber=n end
function weapon:GetArcChambered() return state.chamber end
function weapon:SetArcMagazine(n) state.mag=n end
function weapon:GetArcMagazine() return state.mag end
function weapon:SetClip1(n) state.clip=n end
function weapon:GetClass() return "gquest_arcvr_aniv_glock" end
function weapon:EmitSound() end
local player={ammo=100,shots=0,lastShot=nil}
function player:Alive() return true end
function player:GetActiveWeapon() return weapon end
function player:GetAmmoCount() return self.ammo end
function player:RemoveAmmo(n) self.ammo=self.ammo-n end
function player:GiveAmmo(n) self.ammo=self.ammo+n end
function player:ChatPrint() end
function player:EyePos() return {x=0,y=0,z=0} end
function player:LagCompensation() end
function player:FireBullets(bullet) self.shots=self.shots+1 self.lastShot=bullet end
weapon:Initialize()
assert(state.loaded==0 and state.chamber==0 and state.clip==0)
commands.gquest_arcvr_test_insert(player)
assert(state.loaded==17 and state.chamber==0 and player.ammo==83)
commands.gquest_arcvr_test_insert(player)
assert(player.ammo==83) -- duplicate insertion cannot consume or duplicate ammo
commands.gquest_arcvr_test_rack(player)
assert(state.loaded==16 and state.chamber==1 and state.clip==17)
local shot=receivers.gquest_arcvr_shot
shot(0,player)
assert(player.shots==1 and state.loaded==15 and state.chamber==1 and state.clip==16)
assert(player.lastShot.Damage==22.5 and player.lastShot.Force==7.5)
shot(0,player)
assert(player.shots==1) -- immediate repeat rejected by source RPM limit
now=0.051 shot(0,player)
assert(player.shots==2 and state.clip==15)
src.x=1000 now=0.2 shot(0,player)
assert(player.shots==2 and state.clip==15) -- implausible muzzle cannot shoot
src.x=0 single=false now=0.3 shot(0,player)
assert(player.shots==2 and state.clip==15) -- private singleplayer scope enforced
single=true
commands.gquest_arcvr_test_eject(player)
assert(player.ammo==97 and state.loaded==0 and state.chamber==1 and state.clip==1)
now=0.4 shot(0,player)
assert(player.shots==3 and state.clip==0 and state.chamber==0)
now=0.5 shot(0,player)
assert(player.shots==3 and state.clip==0) -- empty chamber cannot create bullets
print("PASS source magazine/chamber conservation,22.5 damage,1200 RPM and server gates")

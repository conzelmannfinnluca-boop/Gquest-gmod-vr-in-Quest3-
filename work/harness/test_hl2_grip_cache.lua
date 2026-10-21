local vec={};vec.__index=vec
function Vector(x,y,z) return setmetatable({x=x,y=y,z=z},vec) end
function vec:DistToSqr(b) return (self.x-b.x)^2+(self.y-b.y)^2+(self.z-b.z)^2 end
function Angle(p,y,r) return {p=p,y=y,r=r,kind="angle"} end
function isvector(v) return type(v)=="table" and getmetatable(v)==vec end
function isangle(v) return type(v)=="table" and v.kind=="angle" end
function IsValid(v) return type(v)=="table" end
function AddCSLuaFile() end
hook={Add=function() end}
assert(loadfile("work/gquest-ui/lua/autorun/server/gquest_hl2_models.lua"))()
local keys={"m_gripLocalOffset","m_gripLocalAngles","m_foregripLocalOffset","m_foregripLocalAngles"}
local state,sets={},0
local origin=Vector(100,200,300);local rotation=Angle(0,90,0)
local positions={Vector(-1.2,0,-2.06),Vector(6.9,0,-2.32)}
function WorldToLocal(pos,ang,p,a)
 assert(p==origin and a==rotation,"must use weapon-local frame")
 return pos,ang
end
local w={}
function w:GetClass() return "hlvr_weapon_smg1" end
function w:GetPos() return origin end;function w:GetAngles() return rotation end
function w:GetSaveTable() local out={};for k,v in pairs(state) do out[k]=v end;return out end
function w:LookupAttachment(name) return name=="grip" and 1 or (name=="foregrip" and 2 or 0) end
function w:GetAttachment(i) return {Pos=positions[i],Ang=Angle(0,0,0)} end
local fail
function w:SetSaveValue(key,v)
 sets=sets+1
 if key==fail then fail=nil;return false end
 state[key]=v;return true
end
local function reset()
 sets=0;state={m_gripLocalOffset=Vector(0,0,0),m_gripLocalAngles=Angle(0,0,0),m_foregripLocalOffset=Vector(0,0,0),m_foregripLocalAngles=Angle(0,0,0)}
end
reset();assert(GquestHL2Models.RefreshGrips(w));assert(sets==4)
assert(state[keys[1]]==positions[1] and state[keys[3]]==positions[2])
assert(state[keys[1]]:DistToSqr(state[keys[3]])>64,"zero support baseline retained")
reset();state[keys[2]]=Vector(0,0,0);state[keys[4]]=Vector(0,0,0)
assert(GquestHL2Models.RefreshGrips(w) and sets==4,"GMod FIELD_VECTOR angle cache rejected")
for _,key in ipairs(keys) do
 reset();local old=w:GetSaveTable();fail=key
 assert(not GquestHL2Models.RefreshGrips(w))
 for _,k in ipairs(keys) do assert(state[k]==old[k],"partial failed write not rolled back") end
end
reset();positions[2]=positions[1];assert(not GquestHL2Models.RefreshGrips(w) and sets==0,"coincident grips written")
positions[2]=Vector(0/0,0,0);assert(not GquestHL2Models.RefreshGrips(w) and sets==0,"nonfinite anchor written")
positions[2]=Vector(1000,0,0);assert(not GquestHL2Models.RefreshGrips(w) and sets==0,"implausible anchor written")
positions[2]=Vector(6.9,0,-2.32);state[keys[3]]=nil
assert(not GquestHL2Models.RefreshGrips(w) and sets==0,"unknown native data layout changed")
print("PASS grip cache: real model-local anchors, zero-baseline regression, four partial-write rollback boundaries, finite/range/schema guards")

-- Retail muzzle axes are stale after changing the entity model. Verify actual
-- attachment frames replace them without altering clip/reserve state.
local muzzle=true
local support=true
positions[3]=Vector(30,0,4)
local angles={Angle(0,0,0),Angle(0,0,0),Angle(0,0,0)}
function w:LookupAttachment(name)
 if name=="grip" then return 1 end
 if name=="foregrip" then return support and 2 or 0 end
 if name=="muzzle" then return muzzle and 3 or 0 end
 return 0
end
function w:GetAttachment(i) return {Pos=positions[i],Ang=angles[i]} end
local function firearm()
 reset()
 state.m_muzzleLocalOffset=Vector(-15,0,1)
 state.m_muzzleLocalAngles=Vector(0,180,90)
 state.m_bHasMuzzlePose=false
 state.clip=3;state.reserve=41
end
firearm();assert(GquestHL2Models.RefreshGrips(w) and sets==7)
assert(state.m_muzzleLocalOffset==positions[3] and state.m_muzzleLocalAngles.y==0 and state.m_bHasMuzzlePose)
assert(state.clip==3 and state.reserve==41,"frame repair changed ammunition")
local allkeys={"m_gripLocalOffset","m_gripLocalAngles","m_foregripLocalOffset","m_foregripLocalAngles","m_muzzleLocalOffset","m_muzzleLocalAngles","m_bHasMuzzlePose"}
for _,key in ipairs(allkeys) do
 firearm();local old=w:GetSaveTable();fail=key
 assert(not GquestHL2Models.RefreshGrips(w))
 for _,k in ipairs(allkeys) do assert(state[k]==old[k],"muzzle transaction partially applied") end
end
firearm();positions[3]=Vector(0/0,0,0)
assert(not GquestHL2Models.RefreshGrips(w) and sets==0,"invalid muzzle changed valid grip state")
positions[3]=Vector(30,0,4)
firearm();support=false;muzzle=false;angles[1]=Angle(0,0,90)
assert(GquestHL2Models.RefreshGrips(w) and sets==2,"single-hand crowbar grip skipped without foregrip")
assert(state.m_gripLocalAngles.r==90 and not state.m_bHasMuzzlePose,"melee model acquired a fabricated muzzle")
print("PASS muzzle and single-hand frames: reversed retail axes replaced, ammo retained, seven rollback boundaries, invalid-muzzle guard, crowbar without foregrip")

-- Exact crowbar-only correction confirmed by the wearer on Quest3.
function w:GetClass() return "hlvr_weapon_crowbar" end
angles[1]=Angle(0,0,0)
firearm();support=false;muzzle=false
assert(GquestHL2Models.RefreshGrips(w) and sets==2)
assert(state.m_gripLocalAngles.p==-90 and state.m_gripLocalAngles.y==0 and state.m_gripLocalAngles.r==0)
assert(state.m_gripLocalOffset==positions[1],"direction fix moved grip")
assert(GquestHL2Models.RefreshGrips(w) and state.m_gripLocalAngles.p==-90,"repeat Deploy accumulated pitch")
assert(angles[1].p==0,"source attachment mutated")
assert(state.clip==3 and state.reserve==41,"crowbar repair changed ammunition")
for _,class in ipairs({"hlvr_weapon_pistol","hlvr_weapon_shotgun","hlvr_weapon_smg1"}) do
 function w:GetClass() return class end
 firearm();support=true;muzzle=true
 assert(GquestHL2Models.RefreshGrips(w) and state.m_gripLocalAngles.p==0,"crowbar correction leaked into firearm")
end
print("PASS crowbar direction: exact wearer-confirmed pitch, repeat-Deploy idempotence, source frame/position/ammo retained, firearm isolation")

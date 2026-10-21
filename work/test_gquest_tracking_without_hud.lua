-- Removing the wrist renderer must retain native world-pose conversion.
local vector={};vector.__index=vector
function Vector(x,y,z) return setmetatable({x=x,y=y,z=z},vector) end
vector.__add=function(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
vector.__sub=function(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
function vector:Rotate(a) assert(a.p==0 and a.y==0 and a.r==0) end
function vector:AngleEx(up)
 assert(self.x==0 and self.y==1 and self.z==0)
 assert(up.x==0 and up.y==0 and up.z==1)
 return Angle(0,0,0)
end
function Angle(p,y,r) return {p=p,y=y,r=r,RotateAroundAxis=function(self,axis,yaw) assert(yaw==0) end} end
math.AngleDifference=function(a,b) return a-b end
function IsValid(v) return v~=nil end
local p={EyeAngles=function() return Angle(0,0,0) end,EyePos=function() return Vector(100,200,300) end}
function LocalPlayer() return p end
vr={GetHeadPose=function() return {x=0,y=0,z=10},{p=0,y=0,r=0},true end,
GetHandPose=function(side) return {x=side==0 and -5 or 5,y=20,z=8},{p=0,y=0,r=0},true end}
local removed={};hook={Remove=function(event,name) removed[name]=event end,Add=function() error("renderer re-registered") end}
function CreateClientConVar() end
function RunConsoleCommand(name,value) assert(name=="gquest_wrist_hud" and value=="0") end
assert(loadfile("work/gquest-ui/lua/autorun/client/gquest_wrist_hud.lua"))()
local t=assert(GquestXR.GetWorldTracking())
assert(t.pose_lefthand.pos.x==95 and t.pose_righthand.pos.x==105)
assert(t.pose_lefthand.pos.y==220 and t.pose_lefthand.pos.z==298)
assert(removed.GquestWristHUD and removed.GquestVitals)
vr.GetHeadPose=function() return nil,nil,false end
assert(GquestXR.GetWorldTracking()==nil)
print("Tracking remains available for both hands; invalid tracking rejected; wrist renderer removed")

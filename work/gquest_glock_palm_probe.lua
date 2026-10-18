if not CLIENT then return end
local deadline=SysTime()+10
local nextSample=0
local samples=0
local function vec(v) return {x=v.x,y=v.y,z=v.z} end
local function ang(a) return {p=a.p,y=a.y,r=a.r} end
hook.Add("PostDrawTranslucentRenderables","GquestGlockPalmProbe",function(depth,sky)
    if depth or sky then return end
    local now=SysTime()
    if now>deadline or samples>=3 then hook.Remove("PostDrawTranslucentRenderables","GquestGlockPalmProbe");return end
    if now<nextSample then return end
    nextSample=now+0.5
    local player=LocalPlayer()
    local tracking=GquestXR and GquestXR.GetWorldTracking()
    if not IsValid(player) or not tracking or not tracking.pose_righthand then return end
    local weapon=player:GetActiveWeapon()
    if not IsValid(weapon) or weapon:GetClass()~="gquest_arcvr_aniv_glock" then return end
    local report={time=now,model=weapon:GetModel(),bones={},weapon={position=vec(weapon:GetPos()),angles=ang(weapon:GetAngles())},grip={position=vec(tracking.pose_righthand.pos),angles=ang(tracking.pose_righthand.ang)}}
    for _,name in ipairs({"Hand","Finger0","Finger01","Finger1","Finger11","Finger2","Finger21","Finger3","Finger31","Finger4"}) do
        local index=player:LookupBone("ValveBiped.Bip01_R_"..name)
        local matrix=index and player:GetBoneMatrix(index)
        if matrix then
            local pos,angle=matrix:GetTranslation(),matrix:GetAngles()
            local p,a=WorldToLocal(pos,angle,weapon:GetPos(),weapon:GetAngles())
            report.bones[name]={position=vec(pos),angles=ang(angle),relative_weapon_position=vec(p),relative_weapon_angles=ang(a)}
        end
    end
    samples=samples+1
    print("GQUEST_GLOCK_PALM "..util.TableToJSON(report,false))
end)

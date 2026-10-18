if not CLIENT then return end
local untilTime=SysTime()+20
local nextSample=0
hook.Add("PostDrawTranslucentRenderables","GquestHandFrameProbe",function(depth,sky)
    if depth or sky then return end
    local now=SysTime()
    if now>untilTime then hook.Remove("PostDrawTranslucentRenderables","GquestHandFrameProbe");return end
    if now<nextSample then return end
    nextSample=now+0.5
    local player=LocalPlayer()
    local tracking=GquestXR and GquestXR.GetWorldTracking()
    if not IsValid(player) or not tracking then return end
    local report={time=now,model=player:GetModel()}
    for _,side in ipairs({"L","R"}) do
        local pose=tracking[side=="L" and "pose_lefthand" or "pose_righthand"]
        local bone=player:LookupBone("ValveBiped.Bip01_"..side.."_Hand")
        local matrix=bone and player:GetBoneMatrix(bone)
        if pose and matrix then
            local p,a=WorldToLocal(matrix:GetTranslation(),matrix:GetAngles(),pose.pos,pose.ang)
            report[side]={offset={x=p.x,y=p.y,z=p.z},relative={p=a.p,y=a.y,r=a.r},grip={p=pose.ang.p,y=pose.ang.y,r=pose.ang.r}}
        end
    end
    print("GQUEST_HAND_FRAME "..util.TableToJSON(report,false))
end)
print("GQUEST_HAND_FRAME ready 20 seconds")

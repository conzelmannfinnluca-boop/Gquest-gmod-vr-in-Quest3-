-- Optional client-only observation. No model, bone, convar or pose writes.
-- Run once with: lua_openscript_cl gquest_left_hand_audit.lua
-- Then: gquest_left_hand_audit
if not CLIENT then return end
local function vector(v)
    return v and {x=v.x,y=v.y,z=v.z} or nil
end
local function angle(v)
    return v and {p=v.p,y=v.y,r=v.r} or nil
end
local function inspect(ent)
    if not IsValid(ent) then return end
    local hand=ent:LookupBone("ValveBiped.Bip01_L_Hand")
    if not hand then return end
    local out={entity=ent:EntIndex(),class=ent:GetClass(),model=ent:GetModel(),bones={}}
    -- Read existing matrices only. SetupBones/InvalidateBoneCache are deliberately
    -- avoided so this probe cannot replace the current native render pose.
    for bone=0,ent:GetBoneCount()-1 do
        local name=ent:GetBoneName(bone)
        if name=="ValveBiped.Bip01_L_Hand" or string.find(name,"ValveBiped.Bip01_L_Finger",1,true)==1 then
            local matrix=ent:GetBoneMatrix(bone)
            local parent=ent:GetBoneParent(bone)
            local parentMatrix=parent>=0 and ent:GetBoneMatrix(parent) or nil
            local row={name=name,index=bone,parent=parent,has_matrix=matrix~=nil}
            if matrix then
                row.position=vector(matrix:GetTranslation())
                row.angles=angle(matrix:GetAngles())
                if parentMatrix then
                    local p,a=WorldToLocal(matrix:GetTranslation(),matrix:GetAngles(),parentMatrix:GetTranslation(),parentMatrix:GetAngles())
                    row.parent_local_position=vector(p);row.parent_local_angles=angle(a)
                end
            end
            row.manipulated_angles=angle(ent:GetManipulateBoneAngles(bone))
            row.manipulated_position=vector(ent:GetManipulateBonePosition(bone))
            row.manipulated_scale=vector(ent:GetManipulateBoneScale(bone))
            out.bones[#out.bones+1]=row
        end
    end
    return out
end
concommand.Add("gquest_left_hand_audit",function()
    local player=LocalPlayer()
    if not IsValid(player) then print("GQUEST_LEFT_AUDIT no player");return end
    local report={time=RealTime(),entities={},convars={}}
    for _,name in ipairs({"hlvr_test_hand_pose","hlvr_grip_yaw_correction","hlvr_legacy_aiming","vr_player_body_vr_hands"}) do
        local cv=GetConVar(name);report.convars[name]=cv and cv:GetString() or "absent"
    end
    if GquestXR and GquestXR.GetWorldTracking then
        local tracking=GquestXR.GetWorldTracking()
        local left=tracking and tracking.pose_lefthand
        report.tracked_left=left and {position=vector(left.pos),angles=angle(left.ang)} or nil
    end
    local seen={}
    local function add(ent)
        if not IsValid(ent) or seen[ent] then return end
        seen[ent]=true
        local data=inspect(ent)
        if data then report.entities[#report.entities+1]=data end
    end
    add(player);add(player:GetHands());add(player:GetViewModel())
    -- Native body/hand renderables may not be exposed to GLua at all. Zero
    -- matching entities is a useful boundary finding, not proof of missing hands.
    for _,ent in ipairs(ents.GetAll()) do
        if IsValid(ent) and ent:GetPos():DistToSqr(player:GetPos())<256*256 then add(ent) end
        if #report.entities>=12 then break end
    end
    print("GQUEST_LEFT_AUDIT "..util.TableToJSON(report,false))
end)
print("GQUEST_LEFT_AUDIT read-only command ready")

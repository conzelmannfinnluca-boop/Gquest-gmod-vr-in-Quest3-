if not CLIENT then return end
local function vec(v) return v and {x=v.x,y=v.y,z=v.z} end
local function ang(v) return v and {p=v.p,y=v.y,r=v.r} end
-- Resolve through GAME rather than reading the APK source: another mount may
-- shadow an otherwise correctly packaged script.
local expectedModels={
    weapon_357="357",weapon_ar2="irifle",weapon_bugbait="bugbait",
    weapon_crossbow="crossbow",weapon_crowbar="crowbar",weapon_frag="grenade",
    weapon_physcannon="physcannon",weapon_physgun="superphyscannon",
    weapon_pistol="pistol",weapon_rpg="rocket_launcher",
    weapon_shotgun="shotgun",weapon_smg1="smg"
}
local scripts={}
for class,stem in pairs(expectedModels) do
    local path="scripts/"..class..".txt"
    local text=file.Read(path,"GAME")
    local data=text and util.KeyValuesToTable(text)
    local right=data and data.vrmodel
    local left=data and data.vrmodel_l
    local expectedRight="models/weapons/vr_"..stem..".mdl"
    local expectedLeft="models/weapons/left_handed/vr_"..stem.."_l.mdl"
    local row={path=path,readable=text~=nil,vrmodel=right,vrmodel_l=left,
        matches_expected=right==expectedRight and left==expectedLeft,
        expected_assets_present=file.Exists(expectedRight,"GAME") and file.Exists(expectedLeft,"GAME")}
    if text and util.SHA256 then row.sha256=util.SHA256(text) end
    scripts[class]=row
end
print("GQUEST_MODEL_SCRIPTS "..util.TableToJSON(scripts,false))
local player=LocalPlayer()
if not IsValid(player) then print("GQUEST_MODEL_PROBE no player");return end
local weapon=player:GetActiveWeapon()
if not IsValid(weapon) then print("GQUEST_MODEL_PROBE no active weapon");return end
local report={class=weapon:GetClass(),model=weapon:GetModel(),scale=weapon:GetModelScale(),bounds={min=vec(weapon:OBBMins()),max=vec(weapon:OBBMaxs())},position=vec(weapon:GetPos()),angles=ang(weapon:GetAngles()),materials={},attachments={},tracking_valid=false,
    transform_scope="GLua entity snapshot outside native render; does not prove rendered held-model transform"}
for _,name in ipairs(weapon:GetMaterials()) do
    report.materials[#report.materials+1]={name=name,error=Material(name):IsError()}
end
for _,entry in ipairs(weapon:GetAttachments() or {}) do
    local attachment=weapon:GetAttachment(entry.id)
    report.attachments[#report.attachments+1]={name=entry.name,id=entry.id,position=attachment and vec(attachment.Pos),angles=attachment and ang(attachment.Ang)}
end
local tracking=GquestXR and GquestXR.GetWorldTracking()
local rootBone=weapon:GetBoneMatrix(0)
if rootBone then report.root_bone={position=vec(rootBone:GetTranslation()),angles=ang(rootBone:GetAngles())} end
if tracking and tracking.pose_righthand then
    report.tracking_valid=true
    local right=tracking.pose_righthand
    report.right={position=vec(right.pos),angles=ang(right.ang)}
    local p,a=WorldToLocal(weapon:GetPos(),weapon:GetAngles(),right.pos,right.ang)
    report.entity_relative_to_right={position=vec(p),angles=ang(a)}
    if weapon:GetClass()=="gquest_arcvr_aniv_glock" and GquestArcVR then
        local expectedPos,expectedAng=GquestArcVR.GlockTransform(right)
        report.arcvr_expected={position=vec(expectedPos),angles=ang(expectedAng)}
        local dp,da=WorldToLocal(weapon:GetPos(),weapon:GetAngles(),expectedPos,expectedAng)
        report.entity_relative_to_arcvr_expected={position=vec(dp),angles=ang(da)}
    end
end
report.convars={}
for _,name in ipairs({"hlvr_grip_yaw_correction","vr_first_person_uses_world_model","vr_controller_offset_x","vr_controller_offset_y","vr_controller_offset_z","vr_controller_offset_pitch","vr_controller_offset_yaw","vr_controller_offset_roll","vr_viewmodel_offset_forward","vr_viewmodel_offset_forward_large","gquest_arcvr_native_model"}) do
    local cv=GetConVar(name);report.convars[name]=cv and cv:GetString() or "absent"
end
if vr and vr.GetHandPose and vr.GetAimPose then
    report.raw={}
    for _,entry in ipairs({{"grip",vr.GetHandPose},{"aim",vr.GetAimPose}}) do
        local ok,p,a,valid=pcall(entry[2],1)
        report.raw[entry[1]]={ok=ok,valid=valid==true,position=ok and vec(p),angles=ok and ang(a)}
    end
end
print("GQUEST_MODEL_PROBE "..util.TableToJSON(report,false))

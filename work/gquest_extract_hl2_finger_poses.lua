local suffixes={"0","01","02","1","11","12","2","21","22","3","31","32","4","41","42"}
local targets={weapon_pistol="pistol",weapon_357="357",weapon_smg1="smg",weapon_ar2="irifle",
    weapon_shotgun="shotgun",weapon_crossbow="crossbow",weapon_rpg="rocket_launcher",
    weapon_crowbar="crowbar",weapon_frag="grenade",weapon_physcannon="physcannon",
    weapon_physgun="superphyscannon",weapon_bugbait="bugbait"}
local player=LocalPlayer()
if not IsValid(player) then return end
local reference=ClientsideModel(player:GetModel(),RENDERGROUP_OPAQUE)
if not IsValid(reference) then return end
reference:SetNoDraw(true);reference:ResetSequence(0);reference:SetupBones()
local zero=Vector(0,0,0)
local function localAngle(entity,name)
    local bone=entity:LookupBone(name)
    if not bone then return end
    local a,b=entity:GetBoneMatrix(bone),entity:GetBoneMatrix(entity:GetBoneParent(bone))
    if not a or not b then return end
    local _,angle=WorldToLocal(zero,a:GetAngles(),zero,b:GetAngles())
    return angle
end
local report={reference_model=player:GetModel(),reference_sequence=reference:GetSequenceName(0),weapons={}}
for _,class in ipairs({"gmod_tool","gmod_camera","weapon_medkit"}) do local stored=weapons.GetStored(class) if stored and stored.ViewModel then targets[class]=stored.ViewModel end end
for class,stem in pairs(targets) do
    local path=string.sub(stem,1,7)=="models/" and stem or ("models/weapons/vr_"..stem..".mdl")
    local model=ClientsideModel(path,RENDERGROUP_OPAQUE)
    local item={model=path,complete=false,angles={}}
    if IsValid(model) then
        model:SetNoDraw(true)
        local seq=model:LookupSequence("idle")
        if not seq or seq<0 then seq=0 end
        model:ResetSequence(seq);model:SetCycle(0);model:SetupBones()
        item.sequence=model:GetSequenceName(seq)
        for _,suffix in ipairs(suffixes) do
            local name="ValveBiped.Bip01_R_Finger"..suffix
            local a,b=localAngle(reference,name),localAngle(model,name)
            if not a or not b then item.missing=name;break end
            item.angles[#item.angles+1]={math.NormalizeAngle(b.p-a.p),math.NormalizeAngle(b.y-a.y),math.NormalizeAngle(b.r-a.r)}
        end
        item.complete=#item.angles==15;model:Remove()
    end
    report.weapons[class]=item
end
reference:Remove()
file.Write("gquest_hl2_authored_fingers.json",util.TableToJSON(report,true))
print("GQUEST_HL2_FINGER_EXPORT saved authored weapon-relative finger poses")

print("GQUEST_HL2_FINGER_REFERENCE "..report.reference_model.." "..report.reference_sequence)
for class,item in pairs(report.weapons) do
 print("GQUEST_HL2_FINGER_META "..class.." "..util.TableToJSON({model=item.model,complete=item.complete,sequence=item.sequence},false))
 for start=1,#item.angles,5 do local chunk={} for i=start,math.min(start+4,#item.angles) do chunk[#chunk+1]=item.angles[i] end print("GQUEST_HL2_FINGER_CHUNK "..class.." "..start.." "..util.TableToJSON(chunk,false)) end
end

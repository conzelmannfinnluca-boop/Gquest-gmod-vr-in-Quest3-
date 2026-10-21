-- Native bridge reads only this allowlisted class name. Input interpolation
-- remains inside GDroid; this file supplies no invented tracking/finger input.
local path="gquest_native_weapon_pose.txt"
local classes={    weapon_pistol=true,weapon_357=true,weapon_smg1=true,weapon_ar2=true,
    weapon_shotgun=true,weapon_crossbow=true,weapon_rpg=true,weapon_crowbar=true,
    weapon_frag=true,weapon_bugbait=true,weapon_physcannon=true,weapon_physgun=true}
local previous
local diagnostics=0
local nextDiagnostic=0
file.Write(path,"none\n")
hook.Add("Think","GquestNativeWeaponPoseClass",function()
    local class="none"
    local player=LocalPlayer()
    if IsValid(player) and player:Alive() and vr and vr.IsActive and vr.IsActive() then
        local weapon=player:GetActiveWeapon()
        if IsValid(weapon) and (not vr.GetPrimaryHand or vr.GetPrimaryHand()==1) then
            local name=weapon:GetClass()
            if string.sub(name,1,5)=="hlvr_" then name=string.sub(name,6) end
            if classes[name] then class=name end
        end
    end
    if diagnostics<4 and RealTime()>=nextDiagnostic then
        diagnostics=diagnostics+1;nextDiagnostic=RealTime()+8
        print("GQUEST_POSE_GATE "..util.TableToJSON({alive=IsValid(player) and player:Alive(),
            active=vr and vr.IsActive and vr.IsActive(),
            primary=vr and vr.GetPrimaryHand and vr.GetPrimaryHand(),selected=class},false))
    end
    if class==previous then return end
    previous=class;file.Write(path,class.."\n")
    print("GQUEST_NATIVE_WEAPON_POSE class="..class)
end)

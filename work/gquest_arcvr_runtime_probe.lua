local class="gquest_arcvr_aniv_glock"
local report={realm=SERVER and "server" or "client",registered=weapons.GetStored(class)~=nil,singleplayer=game.SinglePlayer()}
if CLIENT then
    report.menus={game=gui.IsGameUIVisible(),cursor=vgui.CursorVisible(),spawn=IsValid(g_SpawnMenu) and g_SpawnMenu:IsVisible() or false}
    if vr and vr.IsActive then local ok,value=pcall(vr.IsActive);report.session={ok=ok,value=value} end
    local weapon=LocalPlayer():GetActiveWeapon()
    if IsValid(weapon) then
        report.weapon={class=weapon:GetClass(),owner_is_local=weapon:GetOwner()==LocalPlayer(),clip=weapon:Clip1()}
        local muzzle=weapon:LookupAttachment("1")
        local att=muzzle and muzzle>0 and weapon:GetAttachment(muzzle) or nil
        report.weapon.muzzle=muzzle
        report.weapon.attachment_valid=att and isvector(att.Pos) and isangle(att.Ang) or false
        if att and isvector(att.Pos) then
            report.weapon.muzzle_distance_to_eye=att.Pos:Distance(LocalPlayer():EyePos())
            report.weapon.muzzle_world={x=att.Pos.x,y=att.Pos.y,z=att.Pos.z}
        end
        report.weapon.think_source=type(weapon.Think)=="function" and debug.getinfo(weapon.Think,"S").short_src or "none"
    end
    if GquestArcVR then
        report.assets_ok,report.assets_reason=GquestArcVR.CheckGlockAssets()
        report.world_tracking=GquestArcVR.ReadWorld()~=nil
    end
    if vr and vr.GetDigital then
        local ok,state,changed,active=pcall(vr.GetDigital,"attack",1)
        report.digital={ok=ok,state=state==true,changed=changed==true,active=active==true}
    end
    if vr and vr.GetAnalog then
        local ok,x,y,active=pcall(vr.GetAnalog,"trigger_pull",1)
        report.analog={ok=ok,x=ok and x or nil,y=ok and y or nil,active=active==true}
    end
end
print("GQUEST_ARCVR_RUNTIME "..util.TableToJSON(report,false))

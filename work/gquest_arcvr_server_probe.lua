if not SERVER then return end
for _,player in ipairs(player.GetAll()) do
    local weapon=player:GetWeapon("gquest_arcvr_aniv_glock")
    local active=player:GetActiveWeapon()
    local report={active=IsValid(active) and active:GetClass() or "none",owned=IsValid(weapon),singleplayer=game.SinglePlayer()}
    if IsValid(weapon) then
        report.loaded=weapon:GetArcLoaded();report.chamber=weapon:GetArcChambered();report.clip=weapon:Clip1()
    end
    print("GQUEST_ARCVR_SERVER "..util.TableToJSON(report,false))
end

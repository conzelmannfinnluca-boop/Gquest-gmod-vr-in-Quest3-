if not SERVER or not game.SinglePlayer() then return end
local player=player.GetAll()[1]
if not IsValid(player) or not player:Alive() then return end
local class="gquest_arcvr_aniv_glock"
local weapon=player:GetWeapon(class)
local owned=IsValid(weapon)
if not owned then
    local given=player:Give(class)
    weapon=IsValid(given) and given or player:GetWeapon(class)
end
if not IsValid(weapon) then
    print("GQUEST_ARCVR_TEST no owned weapon after Give; registered="..tostring(weapons.GetStored(class)~=nil))
    for _,existing in ipairs(player:GetWeapons()) do
        if IsValid(existing) then print("GQUEST_ARCVR_TEST inventory="..existing:GetClass()) end
    end
    return
end
print("GQUEST_ARCVR_TEST real weapon resolved; already_owned="..tostring(owned).." entity="..weapon:EntIndex())
player:SelectWeapon(class)
-- SelectWeapon is applied by the engine; wait for actual selection before
-- invoking commands guarded by eligible(activeWeapon).
local attempts=0
local function initializeSelected()
    if not IsValid(player) or not IsValid(weapon) then return end
    attempts=attempts+1
    if player:GetActiveWeapon()~=weapon then
        if attempts<20 then timer.Simple(0.1,initializeSelected) else
            local active=player:GetActiveWeapon()
            print("GQUEST_ARCVR_TEST selection pending/blocked; active="..(IsValid(active) and active:GetClass() or "none"))
        end
        return
    end
    -- Repeating this diagnostic must not cycle away a chambered round.
    if weapon:GetArcMagazine() and weapon:GetArcLoaded()==0 and weapon:GetArcChambered()==0 then
        concommand.Run(player,"gquest_arcvr_test_eject",{},"")
    end
    if not weapon:GetArcMagazine() then concommand.Run(player,"gquest_arcvr_test_insert",{},"") end
    if weapon:GetArcChambered()<1 then concommand.Run(player,"gquest_arcvr_test_rack",{},"") end
    print("GQUEST_ARCVR_TEST equipped clip="..weapon:Clip1().." chamber="..weapon:GetArcChambered().." magazine="..weapon:GetArcLoaded().." reserve="..player:GetAmmoCount("pistol"))
end
timer.Simple(0,initializeSelected)

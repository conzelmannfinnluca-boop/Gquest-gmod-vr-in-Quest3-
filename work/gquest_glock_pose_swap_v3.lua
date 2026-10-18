if not SERVER or not game.SinglePlayer() then return end
local owner=player.GetAll()[1]
if not IsValid(owner) then return end
local class="gquest_arcvr_aniv_glock"
local path="models/weapons/gquest_arcvr/pistol_glock_posefix2.mdl"
local definition=weapons.GetStored(class)
local previous=owner:GetWeapon(class)
if not definition or not IsValid(previous) or not file.Exists(path,"GAME") then
    print("GQUEST_POSE_SWAP prerequisite missing");return
end
GquestPoseSwapState={loaded=previous:GetArcLoaded(),chambered=previous:GetArcChambered(),magazine=previous:GetArcMagazine(),reserve=owner:GetAmmoCount("pistol"),nextShot=previous.GquestNextShot or 0}
local state=GquestPoseSwapState
print("GQUEST_POSE_SWAP saved "..util.TableToJSON(state,false))
definition.WorldModel=path
previous:Remove()
local attempts=0
local function restore()
    if not IsValid(owner) then return end
    attempts=attempts+1
    local weapon=owner:GetWeapon(class)
    if not IsValid(weapon) then
        local given=owner:Give(class)
        weapon=IsValid(given) and given or owner:GetWeapon(class)
    end
    if not IsValid(weapon) then
        if attempts<20 then timer.Simple(0.1,restore)
        else print("GQUEST_POSE_SWAP failed; state retained in GquestPoseSwapState") end
        return
    end
    weapon.WorldModel=path
    weapon:SetModel(path)
    weapon:SetArcLoaded(state.loaded)
    weapon:SetArcChambered(state.chambered)
    weapon:SetArcMagazine(state.magazine)
    weapon:SetClip1(state.loaded+state.chambered)
    weapon.GquestNextShot=state.nextShot
    weapon:SyncAmmoFields()
    owner:SetAmmo(state.reserve,"pistol")
    owner:SelectWeapon(class)
    print("GQUEST_POSE_SWAP restored "..util.TableToJSON(state,false))
end
timer.Simple(0.2,restore)

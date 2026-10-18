if not SERVER then return end
local player=Entity(1)
if not IsValid(player) then return end
local class="gquest_arcvr_aniv_glock"
local previous=player:GetWeapon(class)
local definition=weapons.GetStored(class)
if not IsValid(previous) or not definition then return end
local state={loaded=previous:GetArcLoaded(),chambered=previous:GetArcChambered(),magazine=previous:GetArcMagazine(),reserve=player:GetAmmoCount("pistol")}
definition.WorldModel="models/weapons/gquest_arcvr/pistol_glock_posefix.mdl"
previous:Remove()
local weapon=player:Give(class)
if not IsValid(weapon) then print("GQUEST_POSE_RECREATE failed");return end
weapon.WorldModel=definition.WorldModel
weapon:SetModel(definition.WorldModel)
weapon:SetArcLoaded(state.loaded)
weapon:SetArcChambered(state.chambered)
weapon:SetArcMagazine(state.magazine)
weapon:SetClip1(state.loaded+state.chambered)
weapon:SyncAmmoFields()
player:SetAmmo(state.reserve,"pistol")
player:SelectWeapon(class)
print("GQUEST_POSE_RECREATE "..util.TableToJSON(state,false))

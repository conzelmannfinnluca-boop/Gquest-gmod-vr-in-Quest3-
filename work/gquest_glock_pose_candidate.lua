local path="models/weapons/gquest_arcvr/pistol_glock_posefix.mdl"
local class="gquest_arcvr_aniv_glock"
local definition=weapons.GetStored(class)
if definition then definition.WorldModel=path end
local player=CLIENT and LocalPlayer() or Entity(1)
if not IsValid(player) then print("GQUEST_POSE_CANDIDATE no player");return end
local weapon=player:GetWeapon(class)
if not IsValid(weapon) then print("GQUEST_POSE_CANDIDATE no owned Glock");return end
weapon.WorldModel=path
weapon:SetModel(path)
print("GQUEST_POSE_CANDIDATE realm="..(CLIENT and "client" or "server").." model="..weapon:GetModel())

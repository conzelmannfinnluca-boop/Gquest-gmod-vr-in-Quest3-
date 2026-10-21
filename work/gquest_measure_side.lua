local p=LocalPlayer()
local w=p:GetActiveWeapon()
if not IsValid(w) or not w.GquestArcVRWeapon then return end
print("GQUEST_SIDE class="..w:GetClass().." pos="..tostring(w:GetPos()).." ang="..tostring(w:GetAngles()))
local grip=w:GetAttachment(w:LookupAttachment("grip"))
local root=w:GetBoneMatrix(0)
if grip then print("GQUEST_SIDE weapon_grip="..tostring(grip.Pos).." ang="..tostring(grip.Ang)) end
if root then print("GQUEST_SIDE weapon_root="..tostring(root:GetTranslation()).." ang="..tostring(root:GetAngles())) end
for _,name in ipairs({"ValveBiped.Bip01_R_Hand","ValveBiped.Bip01_R_Finger0","ValveBiped.Bip01_R_Finger1","ValveBiped.Bip01_R_Finger2"}) do
 local bone=p:LookupBone(name)
 local m=bone and p:GetBoneMatrix(bone)
 if m then
  local pos=m:GetTranslation()
  local localPos=w:WorldToLocal(pos)
  print("GQUEST_SIDE bone="..name.." pos="..tostring(pos).." weaponlocal="..tostring(localPos))
 end
end
local t=GquestXR and GquestXR.GetWorldTracking()
if t and t.pose_righthand then print("GQUEST_SIDE tracked_hand="..tostring(t.pose_righthand.pos).." ang="..tostring(t.pose_righthand.ang)) end

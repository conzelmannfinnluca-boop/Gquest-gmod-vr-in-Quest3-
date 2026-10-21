local count=0
timer.Create("GquestM9FitMeasure",1,120,function()
 local p=LocalPlayer()
 local w=IsValid(p) and p:GetActiveWeapon()
 if not IsValid(w) or w:GetClass()~="gquest_arcvr_aniv_m9" then return end
 local t=GquestXR and GquestXR.GetWorldTracking()
 if not t or not t.pose_righthand then return end
 count=count+1
 include("gquest_measure_side.lua")
 if count>=3 then
  timer.Remove("GquestM9FitMeasure")
  RunConsoleCommand("vr_eye_readback")
 end
end)
print("GQUEST_SIDE waiting for M9 and valid right hand")

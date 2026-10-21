if not SERVER or not game.SinglePlayer() then return end
local owner=player.GetAll()[1]
if not IsValid(owner) then return end
local paths={
 ["gquest_arcvr_aniv_deagle"]="models/weapons/gquest_arcvr/pistol_deagle_grip_fit1.mdl",
 ["gquest_arcvr_aniv_m9"]="models/weapons/gquest_arcvr/pistol_m9_grip_fit1.mdl",
 ["gquest_arcvr_aniv_usptactical"]="models/weapons/gquest_arcvr/pistol_usp_grip_fit1.mdl",
}
for class,path in pairs(paths) do
 if not weapons.GetStored(class) or not file.Exists(path,"GAME") then
  print("GQUEST_FIT prerequisite missing "..class) return
 end
end
local active=owner:GetActiveWeapon()
local selected=IsValid(active) and active:GetClass()
GquestFitRestore={weapons={},ammo={pistol=owner:GetAmmoCount("pistol"),["357"]=owner:GetAmmoCount("357")},selected=selected}
local state=GquestFitRestore
for class,path in pairs(paths) do
 local w=owner:GetWeapon(class)
 if IsValid(w) then
  state.weapons[class]={loaded=w:GetArcLoaded(),chambered=w:GetArcChambered(),magazine=w:GetArcMagazine(),nextShot=w.GquestNextShot or 0}
 end
 weapons.GetStored(class).WorldModel=path
end
print("GQUEST_FIT saved="..util.TableToJSON(state,false))
for class in pairs(state.weapons) do owner:GetWeapon(class):Remove() end
local attempts=0
local function restore()
 if not IsValid(owner) then return end
 attempts=attempts+1
 local complete=true
 for class,s in pairs(state.weapons) do
  if not s.restored then
   local w=owner:GetWeapon(class)
   if not IsValid(w) then local given=owner:Give(class);w=IsValid(given) and given or owner:GetWeapon(class) end
   if IsValid(w) then
    w.WorldModel=paths[class];w:SetModel(paths[class])
    w:SetArcLoaded(s.loaded);w:SetArcChambered(s.chambered);w:SetArcMagazine(s.magazine)
    w:SetClip1(s.loaded+s.chambered);w.GquestNextShot=s.nextShot;w:SyncAmmoFields()
    s.restored=true
   else complete=false end
  end
 end
 for ammo,count in pairs(state.ammo) do owner:SetAmmo(count,ammo) end
 if not complete then
  if attempts<20 then timer.Simple(0.1,restore) else print("GQUEST_FIT restore incomplete; saved state retained") end
  return
 end
 if selected then owner:SelectWeapon(selected) end
 print("GQUEST_FIT restored="..util.TableToJSON(state,false))
end
timer.Simple(0.2,restore)

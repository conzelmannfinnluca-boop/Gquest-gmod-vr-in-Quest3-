local panels,commands,selected={},{},{}
GquestWeapons=nil
function IsValid(v) return type(v)=="table" and not rawget(v,"closed") end
function ScrW() return 1200 end;function ScrH() return 1000 end
TOP=1;BOTTOM=2;FILL=3;LEFT=4
local methods={}
setmetatable(methods,{__index=function() return function() end end})
function methods:SetText(s) self.text=s end
function methods:Close() self.closed=true end
function methods:IsVisible() return not rawget(self,"closed") end
vgui={Create=function(kind,parent) local p=setmetatable({kind=kind,parent=parent},{__index=methods});panels[#panels+1]=p;return p end}
gui={HideGameUI=function() end}
concommand={Add=function(k,fn) commands[k]=fn end}
function RunConsoleCommand(cmd,arg) selected[#selected+1]={cmd,arg} end
assert(loadfile("work/gquest-ui/lua/autorun/client/gquest_weapon_catalog.lua"))()
commands.gquest_weapons();assert(GquestWeapons.IsMenuVisible())
local count=0
for _,p in ipairs(panels) do
 if p.kind=="DButton" and p.text~="Zurueck zum Spiel" and p.text~="Nachladen / HL2-Magazin auswerfen" then
  count=count+1;p.DoClick();local last=selected[#selected]
  assert(last[1]=="gquest_hl2_equip" and string.sub(last[2],1,7)=="weapon_")
 end
 assert(not string.find(rawget(p,"text") or "","ArcVR",1,true))
end
assert(count==11,"HL2 plus Physgun roster")
assert(not GquestWeapons.IsMenuVisible(),"selection must close menu")
print("PASS HL2-only catalog: eleven real weapon selections, no ArcVR control, selection closes tracked menu")

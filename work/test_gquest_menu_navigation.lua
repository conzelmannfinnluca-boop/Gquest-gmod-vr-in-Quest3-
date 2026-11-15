local commands,panels={},{}
local methods={}
function methods:SetText(text) self.text=text end
function methods:SetTitle(title) self.title=title end
function methods:SetSize(w,h) self.width=w;self.height=h end
function methods:GetWide() return self.width or 660 end
function methods:IsVisible() return self.valid~=false end
function methods:Close() self.valid=false end
function methods:Add(kind) return vgui.Create(kind,self) end
local function create(kind,parent)
 local panel=setmetatable({kind=kind,parent=parent,valid=true},{__index=function(_,key) return methods[key] or function() end end})
 panels[#panels+1]=panel;return panel
end
vgui={Create=create}
file={Read=function() end,Write=function() end}
concommand={Add=function(name,fn) commands[name]=fn end}
hook={Add=function() end}
timer={Simple=function(_,fn) fn() end}
gui={HideGameUI=function() end}
function IsValid(v) return type(v)=="table" and v.valid~=false end
function RealTime() return 0 end
function ScrW() return 1032 end
function ScrH() return 1104 end
function Color() return {} end
local ran={}
local h3Enabled=true
function RunConsoleCommand(...)
 local entry={...}
 ran[#ran+1]=entry
 if entry[1]=="gquest_h3_manual" then h3Enabled=entry[2]=="1" end
end
function GetConVar(name)
 if name=="gquest_h3_manual" then return {GetBool=function() return h3Enabled end} end
end
notification={AddLegacy=function() end}
GQUEST_WEAPON_ALIGN={BuildPanel=function(parent) return create("DPanel",parent) end}
dofile("work/gquest-ui/lua/autorun/client/gquest_vr_ui.lua")
local function click(text)
 for i=#panels,1,-1 do local p=panels[i];if p.text==text and p.valid then assert(type(p.DoClick)=="function");p.DoClick();return end end
 error("missing button "..text)
end
commands.gquest_menu();assert(GquestUI.IsMenuVisible())
click("Waffe ausrichten");assert(GquestUI.IsMenuVisible())
-- Executes the callback that previously called a nonexistent global openRoot.
click("Zurueck");assert(GquestUI.IsMenuVisible())
click("Zurueck zum Spiel");assert(not GquestUI.IsMenuVisible())
commands.gquest_menu();assert(GquestUI.IsMenuVisible())
click("Waffen");assert(not GquestUI.IsMenuVisible())
print("PASS menu callbacks: root -> alignment -> back -> close -> reopen -> weapons; exact former global-openRoot regression and visibility gate")

-- H3VR calibration must be usable with the controller alone: the measure button
-- closes the menu (the sampler needs a free support hand) and arms a delayed
-- measurement, the toggle flips the handling convar, and reset clears the well.
GquestH3={ReadHands=function() return nil end}
commands.gquest_menu();assert(GquestUI.IsMenuVisible())
ran={}
click("Magazinpunkt messen (5 s)")
assert(not GquestUI.IsMenuVisible(),"measuring closes the menu so the support hand is free")
assert(#ran==1 and ran[1][1]=="gquest_h3_sample","the button arms the sampler")
assert(ran[1][2]=="5" and ran[1][3]=="2" and ran[1][4]=="apply","5 s delay and apply mode")
commands.gquest_menu();assert(GquestUI.IsMenuVisible())
ran={}
click("Handling: AN")
assert(#ran==1 and ran[1][1]=="gquest_h3_manual" and ran[1][2]=="0","the toggle turns handling off")
click("Handling: AUS")
assert(#ran==2 and ran[2][2]=="1","the toggle turns handling back on")
ran={}
click("Magazinpunkt zuruecksetzen")
assert(#ran==1 and ran[1][1]=="gquest_h3_reset","reset clears the saved well")
-- Without the module the panel still arms the console path instead of doing nothing.
GquestH3=nil
commands.gquest_menu();ran={}
click("Magazinpunkt messen (5 s)")
assert(#ran==1 and ran[1][1]=="gquest_h3_sample","the module-less fallback still arms the sampler")
print("PASS H3VR menu: measure closes the menu and arms the delayed sampler, handling toggle, reset, module-less fallback")

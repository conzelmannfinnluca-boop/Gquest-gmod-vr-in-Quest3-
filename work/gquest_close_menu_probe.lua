if not CLIENT then return end
local function clickReturn(panel)
    for _,child in ipairs(panel:GetChildren()) do
        if child.GetText and child:GetText()=="Zurueck zum Spiel" then child:DoClick();return true end
        if clickReturn(child) then return true end
    end
end
for _,panel in ipairs(vgui.GetWorldPanel():GetChildren()) do
    if panel.GetTitle and panel:GetTitle()=="Gquest VR" and panel:IsVisible() then
        print("GQUEST_INPUT_PROBE closed_menu",clickReturn(panel))
    end
end
if IsValid(g_SpawnMenu) and g_SpawnMenu:IsVisible() then hook.Run("OnSpawnMenuClose") end
gui.HideGameUI()
timer.Simple(2,function() include("gquest_arcvr_runtime_probe.lua") end)

local function root()
    for _,p in ipairs(vgui.GetWorldPanel():GetChildren()) do
        if p.GetTitle and p:GetTitle()=="Gquest VR" and p:IsVisible() then return p end
    end
end
local function clickReturn(p)
    for _,child in ipairs(p:GetChildren()) do
        if child.GetText and child:GetText()=="Zurueck zum Spiel" then child:DoClick();return true end
        if clickReturn(child) then return true end
    end
end
RunConsoleCommand("gquest_menu")
timer.Simple(0.4,function()
    local frame=root()
    print("GQUEST_SMOKE opened",IsValid(frame))
    if IsValid(frame) then print("GQUEST_SMOKE return_clicked",clickReturn(frame)) end
end)
timer.Simple(2.4,function()
    print("GQUEST_SMOKE closed_stays_closed",not IsValid(root()))
    RunConsoleCommand("gquest_spawnmenu")
end)
timer.Simple(3.0,function()
    print("GQUEST_SMOKE spawn_visible",IsValid(g_SpawnMenu) and g_SpawnMenu:IsVisible())
end)
timer.Simple(4.0,function()
    if IsValid(g_SpawnMenu) and g_SpawnMenu:IsVisible() then RunConsoleCommand("gquest_spawnmenu") end
end)
timer.Simple(5.5,function() RunConsoleCommand("gquest_settings") end)

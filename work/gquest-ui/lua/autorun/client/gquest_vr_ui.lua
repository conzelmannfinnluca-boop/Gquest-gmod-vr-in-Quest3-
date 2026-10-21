-- Gquest's own client UI; native GDroid provides the tracked Derma surface.
local rootFrame,alignFrame
local openRoot
GquestUI=GquestUI or {}
function GquestUI.IsMenuVisible()
    return (IsValid(rootFrame) and rootFrame:IsVisible()) or (IsValid(alignFrame) and alignFrame:IsVisible()) or false
end
local menuBlockedUntil=0
local profilePath = "gquest_vr_profile.txt"
local tiers = { "1032x1104", "1548x1656", "1680x1760" }
local labels = { "Leistung", "Ausgewogen", "Schaerfer" }
local eyeTier, foveation, refresh = tiers[1], 2, 72
local saved = file.Read(profilePath, "DATA")
if saved then
    local parts = string.Explode("\n", saved)
    for _, tier in ipairs(tiers) do if parts[1] == tier then eyeTier = tier end end
    foveation = math.Clamp(tonumber(parts[2]) or 2, 0, 3)
    refresh = tonumber(parts[3]) == 90 and 90 or 72
end
local function saveProfile()
    file.Write(profilePath, eyeTier .. "\n" .. foveation .. "\n" .. refresh .. "\n")
end
local function closeRoot()
    menuBlockedUntil=RealTime()+1.25
    if IsValid(rootFrame) then rootFrame:Close() end
    rootFrame = nil
end
local function spawnToggle()
    closeRoot()
    gui.HideGameUI()
    if not IsValid(g_SpawnMenu) then
        notification.AddLegacy("Spawn-Menue ist in diesem Spielmodus nicht verfuegbar.", NOTIFY_ERROR, 4)
        return
    end
    if g_SpawnMenu:IsVisible() then hook.Run("OnSpawnMenuClose")
    else
        hook.Run("OnSpawnMenuOpen")
        timer.Simple(0.15,function()
            if IsValid(g_SpawnMenu) and g_SpawnMenu:IsVisible() then
                g_SpawnMenu:MakePopup()
                print("GQUEST_UI spawn focus acquired")
            end
        end)
    end
end
-- Runs the weapon-model report (gquest_weapon_models.lua) and shows its
-- summary in-headset. The report itself only reads and prints.
local function weaponModelCheck()
    local module = GQUEST_WEAPON_MODELS
    if not module or not module.Run then
        RunConsoleCommand("gquest_wmodel")
        notification.AddLegacy("Waffenmodelle werden geprueft, Ergebnis im Log.", NOTIFY_GENERIC, 4)
        return
    end
    local ok, matched, missingRight, missingLeft, partsMissing = pcall(module.Run, false)
    if not ok then
        notification.AddLegacy("Waffenmodell-Pruefung fehlgeschlagen: " .. tostring(matched), NOTIFY_ERROR, 6)
        return
    end
    local text = string.format("Waffenmodelle %d/12 ok, fehlend rechts %d / links %d, Teile fehlen %d",
        matched, missingRight, missingLeft, partsMissing)
    notification.AddLegacy(text, (missingRight + missingLeft + partsMissing) > 0 and NOTIFY_ERROR or NOTIFY_GENERIC, 8)
end
-- The alignment controls live in gquest_weapon_align.lua; this only hosts them
-- in a frame so the menu keeps one code path for opening and closing panels.
local function openAlign()
    local builder = GQUEST_WEAPON_ALIGN and GQUEST_WEAPON_ALIGN.BuildPanel
    if not builder then
        RunConsoleCommand("gquest_align")
        notification.AddLegacy("Ausrichtung nur per Konsole: gquest_align_status", NOTIFY_GENERIC, 5)
        return
    end
    closeRoot(); gui.HideGameUI()
    if IsValid(alignFrame) then alignFrame:Close() end
    alignFrame = vgui.Create("DFrame")
    alignFrame:SetTitle("Waffen ausrichten")
    alignFrame:SetSize(math.min(660, ScrW() - 48), math.min(660, ScrH() - 48))
    alignFrame:Center(); alignFrame:SetDeleteOnClose(true); alignFrame:MakePopup()
    alignFrame:SetKeyboardInputEnabled(false)
    alignFrame:SetMouseInputEnabled(true)
    local frame = alignFrame
    timer.Simple(0.15, function()
        if not IsValid(frame) then return end
        frame:MakePopup(); frame:SetKeyboardInputEnabled(false)
        frame:SetMouseInputEnabled(true); frame:MoveToFront()
        print("GQUEST_UI align focus acquired")
    end)
    local back = vgui.Create("DButton", frame); back:Dock(TOP); back:SetTall(46)
    back:SetText("Zurueck")
    back.DoClick = function() frame:Close(); openRoot(true) end
    local panel = builder(frame)
    panel:Dock(FILL)
    print("GQUEST_UI align opened")
end
local function settingsPanel(parent)
    local panel = vgui.Create("DScrollPanel", parent)
    local y = 12
    local function text(value, height)
        local label = panel:Add("DLabel")
        label:SetText(value); label:SetFont("DermaDefaultBold"); label:SetWrap(true)
        label:SetTextColor(Color(235,235,235)); label:SetPos(16,y); label:SetSize(580,height)
        y = y + height + 12
    end
    local function combo(title, choices, selected, changed)
        text(title,24)
        local box = panel:Add("DComboBox"); box:SetPos(16,y); box:SetSize(560,42)
        box:SetSortItems(false)
        for _, entry in ipairs(choices) do box:AddChoice(entry[1],entry[2],entry[2]==selected) end
        box.OnSelect = function(_,_,_,data) changed(data) end
        y = y + 58
    end
    text("VR-Einstellungen",32)
    combo("Bildprofil (nach Neustart)", {
        {labels[1].." - 1032 x 1104",tiers[1]}, {labels[2].." - 1548 x 1656",tiers[2]}, {labels[3].." - 1680 x 1760",tiers[3]}
    },eyeTier,function(value) eyeTier=value; saveProfile(); RunConsoleCommand("vr_eye_resolution",value) end)
    combo("Randaufloesung: mehr Reduktion spart Grafikleistung", {
        {"Keine Reduktion",0},{"Wenig",1},{"Mittel",2},{"Stark",3}
    },foveation,function(value) foveation=value; saveProfile(); RunConsoleCommand("vr_ffr_level",tostring(value)) end)
    combo("Bildwiederholrate", {{"72 Hz",72},{"90 Hz",90}},refresh,function(value)
        refresh=value; saveProfile(); RunConsoleCommand("vr_refresh_rate",tostring(value))
    end)
    text("Waffenmodelle",28)
    text("Prueft im laufenden Spiel, welches Handmodell jede Waffe tatsaechlich benutzt und ob alle Modelle geladen werden. Das Ergebnis steht im Log und in data/gquest/weapon_models.json.",76)
    local modelCheck=panel:Add("DButton"); modelCheck:SetText("Waffenmodelle pruefen")
    modelCheck:SetPos(16,y); modelCheck:SetSize(560,46)
    modelCheck.DoClick=weaponModelCheck
    y = y + 58
    text("Ausrichtung",28)
    text("Waffenhaltung pro Modell pruefen und feinjustieren. Die native Quest-Darstellung wird nicht von jeder VRMod-Einstellung beeinflusst.",76)
    local alignButton=panel:Add("DButton"); alignButton:SetText("Waffe ausrichten")
    alignButton:SetPos(16,y); alignButton:SetSize(560,46)
    alignButton.DoClick=openAlign
    y = y + 58
    text("Leistung liefert ein weicheres Bild. Ausgewogen und Schaerfer kosten mehr GPU-Zeit. Das Bildprofil wird beim naechsten Start angewendet.",76)
    local reset=panel:Add("DButton"); reset:SetText("Empfohlene Einstellungen wiederherstellen")
    reset:SetPos(16,y); reset:SetSize(560,46)
    reset.DoClick=function()
        eyeTier=tiers[1]; foveation=2; refresh=72; saveProfile()
        RunConsoleCommand("vr_ffr_level","2"); RunConsoleCommand("vr_refresh_rate","72")
        notification.AddLegacy("Gespeichert. Bildprofil gilt nach Neustart.",NOTIFY_GENERIC,4)
    end
    return panel
end
openRoot=function(settings)
    closeRoot(); gui.HideGameUI()
    rootFrame=vgui.Create("DFrame")
    rootFrame:SetTitle("Gquest VR"); rootFrame:SetSize(math.min(680,ScrW()-48),math.min(680,ScrH()-48))
    rootFrame:Center(); rootFrame:SetDeleteOnClose(true); rootFrame:MakePopup()
    rootFrame:SetKeyboardInputEnabled(false)
    rootFrame:SetMouseInputEnabled(true); rootFrame:MoveToFront()
    local frame=rootFrame
    timer.Simple(0.15,function()
        if not IsValid(frame) or frame~=rootFrame then return end
        frame:MakePopup(); frame:SetKeyboardInputEnabled(false)
        frame:SetMouseInputEnabled(true); frame:MoveToFront()
        print("GQUEST_UI focus acquired")
    end)
    local buttons=vgui.Create("DPanel",rootFrame); buttons:Dock(TOP); buttons:SetTall(54)
    -- Four buttons share the row; the previous fixed 196 px would overflow the
    -- frame width once a fourth control was added.
    local buttonWidth=math.max(140, math.floor(rootFrame:GetWide()/4)-8)
    local function button(title,action)
        local b=vgui.Create("DButton",buttons); b:Dock(LEFT); b:DockMargin(4,4,4,4); b:SetWide(buttonWidth); b:SetText(title); b.DoClick=function() print("GQUEST_UI click="..title); action() end
    end
    button("Spawn-Menue",spawnToggle)
    button("VR-Einstellungen",function() openRoot(true) end)
    button("Waffen",function() closeRoot();RunConsoleCommand("gquest_weapons") end)
    button("Zurueck zum Spiel",function() closeRoot(); gui.HideGameUI() end)
    local panel=settingsPanel(rootFrame); panel:Dock(FILL)
    print("GQUEST_UI opened settings="..tostring(settings==true))
end
concommand.Add("gquest_menu",function() openRoot(false) end)
concommand.Add("gquest_settings",function() openRoot(true) end)
concommand.Add("gquest_spawnmenu",spawnToggle)
hook.Add("AddToolMenuCategories","GquestCategory",function()
    spawnmenu.AddToolCategory("Utilities","Gquest","Gquest")
end)
hook.Add("PopulateToolMenu","GquestSettings",function()
    spawnmenu.AddToolMenuOption("Utilities","Gquest","GquestVRSettings","VR-Einstellungen","","",function(panel)
        panel:ClearControls()
        panel:Button("VR-Einstellungen oeffnen","gquest_settings")
        panel:Button("Gquest-Menue oeffnen","gquest_menu")
        panel:Button("Waffenmodelle pruefen","gquest_wmodel")
        panel:Button("Waffe ausrichten","gquest_align")
        panel:Help("Ausrichtung: gespeicherte Werte in data/gquest/weapon_align.json.")
        panel:Help("Bildprofil, Randaufloesung und Bildwiederholrate fuer Quest.")
        panel:Help("Waffenmodell-Bericht: gquest_wmodel oder gquest_wmodel_verbose.")
    end)
end)
if spawnmenu and spawnmenu.AddCreationTab then
    spawnmenu.AddCreationTab("Gquest VR",function()
        local panel=vgui.Create("DPanel")
        local button=vgui.Create("DButton",panel); button:Dock(TOP); button:SetTall(64)
        button:SetText("Gquest VR-Einstellungen"); button.DoClick=function() openRoot(true) end
        return panel
    end,"icon16/controller.png",99,"Quest VR-Einstellungen")
end
local gameUIWasVisible=false
hook.Add("Think","GquestPauseMenu",function()
    local visible=gui.IsGameUIVisible()
    local spawnVisible=IsValid(g_SpawnMenu) and g_SpawnMenu:IsVisible()
    if visible and not gameUIWasVisible and IsValid(LocalPlayer()) and
        RealTime()>menuBlockedUntil and not spawnVisible then
        if not IsValid(rootFrame) then openRoot(false)
        end
    end
    gameUIWasVisible=gui.IsGameUIVisible()
end)
-- The native PANEL menu and Lua Derma must not compete for controller input.
RunConsoleCommand("vr_panel_menu_auto","0")
RunConsoleCommand("gmod_derma_vr_debug","1")
RunConsoleCommand("cl_drawhud","1")
RunConsoleCommand("vr_hud_in_world","1")
RunConsoleCommand("vr_weapon_hud","1")
print("GQUEST_UI ready: settings and spawn-menu controls registered")

local lastWeapon
hook.Add("Think","GquestWeaponDiagnostic",function()
    local player=LocalPlayer()
    if not IsValid(player) then return end
    local weapon=player:GetActiveWeapon()
    if not IsValid(weapon) or weapon==lastWeapon then return end
    lastWeapon=weapon
    print("GQUEST_WEAPON class="..weapon:GetClass().." model="..tostring(weapon:GetModel()).." world="..tostring(weapon.WorldModel).." view="..tostring(weapon.ViewModel))
end)

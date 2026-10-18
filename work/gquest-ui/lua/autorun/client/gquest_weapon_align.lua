-- Gquest: in-hand alignment for the 12 VR weapon models.
--
-- Why this exists: vrmod's own defaults (vrmod/vrmod_weapons_config.json) carry
-- offsets tuned for the stock v_* viewmodels, e.g. weapon_physgun -31.5/13.4/14.5.
-- The port's weapon scripts now select models/weapons/vr_*.mdl, and every one of
-- those models carries its grip attachment within a few units of its own origin
-- (outputs/Gquest-weapon-model-audit.md). Keeping the old offsets therefore
-- moves each gun by tens of units off the hand.
--
-- What this does: for every class whose script model is a vr_* model it clears
-- that stale offset and lays the weapon on the hand origin, then reapplies any
-- fine tuning the user saved. Nothing is invented: a class is only touched when
-- its script really names a vr_* model that ships.
--
-- Commands
--   gquest_align                  align the active weapon and print its values
--   gquest_align_move x y z      nudge in hand space (units)
--   gquest_align_rot p y r       nudge rotation (degrees)
--   gquest_align_step n          nudge step for the panel (default 0.5 / 1 deg)
--   gquest_align_save            persist the active weapon's values
--   gquest_align_reset           drop the active weapon's tuning
--   gquest_align_all             reset all 12 weapons to the hand origin
--   gquest_align_status          print every class and its current values
--   gquest_align_baseline 0|1    disable/enable the automatic baseline
--
-- Saved values: data/gquest/weapon_align.json (also readable over adb) and,
-- through vrmod's own API, its normal weapon config so both stay in sync.

local SAVE_PATH = "gquest/weapon_align.json"
local BASELINE_CVAR = "gquest_weapon_align_baseline"

-- Class -> the vr_* model its own weapon script selects.
local VR_CLASSES = {
    weapon_357 = "models/weapons/vr_357.mdl",
    weapon_ar2 = "models/weapons/vr_irifle.mdl",
    weapon_bugbait = "models/weapons/vr_bugbait.mdl",
    weapon_crossbow = "models/weapons/vr_crossbow.mdl",
    weapon_crowbar = "models/weapons/vr_crowbar.mdl",
    weapon_frag = "models/weapons/vr_grenade.mdl",
    weapon_physcannon = "models/weapons/vr_physcannon.mdl",
    weapon_physgun = "models/weapons/vr_superphyscannon.mdl",
    weapon_pistol = "models/weapons/vr_pistol.mdl",
    weapon_rpg = "models/weapons/vr_rocket_launcher.mdl",
    weapon_shotgun = "models/weapons/vr_shotgun.mdl",
    weapon_smg1 = "models/weapons/vr_smg.mdl",
}

local STOCK_OFFSETS = {
    weapon_physgun = { -31.5, 13.4, 14.5 },
    weapon_physcannon = { -31.5, 13.4, 10.5 },
    weapon_shotgun = { -14.5, 10, 8.5 },
    weapon_crossbow = { -14.5, 10, 8.5 },
    weapon_rpg = { -27.5, 19, 10.5 },
}

local function convarInt(name, fallback)
    local convar = GetConVar(name)
    return convar and convar:GetInt() or fallback
end

local stepPosition, stepAngle = 0.5, 1

local saved = {classes = {}}

local function loadSaved()
    saved = {classes = {}}
    local text = file.Read(SAVE_PATH, "DATA")
    if not text or text == "" then return end
    local parsed = util.JSONToTable(text)
    if type(parsed) ~= "table" or type(parsed.classes) ~= "table" then return end
    saved = parsed
end

local function writeSaved()
    if not file.IsDir("gquest", "DATA") then file.CreateDir("gquest") end
    file.Write(SAVE_PATH, util.TableToJSON(saved, true) or "{}")
end

-- vrmod owns the actual hand transform; every write goes through its API so a
-- running VR session and its own weapon config stay consistent.
local function api()
    if type(vrmod) ~= "table" or type(g_VR) ~= "table" then return nil end
    return vrmod
end

local function entryFor(class, create)
    local module = api()
    if module then
        if create and module.EnsureWeaponViewModelEntry then
            return module.EnsureWeaponViewModelEntry(class)
        end
        if module.GetWeaponViewModelEntry then
            return module.GetWeaponViewModelEntry(class)
        end
    end
    -- Fallback for a build whose vrmod does not expose the public API: the
    -- table it reads is the same one, so writing it directly is equivalent.
    if type(g_VR) ~= "table" then return nil end
    g_VR.viewModelInfo = g_VR.viewModelInfo or {}
    local entry = g_VR.viewModelInfo[class]
    if not entry and not create then return nil end
    entry = entry or {}
    g_VR.viewModelInfo[class] = entry
    return entry
end

local function applyValues(class, pos, ang, persist)
    local entry = entryFor(class, true)
    if not entry then return false end
    entry.offsetPos = Vector(pos[1] or 0, pos[2] or 0, pos[3] or 0)
    entry.offsetAng = Angle(ang[1] or 0, ang[2] or 0, ang[3] or 0)
    local module = api()
    if module and module.ApplyWeaponViewModelLive then pcall(module.ApplyWeaponViewModelLive, class) end
    if persist then writeSaved() end
    return true
end

local function currentValues(class)
    local entry = entryFor(class, false)
    if not entry then return nil end
    local pos = entry.offsetPos or Vector(0, 0, 0)
    local ang = entry.offsetAng or Angle(0, 0, 0)
    return {pos.x, pos.y, pos.z}, {ang.p, ang.y, ang.r}
end

local function describe(class)
    local pos, ang = currentValues(class)
    if not pos then return class .. ": keine vrmod-Einstellung" end
    return string.format("%s pos=%.2f,%.2f,%.2f ang=%.2f,%.2f,%.2f %s",
        class, pos[1], pos[2], pos[3], ang[1], ang[2], ang[3],
        VR_CLASSES[class] and "" or "(kein VR-Modell)")
end

-- Replaces the stock-viewmodel offset with the model's own grip frame: for the
-- vr_* models that is the hand origin, and any value the user saved wins.
local function applyBaseline(class, force)
    if not VR_CLASSES[class] then return false end
    if convarInt(BASELINE_CVAR, 1) == 0 and not force then return false end
    local custom = saved.classes[class]
    if custom and custom.pos and custom.ang then
        return applyValues(class, custom.pos, custom.ang, false)
    end
    return applyValues(class, {0, 0, 0}, {0, 0, 0}, false)
end

local function applyAll()
    local changed = 0
    for class in pairs(VR_CLASSES) do
        if applyBaseline(class) then changed = changed + 1 end
    end
    return changed
end

local function contentChecked(class)
    local path = VR_CLASSES[class]
    if not path then return false, "kein VR-Modell eingetragen" end
    if not file.Exists(path, "GAME") then return false, path .. " fehlt" end
    return true, path
end

local function activeClass()
    local player = LocalPlayer()
    local weapon = IsValid(player) and player:GetActiveWeapon() or NULL
    return IsValid(weapon) and weapon:GetClass() or nil
end

local function report(class, note)
    local ok, path = contentChecked(class)
    local pos, ang = currentValues(class)
    local line = string.format("GQUEST_ALIGN class=%s model=%s model_present=%s note=%s",
        class, tostring(path), tostring(ok), note or "-")
    if pos then
        line = line .. string.format(" pos=%.3f,%.3f,%.3f ang=%.3f,%.3f,%.3f",
            pos[1], pos[2], pos[3], ang[1], ang[2], ang[3])
    end
    print(line)
    return ok
end

local function nudge(class, dPos, dAng)
    local pos, ang = currentValues(class)
    if not pos then
        notification.AddLegacy("Keine vrmod-Einstellung fuer " .. class, NOTIFY_ERROR, 4)
        return false
    end
    applyValues(class,
        {pos[1] + (dPos[1] or 0) * stepPosition, pos[2] + (dPos[2] or 0) * stepPosition, pos[3] + (dPos[3] or 0) * stepPosition},
        {ang[1] + (dAng[1] or 0) * stepAngle, ang[2] + (dAng[2] or 0) * stepAngle, ang[3] + (dAng[3] or 0) * stepAngle},
        false)
    report(class, "nudge")
    return true
end

local function saveClass(class)
    local pos, ang = currentValues(class)
    if not pos then return false end
    saved.classes[class] = {pos = pos, ang = ang, at = os.time()}
    writeSaved()
    local module = api()
    if module and module.SaveWeaponViewModelConfig then pcall(module.SaveWeaponViewModelConfig) end
    report(class, "saved")
    notification.AddLegacy("Gespeichert: " .. class, NOTIFY_GENERIC, 3)
    return true
end

local function resetClass(class)
    saved.classes[class] = nil
    writeSaved()
    applyBaseline(class, true)
    report(class, "reset")
    return true
end

concommand.Add("gquest_align", function()
    local class = activeClass()
    if not class then
        notification.AddLegacy("Keine Waffe in der Hand.", NOTIFY_ERROR, 3)
        return
    end
    if not currentValues(class) then applyBaseline(class) end
    report(class, "active")
end)

concommand.Add("gquest_align_move", function(_, _, arguments)
    local class = activeClass()
    if not class then return end
    nudge(class, {tonumber(arguments and arguments[1] or "") or 0,
        tonumber(arguments and arguments[2] or "") or 0,
        tonumber(arguments and arguments[3] or "") or 0}, {0, 0, 0})
end)

concommand.Add("gquest_align_rot", function(_, _, arguments)
    local class = activeClass()
    if not class then return end
    nudge(class, {0, 0, 0}, {tonumber(arguments and arguments[1] or "") or 0,
        tonumber(arguments and arguments[2] or "") or 0,
        tonumber(arguments and arguments[3] or "") or 0})
end)

concommand.Add("gquest_align_step", function(_, _, arguments)
    local value = tonumber(arguments and arguments[1] or "")
    if value and value > 0 then
        stepPosition = value
        stepAngle = math.max(0.1, value)
    end
    print(string.format("GQUEST_ALIGN step pos=%.2f ang=%.2f", stepPosition, stepAngle))
end)

concommand.Add("gquest_align_save", function()
    local class = activeClass()
    if class then saveClass(class) end
end)

concommand.Add("gquest_align_reset", function()
    local class = activeClass()
    if class then resetClass(class) end
end)

concommand.Add("gquest_align_all", function()
    for class in pairs(VR_CLASSES) do saved.classes[class] = nil end
    writeSaved()
    local changed = applyAll()
    print(string.format("GQUEST_ALIGN all reset classes=%d", changed))
    notification.AddLegacy("Alle VR-Waffen auf Handursprung gesetzt.", NOTIFY_GENERIC, 4)
end)

concommand.Add("gquest_align_status", function()
    print("GQUEST_ALIGN STATUS BEGIN")
    for class in pairs(VR_CLASSES) do print("GQUEST_ALIGN " .. describe(class)) end
    print(string.format("GQUEST_ALIGN STATUS baseline=%d saved=%d", convarInt(BASELINE_CVAR, 1),
        table.Count(saved.classes)))
    print("GQUEST_ALIGN STATUS END")
end)

CreateClientConVar(BASELINE_CVAR, "1", true, false,
    "Set the 12 VR weapon models on the hand origin instead of the stock-viewmodel offsets.")

-- The convar is its own command; the callback keeps a live toggle consistent
-- without registering a second, conflicting console command.
cvars.AddChangeCallback(BASELINE_CVAR, function(_, _, value)
    local enabled = tonumber(value) ~= 0
    print(string.format("GQUEST_ALIGN baseline=%d", enabled and 1 or 0))
    if enabled then applyAll() else report(activeClass() or "-", "baseline off") end
end)

-- Panel: same Derma pattern as the rest of the port's own UI, so the tracked
-- controller pointer reaches every button.
local function alignPanel(parent)
    local panel = vgui.Create("DScrollPanel", parent)
    local y = 12
    local function line(value, height)
        local label = panel:Add("DLabel")
        label:SetText(value); label:SetFont("DermaDefaultBold"); label:SetWrap(true)
        label:SetTextColor(Color(235, 235, 235)); label:SetPos(16, y); label:SetSize(580, height)
        y = y + height + 10
    end
    local function button(title, action, width)
        local button_ = panel:Add("DButton")
        button_:SetText(title); button_:SetPos(16, y); button_:SetSize(width or 178, 44)
        button_.DoClick = function() print("GQUEST_UI click=" .. title); action() end
        return button_
    end
    line("Waffe ausrichten", 30)
    local state = panel:Add("DLabel")
    state:SetFont("DermaDefaultBold"); state:SetPos(16, y); state:SetSize(580, 46); state:SetWrap(true)
    state:SetTextColor(Color(235, 235, 235)); y = y + 56
    local function refresh()
        local class = activeClass() or "-"
        local pos, ang = class ~= "-" and currentValues(class) or nil
        if pos then
            state:SetText(string.format("%s\npos %.2f, %.2f, %.2f   ang %.2f, %.2f, %.2f",
                class, pos[1], pos[2], pos[3], ang[1], ang[2], ang[3]))
        else
            state:SetText(class .. "\nkeine vrmod-Einstellung")
        end
    end
    local function move(dx, dy, dz, dp, dy2, dr, label)
        local class = activeClass()
        if not class then return end
        if not currentValues(class) then applyBaseline(class) end
        nudge(class, {dx, dy, dz}, {dp, dy2, dr})
        refresh()
    end
    local axes = {
        {"Links", -1, 0, 0, 0, 0, 0}, {"Rechts", 1, 0, 0, 0, 0, 0},
        {"Naeher", 0, 1, 0, 0, 0, 0}, {"Weiter", 0, -1, 0, 0, 0, 0},
        {"Hoeher", 0, 0, 1, 0, 0, 0}, {"Tiefer", 0, 0, -1, 0, 0, 0},
        {"Nick +", 0, 0, 0, 1, 0, 0}, {"Nick -", 0, 0, 0, -1, 0, 0},
        {"Gier +", 0, 0, 0, 0, 1, 0}, {"Gier -", 0, 0, 0, 0, -1, 0},
        {"Roll +", 0, 0, 0, 0, 0, 1}, {"Roll -", 0, 0, 0, 0, 0, -1},
    }
    local width = 136
    for index, entry in ipairs(axes) do
        local label = entry[1]
        local a, b, c, d, e, f = entry[2], entry[3], entry[4], entry[5], entry[6], entry[7]
        local button_ = button(label, function() move(a, b, c, d, e, f, label) end, width)
        local column = (index - 1) % 4
        local row = math.floor((index - 1) / 4)
        button_:SetPos(16 + column * (width + 8), y + row * 50)
        if index == #axes then y = y + 3 * 50 end
    end
    y = y + 8
    local save = button("Speichern", function() local class = activeClass(); if class then saveClass(class); refresh() end end)
    save:SetPos(16, y)
    local reset = button("Zuruecksetzen", function() local class = activeClass(); if class then resetClass(class); refresh() end end)
    reset:SetPos(16 + 186, y)
    local all = button("Alle 12 zuruecksetzen", function() RunConsoleCommand("gquest_align_all"); refresh() end, 178)
    all:SetPos(16 + 372, y)
    y = y + 52
    line("Schrittweite: " .. stepPosition .. " Einheiten / " .. stepAngle .. " Grad (gquest_align_step 1). " ..
        "Der Knopf wirkt auf die gerade gehaltene Waffe; Speichern gilt nur fuer sie.", 52)
    timer.Create("GquestAlignRefresh", 0.5, 0, function()
        if not IsValid(panel) then timer.Remove("GquestAlignRefresh") return end
        refresh()
    end)
    refresh()
    return panel
end

GQUEST_WEAPON_ALIGN = GQUEST_WEAPON_ALIGN or {}
GQUEST_WEAPON_ALIGN.ApplyAll = applyAll
GQUEST_WEAPON_ALIGN.Classes = VR_CLASSES
GQUEST_WEAPON_ALIGN.BuildPanel = alignPanel

loadSaved()

-- vrmod loads its config at file scope and again on VRMod_Start, and the saved
-- config is merged over the defaults, so the baseline has to be applied after
-- both. Timers cover the case where the mod starts a moment later than us.
local function startBaseline()
    if type(g_VR) ~= "table" then
        print("GQUEST_ALIGN vrmod/Tabelle nicht geladen; Ausrichtung inaktiv")
        return
    end
    local changed = applyAll()
    print(string.format("GQUEST_ALIGN baseline applied classes=%d baseline_cvar=%d api=%s",
        changed, convarInt(BASELINE_CVAR, 1), api() and "vrmod" or "raw g_VR"))
end

hook.Add("VRMod_Start", "GquestWeaponAlignBaseline", function()
    timer.Simple(0, startBaseline)
    timer.Simple(1, startBaseline)
end)

hook.Add("PlayerSwitchWeapon", "GquestWeaponAlignBaseline", function(player, old, new)
    if player ~= LocalPlayer() or not IsValid(new) then return end
    -- Report only: re-baselining here would discard unsaved tuning each switch.
    timer.Simple(0, function() report(new:GetClass(), "switch") end)
end)

timer.Simple(2, startBaseline)
print("GQUEST_ALIGN ready: gquest_align / gquest_align_status / gquest_align_save")

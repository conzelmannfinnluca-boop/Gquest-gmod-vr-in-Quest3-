-- Gquest: in-headset weapon-model verification.
--
-- The port picks each weapon's in-hand model from the weapon script's vrmodel /
-- vrmodel_l keys, and its physical parts (magazine, slide, foregrip, shell) from
-- a fixed part-model convention. This file answers, on the real device, the two
-- questions that cannot be answered offline: which model each weapon actually
-- resolves to, and whether every one of those files really loads there.
--
-- Console: gquest_wmodel / gquest_wmodel_verbose (the plain form also runs by
-- itself 20 s after the map loads)
-- Output : prints GQUEST_WMODEL lines and writes data/gquest/weapon_models.json
--
-- The report never changes a weapon, model or cvar; it only reads and reports.

local EXPECTED = {
    {class = "weapon_357", stem = "357"},
    {class = "weapon_ar2", stem = "irifle"},
    {class = "weapon_bugbait", stem = "bugbait"},
    {class = "weapon_crossbow", stem = "crossbow"},
    {class = "weapon_crowbar", stem = "crowbar"},
    {class = "weapon_frag", stem = "grenade"},
    {class = "weapon_physcannon", stem = "physcannon"},
    {class = "weapon_physgun", stem = "superphyscannon"},
    {class = "weapon_pistol", stem = "pistol"},
    {class = "weapon_rpg", stem = "rocket_launcher"},
    {class = "weapon_shotgun", stem = "shotgun"},
    {class = "weapon_smg1", stem = "smg"},
}

-- Part models the shipped client logs for by name ("VRWEAP-PART: ..."), taken
-- from the device log so this check follows the engine instead of a guess.
local PARTS = {
    "models/weapons/vr_357_reloader.mdl",
    "models/weapons/left_handed/vr_357_reloader_l.mdl",
    "models/weapons/vr_crossbow_rebar.mdl",
    "models/weapons/left_handed/vr_crossbow_rebar_l.mdl",
    "models/weapons/vr_irifle_clip.mdl",
    "models/weapons/left_handed/vr_irifle_clip_l.mdl",
    "models/weapons/vr_pistol_clip.mdl",
    "models/weapons/left_handed/vr_pistol_clip_l.mdl",
    "models/weapons/vr_pistol_slide.mdl",
    "models/weapons/left_handed/vr_pistol_slide_l.mdl",
    "models/weapons/vr_rocket_launcher_missile.mdl",
    "models/weapons/left_handed/vr_rocket_launcher_missile_l.mdl",
    "models/weapons/vr_shotgun_foregrip.mdl",
    "models/weapons/left_handed/vr_shotgun_foregrip_l.mdl",
    "models/weapons/vr_shotgun_shell.mdl",
    "models/weapons/left_handed/vr_shotgun_shell_l.mdl",
    "models/weapons/vr_smg_charginghandle.mdl",
    "models/weapons/left_handed/vr_smg_charginghandle_l.mdl",
    "models/weapons/vr_smg_clip.mdl",
    "models/weapons/left_handed/vr_smg_clip_l.mdl",
    "models/weapons/vr_smg_foregrip.mdl",
    "models/weapons/left_handed/vr_smg_foregrip_l.mdl",
}

local CVARS = {
    "hlvr_grip_yaw_correction",
    "vr_first_person_uses_world_model",
    "cl_first_person_uses_world_model",
    "vr_custom_mod_world_model_in_hand",
    "vr_custom_mod_force_world_model_in_hand",
    "vr_viewmodel_offset_forward",
    "vr_viewmodel_offset_forward_large",
    "vr_controller_offset_x",
    "vr_controller_offset_y",
    "vr_controller_offset_z",
    "vr_controller_offset_pitch",
    "vr_controller_offset_yaw",
    "vr_controller_offset_roll",
}

local function vec(value)
    if not value then return nil end
    return {x = value.x, y = value.y, z = value.z}
end

local function ang(value)
    if not value then return nil end
    return {p = value.p, y = value.y, r = value.r}
end

-- A weapon script's model keys may sit at the top level or inside a nested
-- block (the retail scripts wrap everything in "WeaponData"), and
-- util.KeyValuesToTable lowercases keys, so the key is searched recursively
-- instead of assuming one shape.
local function findKey(table_, wanted, depth)
    if type(table_) ~= "table" or (depth or 0) > 4 then return nil end
    for key, value in pairs(table_) do
        if type(key) == "string" and string.lower(key) == wanted and type(value) == "string" then
            return value
        end
    end
    for _, value in pairs(table_) do
        if type(value) == "table" then
            local found = findKey(value, wanted, (depth or 0) + 1)
            if found then return found end
        end
    end
    return nil
end

local function cvarString(name)
    local convar = GetConVar(name)
    return convar and convar:GetString() or "absent"
end

-- Read a weapon script once. util.KeyValuesToTable returns nil for a malformed
-- file; then the raw expressions are reported instead of a fabricated model.
local function readScript(path)
    local text = file.Read(path, "GAME")
    if not text then return {unreadable = true} end
    local data = util.KeyValuesToTable(text)
    local entry = {text = text}
    if data then
        entry.vrmodel = findKey(data, "vrmodel")
        entry.vrmodel_l = findKey(data, "vrmodel_l")
        if not entry.vrmodel then entry.note = "no vrmodel key" end
    else
        entry.note = "keyvalues parse failed"
        entry.vrmodel = string.match(text, "\"vrmodel\"%s*\"([^\"]+)\"")
        entry.vrmodel_l = string.match(text, "\"vrmodel_l\"%s*\"([^\"]+)\"")
    end
    return entry
end

local function clientModelInfo(path)
    if not path or path == "" then return {loaded = false, reason = "no path"} end
    if not file.Exists(path, "GAME") then return {loaded = false, reason = "missing on GAME"} end
    local model = ClientsideModel(path, RENDERGROUP_VIEWMODEL)
    if not IsValid(model) then return {loaded = false, reason = "ClientsideModel failed"} end
    local info = {
        loaded = true,
        attachments = {},
        bounds = {min = vec(model:OBBMins()), max = vec(model:OBBMaxs())},
        scale = model:GetModelScale(),
    }
    for _, entry in ipairs(model:GetAttachments() or {}) do
        info.attachments[#info.attachments + 1] = {
            name = entry.name, id = entry.id,
            position = vec(entry.Pos), angles = ang(entry.Ang),
        }
    end
    if info.bounds.min and info.bounds.max then
        info.bounds.size = {
            x = info.bounds.max.x - info.bounds.min.x,
            y = info.bounds.max.y - info.bounds.min.y,
            z = info.bounds.max.z - info.bounds.min.z,
        }
    end
    model:Remove()
    return info
end

local function buildReport()
    local report = {time = os.time(), realm = CLIENT and "client" or "server", weapons = {}, parts = {}, cvars = {}, active = nil}
    for _, entry in ipairs(EXPECTED) do
        local script = "scripts/" .. entry.class .. ".txt"
        local parsed = readScript(script)
        local right, left = parsed.vrmodel, parsed.vrmodel_l
        local expectedRight = "models/weapons/vr_" .. entry.stem .. ".mdl"
        local expectedLeft = "models/weapons/left_handed/vr_" .. entry.stem .. "_l.mdl"
        report.weapons[#report.weapons + 1] = {
            class = entry.class,
            script = script,
            unreadable = parsed.unreadable or false,
            parse_note = parsed.note,
            vrmodel = right,
            vrmodel_l = left,
            expected_vrmodel = expectedRight,
            expected_vrmodel_l = expectedLeft,
            matches_expected = right == expectedRight and left == expectedLeft,
            right_loads = file.Exists(right or "", "GAME"),
            left_loads = file.Exists(left or "", "GAME"),
        }
    end
    for _, path in ipairs(PARTS) do
        report.parts[#report.parts + 1] = {model = path, loads = file.Exists(path, "GAME")}
    end
    for _, name in ipairs(CVARS) do report.cvars[name] = cvarString(name) end

    local player = LocalPlayer()
    local weapon = IsValid(player) and player:GetActiveWeapon() or NULL
    if IsValid(weapon) then
        local parsed = readScript("scripts/" .. weapon:GetClass() .. ".txt")
        report.active = {
            class = weapon:GetClass(),
            entity_model = weapon:GetModel(),
            script_model = parsed.vrmodel,
            script_model_l = parsed.vrmodel_l,
            entity_uses_expected = weapon:GetModel() == parsed.vrmodel,
        }
    end
    return report
end

local function writeReport(report)
    if not file.IsDir("gquest", "DATA") then file.CreateDir("gquest") end
    file.Write("gquest/weapon_models.json", util.TableToJSON(report, true) or "{}")
end

local function summarise(report, verbose)
    local matched, missingRight, missingLeft = 0, 0, 0
    for _, entry in ipairs(report.weapons) do
        if entry.matches_expected then matched = matched + 1 end
        if not entry.right_loads then missingRight = missingRight + 1 end
        if not entry.left_loads then missingLeft = missingLeft + 1 end
        if verbose or not entry.matches_expected or not entry.right_loads or not entry.left_loads then
            print(string.format(
                "GQUEST_WMODEL %s script=%s right=%s loads=%s left=%s loads=%s expected=%s",
                entry.class, entry.script, tostring(entry.vrmodel), tostring(entry.right_loads),
                tostring(entry.vrmodel_l), tostring(entry.left_loads), tostring(entry.matches_expected)))
        end
    end
    local partsMissing = 0
    for _, entry in ipairs(report.parts) do
        if not entry.loads then
            partsMissing = partsMissing + 1
            print("GQUEST_WMODEL part missing " .. entry.model)
        end
    end
    print(string.format(
        "GQUEST_WMODEL SUMMARY weapons=%d matched=%d right_missing=%d left_missing=%d parts=%d parts_missing=%d",
        #report.weapons, matched, missingRight, missingLeft, #report.parts, partsMissing))
    if report.active then
        print(string.format("GQUEST_WMODEL ACTIVE class=%s entity_model=%s script_model=%s uses_expected=%s",
            report.active.class, tostring(report.active.entity_model),
            tostring(report.active.script_model), tostring(report.active.entity_uses_expected)))
    end
    return matched, missingRight, missingLeft, partsMissing
end

local function run(verbose)
    local report = buildReport()
    print("GQUEST_WMODEL BEGIN")
    local matched, missingRight, missingLeft, partsMissing = summarise(report, verbose or false)
    writeReport(report)

    -- The active weapon's own models are read through the client model path, so
    -- the report carries what the engine can load, not what the script claims.
    if report.active then
        for _, key in ipairs({"script_model", "entity_model"}) do
            local path = report.active[key]
            if path and path ~= "" and file.Exists(path, "GAME") then
                local info = clientModelInfo(path)
                local names = {}
                for _, attachment in ipairs(info.attachments) do
                    names[#names + 1] = attachment.name
                end
                local size = info.bounds and info.bounds.size
                print(string.format("GQUEST_WMODEL MODEL %s %s loaded=%s attachments=%s size=%s scale=%s",
                    key, path, tostring(info.loaded), table.concat(names, ","),
                    size and string.format("%.2f,%.2f,%.2f", size.x, size.y, size.z) or "none",
                    tostring(info.scale)))
                report.active[key .. "_info"] = {
                    loads = file.Exists(path, "GAME"), attachments = names,
                    attachment_detail = info.attachments,
                    bounds = info.bounds, scale = info.scale,
                }
            end
        end
        writeReport(report)
    end
    print("GQUEST_WMODEL END")
    return matched, missingRight, missingLeft, partsMissing
end

GQUEST_WEAPON_MODELS = GQUEST_WEAPON_MODELS or {}
GQUEST_WEAPON_MODELS.Run = run

concommand.Add("gquest_wmodel", function(_, _, arguments)
    run((arguments or {}).k ~= nil)
end)

concommand.Add("gquest_wmodel_verbose", function() run(true) end)

-- One automatic run per map load: late enough that the weapons and the content
-- mount are in place, early enough to still land in the session log.
hook.Add("InitPostEntity", "GquestWeaponModelReport", function()
    timer.Simple(20, function()
        local ok, matched, missingRight, missingLeft, partsMissing = pcall(run, false)
        if not ok then
            print("GQUEST_WMODEL ERROR " .. tostring(matched))
            return
        end
        local text = string.format("Waffenmodelle: %d/12 richtig, fehlend rechts %d / links %d, Teile fehlen %d",
            matched, missingRight, missingLeft, partsMissing)
        notification.AddLegacy(text, partsMissing > 0 and NOTIFY_ERROR or NOTIFY_GENERIC, 8)
        print("GQUEST_WMODEL toast " .. text)
    end)
end)

print("GQUEST_WMODEL ready: gquest_wmodel / gquest_wmodel_verbose")

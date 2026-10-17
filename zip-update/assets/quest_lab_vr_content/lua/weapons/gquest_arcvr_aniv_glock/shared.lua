-- Private standalone first slice of Pescorr ArcVR anniversary Glock.
-- Source: commit 0d8d5bed01c77ad1550097689dc0d1e6fc035385,
-- lua/weapons/arcticvr_aniv_glock/shared.lua and arcticvr_base/sv_server.lua.
-- Uses real native trigger state, source muzzle attachment, and server ammunition.
-- Physical magazine grabbing and full ArcVR stabilization remain unimplemented.
AddCSLuaFile()
SWEP.Base = "weapon_base"
SWEP.PrintName = "Gquest ArcVR Glock 17 (test)"
SWEP.Category = "Gquest ArcVR Lab"
SWEP.Spawnable = true
SWEP.AdminOnly = false
SWEP.UseHands = false
SWEP.ViewModel = "models/weapons/arcticvr/aniv/pistol_glock.mdl"
SWEP.WorldModel = "models/weapons/gquest_arcvr/pistol_glock_posefix2.mdl"
SWEP.ArcVRSourceWorldModel = "models/weapons/w_pist_glock18.mdl"
SWEP.DrawAmmo = true
SWEP.DrawCrosshair = false
SWEP.GquestArcVRWeapon = true
SWEP.ArcVRSourceClass = "arcticvr_aniv_glock"
SWEP.Primary = {ClipSize = 17, DefaultClip = 1000, Automatic = false, Ammo = "pistol"}
SWEP.Secondary = {ClipSize = -1, DefaultClip = -1, Automatic = false, Ammo = "none"}
SWEP.DamageMin = 15
SWEP.DamageMax = 30
SWEP.MaxRange = 6000
SWEP.Penetration = 4
SWEP.MuzzleVelocity = 200000
SWEP.RPM = 1200
SWEP.Spread = 1 / 105
SWEP.Firemode = 1
SWEP.MagType = "glock"
SWEP.DefaultMagazine = "glock_17_aniv"
SWEP.FireSound = "weapons/glock/glock18-1.wav"
SWEP.DryFireSound = "weapons/clipempty_pistol.wav"

function SWEP:SetupDataTables()
    self:NetworkVar("Int", 0, "ArcLoaded")
    self:NetworkVar("Int", 1, "ArcChambered")
    self:NetworkVar("Bool", 0, "ArcMagazine")
end

function SWEP:Initialize()
    self:SetHoldType("pistol")
    if SERVER then
        -- Faithful source starts empty: a magazine must be inserted and racked.
        self:SetArcLoaded(0)
        self:SetArcChambered(0)
        self:SetArcMagazine(false)
        self:SetClip1(0)
        self.GquestNextShot = 0
    end
end

-- Engine +attack/+reload must not duplicate the explicit XR state machine.
function SWEP:PrimaryAttack() end
function SWEP:SecondaryAttack() end
function SWEP:Reload() end

function SWEP:SyncAmmoFields()
    self.LoadedRounds = self:GetArcLoaded()
    self.Chambered = self:GetArcChambered()
    self.Magazine = self:GetArcMagazine() and self.DefaultMagazine or nil
end
function SWEP:Think()
    self:SyncAmmoFields()
    if SERVER then self:SetClip1(self:GetArcLoaded() + self:GetArcChambered()) end
end

if SERVER then
    util.AddNetworkString("gquest_arcvr_shot")
    util.AddNetworkString("gquest_arcvr_confirm")
    local function eligible(player)
        if not IsValid(player) or not player:Alive() or not game.SinglePlayer() then return end
        local weapon = player:GetActiveWeapon()
        if not IsValid(weapon) or weapon:GetClass() ~= "gquest_arcvr_aniv_glock" then return end
        return weapon
    end
    local function cycle(weapon)
        -- ArcVR Cycle for closed-bolt Glock consumes a magazine round into chamber.
        if weapon:GetArcLoaded() > 0 then
            weapon:SetArcChambered(1)
            weapon:SetArcLoaded(weapon:GetArcLoaded() - 1)
        else
            weapon:SetArcChambered(0)
            weapon:SetArcLoaded(0)
        end
        weapon:SetClip1(weapon:GetArcLoaded() + weapon:GetArcChambered())
        weapon:SyncAmmoFields()
    end
    concommand.Add("gquest_arcvr_test_insert", function(player)
        local weapon = eligible(player)
        if not weapon then return end
        -- Diagnostic insertion only: no ghost magazine entity or fake pickup state.
        if weapon:GetArcMagazine() then
            player:ChatPrint("Glock: magazine already inserted")
            return
        end
        local count = math.min(17, player:GetAmmoCount("pistol"))
        if count < 1 then return end
        player:RemoveAmmo(count, "pistol")
        weapon:SetArcLoaded(count)
        weapon:SetArcMagazine(true)
        weapon:SetClip1(count + weapon:GetArcChambered())
        weapon:SyncAmmoFields()
        print("GQUEST_ARCVR inserted source 17-round magazine; rounds=" .. count)
    end)
    concommand.Add("gquest_arcvr_test_rack", function(player)
        local weapon = eligible(player)
        if not weapon then return end
        cycle(weapon)
        print("GQUEST_ARCVR rack: chamber=" .. weapon:GetArcChambered() .. " magazine=" .. weapon:GetArcLoaded())
    end)
    concommand.Add("gquest_arcvr_test_eject", function(player)
        local weapon = eligible(player)
        if not weapon or not weapon:GetArcMagazine() then return end
        -- Return actual unspent magazine rounds; the chamber remains chambered.
        player:GiveAmmo(weapon:GetArcLoaded(), "pistol", true)
        weapon:SetArcLoaded(0)
        weapon:SetArcMagazine(false)
        weapon:SetClip1(weapon:GetArcChambered())
        weapon:SyncAmmoFields()
    end)
    net.Receive("gquest_arcvr_shot", function(_, player)
        local weapon = eligible(player)
        if not weapon then return end
        local src, ang = net.ReadVector(), net.ReadAngle()
        for _, value in ipairs({src.x, src.y, src.z, ang.p, ang.y, ang.r}) do
            if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then return end
        end
        -- Source accepts client muzzle data; the isolated Quest slice restricts it
        -- to a plausible tracked-hand reach and adds authoritative ammo/rate checks.
        if src:DistToSqr(player:EyePos()) > 96 * 96 then return end
        local now = CurTime()
        if now < (weapon.GquestNextShot or 0) then return end
        weapon.GquestNextShot = now + 60 / weapon.RPM
        if weapon:GetArcChambered() < 1 then
            weapon:EmitSound(weapon.DryFireSound)
            return
        end
        local sang = ang + AngleRand() * weapon.Spread * 0.1
        -- Exact source default hitscan branch: average 22.5 damage, force 7.5.
        player:LagCompensation(true)
        player:FireBullets({Attacker = player, Damage = (weapon.DamageMin + weapon.DamageMax) / 2,
            Force = (weapon.DamageMin + weapon.DamageMax) / 6, Tracer = 1, Spread = 0,
            Src = src, Dir = sang:Forward(), IgnoreEntity = player})
        player:LagCompensation(false)
        weapon:SetArcChambered(0)
        cycle(weapon)
        weapon:EmitSound(weapon.FireSound, 75, 100, 1, CHAN_WEAPON)
        net.Start("gquest_arcvr_confirm")
        net.WriteEntity(weapon)
        net.Send(player)
        print("GQUEST_ARCVR source shot: chamber=" .. weapon:GetArcChambered() .. " magazine=" .. weapon:GetArcLoaded())
    end)
end

if CLIENT then
    local nativeModel = CreateClientConVar("gquest_arcvr_native_model", "1", true, false,
        "Use the derived native grip model instead of the paired GLua viewmodel")
    local models = setmetatable({}, {__mode = "k"})
    local sourceBones = {"pistol", "magazine", "trigger", "slide", "bullet", "selector", "muzzle", "eject", "slidelock", "foregrip"}
    local function modelFor(weapon)
        if IsValid(models[weapon]) then return models[weapon] end
        local adapter = _G.GquestArcVR
        if not adapter or not adapter.CheckGlockAssets() then return end
        local model = ClientsideModel(weapon.ViewModel, RENDERGROUP_OPAQUE)
        if not IsValid(model) then return end
        model:SetNoDraw(true)
        for index, name in ipairs(sourceBones) do
            if model:LookupBone(name) ~= index - 1 then
                model:Remove()
                print("GQUEST_ARCVR weapon model bone contract failed: " .. name)
                return
            end
        end
        models[weapon] = model
        return model
    end
    local function updateModel(weapon)
        local adapter = _G.GquestArcVR
        if not adapter then return end
        local tracking = adapter.ReadWorld()
        if not tracking then return end
        local model = modelFor(weapon)
        if not model then return end
        local pos, ang = adapter.GlockTransform(tracking.right)
        model:SetPos(pos)
        model:SetAngles(ang)
        local slide = math.max(0, (weapon.GquestSlideUntil or 0) - CurTime()) * weapon.RPM / 60
        model:ManipulateBonePosition(3, Vector(0, 0, -1.4 * math.Clamp(slide, 0, 1)))
        local trigger = weapon.GquestTrigger or 0
        model:ManipulateBoneAngles(2, Angle(0, 0, 15 * trigger))
        model:SetupBones()
        return model
    end
    function SWEP:Think()
        self:SyncAmmoFields()
        if self:GetOwner() ~= LocalPlayer() or LocalPlayer():GetActiveWeapon() ~= self then return end
        local api = _G.vr
        if not api or not api.IsActive then return end
        local sessionOK, sessionActive = pcall(api.IsActive)
        if not sessionOK or sessionActive ~= true then self.GquestWasPressed = false return end
        local analogValid, trigger = false, 0
        if api.GetAnalog then
            local analogOK, x, _, analogActive = pcall(api.GetAnalog, "trigger_pull", 1)
            if analogOK and analogActive == true and type(x) == "number" and x == x and math.abs(x) ~= math.huge then
                analogValid, trigger = true, math.Clamp(x, 0, 1)
            end
        end
        local digitalValid, pressed = false, false
        if api.GetDigital then
            local ok, state, _, active = pcall(api.GetDigital, "attack", 1)
            digitalValid = ok and active == true and type(state) == "boolean"
            if digitalValid then pressed = state end
        end
        if not digitalValid then
            -- This Quest runtime exposes a real trigger axis while the attack
            -- action is inactive. Derive an edge only from that active axis;
            -- hysteresis prevents threshold noise from generating extra shots.
            if not analogValid then self.GquestWasPressed = false self.GquestTrigger = 0 return end
            pressed = self.GquestWasPressed and trigger > 0.45 or trigger >= 0.55
        end
        local rising = pressed and not self.GquestWasPressed
        self.GquestWasPressed = pressed
        self.GquestTrigger = analogValid and trigger or (pressed and 1 or 0)
        -- Default source firemode1 requires a genuine fresh trigger pull.
        local menuVisible = gui.IsGameUIVisible() or vgui.CursorVisible() or
            (IsValid(g_SpawnMenu) and g_SpawnMenu:IsVisible()) or
            (IsValid(g_ContextMenu) and g_ContextMenu:IsVisible())
        if _G.GquestUI and type(_G.GquestUI.IsMenuVisible) == "function" then
            menuVisible = menuVisible or _G.GquestUI.IsMenuVisible()
        end
        if not rising or menuVisible then return end
        local att
        if nativeModel:GetBool() then
            -- Use the exact muzzle on the calibrated native held model.
            -- The source MDL names attachment1 "1"; "muzzle" is its bone name.
            local muzzle=self:LookupAttachment("1")
            if muzzle and muzzle>0 then att=self:GetAttachment(muzzle) end
        else
            local model=updateModel(self)
            if model then att=model:GetAttachment(1) end
        end
        if not att or not isvector(att.Pos) or not isangle(att.Ang) then return end
        net.Start("gquest_arcvr_shot")
        net.WriteVector(att.Pos)
        net.WriteAngle(att.Ang)
        net.SendToServer()
        print("GQUEST_ARCVR native trigger -> source muzzle request")
    end
    function SWEP:DrawWorldModel()
        if self:GetOwner() ~= LocalPlayer() then self:DrawModel() return end
        if nativeModel:GetBool() or not _G.GquestArcVR or not _G.GquestArcVR.ReadWorld() then self:DrawModel() end
    end
    function SWEP:PreDrawViewModel()
        if _G.GquestArcVR and _G.GquestArcVR.ReadWorld() then return true end
    end
    local function cleanup(weapon)
        if IsValid(models[weapon]) then models[weapon]:Remove() end
        models[weapon] = nil
    end
    function SWEP:OnRemove() cleanup(self) end
    function SWEP:Holster() cleanup(self) return true end
    hook.Add("PostDrawOpaqueRenderables", "GquestArcVRActiveGlock", function(depth, sky)
        if depth or sky then return end
        if nativeModel:GetBool() then return end
        local player = LocalPlayer()
        if not IsValid(player) then return end
        local weapon = player:GetActiveWeapon()
        if not IsValid(weapon) or weapon:GetClass() ~= "gquest_arcvr_aniv_glock" then return end
        local model = updateModel(weapon)
        if model then model:DrawModel() end
    end)
    net.Receive("gquest_arcvr_confirm", function()
        local weapon = net.ReadEntity()
        if not IsValid(weapon) or weapon:GetClass() ~= "gquest_arcvr_aniv_glock" then return end
        weapon.GquestSlideUntil = CurTime() + 60 / weapon.RPM
        -- Native signature hand,durationSeconds,frequencyHz,amplitude0..1.
        -- Original uses amplitude20 outside normalized range; do not copy it blind.
        if vr and vr.TriggerHaptic then pcall(vr.TriggerHaptic, 1, 0.3, 15, 0.5) end
        print("GQUEST_ARCVR server confirmed shot")
    end)
end

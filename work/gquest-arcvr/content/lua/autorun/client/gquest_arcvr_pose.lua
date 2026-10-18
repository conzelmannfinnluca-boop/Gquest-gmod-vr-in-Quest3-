-- Private Gquest bridge foundation, sourced against ArcVR commit
-- 0d8d5bed01c77ad1550097689dc0d1e6fc035385. This does not impersonate VRMod.
-- World transform must be supplied from the engine's verified playspace origin.
local A = {}
GquestArcVR = A
A.SourceCommit = "0d8d5bed01c77ad1550097689dc0d1e6fc035385"
A.SourceWeaponClass = "arcticvr_aniv_glock"
A.SourceWeaponPath = "lua/weapons/arcticvr_aniv_glock/shared.lua"
A.Glock = {
    Model = "models/weapons/arcticvr/aniv/pistol_glock.mdl",
    MagazineModel = "models/weapons/arcticvr/aniv/mag_glock.mdl",
    DamageMin = 15, DamageMax = 30, RPM = 1200, MagazineCapacity = 17,
    OffsetPos = Vector(-4.9, -4, 1.3), OffsetAng = Angle(10, 0, 0),
    MagazinePosePos = Vector(-6.5, 3.2, -5), MagazinePoseAng = Angle(0, 0, 90)
}

local function nativePose(callback, hand)
    local ok, pos, ang, valid = pcall(callback, hand)
    if not ok or valid ~= true or not pos or not ang then return nil end
    -- The native XR wrappers return tagged field tables. Copy their real fields
    -- into engine userdata before arithmetic; tagged-table tostring is invalid.
    local readable, fields = pcall(function()
        return {pos.x, pos.y, pos.z, ang.p, ang.y, ang.r}
    end)
    if not readable then return nil end
    for i = 1, 6 do
        local value = fields[i]
        if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then return nil end
    end
    return {pos = Vector(pos.x, pos.y, pos.z), ang = Angle(ang.p, ang.y, ang.r)}
end

function A.ReadPlayspace()
    local api = _G.vr
    if type(api) ~= "table" or type(api.IsActive) ~= "function" or
        type(api.GetHeadPose) ~= "function" or type(api.GetHandPose) ~= "function" then
        return nil, "native pose API unavailable"
    end
    local ok, active = pcall(api.IsActive)
    if not ok or active ~= true then return nil, "VR session inactive" end
    local head = nativePose(api.GetHeadPose)
    local left = nativePose(api.GetHandPose, 0)
    local right = nativePose(api.GetHandPose, 1)
    if not head or not left or not right then return nil, "head or controller pose invalid" end
    return {head = head, left = left, right = right}
end

function A.ToWorld(poses, originPos, originAng)
    if not poses or not isvector(originPos) or not isangle(originAng) then return nil end
    local world = {}
    for _, key in ipairs({"head", "left", "right"}) do
        local pose = poses[key]
        if not pose then return nil end
        local pos, ang = LocalToWorld(pose.pos, pose.ang, originPos, originAng)
        world[key] = {pos = pos, ang = ang}
    end
    return world
end

function A.GlockTransform(right)
    if not right or not isvector(right.pos) or not isangle(right.ang) then return nil end
    -- Preserve VRMod's ordinary viewmodel transform, including Source's positive
    -- local Y convention. A worldmodel override uses a different transform.
    return LocalToWorld(A.Glock.OffsetPos, A.Glock.OffsetAng, right.pos, right.ang)
end

function A.CheckGlockAssets()
    for _, path in ipairs({A.Glock.Model, A.Glock.MagazineModel}) do
        for _, ext in ipairs({".mdl", ".vvd", ".dx90.vtx"}) do
            local companion = string.gsub(path, "%.mdl$", ext)
            if not file.Exists(companion, "GAME") then return false, "missing " .. companion end
        end
    end
    local material = Material("models/weapons/v_models/pist_glock18/glock18")
    if material:IsError() then return false, "missing mounted Glock18 material" end
    return true
end

-- An explicit origin provider permits a diagnostic model preview without moving
-- native hands, modifying g_VR, or sending fabricated weapon/pickup packets.
function A.SetOriginProvider(provider)
    if type(provider) ~= "function" then return false end
    A.OriginProvider = provider
    return true
end

function A.ReadWorld()
    local shared = _G.GquestXR
    if type(shared) == "table" and type(shared.GetWorldTracking) == "function" then
        local ok, tracking = pcall(shared.GetWorldTracking)
        if not ok or not tracking then return nil, "shared world tracking unavailable" end
        local right = tracking.pose_righthand
        if not tracking.hmd or not right or not isvector(right.pos) or not isangle(right.ang) then
            return nil, "shared right-hand tracking invalid"
        end
        return {head = tracking.hmd, left = tracking.pose_lefthand, right = right}
    end
    if not A.OriginProvider then return nil, "world tracking provider not connected" end
    local poses, reason = A.ReadPlayspace()
    if not poses then return nil, reason end
    local ok, originPos, originAng = pcall(A.OriginProvider)
    if not ok then return nil, "origin provider failed" end
    return A.ToWorld(poses, originPos, originAng)
end

local preview
local previewEnabled = false
local slidePreview = 0
local triggerPreview = 0
local function removePreview()
    if IsValid(preview) then preview:Remove() end
    preview = nil
end
concommand.Add("gquest_arcvr_glock_parts", function(_, _, args)
    -- Source Glock slide travel 1.4 units on local -Z and trigger roll 15 degrees.
    -- Pure visual inspection; this deliberately changes no ammunition or fire state.
    slidePreview = math.Clamp(tonumber(args[1]) or 0, 0, 1)
    triggerPreview = math.Clamp(tonumber(args[2]) or 0, 0, 1)
end)
concommand.Add("gquest_arcvr_glock_preview", function(_, _, args)
    previewEnabled = args[1] == "1"
    if not previewEnabled then removePreview() return end
    local ready, reason = A.CheckGlockAssets()
    local world, trackingReason = A.ReadWorld()
    if not ready or not world then
        previewEnabled = false
        print("GQUEST_ARCVR preview unavailable: " .. (reason or trackingReason or "world tracking invalid"))
    else
        print("GQUEST_ARCVR anniversary Glock model preview enabled; shooting adapter is not active")
    end
end)
hook.Add("PostDrawOpaqueRenderables", "GquestArcVRGlockPreview", function(depth, sky)
    if not previewEnabled or depth or sky then return end
    local world = A.ReadWorld()
    if not world then return end
    if not IsValid(preview) then
        preview = ClientsideModel(A.Glock.Model, RENDERGROUP_OPAQUE)
        if not IsValid(preview) then return end
        preview:SetNoDraw(true)
        local names = {"pistol", "magazine", "trigger", "slide", "bullet", "selector", "muzzle", "eject", "slidelock", "foregrip"}
        for i, name in ipairs(names) do
            if preview:LookupBone(name) ~= i - 1 then
                print("GQUEST_ARCVR unexpected model bone " .. name)
                previewEnabled = false
                removePreview()
                return
            end
        end
    end
    local pos, ang = A.GlockTransform(world.right)
    preview:SetPos(pos)
    preview:SetAngles(ang)
    preview:ManipulateBonePosition(3, Vector(0, 0, -1.4 * slidePreview))
    preview:ManipulateBoneAngles(2, Angle(0, 0, 15 * triggerPreview))
    preview:SetupBones()
    preview:DrawModel()
end)
hook.Add("ShutDown", "GquestArcVRCleanup", removePreview)
print("GQUEST_ARCVR foundation loaded; model preview requires verified origin and assets")

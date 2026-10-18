-- Original Gquest wrist HUD, inspired by glove-based VR interfaces.
-- Native vr poses are in playspace Source units, not world coordinates.
GquestXR=GquestXR or {}
local function sourcePoseAngle(raw)
    -- The native API converts positions to (x,-z,y), but its Euler angles
    -- are still in the XR axes. Transform forward(-Z) and up(+Y) explicitly.
    local rotation=Angle(raw.p,raw.y,raw.r)
    local forward,up=Vector(0,0,-1),Vector(0,1,0)
    forward:Rotate(rotation);up:Rotate(rotation)
    forward=Vector(forward.x,-forward.z,forward.y)
    up=Vector(up.x,-up.z,up.y)
    return forward:AngleEx(up)
end
function GquestXR.GetWorldTracking()
    local player=LocalPlayer()
    if not IsValid(player) or not vr or not vr.GetHeadPose or not vr.GetHandPose then return end
    local head,headAngle,headValid=vr.GetHeadPose()
    if not headValid then return end
    -- This port's native pose binding returns field tables with legacy meta tags.
    -- Recreate actual Vector/Angle userdata before applying native math methods.
    head=Vector(head.x,head.y,head.z)
    headAngle=sourcePoseAngle(headAngle)
    local yaw=math.AngleDifference(player:EyeAngles().y,headAngle.y)
    local rotation=Angle(0,yaw,0)
    local headWorld=player:EyePos()
    local result={hmd={pos=headWorld,ang=player:EyeAngles()}}
    for hand=0,1 do
        local position,angle,valid=vr.GetHandPose(hand)
        if valid then
            position=Vector(position.x,position.y,position.z)
            angle=sourcePoseAngle(angle)
            local delta=position-head
            delta:Rotate(rotation)
            local worldAngle=Angle(angle.p,angle.y,angle.r)
            worldAngle:RotateAroundAxis(Vector(0,0,1),yaw)
            result[hand==0 and "pose_lefthand" or "pose_righthand"]={pos=headWorld+delta,ang=worldAngle}
        end
    end
    return result
end
local enabled=CreateClientConVar("gquest_wrist_hud","1",true,false,"Gquest wrist display")
local size=CreateClientConVar("gquest_wrist_hud_scale","0.015",true,false,"Wrist display scale",0.008,0.03)
local side=CreateClientConVar("gquest_wrist_hud_flip","0",true,false,"Use the opposite wrist surface")
-- The panel used to sit 1.4 units in front of the raw hand pose, i.e. directly
-- on the glove. These offsets move it off the hand in the hand's own frame so
-- the hand stays visible where the panel was.
local offsetSide=CreateClientConVar("gquest_wrist_hud_offset_side","4.5",true,false,"Wrist display offset across the hand",-15,15)
local offsetUp=CreateClientConVar("gquest_wrist_hud_offset_up","5",true,false,"Wrist display offset above the hand",-15,15)
local offsetForward=CreateClientConVar("gquest_wrist_hud_offset_forward","1.4",true,false,"Wrist display offset towards the eye",0.5,10)
-- Hidden while the hand is up at the face or while aiming; 0 disables each test.
local offsetNearHide=CreateClientConVar("gquest_wrist_hud_near_hide","14",true,false,"Hide the wrist display when the hand is this close to the head (0 = off)",0,40)
local hideWhileAiming=CreateClientConVar("gquest_wrist_hud_hide_aim","1",true,false,"Hide the wrist display while aiming")
surface.CreateFont("GquestWristValue",{font="DejaVu Sans",size=42,weight=800})
surface.CreateFont("GquestWristSmall",{font="DejaVu Sans",size=15,weight=600})
hook.Remove("HUDPaint","GquestVitals")
local reported=false
local calls=0
concommand.Add("gquest_wrist_probe",function()
    local tracking=GquestXR.GetWorldTracking()
    print("GQUEST_WRIST_PROBE hooks",calls,"tracking",tracking~=nil,"left",tracking and tracking.pose_lefthand~=nil)
end)
-- Keep the anchor on the left wrist but make the read surface face the head.
-- Raw OpenXR grip axes differ from the rendered glove's authored axes, and the
-- offsets are applied in the hand's frame so the panel rides with the wrist
-- without covering it.
local function hudAnchor(tracking)
    local hand=tracking and tracking.pose_lefthand
    if not hand then return nil end
    local towardsEye=tracking.hmd.pos-hand.pos
    local distance=towardsEye:Length()
    if distance<4 or distance>65 then return nil end
    towardsEye:Normalize()
    local handAngle=hand.ang or Angle(0,0,0)
    local position=hand.pos+towardsEye*offsetForward:GetFloat()
        +handAngle:Right()*offsetSide:GetFloat()+handAngle:Up()*offsetUp:GetFloat()
    local angle=Angle(tracking.hmd.ang.p,tracking.hmd.ang.y,tracking.hmd.ang.r)
    angle:RotateAroundAxis(angle:Up(),-90)
    angle:RotateAroundAxis(angle:Forward(),90)
    if side:GetBool() then angle:RotateAroundAxis(angle:Up(),180) end
    return position,angle,distance
end

-- Hide it when it would only be in the way: hand up at the face, or a
-- two-handed grip (= aiming). The near test has hysteresis so a hand hovering
-- around the threshold cannot make the panel flicker.
local nearHidden=false
local lastHideReason=nil
local function aimingNow()
    if type(vrmod)=="table" and vrmod.IsForegripActive then
        local ok,active=pcall(vrmod.IsForegripActive)
        if ok and active then return true end
    end
    if type(g_VR)=="table" and g_VR.foregripActive then return true end
    local player=LocalPlayer()
    local weapon=IsValid(player) and player:GetActiveWeapon() or nil
    return IsValid(weapon) and weapon.ForegripGrabbed and true or false
end
local function hideReason(tracking,distance)
    local limit=offsetNearHide:GetFloat()
    if limit>0 then
        if distance<limit then nearHidden=true
        elseif distance>limit+3 then nearHidden=false end
        if nearHidden then return "near" end
    else
        nearHidden=false
    end
    if hideWhileAiming:GetBool() and aimingNow() then return "aim" end
    return nil
end

-- Prints where the panel actually sits relative to the hand, so the offsets
-- (and their signs) can be judged on the device instead of guessed here.
concommand.Add("gquest_wrist_report",function()
    local tracking=GquestXR.GetWorldTracking()
    local hand=tracking and tracking.pose_lefthand
    if not hand then print("GQUEST_WRIST report: no left hand pose"); return end
    local position=hudAnchor(tracking)
    if not position then print("GQUEST_WRIST report: no anchor (hand out of range)"); return end
    local delta=position-hand.pos
    print(string.format("GQUEST_WRIST report hand=%.2f,%.2f,%.2f panel=%.2f,%.2f,%.2f delta=%.2f,%.2f,%.2f len=%.2f",
        hand.pos.x,hand.pos.y,hand.pos.z,position.x,position.y,position.z,
        delta.x,delta.y,delta.z,delta:Length()))
    print(string.format("GQUEST_WRIST report distance=%.2f near_limit=%.2f aiming=%s hide_aim=%s",
        (hand.pos-tracking.hmd.pos):Length(),offsetNearHide:GetFloat(),
        tostring(aimingNow()),tostring(hideWhileAiming:GetBool())))
end)

-- Place the panel from the console; the VR menu calls the same commands.
concommand.Add("gquest_wrist_offset",function(_,_,arguments)
    for index,name in ipairs({"side","up","forward"}) do
        local value=tonumber(arguments and arguments[index] or "")
        if value then RunConsoleCommand("gquest_wrist_hud_offset_"..name,tostring(value)) end
    end
    print(string.format("GQUEST_WRIST offset side=%.2f up=%.2f forward=%.2f",
        offsetSide:GetFloat(),offsetUp:GetFloat(),offsetForward:GetFloat()))
end)
local function paint(player)
    local health=math.Clamp(player:Health()/math.max(player:GetMaxHealth(),1),0,1)
    local armor=math.Clamp(player:Armor()/100,0,1)
    local white=Color(226,249,248,245)
    local cyan=Color(65,210,220,240)
    local healthColor=health<=0.25 and Color(255,75,60,245) or Color(104,239,173,245)
    draw.RoundedBox(9,-144,-72,288,144,Color(5,16,22,205))
    surface.SetDrawColor(cyan);surface.DrawOutlinedRect(-141,-69,282,138,2)
    draw.SimpleText("VITAL", "GquestWristSmall",-125,-57,white)
    local function heart(x,y,color)
        surface.SetDrawColor(color);draw.NoTexture()
        surface.DrawPoly({{x=x-16,y=y-3},{x=x+16,y=y-3},{x=x,y=y+18}})
        for _,center in ipairs({x-7,x+7}) do
            local points={}
            for step=0,20 do
                local angle=step*math.pi*2/20
                points[#points+1]={x=center+math.cos(angle)*9,y=y-5+math.sin(angle)*9}
            end
            surface.DrawPoly(points)
        end
    end
    for segment=0,2 do
        local amount=math.Clamp(health*3-segment,0,1)
        heart(-110+segment*37,-21,amount>0 and Color(healthColor.r,healthColor.g,healthColor.b,90+155*amount) or Color(29,65,62,220))
    end
    draw.SimpleText(tostring(math.max(0,player:Health())),"GquestWristSmall",-125,6,healthColor)
    draw.SimpleText("PANZERUNG", "GquestWristSmall",-125,28,Color(236,200,112,240))
    draw.RoundedBox(2,-125,51,111,6,Color(52,49,39,220))
    if armor>0 then draw.RoundedBox(2,-125,51,111*armor,6,Color(236,200,112,240)) end
    surface.SetDrawColor(65,120,128,180);surface.DrawRect(0,-49,1,105)
    local weapon=player:GetActiveWeapon()
    local clip,reserve=nil,nil
    if IsValid(weapon) then
        -- ArcVR stores inserted rounds/chamber separately from Source Clip1.
        if weapon.ArcticVR then
            clip=(weapon.LoadedRounds or 0)+(weapon.Chambered or 0)
        elseif weapon:Clip1()>=0 then clip=weapon:Clip1() end
        local ammo=weapon:GetPrimaryAmmoType()
        if ammo>=0 then reserve=player:GetAmmoCount(ammo) end
    end
    draw.SimpleText(clip and "MUNITION" or "WERKZEUG","GquestWristSmall",18,-57,white)
    draw.SimpleText(clip and string.format("%02d",clip) or "--","GquestWristValue",18,-31,white)
    draw.SimpleText(reserve and "/ "..reserve or "GQUEST","GquestWristSmall",20,26,cyan)
end
hook.Add("PostDrawTranslucentRenderables","GquestWristHUD",function(depth,skybox)
    calls=calls+1
    if depth or skybox or not enabled:GetBool() then return end
    local player=LocalPlayer()
    if not IsValid(player) or not player:Alive() then return end
    local tracking=GquestXR.GetWorldTracking()
    local position,angle,distance=hudAnchor(tracking)
    if not position then return end
    local reason=hideReason(tracking,distance)
    if reason~=lastHideReason then
        print(string.format("GQUEST_WRIST hide=%s distance=%.2f",tostring(reason),distance))
        lastHideReason=reason
    end
    if reason then return end
    cam.Start3D2D(position,angle,size:GetFloat())
    paint(player)
    cam.End3D2D()
    if not reported then
        print(string.format("GQUEST_WRIST rendered at %.2f %.2f %.2f offsets side=%.2f up=%.2f forward=%.2f",
            position.x,position.y,position.z,offsetSide:GetFloat(),offsetUp:GetFloat(),offsetForward:GetFloat()))
        reported=true
    end
end)
print("GQUEST_WRIST ready: native left wrist, health armor ammo")

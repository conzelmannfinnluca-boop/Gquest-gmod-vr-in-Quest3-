if not CLIENT then return end
local stopAt=SysTime()+45
local nextSample=0
hook.Add("Think","GquestLeftGripTrace",function()
    local now=SysTime()
    if now>stopAt then hook.Remove("Think","GquestLeftGripTrace");print("GQUEST_LEFT_TRACE finished");return end
    if now<nextSample then return end
    nextSample=now+0.5
    local report={time=now}
    if vr and vr.GetDigital then
        local ok,state,changed,active=pcall(vr.GetDigital,"grab",0)
        report.grab={ok=ok,state=state==true,active=active==true}
    end
    if vr and vr.GetAnalog then
        local ok,x,y,active=pcall(vr.GetAnalog,"hand_curl",0)
        report.curl={ok=ok,x=ok and x or nil,y=ok and y or nil,active=active==true}
    end
    if GquestXR then
        local tracking=GquestXR.GetWorldTracking()
        local hand=tracking and tracking.pose_lefthand
        if hand then report.hand={p=hand.ang.p,y=hand.ang.y,r=hand.ang.r} end
    end
    print("GQUEST_LEFT_TRACE "..util.TableToJSON(report,false))
end)
print("GQUEST_LEFT_TRACE ready 45 seconds")

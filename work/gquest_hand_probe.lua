for _,name in ipairs({"vr","vrmod","vrmod_xr","GmodVR"}) do
    local api=_G[name]
    print("GQUEST_API",name,type(api))
    if type(api)=="table" then
        for key,value in pairs(api) do if type(value)=="function" then print("GQUEST_API_FUNCTION",name,key) end end
        if api.GetHandPose then
            for hand=0,1 do
                local ok,pos,ang,valid=pcall(api.GetHandPose,hand)
                print("GQUEST_HAND_PROBE",name,hand,ok,type(pos),type(ang),valid,ok and pos.x,ok and pos.y,ok and pos.z)
            end
        end
    end
end

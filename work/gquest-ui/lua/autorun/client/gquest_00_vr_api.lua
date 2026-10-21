-- Load our small native compatibility module before other Gquest autoruns.
if not vr or not vr.GetHandPose or not vr.GetDigital then
    local ok,result=pcall(require,"gquest_vr")
    if not ok then print("GQUEST_VRLUA load failed: "..tostring(result)) return end
    if type(result)=="table" and result.GetHandPose then vr=result end
end
print("GQUEST_VRLUA ready="..tostring(vr and type(vr.GetHandPose)=="function"))

// Retire only the 63 files previously installed by the private ArcVR overlay.
// Rename into an unmounted backup; never traverse/delete user addon trees.
#pragma once
static const char* const GquestRetiredArcVRPaths[]={
    "lua/autorun/client/gquest_arcvr_pose.lua",
    "lua/autorun/server/gquest_arcvr_collection.lua",
    "lua/weapons/gquest_arcvr_aniv_deagle/shared.lua",
    "lua/weapons/gquest_arcvr_aniv_glock/shared.lua",
    "lua/weapons/gquest_arcvr_aniv_m9/shared.lua",
    "lua/weapons/gquest_arcvr_aniv_usptactical/shared.lua",
    "materials/models/weapons/arcticvr/p38/bullet_normal_flat.vtf",
    "materials/models/weapons/arcticvr/p38/v_p38.vmt",
    "materials/models/weapons/arcticvr/p38/v_p38.vtf",
    "materials/models/weapons/v_models/pist_deagle/deagle_skin1.vmt",
    "materials/models/weapons/v_models/pist_deagle/deagle_skin1.vtf",
    "materials/models/weapons/v_models/pist_deagle/deagle_skin1_ref.vtf",
    "materials/models/weapons/v_models/pist_elite/pist_elite.vmt",
    "materials/models/weapons/v_models/pist_elite/pist_elite.vtf",
    "materials/models/weapons/v_models/pist_elite/pist_elite_ref.vtf",
    "materials/models/weapons/v_models/pist_usp/pist_usp.vmt",
    "materials/models/weapons/v_models/pist_usp/pist_usp.vtf",
    "materials/models/weapons/v_models/pist_usp/pist_usp_ref.vtf",
    "models/weapons/arcticvr/aniv/9mmbullet.dx90.vtx",
    "models/weapons/arcticvr/aniv/9mmbullet.mdl",
    "models/weapons/arcticvr/aniv/9mmbullet.vvd",
    "models/weapons/arcticvr/aniv/9mmcase.dx90.vtx",
    "models/weapons/arcticvr/aniv/9mmcase.mdl",
    "models/weapons/arcticvr/aniv/9mmcase.vvd",
    "models/weapons/arcticvr/aniv/mag_glock.dx90.vtx",
    "models/weapons/arcticvr/aniv/mag_glock.mdl",
    "models/weapons/arcticvr/aniv/mag_glock.phy",
    "models/weapons/arcticvr/aniv/mag_glock.vvd",
    "models/weapons/arcticvr/aniv/pistol_deagle.dx90.vtx",
    "models/weapons/arcticvr/aniv/pistol_deagle.mdl",
    "models/weapons/arcticvr/aniv/pistol_deagle.phy",
    "models/weapons/arcticvr/aniv/pistol_deagle.vvd",
    "models/weapons/arcticvr/aniv/pistol_glock.dx90.vtx",
    "models/weapons/arcticvr/aniv/pistol_glock.mdl",
    "models/weapons/arcticvr/aniv/pistol_glock.phy",
    "models/weapons/arcticvr/aniv/pistol_glock.vvd",
    "models/weapons/arcticvr/aniv/pistol_m9.dx90.vtx",
    "models/weapons/arcticvr/aniv/pistol_m9.mdl",
    "models/weapons/arcticvr/aniv/pistol_m9.phy",
    "models/weapons/arcticvr/aniv/pistol_m9.vvd",
    "models/weapons/arcticvr/aniv/pistol_usp.dx90.vtx",
    "models/weapons/arcticvr/aniv/pistol_usp.mdl",
    "models/weapons/arcticvr/aniv/pistol_usp.phy",
    "models/weapons/arcticvr/aniv/pistol_usp.vvd",
    "models/weapons/gquest_arcvr/pistol_deagle_grip_fit1.dx90.vtx",
    "models/weapons/gquest_arcvr/pistol_deagle_grip_fit1.mdl",
    "models/weapons/gquest_arcvr/pistol_deagle_grip_fit1.phy",
    "models/weapons/gquest_arcvr/pistol_deagle_grip_fit1.vvd",
    "models/weapons/gquest_arcvr/pistol_glock_posefix2.dx90.vtx",
    "models/weapons/gquest_arcvr/pistol_glock_posefix2.mdl",
    "models/weapons/gquest_arcvr/pistol_glock_posefix2.phy",
    "models/weapons/gquest_arcvr/pistol_glock_posefix2.vvd",
    "models/weapons/gquest_arcvr/pistol_m9_grip_fit1.dx90.vtx",
    "models/weapons/gquest_arcvr/pistol_m9_grip_fit1.mdl",
    "models/weapons/gquest_arcvr/pistol_m9_grip_fit1.phy",
    "models/weapons/gquest_arcvr/pistol_m9_grip_fit1.vvd",
    "models/weapons/gquest_arcvr/pistol_usp_grip_fit1.dx90.vtx",
    "models/weapons/gquest_arcvr/pistol_usp_grip_fit1.mdl",
    "models/weapons/gquest_arcvr/pistol_usp_grip_fit1.phy",
    "models/weapons/gquest_arcvr/pistol_usp_grip_fit1.vvd",
    "sound/weapons/deagle/deagle-1.wav",
    "sound/weapons/elite/elite-1.wav",
    "sound/weapons/usp/usp1.wav",
};
static bool RetireGquestArcVR(const std::string& root,const std::string& backup) {
    unsigned moved=0;
    for (const char* relative:GquestRetiredArcVRPaths) {
        const std::string source=root+relative;
        struct stat st{};
        if (lstat(source.c_str(),&st)!=0) { if(errno==ENOENT) continue; return false; }
        if (!S_ISREG(st.st_mode)) {LOG("RETIRE ArcVR unexpected non-file: %s",relative);return false;}
        const std::string target=backup+relative;
        if (!EnsureContentDirectory(target.substr(0,target.find_last_of('/')))) return false;
        std::string destination=target;
        // Preserve a previous backup if the old APK installed its content again.
        unsigned suffix=0;
        while (lstat(destination.c_str(),&st)==0) {
            if (++suffix>100) return false;
            destination=target+"."+std::to_string(suffix);
        }
        if (errno!=ENOENT || rename(source.c_str(),destination.c_str())!=0) return false;
        ++moved;
    }
    LOG("RETIRE ArcVR moved=%u mounted_files_remaining=0",moved);
    return true;
}

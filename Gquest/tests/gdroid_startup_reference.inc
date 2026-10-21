// Frozen own C++ startup behavior from working GDroid bridge.
// Source SHA256: 776d1751a38656c5854f5bed1479a097568936cb1fa438e42661fd5d8334f777
static std::string EyeTier = "1032x1104";
static std::string Foveation = "2";
static std::string RefreshRate = "72";
static void AppendQuestDefaults(std::vector<char*>& args) {
    // Applied after Flat android_settings.cfg and before level loading.
    static const char* settings[] = {
        "+touch_enable", "0", "+vr_mainmenu", "1",
        "+vr_panel_menu_auto", "1", "+vr_spawn_menu_enable", "1",
        "+gmod_derma_vr", "1", "+vr_gameui_cursor", "1",
        "+hlvr_grip_yaw_correction", "0",
        "+vr_gameui_software_cursor", "0",
        "+vr_eye_resolution", "1032x1104", "+vr_ffr_level", "2",
        "+vr_perf_level", "50", "+vr_refresh_rate", "72", "+mat_vsync", "0"
    };
    for (size_t i=0; i<sizeof(settings)/sizeof(settings[0]); ++i) {
        const char* value = settings[i];
        if (i>0 && strcmp(settings[i-1],"+vr_eye_resolution")==0) value=EyeTier.c_str();
        if (i>0 && strcmp(settings[i-1],"+vr_ffr_level")==0) value=Foveation.c_str();
        if (i>0 && strcmp(settings[i-1],"+vr_refresh_rate")==0) value=RefreshRate.c_str();
        args.push_back(const_cast<char*>(value));
    }
}


static std::vector<std::string> gdroid_reference(int argc, char** argv) {
    std::vector<char*> vrArgs;
    char vrSwitch[] = "-vr";
    char vrPlayer[] = "+hlvr_isvrplayer";
    char playerEnabled[] = "1";
    // Put startup commands before the first map command.
    bool inserted = false;
    for (int i = 0; i < argc; ++i) {
        if (!inserted && argv[i] && std::string(argv[i]) == "+map") {
            AppendQuestDefaults(vrArgs);
            vrArgs.push_back(vrPlayer);
            vrArgs.push_back(playerEnabled);
            inserted = true;
        }
        vrArgs.push_back(argv[i]);
        if (i == 0) vrArgs.push_back(vrSwitch);
    }
    if (!inserted) {
        AppendQuestDefaults(vrArgs);
        vrArgs.push_back(vrPlayer);
        vrArgs.push_back(playerEnabled);
    }
    bool hasLevelCommand = false;
    for (int i = 0; i < argc; ++i) {
        if (!argv[i]) continue;
        const std::string arg(argv[i]);
        if (arg == "+map" || arg == "+connect" || arg == "+load" || arg == "+changelevel") hasLevelCommand = true;
    }
    char defaultMapCommand[] = "+map";
    char defaultMap[] = "gm_construct";
    if (!hasLevelCommand) {
        // The Flat setup launcher can omit a level and leave this VR lab at an
        // empty menu. Give the isolated test package a known playable entry.
        vrArgs.push_back(defaultMapCommand);
        vrArgs.push_back(defaultMap);
        LOG("START no level command supplied; using lab map gm_construct");
    }
    std::vector<std::string> copied;
    for (auto arg: vrArgs) copied.emplace_back(arg);
    return copied;
}

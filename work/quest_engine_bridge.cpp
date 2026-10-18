#include <jni.h>
#include <android/log.h>
#include <dlfcn.h>
#include <unistd.h>
#include <cstdio>
#include <cstdarg>
#include <chrono>
#include <vector>
#include <string>
#include <cstring>
#include <cstdint>
#include <link.h>
#include <sys/mman.h>
#include <EGL/egl.h>
#include <GLES3/gl3.h>
#include <cstdlib>
#include <android/asset_manager.h>
#include <android/asset_manager_jni.h>
#include <sys/stat.h>
#include <cerrno>

static void BridgeLog(const char* format, ...) {
    char text[1024];
    va_list args;
    va_start(args, format);
    vsnprintf(text, sizeof(text), format, args);
    va_end(args);
    __android_log_print(ANDROID_LOG_INFO, "QUEST_ENGINE_BRIDGE", "%s", text);
    if (FILE* file = fopen("/data/user/0/com.gmodvr.qvrx/files/diagnostics/quest_engine_bridge.log", "a")) {
        fprintf(file, "%s\n", text);
        fclose(file);
    }
}
#define LOG(...) BridgeLog(__VA_ARGS__)

// SDL's EGL implementation accepts the raw EGLContext as SDL_GLContext.
// Intercept only the launcher's imported context factory, leaving native code
// and the installed Flat application intact. Resolve the slot by symbol name.
using CreateContext = void* (*)(void*);
static CreateContext OriginalCreateContext;
static EGLContext BootstrapContext = EGL_NO_CONTEXT;
static EGLContext EngineContext = EGL_NO_CONTEXT;
static EGLDisplay EngineDisplay = EGL_NO_DISPLAY;
static pid_t EngineContextOwner = 0;
using PollEvent = int (*)(void*);
static PollEvent OriginalPollEvent;
static bool ReadableMemory(const void* address, size_t length) {
    const uintptr_t begin=reinterpret_cast<uintptr_t>(address);
    if (!begin || begin+length<begin) return false;
    FILE* maps=fopen("/proc/self/maps","r");
    if (!maps) return false;
    char line[512], permissions[5]; unsigned long low,high; bool readable=false;
    while (fgets(line,sizeof(line),maps)) {
        if (sscanf(line,"%lx-%lx %4s",&low,&high,permissions)==3 && permissions[0]=='r' && begin>=low && begin+length<=high) { readable=true;break; }
    }
    fclose(maps);return readable;
}
// Private, opt-in A/B for this exact client: its measured left local controller
// offset is already handed, while the legacy constructor negates pitch/roll.
// Change only that left visual operation; right follows the same branch target.
static void ConfigureQuestLeftPalm(bool shuttingDown=false) {
    static unsigned char* base=nullptr;
    static unsigned char* instance=nullptr;
    static void* lastInstanceChecked=nullptr;
    static void** instanceGlobal=nullptr;
    static void* pinnedLibrary=nullptr;
    static bool requested=false,modified=false,blocked=false,shutdownSeen=false;
    static auto nextFileCheck=std::chrono::steady_clock::now();
    static auto nextPatchAttempt=nextFileCheck;
    if (gettid()!=EngineContextOwner) return;
    shutdownSeen=shutdownSeen || shuttingDown;
    if (shutdownSeen && !modified) {
        if (pinnedLibrary) dlclose(pinnedLibrary);
        pinnedLibrary=nullptr;base=nullptr;return;
    }
    if (blocked && !modified) return;
    const auto now=std::chrono::steady_clock::now();
    if (now>=nextFileCheck || shuttingDown) {
        requested=!shutdownSeen && !blocked && access("/data/user/0/com.gmodvr.qvrx/files/diagnostics/left-palm-native.enable",F_OK)==0;
        nextFileCheck=now+std::chrono::seconds(1);
    }
    if (shutdownSeen || blocked) requested=false;
    if (!base && requested) {
        void* library=dlopen("libclient.so",RTLD_NOW|RTLD_NOLOAD);
        if (!library) return;
        Dl_info info{};auto factory=dlsym(library,"CreateInterface");
        if (!factory || !dladdr(factory,&info) || !info.dli_fbase) {dlclose(library);return;}
        auto candidate=static_cast<unsigned char*>(info.dli_fbase);
        const unsigned char signature[]={0xff,0x83,0x04,0xd1,0xeb,0x2b,0x0a,0x6d,0xe9,0x23,0x0b,0x6d,0xfd,0x7b,0x0c,0xa9,0xfc,0x6f,0x0d,0xa9,0xfa,0x67,0x0e,0xa9,0xf8,0x5f,0x0f,0xa9,0xf6,0x57,0x10,0xa9};
        const uint32_t expected[]={0x370000b3,0x1e214000,0x1e214021,0xbd000ea0,0xbd0016a1};
        if (memcmp(candidate+0x3a1428,signature,sizeof(signature)) || memcmp(candidate+0x3a164c,expected,sizeof(expected))) {
            blocked=true;LOG("LEFT_PALM signature mismatch; no change");dlclose(library);return;
        }
        instanceGlobal=*reinterpret_cast<void***>(candidate+0xddce48);
        if (!ReadableMemory(instanceGlobal,sizeof(void*))) {dlclose(library);return;}
        base=candidate;pinnedLibrary=library;
        LOG("LEFT_PALM exact constructor/branch verified; opt-in candidate ready");
    }
    if (!base) return;
    bool cachedController=false;
    if (requested) {
        auto current=static_cast<unsigned char*>(*instanceGlobal);
        if (current!=lastInstanceChecked) {
            lastInstanceChecked=current;
            instance=ReadableMemory(current,5026)?current:nullptr;
        }
        cachedController=instance && instance[4888] && !instance[977] && instance[5024];
    }
    const bool enable=requested && cachedController;
    if (enable==modified || now<nextPatchAttempt) return;
    auto instruction=reinterpret_cast<uint32_t*>(base+0x3a164c);
    const uint32_t before=modified?0x14000005:0x370000b3;
    const uint32_t after=enable?0x14000005:0x370000b3;
    if (*instruction!=before) {blocked=true;LOG("LEFT_PALM unexpected instruction; no write");return;}
    const size_t pageSize=static_cast<size_t>(sysconf(_SC_PAGESIZE));
    void* page=reinterpret_cast<void*>(reinterpret_cast<uintptr_t>(instruction)&~(pageSize-1));
    if (mprotect(page,pageSize,PROT_READ|PROT_WRITE|PROT_EXEC)!=0) {
        LOG("LEFT_PALM code permission denied errno=%d rollback_pending=%d",errno,int(modified));
        blocked=true;nextPatchAttempt=now+std::chrono::seconds(1);return;
    }
    __atomic_store_n(instruction,after,__ATOMIC_RELEASE);
    __builtin___clear_cache(reinterpret_cast<char*>(instruction),reinterpret_cast<char*>(instruction+1));
    modified=enable;
    if (mprotect(page,pageSize,PROT_READ|PROT_EXEC)!=0) LOG("LEFT_PALM failed to restore RX errno=%d",errno);
    LOG("LEFT_PALM candidate=%d cached_controller=%d right_path_unchanged=1",int(modified),int(cachedController));
}
// Opt-in, bounded observations of the shipped client's actual per-hand local
// pose cache. No tracking, model, bone, or convar writes are performed here.
static void ProbeQuestHandOffsets() {
    static const auto start=std::chrono::steady_clock::now();
    static auto last=start;
    static bool checked=false,enabled=false;
    static unsigned samples=0;
    const auto now=std::chrono::steady_clock::now();
    if (samples>=6 || gettid()!=EngineContextOwner || now-start<std::chrono::seconds(30) || now-last<std::chrono::seconds(5)) return;
    last=now;
    if (!checked) {
        checked=true;
        const char* gate="/data/user/0/com.gmodvr.qvrx/files/diagnostics/hand-axis-probe.enable";
        enabled=access(gate,F_OK)==0;
        if (enabled) unlink(gate);
    }
    if (!enabled) return;
    void* library=dlopen("libclient.so",RTLD_NOW|RTLD_NOLOAD);
    if (!library) return;
    Dl_info info{};auto factory=dlsym(library,"CreateInterface");
    if (!factory || !dladdr(factory,&info) || !info.dli_fbase) {dlclose(library);return;}
    auto base=static_cast<unsigned char*>(info.dli_fbase);
    const unsigned char signature[]={0xff,0x03,0x02,0xd1,0xfd,0x7b,0x06,0xa9,0xf3,0x3b,0x00,0xf9,0xfd,0x83,0x01,0x91,0xf3,0x03,0x08,0xaa,0x08,0xf0,0xa7,0x52,0xff,0xc3,0x02,0xf8,0xe8,0x23,0x00,0xb9};
    if (memcmp(base+0x34b0f8,signature,sizeof(signature))!=0) {enabled=false;LOG("HAND_LOCAL signature mismatch; no observation");dlclose(library);return;}
    auto instanceGlobal=*reinterpret_cast<void***>(base+0xddce48);
    if (!ReadableMemory(instanceGlobal,sizeof(void*)) || !ReadableMemory(*instanceGlobal,5026)) {dlclose(library);return;}
    auto instance=static_cast<unsigned char*>(*instanceGlobal);
    struct alignas(16) Mat4 {float values[16];};
    using LocalPose=Mat4(*)(void*,bool);
    ++samples;
    for (int side=0;side<2;++side) {
        const Mat4 local=reinterpret_cast<LocalPose>(base+0x34b0f8)(instance,side!=0);
        Mat4 grip{};memcpy(&grip,instance+32+64*side,sizeof(grip));
        unsigned char active,tracked,cached;
        memcpy(&active,instance+4888,1);memcpy(&tracked,instance+977+side,1);memcpy(&cached,instance+5024+side,1);
        LOG("HAND_LOCAL sample=%u side=%d vr=%u skeletal=%u cached=%u matrix=%.6g,%.6g,%.6g,%.6g,%.6g,%.6g,%.6g,%.6g,%.6g,%.6g,%.6g,%.6g,%.6g,%.6g,%.6g,%.6g",samples,side,active,tracked,cached,local.values[0],local.values[1],local.values[2],local.values[3],local.values[4],local.values[5],local.values[6],local.values[7],local.values[8],local.values[9],local.values[10],local.values[11],local.values[12],local.values[13],local.values[14],local.values[15]);
        LOG("HAND_GRIP_SOURCE sample=%u side=%d matrix=%.6g,%.6g,%.6g,%.6g,%.6g,%.6g,%.6g,%.6g,%.6g,%.6g,%.6g,%.6g,%.6g,%.6g,%.6g,%.6g",samples,side,grip.values[0],grip.values[1],grip.values[2],grip.values[3],grip.values[4],grip.values[5],grip.values[6],grip.values[7],grip.values[8],grip.values[9],grip.values[10],grip.values[11],grip.values[12],grip.values[13],grip.values[14],grip.values[15]);
    }
    dlclose(library);
}
// Private lab compatibility: the transplanted client retains the layer allocator,
// but its render targets are absent at runtime. Invoke it once on the SDL engine
// thread after material-system startup; never call with another build/layout.
static void EnsureQuestLayerTargets() {
    static bool attempted=false;
    static const auto start=std::chrono::steady_clock::now();
    if (attempted || gettid()!=EngineContextOwner ||
        eglGetCurrentContext()!=EngineContext ||
        std::chrono::steady_clock::now()-start<std::chrono::seconds(30)) return;
    void* library=dlopen("libclient.so",RTLD_NOW|RTLD_NOLOAD);
    if (!library) return;
    Dl_info info{};
    auto factory=dlsym(library,"CreateInterface");
    if (!factory || !dladdr(factory,&info) || !info.dli_fbase) { dlclose(library); return; }
    auto base=static_cast<unsigned char*>(info.dli_fbase);
    const unsigned char signature[]={0xff,0x3,0x2,0xd1,0xfd,0x7b,0x2,0xa9,0xfc,0x6f,0x3,0xa9,0xfa,0x67,0x4,0xa9,0xf8,0x5f,0x5,0xa9,0xf6,0x57,0x6,0xa9,0xf4,0x4f,0x7,0xa9,0xfd,0x83,0x0,0x91};
    if (memcmp(base+0x322490,signature,sizeof(signature))!=0) {
        attempted=true; LOG("LAYERS allocator signature mismatch; no call"); dlclose(library); return;
    }
    // The allocator itself loads this relocated material-system global.
    auto materialGlobal=*reinterpret_cast<void***>(base+0xddccb0);
    if (!materialGlobal || !*materialGlobal) { dlclose(library); return; }
    attempted=true;
    LOG("LAYERS initializing retained client targets on engine thread");
    reinterpret_cast<void(*)()>(base+0x322490)();
    for (int i=0;i<5;++i) {
        auto record=base+0xde39d8+i*48;
        void* texture; int surface;
        memcpy(&texture,record+16,sizeof(texture)); memcpy(&surface,record+24,sizeof(surface));
        LOG("LAYERS target %d texture=%p surface=%d",i,texture,surface);
    }
    dlclose(library);
}

static int QuestPollEvent(void* event) {
    const int result = OriginalPollEvent(event);
    // SDL2 SDL_QUIT (0x100) is delivered before Source's IE_Quit teardown.
    uint32_t type = 0;
    if (result && event) memcpy(&type, event, sizeof(type));
    if (type!=0x100) { EnsureQuestLayerTargets(); ConfigureQuestLeftPalm(); ProbeQuestHandOffsets(); }
    else ConfigureQuestLeftPalm(true);
    if (type == 0x100 && EngineContext && gettid() == EngineContextOwner &&
        eglGetCurrentContext() == EGL_NO_CONTEXT) {
        EGLint version = 0;
        if (eglQueryContext(EngineDisplay, EngineContext, EGL_CONTEXT_CLIENT_VERSION, &version)) {
            const bool bound = eglMakeCurrent(EngineDisplay, EGL_NO_SURFACE, EGL_NO_SURFACE, EngineContext);
            LOG("QUIT context restore=%d version=%d current=%p", int(bound), version, eglGetCurrentContext());
        } else {
            LOG("QUIT context no longer valid; no stale handle rebound");
        }
    }
    return result;
}
static void* SharedCreateContext(void* window) {
    using MakeCurrent = int (*)(void*, void*);
    using SetAttribute = int (*)(int, int);
    using GetAttribute = int (*)(int, int*);
    auto makeCurrent = reinterpret_cast<MakeCurrent>(dlsym(RTLD_DEFAULT, "SDL_GL_MakeCurrent"));
    auto setAttribute = reinterpret_cast<SetAttribute>(dlsym(RTLD_DEFAULT, "SDL_GL_SetAttribute"));
    auto getAttribute = reinterpret_cast<GetAttribute>(dlsym(RTLD_DEFAULT, "SDL_GL_GetAttribute"));
    constexpr int ShareWithCurrentContext = 22;
    int previous = 0;
    if (!makeCurrent || !setAttribute || !getAttribute || !BootstrapContext || !OriginalCreateContext) {
        LOG("FAIL EGL sharing API missing"); return nullptr;
    }
    // The Android SDL driver establishes its EGL display/surface on its first
    // context creation. Create a temporary context before binding XR into SDL.
    void* temporary = OriginalCreateContext(window);
    using DeleteContext = void (*)(void*);
    auto deleteContext = reinterpret_cast<DeleteContext>(dlsym(RTLD_DEFAULT, "SDL_GL_DeleteContext"));
    using Error = const char* (*)();
    auto error = reinterpret_cast<Error>(dlsym(RTLD_DEFAULT, "SDL_GetError"));
    if (!temporary || !deleteContext) {
        LOG("FAIL SDL initial context: %s", error ? error() : "missing API"); return nullptr;
    }
    getAttribute(ShareWithCurrentContext, &previous);
    if (makeCurrent(nullptr, BootstrapContext) != 0 || setAttribute(ShareWithCurrentContext, 1) != 0) {
        LOG("FAIL could not bind bootstrap context for SDL sharing: %s egl=0x%x", error ? error() : "", eglGetError());
        deleteContext(temporary);
        return nullptr;
    }
    void* context = OriginalCreateContext(window);
    setAttribute(ShareWithCurrentContext, previous);
    deleteContext(temporary);
    if (context && (!EngineContextOwner || EngineContextOwner == gettid())) {
        EngineContext = static_cast<EGLContext>(context);
        EngineDisplay = eglGetCurrentDisplay();
        EngineContextOwner = gettid();
    }
    LOG("EGL shared context bootstrap=%p engine=%p current=%p", BootstrapContext, context, eglGetCurrentContext());
    return context;
}
static int InstallContextSharing(dl_phdr_info* info, size_t, void* result) {
    const char* basename = strrchr(info->dlpi_name, '/');
    basename = basename ? basename + 1 : info->dlpi_name;
    if (strcmp(basename, "liblauncher.so") != 0) return 0;
    const ElfW(Dyn)* dynamic = nullptr;
    for (int i = 0; i < info->dlpi_phnum; ++i)
        if (info->dlpi_phdr[i].p_type == PT_DYNAMIC)
            dynamic = reinterpret_cast<const ElfW(Dyn)*>(info->dlpi_addr + info->dlpi_phdr[i].p_vaddr);
    if (!dynamic) return 1;
    const ElfW(Sym)* symbols = nullptr;
    const char* strings = nullptr;
    const ElfW(Rela)* relocs = nullptr;
    size_t bytes = 0;
    for (auto d = dynamic; d->d_tag != DT_NULL; ++d) {
        if (d->d_tag == DT_SYMTAB) symbols = reinterpret_cast<const ElfW(Sym)*>(info->dlpi_addr + d->d_un.d_ptr);
        if (d->d_tag == DT_STRTAB) strings = reinterpret_cast<const char*>(info->dlpi_addr + d->d_un.d_ptr);
        if (d->d_tag == DT_JMPREL) relocs = reinterpret_cast<const ElfW(Rela)*>(info->dlpi_addr + d->d_un.d_ptr);
        if (d->d_tag == DT_PLTRELSZ) bytes = d->d_un.d_val;
    }
    if (!symbols || !strings || !relocs) return 1;
    for (size_t i = 0; i < bytes / sizeof(*relocs); ++i) {
        if (ELF64_R_TYPE(relocs[i].r_info) != R_AARCH64_JUMP_SLOT) continue;
        const auto& symbol = symbols[ELF64_R_SYM(relocs[i].r_info)];
        const char* name = strings + symbol.st_name;
        const bool contextFactory = strcmp(name, "SDL_GL_CreateContext") == 0;
        const bool eventPump = strcmp(name, "SDL_PollEvent") == 0;
        if (!contextFactory && !eventPump) continue;
        auto slot = reinterpret_cast<void**>(info->dlpi_addr + relocs[i].r_offset);
        auto expected = dlsym(RTLD_DEFAULT, name);
        if (*slot != expected || !expected) { LOG("FAIL unexpected SDL context import"); return 1; }
        const size_t pageSize = static_cast<size_t>(sysconf(_SC_PAGESIZE));
        void* page = reinterpret_cast<void*>(reinterpret_cast<uintptr_t>(slot) & ~(pageSize - 1));
        int protection = PROT_READ;
        for (int j = 0; j < info->dlpi_phnum; ++j) {
            const auto& ph = info->dlpi_phdr[j];
            if (ph.p_type == PT_LOAD && relocs[i].r_offset >= ph.p_vaddr && relocs[i].r_offset < ph.p_vaddr + ph.p_memsz)
                protection = PROT_READ | ((ph.p_flags & PF_W) ? PROT_WRITE : 0);
        }
        for (int j = 0; j < info->dlpi_phnum; ++j) {
            const auto& ph = info->dlpi_phdr[j];
            if (ph.p_type == PT_GNU_RELRO && relocs[i].r_offset >= ph.p_vaddr && relocs[i].r_offset < ph.p_vaddr + ph.p_memsz)
                protection &= ~PROT_WRITE;
        }
        if (mprotect(page, pageSize, protection | PROT_WRITE) != 0) return 1;
        if (contextFactory) OriginalCreateContext = reinterpret_cast<CreateContext>(expected);
        else OriginalPollEvent = reinterpret_cast<PollEvent>(expected);
        *slot = contextFactory ? reinterpret_cast<void*>(&SharedCreateContext) : reinterpret_cast<void*>(&QuestPollEvent);
        if (mprotect(page, pageSize, protection) != 0) { LOG("FAIL restoring import page protections"); return 1; }
        if (contextFactory) *static_cast<bool*>(result) = true;
        LOG("SDL bridge installed on launcher import %s", name);
    }
    return 1;
}

// Both VRXR_LocateInput and the client's IInputSystem snapshot consumer use
// the same 4288-byte payload (confirmed from their native memcpy contracts).
// Time 0 requests the already-produced XR snapshot, without extra xrLocate calls.
using LocateInput = bool (*)(int64_t, void*);
static LocateInput CachedXRInput;
static bool XRInputSnapshot(void*, void* output) {
    const bool valid = output && CachedXRInput && CachedXRInput(0, output);
    static unsigned samples = 0;
    if (valid && ((samples++ & 255u) == 0)) {
        const auto* bytes = static_cast<const unsigned char*>(output);
        float pose[7]; memcpy(pose, bytes + 8, sizeof(pose));
        uint64_t stamp; memcpy(&stamp, bytes, sizeof(stamp));
        LOG("POSE snapshot valid stamp=%llu head=(%.3f %.3f %.3f) q=(%.3f %.3f %.3f %.3f)",
            static_cast<unsigned long long>(stamp), pose[0], pose[1], pose[2], pose[3], pose[4], pose[5], pose[6]);
    }
    return valid;
}
static bool InstallInputSnapshotBridge(void* xr) {
    void* library = dlopen("libinputsystem.so", RTLD_NOW | RTLD_LOCAL);
    using Factory = void* (*)(const char*, int*);
    auto create = library ? reinterpret_cast<Factory>(dlsym(library, "CreateInterface")) : nullptr;
    CachedXRInput = reinterpret_cast<LocateInput>(dlsym(xr, "VRXR_LocateInput"));
    void* input = create ? create("InputSystemVersion002", nullptr) : nullptr;
    if (!input || !CachedXRInput) return false;
    auto table = *reinterpret_cast<void***>(input);
    void** slot = table + 464 / sizeof(void*);
    Dl_info owner{};
    if (!dladdr(*slot, &owner) || !owner.dli_fbase ||
        reinterpret_cast<uintptr_t>(*slot) - reinterpret_cast<uintptr_t>(owner.dli_fbase) != 0x174d4) return false;
    const unsigned char stub[] = {0xe0,0x03,0x1f,0x2a,0xc0,0x03,0x5f,0xd6};
    if (memcmp(*slot, stub, sizeof(stub)) != 0) return false;
    // Query actual page permissions rather than leave the read-only vtable writable.
    int protection = 0;
    if (FILE* maps = fopen("/proc/self/maps", "r")) {
        char line[512], permissions[5]; unsigned long start, end;
        while (fgets(line, sizeof(line), maps)) {
            if (sscanf(line, "%lx-%lx %4s", &start, &end, permissions) == 3 &&
                reinterpret_cast<uintptr_t>(slot) >= start && reinterpret_cast<uintptr_t>(slot) < end) {
                protection = (permissions[0]=='r' ? PROT_READ:0) | (permissions[1]=='w' ? PROT_WRITE:0) | (permissions[2]=='x' ? PROT_EXEC:0); break;
            }
        }
        fclose(maps);
    }
    if (!(protection & PROT_READ) || (protection & PROT_EXEC)) return false;
    const size_t pageSize = static_cast<size_t>(sysconf(_SC_PAGESIZE));
    void* page = reinterpret_cast<void*>(reinterpret_cast<uintptr_t>(slot) & ~(pageSize - 1));
    if (mprotect(page, pageSize, protection | PROT_WRITE) != 0) return false;
    *slot = reinterpret_cast<void*>(&XRInputSnapshot);
    if (mprotect(page, pageSize, protection) != 0) return false;
    LOG("POSE installed cached XR snapshot provider for InputSystemVersion002");
    return true;
}

static bool EnsureContentDirectory(const std::string& path) {
    for (size_t i = 1; i <= path.size(); ++i) {
        if (i != path.size() && path[i] != '/') continue;
        const std::string dir = path.substr(0, i);
        if (mkdir(dir.c_str(), 0700) != 0 && errno != EEXIST) return false;
        struct stat st{};
        if (stat(dir.c_str(), &st) != 0 || !S_ISDIR(st.st_mode)) return false;
    }
    return true;
}
static bool InstallVRContent(JNIEnv* env, jobject activity) {
    jclass cls = env->GetObjectClass(activity);
    jmethodID method = env->GetMethodID(cls, "getAssets", "()Landroid/content/res/AssetManager;");
    jobject object = method ? env->CallObjectMethod(activity, method) : nullptr;
    env->DeleteLocalRef(cls);
    if (env->ExceptionCheck()) { env->ExceptionClear(); return false; }
    AAssetManager* assets = object ? AAssetManager_fromJava(env, object) : nullptr;
    if (!assets) { if (object) env->DeleteLocalRef(object); return false; }
    AAsset* manifest = AAssetManager_open(assets, "quest_lab_vr_content.tsv", AASSET_MODE_BUFFER);
    if (!manifest) { env->DeleteLocalRef(object); return false; }
    const auto length = AAsset_getLength(manifest);
    const char* data = static_cast<const char*>(AAsset_getBuffer(manifest));
    std::string listing = data && length > 0 ? std::string(data, length) : std::string();
    AAsset_close(manifest);
    const std::string root = "/storage/emulated/0/Android/data/com.gmodvr.qvrx/files/user/vr_content/";
    bool ok = !listing.empty() && EnsureContentDirectory(root);
    unsigned installed = 0, existing = 0;
    std::vector<char> buffer(256 * 1024);
    for (size_t pos = 0; ok && pos < listing.size();) {
        size_t end = listing.find('\n', pos);
        if (end == std::string::npos) { ok = false; break; }
        const std::string line = listing.substr(pos, end-pos); pos = end+1;
        const auto tab = line.find('\t');
        if (tab == std::string::npos) { ok = false; break; }
        char* numberEnd = nullptr;
        const unsigned long long expected = strtoull(line.c_str(), &numberEnd, 10);
        const std::string relative = line.substr(tab+1);
        if (numberEnd != line.c_str()+tab || relative.empty() || relative[0]=='/' || relative.find("..")!=std::string::npos) { ok = false; break; }
        const std::string target = root + relative;
        struct stat st{};
        if (relative.compare(0,4,"lua/") != 0 && stat(target.c_str(), &st)==0 && S_ISREG(st.st_mode) && static_cast<unsigned long long>(st.st_size)==expected) { ++existing; continue; }
        if (!EnsureContentDirectory(target.substr(0,target.find_last_of('/')))) { ok=false; break; }
        AAsset* asset = AAssetManager_open(assets, ("quest_lab_vr_content/"+relative).c_str(), AASSET_MODE_STREAMING);
        if (!asset || static_cast<unsigned long long>(AAsset_getLength64(asset))!=expected) { if(asset) AAsset_close(asset); ok=false; break; }
        const std::string temporary = target+".quest-lab-part";
        FILE* output = fopen(temporary.c_str(), "wb");
        unsigned long long written=0;
        if (!output) ok=false;
        while (ok) {
            int n = AAsset_read(asset, buffer.data(), buffer.size());
            if (n<0) {ok=false;break;} if(n==0) break;
            if (fwrite(buffer.data(),1,n,output)!=static_cast<size_t>(n)) {ok=false;break;}
            written+=n;
        }
        AAsset_close(asset);
        if (output && fclose(output)!=0) ok=false;
        if (written!=expected || !ok || rename(temporary.c_str(),target.c_str())!=0) {ok=false;unlink(temporary.c_str());break;}
        ++installed;
    }
    env->DeleteLocalRef(object);
    LOG("CONTENT ready=%d installed=%u existing=%u root=%s", int(ok), installed, existing, root.c_str());
    return ok;
}

static std::string EyeTier = "1032x1104";
static std::string Foveation = "2";
static std::string RefreshRate = "72";
static void ReadQuestProfile() {
    FILE* file = fopen("/storage/emulated/0/Android/data/com.gmodvr.qvrx/files/user/garrysmod/data/gquest_vr_profile.txt", "r");
    if (!file) return;
    char tier[64] = {}, ffr[16] = {}, rate[16] = {};
    if (fgets(tier,sizeof(tier),file)) {
        tier[strcspn(tier,"\r\n")] = 0;
        for (const char* allowed : {"1032x1104","1548x1656","1680x1760"})
            if (strcmp(tier,allowed)==0) EyeTier=allowed;
    }
    if (fgets(ffr,sizeof(ffr),file)) {
        ffr[strcspn(ffr,"\r\n")] = 0;
        if (strlen(ffr)==1 && ffr[0]>='0' && ffr[0]<='3') Foveation=ffr;
    }
    if (fgets(rate,sizeof(rate),file)) {
        rate[strcspn(rate,"\r\n")] = 0;
        if (strcmp(rate,"72")==0 || strcmp(rate,"90")==0) RefreshRate=rate;
    }
    fclose(file);
    LOG("PROFILE eye=%s ffr=%s refresh=%s",EyeTier.c_str(),Foveation.c_str(),RefreshRate.c_str());
}

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

extern "C" int LauncherMainAndroid(int argc, char** argv) {
    // Keep the original engine loaded as a distinct dependency. This wrapper
    // changes no original native instructions and runs only in the lab package.
    void* engine = dlopen("liblauncher.so", RTLD_NOW | RTLD_LOCAL);
    void* xr = dlopen("libvrxr.so", RTLD_NOW | RTLD_LOCAL);
    using Main = int (*)(int, char**);
    using Env = JNIEnv* (*)();
    using Activity = jobject (*)();
    using Bootstrap = bool (*)(JavaVM*, jobject);
    using Start = bool (*)(int);
    using Shutdown = void (*)();
    using WaitHandover = bool (*)(int);
    using Ready = bool (*)();
    using Status = int (*)();
    using Message = int (*)(unsigned, const char*, const char*, void*);
    auto main = engine ? reinterpret_cast<Main>(dlsym(engine, "LauncherMainAndroid")) : nullptr;
    auto getEnv = reinterpret_cast<Env>(dlsym(RTLD_DEFAULT, "SDL_AndroidGetJNIEnv"));
    auto getActivity = reinterpret_cast<Activity>(dlsym(RTLD_DEFAULT, "SDL_AndroidGetActivity"));
    auto bootstrap = xr ? reinterpret_cast<Bootstrap>(dlsym(xr, "VRXR_BootstrapSession")) : nullptr;
    auto start = xr ? reinterpret_cast<Start>(dlsym(xr, "VRXR_StartPresentationThread")) : nullptr;
    auto shutdown = xr ? reinterpret_cast<Shutdown>(dlsym(xr, "VRXR_Shutdown")) : nullptr;
    auto waitHandover = xr ? reinterpret_cast<WaitHandover>(dlsym(xr, "VRXR_WaitForEngineHandover")) : nullptr;
    auto ready = xr ? reinterpret_cast<Ready>(dlsym(xr, "VRXR_IsBootstrapped")) : nullptr;
    auto startupStatus = xr ? reinterpret_cast<Status>(dlsym(xr, "VRXR_GetPresentationStartupStatus")) : nullptr;
    auto message = reinterpret_cast<Message>(dlsym(RTLD_DEFAULT, "SDL_ShowSimpleMessageBox"));
    if (!main || !getEnv || !getActivity || !bootstrap || !start || !shutdown || !waitHandover || !ready || !startupStatus) {
        LOG("FAIL required launcher/SDL/XR entry missing: %s", dlerror());
        return 1;
    }
    JNIEnv* env = getEnv();
    JavaVM* vm = nullptr;
    if (!env || env->GetJavaVM(&vm) != JNI_OK) {
        LOG("FAIL SDL thread has no VM"); return 1;
    }
    jobject activity = getActivity();
    if (!activity) { LOG("FAIL SDL activity missing"); return 1; }
    LOG("ENTRY SDL engine thread argc=%d", argc);
    if (!InstallVRContent(env, activity)) {
        LOG("STOP incomplete VR content installation"); env->DeleteLocalRef(activity); return 1;
    }
    // This allowlisted XR setting is startup-latched, before swapchain creation.
    ReadQuestProfile();
    setenv("SOURCEVR_EYE_RESOLUTION", EyeTier.c_str(), 1);
    const bool boot = bootstrap(vm, activity);
    BootstrapContext = eglGetCurrentContext();
    LOG("EGL bootstrap current=%p display=%p", BootstrapContext, eglGetCurrentDisplay());
    LOG("RESULT bootstrap=%d", int(boot));
    if (!boot) { shutdown(); env->DeleteLocalRef(activity); return 1; }
    // Startup status 2 is published after a successful presentation frame.
    // Starting directly in mode 2 handed over after zero frames and left status
    // 1, causing the engine's IsBootstrapped guard to reject the XR session.
    const bool presentation = start(0);
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(5);
    int status = startupStatus();
    while (presentation && status == 1 && std::chrono::steady_clock::now() < deadline) {
        usleep(10000);
        status = startupStatus();
    }
    LOG("RESULT startup_status=%d ready_before_handover=%d", status, int(ready()));
    const bool handedOver = presentation && status == 2 && waitHandover(5000);
    const bool rendererReady = handedOver && ready();
    LOG("RESULT presentation=%d handover=%d renderer_ready=%d", int(presentation), int(handedOver), int(rendererReady));
    if (!rendererReady) {
        // Do not run the flat renderer alongside an unclaimed XR context.
        // The captured first lab run failed buffer mappings and crashed here.
        LOG("STOP engine launch withheld: XR renderer ownership is not ready");
        shutdown();
        if (message) message(0x10, "GMod Quest Lab", "VR renderer is not ready. The experimental start was stopped. Original GDroid is unchanged.", nullptr);
        env->DeleteLocalRef(activity);
        return 1;
    }
    bool sharingInstalled = false;
    dl_iterate_phdr(InstallContextSharing, &sharingInstalled);
    if (!BootstrapContext || !sharingInstalled) {
        LOG("STOP engine launch withheld: context sharing unavailable");
        shutdown(); env->DeleteLocalRef(activity); return 1;
    }
    if (!InstallInputSnapshotBridge(xr)) {
        LOG("STOP engine launch withheld: VR input snapshot bridge unavailable");
        shutdown(); env->DeleteLocalRef(activity); return 1;
    }
    // VRManager activation reads hlvr_isvrplayer before it requests SourceXR010.
    // Set the startup cvar before +map; never change it during a running map.
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
    const int vrArgc = static_cast<int>(vrArgs.size());
    vrArgs.push_back(nullptr);
    LOG("READY calling original launcher with -vr at initialization and hlvr_isvrplayer=1 before map");
    const int result = main(vrArgc, vrArgs.data());
    LOG("RESULT original launcher returned=%d", result);
    shutdown();
    env->DeleteLocalRef(activity);
    return result;
}

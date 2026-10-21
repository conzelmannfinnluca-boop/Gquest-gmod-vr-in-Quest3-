// Exact-build experiment: replace only the inputs to the native finger blend.
// The original routine still reads controller curls; palm/root and left hand
// always follow the original path. Removing the gate restores the call site.
#include <atomic>
#include "gquest_native_finger_profiles.h"
using GquestBlendFingers = void(*)(void*,bool,const void*,const void*,bool);
static GquestBlendFingers GquestOriginalBlendFingers=nullptr;
static std::atomic<int> GquestFingerProfile{-1};
static void GquestBlendFingersHook(void* output,bool right,const void* open,const void* closed,bool grasp) {
    const int profile=GquestFingerProfile.load(std::memory_order_relaxed);
    if (!right || profile<0 || profile>=GquestFingerProfileCount) {
        GquestOriginalBlendFingers(output,right,open,closed,grasp);return;
    }
    alignas(16) unsigned char ownOpen[460],ownClosed[460];
    memcpy(ownOpen,open,sizeof(ownOpen));memcpy(ownClosed,closed,sizeof(ownClosed));
    memcpy(ownOpen+24,GquestFingerProfiles[profile],15*3*sizeof(float));
    memcpy(ownClosed+24,GquestFingerProfiles[profile]+15,15*3*sizeof(float));
    GquestOriginalBlendFingers(output,right,ownOpen,ownClosed,grasp);
    static int reported=-1;
    if (reported!=profile) {
        reported=profile;
        float baseline[3],actual[3];
        memcpy(baseline,static_cast<const char*>(open)+24+3*12,12);
        memcpy(actual,static_cast<char*>(output)+24+3*12,12);
        LOG("NATIVE_FINGERS applied profile=%d right=1 index_baseline=%.2f,%.2f,%.2f index_result=%.2f,%.2f,%.2f root_unchanged=1",profile,
            baseline[0],baseline[1],baseline[2],actual[0],actual[1],actual[2]);
    }
}
static void ConfigureGquestNativeFingers(bool shutdown=false) {
    static bool stopped=false,blocked=false,installed=false;
    static uint32_t* site=nullptr;
    static uint32_t before=0,after=0;
    static void* pinned=nullptr;
    static auto next=std::chrono::steady_clock::time_point{};
    stopped=stopped || shutdown;
    if (gettid()!=EngineContextOwner || blocked) return;
    auto now=std::chrono::steady_clock::now();
    if (!shutdown && now<next) return;
    next=now+std::chrono::milliseconds(200);
    const bool requested=!stopped && access("/data/user/0/com.gmodvr.qvrx/files/diagnostics/native-weapon-fingers.enable",F_OK)==0;
    int selected=-1;
    if (requested) {
        if (FILE* file=fopen("/sdcard/Android/data/com.gmodvr.qvrx/files/user/garrysmod/data/gquest_native_weapon_pose.txt","r")) {
            char value[80]={};
            if (fgets(value,sizeof(value),file)) {
                value[strcspn(value,"\r\n")]=0;
                for (int i=0;i<GquestFingerProfileCount;++i) if (strcmp(value,GquestFingerProfileNames[i])==0) selected=i;
            }
            fclose(file);
        }
    }
    GquestFingerProfile.store(selected,std::memory_order_relaxed);
    if (!site && requested) {
        void* library=dlopen("libclient.so",RTLD_NOW|RTLD_NOLOAD);
        if (!library) return;
        Dl_info info{};void* factory=dlsym(library,"CreateInterface");
        if (!factory || !dladdr(factory,&info) || !info.dli_fbase) {dlclose(library);return;}
        auto base=static_cast<unsigned char*>(info.dli_fbase);
        const unsigned char signature[]={0xff,0x83,0x3,0xd1,0xe8,0x4b,0x0,0xfd,0xfd,0xfb,0x9,0xa9};
        if (memcmp(base+0x46e7b4,signature,sizeof(signature))!=0) {
            blocked=true;LOG("NATIVE_FINGERS original signature mismatch; unchanged");dlclose(library);return;
        }
        auto candidate=reinterpret_cast<uint32_t*>(base+0x46ed18);
        memcpy(&before,candidate,4);
        const int64_t originalDiff=0x46e7b4-0x46ed18;
        if (before!=(0x94000000u|(static_cast<uint32_t>(originalDiff/4)&0x03ffffffu))) {
            blocked=true;LOG("NATIVE_FINGERS call signature mismatch; unchanged");dlclose(library);return;
        }
        const size_t size=static_cast<size_t>(sysconf(_SC_PAGESIZE));
        const uintptr_t address=reinterpret_cast<uintptr_t>(candidate);
        void* stub=MAP_FAILED;
        // MAP_FIXED_NOREPLACE never displaces any existing process mapping.
        for (int i=1;i<64 && stub==MAP_FAILED;++i) {
            for (int sign: {1,-1}) {
                const uintptr_t nearby=(address+sign*int64_t(i)*0x200000)&~(size-1);
                stub=mmap(reinterpret_cast<void*>(nearby),size,PROT_READ|PROT_WRITE,
                    MAP_PRIVATE|MAP_ANONYMOUS|0x100000,-1,0);
                if (stub!=MAP_FAILED) {
                    if (reinterpret_cast<uintptr_t>(stub)!=nearby) {munmap(stub,size);stub=MAP_FAILED;}
                    else break;
                }
            }
        }
        if (stub==MAP_FAILED) {blocked=true;LOG("NATIVE_FINGERS no nearby stub; unchanged");dlclose(library);return;}
        const uint32_t instructions[]={0x58000050u,0xd61f0200u}; // ldr x16,+8; br x16
        const uintptr_t destination=reinterpret_cast<uintptr_t>(&GquestBlendFingersHook);
        memcpy(stub,instructions,8);memcpy(static_cast<char*>(stub)+8,&destination,8);
        __builtin___clear_cache(static_cast<char*>(stub),static_cast<char*>(stub)+16);
        if (mprotect(stub,size,PROT_READ|PROT_EXEC)!=0) {munmap(stub,size);blocked=true;dlclose(library);return;}
        const int64_t diff=reinterpret_cast<int64_t>(stub)-static_cast<int64_t>(address);
        if (diff%4 || diff<-(1ll<<27) || diff>=(1ll<<27)) {munmap(stub,size);blocked=true;dlclose(library);return;}
        after=0x94000000u|(static_cast<uint32_t>(diff/4)&0x03ffffffu);
        GquestOriginalBlendFingers=reinterpret_cast<GquestBlendFingers>(base+0x46e7b4);
        site=candidate;pinned=library;
    }
    if (!site || installed==requested) return;
    const uint32_t expected=installed?after:before;
    if (*site!=expected) {blocked=true;GquestFingerProfile.store(-1);LOG("NATIVE_FINGERS unexpected call; no write");return;}
    const size_t size=static_cast<size_t>(sysconf(_SC_PAGESIZE));
    void* page=reinterpret_cast<void*>(reinterpret_cast<uintptr_t>(site)&~(size-1));
    if (mprotect(page,size,PROT_READ|PROT_WRITE|PROT_EXEC)!=0) {GquestFingerProfile.store(-1);return;}
    __atomic_store_n(site,requested?after:before,__ATOMIC_RELEASE);
    __builtin___clear_cache(reinterpret_cast<char*>(site),reinterpret_cast<char*>(site+1));
    installed=requested;
    if (mprotect(page,size,PROT_READ|PROT_EXEC)!=0) LOG("NATIVE_FINGERS cannot restore RX errno=%d",errno);
    LOG("NATIVE_FINGERS bridge=%d exact_call_verified=1 left_and_root_original=1",int(installed));
    (void)pinned;
}

#include <cstdio>
#include <cstring>
#include <cstdint>
#include <chrono>
#include <initializer_list>
#include <sys/mman.h>
#include <dlfcn.h>
#include <unistd.h>
#include <cassert>
#define LOG(...) do {} while(0)
static pid_t EngineContextOwner=0;
#include "gquest_native_fingers.h"
static const void* seenOpen;
static const void* seenClosed;
static bool seenRight,seenGrasp;
static unsigned char copiedOpen[460],copiedClosed[460];
static void Original(void* output,bool right,const void* open,const void* closed,bool grasp) {
    seenOpen=open;seenClosed=closed;seenRight=right;seenGrasp=grasp;
    memcpy(copiedOpen,open,460);memcpy(copiedClosed,closed,460);memcpy(output,open,460);
}
int main() {
    unsigned char open[460],closed[460],output[460];
    for (int i=0;i<460;++i) {open[i]=static_cast<unsigned char>(i);closed[i]=static_cast<unsigned char>(255-i);}
    GquestOriginalBlendFingers=&Original;
    for (int profile=0;profile<GquestFingerProfileCount;++profile) {
        GquestFingerProfile.store(profile);
        GquestBlendFingersHook(output,true,open,closed,true);
        assert(seenRight && seenGrasp);
        assert(memcmp(copiedOpen,open,24)==0 && memcmp(copiedClosed,closed,24)==0);
        assert(memcmp(copiedOpen+204,open+204,256)==0);
        assert(memcmp(copiedClosed+204,closed+204,256)==0);
        assert(memcmp(copiedOpen+24,GquestFingerProfiles[profile],180)==0);
        assert(memcmp(copiedClosed+24,GquestFingerProfiles[profile]+15,180)==0);
        GquestBlendFingersHook(output,false,open,closed,false);
        assert(seenOpen==open && seenClosed==closed && !seenRight && !seenGrasp);
        assert(memcmp(output,open,460)==0);
    }
    for (int invalid: {-1,GquestFingerProfileCount,123}) {
        GquestFingerProfile.store(invalid);
        GquestBlendFingersHook(output,true,open,closed,false);
        assert(seenOpen==open && seenClosed==closed && memcmp(output,open,460)==0);
    }
    puts("PASS native finger wrapper: all profiles, left/root/flags untouched, original input interpolation, invalid/off passthrough");
}

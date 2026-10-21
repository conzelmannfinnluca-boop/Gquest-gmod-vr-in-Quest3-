#pragma once
#include <stdint.h>
// Owned Rust storage lives until destroy; the GDroid launcher may edit argv
// bytes in place but must not extend strings or retain them past destroy.
struct GquestRuntime;
struct GquestProfile {
    uint32_t abi_version;
    uint32_t eye_width;
    uint32_t eye_height;
    uint32_t foveation;
    uint32_t refresh_rate;
    uint32_t profile_loaded;
};
static_assert(sizeof(GquestProfile) == 24, "Rust profile ABI size");
extern "C" {
uint32_t gquest_runtime_abi();
GquestRuntime* gquest_runtime_create(int32_t argc, const char* const* argv);
void gquest_runtime_destroy(GquestRuntime* runtime);
bool gquest_runtime_profile(const GquestRuntime* runtime, GquestProfile* output);
int32_t gquest_runtime_argc(const GquestRuntime* runtime);
char** gquest_runtime_argv(GquestRuntime* runtime);
}

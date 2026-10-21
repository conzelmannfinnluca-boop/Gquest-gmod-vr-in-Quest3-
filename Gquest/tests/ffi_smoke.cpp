#include "gquest_runtime.h"
#include <cassert>
#include <cstring>
#include <cstdio>
#include <vector>
#include <string>
#define LOG(...) ((void)0)
#include "gdroid_startup_reference.inc"
int main() {
    assert(gquest_runtime_abi() == 1);
    const char* input[] = {"gmod", "+map", "gm_flatgrass"};
    auto* runtime = gquest_runtime_create(3, input);
    assert(runtime);
    GquestProfile profile{};
    assert(gquest_runtime_profile(runtime, &profile));
    assert(profile.abi_version == 1 && profile.eye_width == 1032 && profile.refresh_rate == 72);
    auto argc = gquest_runtime_argc(runtime);
    auto argv = gquest_runtime_argv(runtime);
    assert(argc > 20 && argv[argc] == nullptr);
    assert(!strcmp(argv[0], "gmod") && !strcmp(argv[1], "-vr"));
    int map = -1, vr = -1;
    for (int i = 0; i < argc; ++i) {
        if (!strcmp(argv[i], "+map")) map = i;
        if (!strcmp(argv[i], "+hlvr_isvrplayer")) vr = i;
    }
    assert(vr > 1 && vr < map && !strcmp(argv[map + 1], "gm_flatgrass"));
    argv[0][0] = 'G'; // Caller-owned edit is permitted during launcher execution.
    gquest_runtime_destroy(runtime);
    assert(!gquest_runtime_create(1, nullptr));
    for (const auto& test: std::vector<std::vector<std::string>> {
        {"gmod"}, {"gmod", "+map", "gm_construct"},
        {"gmod", "+connect", "example"}, {"gmod", "+load", "savedgame"},
        {"gmod", "+changelevel", "gm_flatgrass"},
        {"gmod", "-console", "+map", "gm_flatgrass", "+vr_refresh_rate", "90"},
    }) {
        std::vector<char*> input;
        for (const auto& arg: test) input.push_back(const_cast<char*>(arg.c_str()));
        auto expected = gdroid_reference(input.size(), input.data());
        // Intentional policy delta from the frozen, previously tested startup:
        // synchronous context ownership and fixed right-controller menu pointer.
        const std::vector<std::string> menuPolicy={"+mat_queue_mode","0",
            "+gmod_derma_vr_pointer_hand","0","+gmod_derma_vr_placement","2",
            "+gmod_derma_vr_outline","1","+gmod_derma_vr_bg","180"};
        size_t policyAt=0;
        while(policyAt<expected.size() && expected[policyAt]!="+hlvr_isvrplayer") ++policyAt;
        assert(policyAt<expected.size());
        expected.insert(expected.begin()+policyAt,menuPolicy.begin(),menuPolicy.end());
        auto* runtime = gquest_runtime_create(input.size(), input.data());
        assert(runtime);
        auto argc = gquest_runtime_argc(runtime);
        auto argv = gquest_runtime_argv(runtime);
        assert(argc == static_cast<int>(expected.size()));
        for (int i = 0; i < argc; ++i) assert(expected[i] == argv[i]);
        gquest_runtime_destroy(runtime);
    }
    std::puts("GDroid/Rust launcher: 6 cases match frozen startup plus explicit verified menu policy");
    std::puts("C++/Rust ABI smoke: passed");
}

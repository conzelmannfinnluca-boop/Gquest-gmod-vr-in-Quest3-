#include <android_native_app_glue.h>
#include <android/log.h>
#include <dlfcn.h>
#include <unistd.h>
#include <chrono>

#define NOTE(...) __android_log_print(ANDROID_LOG_INFO, "GDROID_BOOT_PROBE", __VA_ARGS__)

// Experimental ABI recovered from this exact GDroid ARM64 library. This is
// deliberately an isolated initialization test, not a GMod replacement launcher.
void android_main(android_app* app) {
    app_dummy();
    NOTE("ENTRY native activity diagnostic started");
    JNIEnv* env = nullptr;
    const bool attached = app->activity->vm->AttachCurrentThread(&env, nullptr) == JNI_OK;
    if (!attached) { NOTE("FAIL attach thread"); ANativeActivity_finish(app->activity); return; }
    int events;
    android_poll_source* source = nullptr;
    // Immersive Quest activities need not supply a 2D Android window. GDroid's
    // bootstrap owns an EGL pbuffer, so waiting for app->window deadlocks here.
    void* library = dlopen("libvrxr.so", RTLD_NOW | RTLD_LOCAL);
    if (!library) {
        NOTE("FAIL dlopen: %s", dlerror());
    } else {
        using Bootstrap = bool (*)(JavaVM*, jobject);
        using IsBootstrapped = bool (*)();
        using Shutdown = void (*)();
        using StartPresentation = bool (*)(int);
        auto bootstrap = reinterpret_cast<Bootstrap>(dlsym(library, "VRXR_BootstrapSession"));
        auto ready = reinterpret_cast<IsBootstrapped>(dlsym(library, "VRXR_IsBootstrapped"));
        auto shutdown = reinterpret_cast<Shutdown>(dlsym(library, "VRXR_Shutdown"));
        auto startPresentation = reinterpret_cast<StartPresentation>(dlsym(library, "VRXR_StartPresentationThread"));
        if (!bootstrap || !ready || !shutdown || !startPresentation) {
            NOTE("FAIL required symbols missing");
        } else if (!app->destroyRequested) {
            NOTE("Calling bootstrap with Android VM/activity; no GMod or frame submission");
            const bool ok = bootstrap(app->activity->vm, app->activity->clazz);
            NOTE("RESULT bootstrap=%d is_bootstrapped=%d", int(ok), int(ready()));
            if (ok) {
                // Mode 2 is the engine handover mode observed in this library.
                // Test only its owned presentation thread; no GMod frame owner.
                const bool started = startPresentation(2);
                NOTE("RESULT presentation_started=%d", int(started));
                const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(3);
                while (!app->destroyRequested && std::chrono::steady_clock::now() < deadline) {
                    source = nullptr;
                    if (ALooper_pollAll(50, nullptr, &events, reinterpret_cast<void**>(&source)) >= 0 && source) source->process(app, source);
                }
                NOTE("RESULT after_presentation is_bootstrapped=%d", int(ready()));
            }
            shutdown();
            NOTE("RESULT shutdown_complete is_bootstrapped=%d", int(ready()));
        }
        // Keep the library mapped until process exit; it may own cached callbacks.
    }
    ANativeActivity_finish(app->activity);
    while (!app->destroyRequested) {
        source = nullptr;
        if (ALooper_pollAll(100, nullptr, &events, reinterpret_cast<void**>(&source)) >= 0 && source) source->process(app, source);
    }
    app->activity->vm->DetachCurrentThread();
}

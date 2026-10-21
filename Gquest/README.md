# Gquest — GDroid0.1.30, native HL2 weapons

Active target: standalone Quest3/3S with the GDroid GMod runtime. ArcVR has been removed at the user’s request. Older Rust prototypes and retired weapon sources remain private backups outside the active package.

Build in the existing private workspace:

```sh
rtk proxy python3 Gquest-Hybrid/tools/build.py
```

Requires the pinned official0.1.30 ARM64 APK, private game/VR assets, Android/JDK toolchains and local signing key. No engine, assets, SDK or keys are included in the source ZIP. The historical Gquest-Hybrid name refers to the small Rust argument/profile component and C++ bootstrap, using one existing GDroid OpenXR session.

The build verifies the official digest and native signatures, Rust/C++ ABI, native finger wrapper, own VRLua API, retirement migration, APK signature, payload identities and unchanged upstream libraries. Only the previously audited manifest, DEX launcher reference and four-byte VR-player instruction modify existing official APK entries. Own bridge, Lua and VR assets are added.

## Current weapon work

The APK ships zero ArcVR payload files; all four ArcVR classes were verified absent on the Quest after startup. The migration moved exactly63 old owned files from vr_content to an unmounted retired_content/arcvr-20261021 backup. Unrelated addons are retained. Repeated launches and backup collisions are tested. Twelve native HL2/Physgun finger profiles remain; ArcVR profiles are removed.

HLVR entities had retained retail w_* models. The allowlisted server policy selects matching shipped VR models after Deploy and on initial load. A separate defect left both native grip caches effectively at zero. Those caches are refreshed from actual model attachment frames via the engine’s SetSaveValue API, with finite/range/schema checks and rollback of partial writes. No synthetic tracking, ammunition or two-hand poses are supplied. Weapon selection reuses owned hlvr_ aliases instead of giving duplicates.

Wearer confirmations on Quest3: pistol orientation now correct; SMG grip/shooting good; SMG two-handed stable while one-handed placement remains correct after cache refresh. Final installation/restart evidence and exact APK SHA are in outputs/Gquest-HL2-only-verification.json. Other weapon fits and reload gestures still require individual visual regression tests. Complete PCVR/GMod addon equivalence and Quest3S hardware behavior are not established.

Head tracking, corrected left palm, removed wrist HUD, own native VRLua API and confirmed menu fixes are retained. Native hooks remain opt-in via existing private diagnostics files. Source export: rtk proxy python3 work/package_gdroid_source.py.

The native muzzle cache now refreshes with the actual VR model attachment frames, including transactional rollback of all seven writes. A stale retail muzzle frame had caused visible shots to miss their intended target. Native damage/ammunition rules remain unchanged. Wearer confirmed shotgun, AR2, Magnum, crossbow and RPG hits/damage; pistol damage was observed through native impact/health events. See outputs/Gquest-HL2-damage-verification.json. Crowbar direction is now wearer-confirmed with a dedicated -90-degree native grip-pitch correction. It derives from the model attachment on each Deploy, does not accumulate, and does not affect firearm grips. Physical melee damage still needs wearer verification.

# Left-hand regression audit — 18 October 2026

Read-only review of existing native bridge, shipped APK, previous runtime logs and hand audits. No device, production source, flags, model or native instruction edits were made by this worker.

## Evidence

- Root measured the installed APK as SHA256 544edd6c0536167fe61f1d604dfd57b4e0388c8d91c268163892dc8f6eb755c4, matching current host APK despite stale status text claiming uninstalled.
- APK lib/arm64-v8a/liblauncheq.so and work/liblauncheq.so are byte-identical SHA256 373135b2f19e3e3d81dc287e522bfec518cf2826c3d707987660e3d39c81850f; both contain LEFT_PALM log strings.
- Root recovered work/latest-bridge-before-nohud.log: 90 lines, one ENTRY, successful layer targets and valid pose snapshots, but no LEFT_PALM ready/signature/candidate/rollback message. This does not prove the patch was active. In current code ready is logged before checking cached-controller validity, so invalid controller cache alone cannot explain the total absence of ready.
- Root reports left-palm-native.enable currently exists; that does not establish its presence/readability during the recovered previous session.
- ConfigureQuestLeftPalm is unchanged from the wearer-confirmed candidate. It checks the flag at most once per second, exact native signatures, engine-owner thread, then enables only VRactive4888 && !skeletalLeft977 && cacheLeft5024. It restores the original instruction when this path becomes inactive.
- Candidate changes VA0x3a164c from0x370000b3 to0x14000005. Right branch semantics are identical. Left skips legacy pitch/roll negation only. Global grip yaw must remain confirmed zero.

## Smallest diagnostic

Fresh launch with wearer and both tracked controllers: collect only the new ENTRY scope and check LEFT_PALM ready then candidate=1 cached_controller=1. If no ready appears, verify flag readable by the running application and no SDL_QUIT was observed before initialization. If candidate1 appears but visual palm is wrong, capture current glove image plus same-frame left/right local-cache matrices and rendered palm matrices before proposing another rotation.

The earlier HAND_LOCAL probe is bounded six samples and requires a fresh-process one-shot gate; root owns any device action. Existing gquest_hand_frame_probe.lua samples both palm-to-tracking relations at render hook, but player bone matrices may not be the actual native first-person glove and cannot alone certify skin appearance.

## HUD removal dependency

The first44 lines of gquest_wrist_hud.lua implement GquestXR.GetWorldTracking, required by ArcVR weapon posing and hand probes. Preserve or extract that provider when removing HUD rendering. HUD placement code only draws a3D2D panel and does not edit hand bones. Removing HUD cannot itself repair a rotated native palm.

## Limits

Previous bind audit found actual left/right hand bind transforms unchanged in VR-body pairs; finger changes under one degree do not justify rewriting models for a large palm twist. Native skeletal mode, cache fallback, rendered mesh identity and latest wearer image remain current-session questions. No guessed global or finger rotations are supported by this audit.

# Native XR inputs and first source shooting slice

Static evidence in `work/lua-shared-full.asm`:

* Wrapper VA0x118bf4: `vr.GetAnalog(name, hand=-1)` checks string arg1,
  optional integer arg2, finds actionset `gameplay`, and returns **x,y,active**.
* Wrapper VA0x118cc4: `vr.GetDigital(name, hand=-1)` returns
  **state,changed,active**. VRXR_GetDigitalAction writes these outputs at
  VA0x4a98c/0x4a994/0x4a99c in `work/vrxr-full.asm`.
* Wrapper VA0x118b04: `vr.TriggerHaptic(hand=1,duration,frequency,amplitude=0.5)`
  converts hand0/1 to left/right. Nonpositive amplitude stops vibration.
  It has no VRMod delay argument.
* `libvrxr.so` default action definition table file record0x608d0 contains
  `trigger_pull` (float type2, category0, id6); record0x60b30 contains `attack`
  (boolean type1, category5 weapon, id25, display label Fire). A separate attack
  belongs to category3 vehicle/id17. Inputs remain gated by real returned active.
* Actionset string `gameplay` is present in liblua_shared at file/VA0x132a8.
  The wrappers clamp a negative FindActionSet result to index0. Whether that
  resolves the desired active weapon context must be checked in the running app.

`content/lua/weapons/gquest_arcvr_aniv_glock/shared.lua` registers a distinct
private test weapon derived from the **anniversary** Glock source. It does not
register or alter upstream `arcticvr_aniv_glock`. It requires genuine VR session
activity and the actual right-hand attack state, fires on rising edges only,
and excludes game UI, cursor, spawn/context menus, and optional own menu focus.
No digital state is invented if the native action returns inactive.

The source default mode is semi, RPM1200. Exact source default hitscan branch:
`AngleRand()*Spread*0.1`, Spread1/105, average damage22.5 and force7.5.
Client defaults to the calibrated native held model and reads its attachment
named `1` (bound to the `muzzle` bone) for shot position and direction. The optional paired preview reads
attachment1 from the original source viewmodel.
Server singleplayer gate checks active weapon, living owner, finite coordinates,
96-unit muzzle reach, fire rate0.05sec, and chamber ammunition before firing.
Ammo has real networked magazine/chamber state; source begins empty.
Each source closed-bolt Cycle consumes one loaded round into the chamber.

Test procedure after mounting assets/source Lua and registering the SWEP:

```
give gquest_arcvr_aniv_glock
gquest_arcvr_test_insert
gquest_arcvr_test_rack
```

Select the weapon, then press/release right trigger. The diagnostic insertion
deducts up to17 real pistol ammo; racking chambers1, leaving16 loaded if full.
`gquest_arcvr_test_eject` returns remaining magazine ammo, retaining the chamber.
These commands are explicit server diagnostic actions, **not physical reload**.
No magazine pickup entity, fake heldItems state, or VRMod success stub is created.

The calibrated native worldmodel is the default display
(`gquest_arcvr_native_model 1`). Select the paired GLua display with
`gquest_arcvr_native_model 0`. Each display mode samples its own actual model's
muzzle attachment, so the test must check both visible alignment and firing direction.
`grip_roundtrip.json` proves the appended `grip` attachment using actual root bind.

Remaining differences: no three-round burst/safe selector, two-hand stabilization,
full recoil hand transforms, finger posing, muzzle/shell effects, attachments,
physical bullet option, penetration simulation, physical pickup/reload, or network
multiplayer. These have not been marked complete. Original unused values such as
MaxRange/Penetration/MuzzleVelocity are preserved fields, but source default
hitscan itself does not use them. Haptic amplitude is normalized0.5 rather than
copying upstream's out-of-range20. Geometry, damage, RPM, magazine/chamber count,
default semi trigger contract and offset are preserved for the first slice.

Locally verified: own Lua5.4 syntax, static API signatures, source pin/data, four
model companion checksum sets, appended attachment relative offsets, float matrix
roundtrip and hashes. `test_server_state.lua` executed actual adapted server methods
with engine boundaries mocked: magazine/chamber/reserve conservation, no duplicate
insertion, damage22.5/force7.5, RPM rate gate, reach rejection, singleplayer gate,
and no shots from an empty chamber passed. Runtime GLua registration, input action activity, rendered
model pose, successful damage and ammo depletion remain pending root device test.
# Live trigger-action correction (2026-10-15)

The new APK's runtime probe in `work/gquest-current-20261015.log` reports
`GetDigital("attack",1)` returning successfully with `active=false`, while
`GetAnalog("trigger_pull",1)` reports `active=true`. The previous client Think
returned before reading that available physical axis, preventing firing.

Client Think now prefers a successfully read active boolean attack action when
available. Otherwise it accepts only a successfully read active, finite physical
trigger axis and applies hysteresis: press at >=0.55, release at <=0.45. An inactive
axis is never converted into input. VR session and all existing menu exclusions
remain in force; state is updated while a menu is visible so closing a menu with
the trigger held cannot synthesize a new press. Server/model/grip code is unchanged.

`test_client_trigger.lua` loads the actual adapted SWEP client code and invokes
its Think with mocked engine boundaries. PASS covers inactive input/session,
threshold noise, one shot per hold, release/repress, menu suppression and held
menu closing, valid digital priority, and throwing/missing digital fallback.
This proves local transition behavior, not headset firing or server acceptance.


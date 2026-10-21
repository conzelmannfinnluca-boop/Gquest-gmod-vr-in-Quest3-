//! Rust-owned startup policy for the existing GDroid renderer/game runtime.
//! This library starts no second OpenXR session and contains no game assets.
use std::{ffi::{c_char, CStr}, io::Read, panic::{catch_unwind, AssertUnwindSafe}, ptr};
pub const ABI: u32 = 1;
const PROFILE: &str = "/storage/emulated/0/Android/data/com.gmodvr.qvrx/files/user/garrysmod/data/gquest_vr_profile.txt";
#[repr(C)]
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct GquestProfile {
    pub abi_version: u32,
    pub eye_width: u32,
    pub eye_height: u32,
    pub foveation: u32,
    pub refresh_rate: u32,
    pub profile_loaded: u32,
}
impl Default for GquestProfile {
    fn default() -> Self {
        Self { abi_version: ABI, eye_width: 1032, eye_height: 1104, foveation: 2, refresh_rate: 72, profile_loaded: 0 }
    }
}
pub fn parse_profile(bytes: &[u8]) -> GquestProfile {
    let mut profile = GquestProfile::default();
    if bytes.len() > 4096 { return profile; }
    profile.profile_loaded = 1;
    let mut lines = bytes.split(|c| *c == b'\n').map(|line| line.split(|c| *c == b'\r').next().unwrap_or_default());
    match lines.next() {
        Some(b"1032x1104") => {},
        Some(b"1548x1656") => { profile.eye_width = 1548; profile.eye_height = 1656; },
        Some(b"1680x1760") => { profile.eye_width = 1680; profile.eye_height = 1760; },
        _ => {},
    }
    match lines.next() {
        Some([value @ b'0'..=b'3']) => profile.foveation = (value - b'0') as u32,
        _ => {},
    }
    if lines.next() == Some(b"90".as_slice()) { profile.refresh_rate = 90; }
    profile
}
fn load_profile() -> GquestProfile {
    let mut bytes = Vec::new();
    match std::fs::File::open(PROFILE).and_then(|file| file.take(4097).read_to_end(&mut bytes)) {
        Ok(_) => parse_profile(&bytes),
        Err(_) => GquestProfile::default(),
    }
}
fn defaults(profile: GquestProfile) -> Vec<Vec<u8>> {
    let values = [
        "+touch_enable", "0", "+vr_mainmenu", "1", "+vr_panel_menu_auto", "1",
        "+vr_spawn_menu_enable", "1", "+gmod_derma_vr", "1", "+vr_gameui_cursor", "1",
        "+hlvr_grip_yaw_correction", "0", "+vr_gameui_software_cursor", "0",
        "+vr_eye_resolution", "", "+vr_ffr_level", "", "+vr_perf_level", "50",
        "+vr_refresh_rate", "", "+mat_vsync", "0",
        "+mat_queue_mode", "0", "+gmod_derma_vr_pointer_hand", "0",
        "+gmod_derma_vr_placement", "2", "+gmod_derma_vr_outline", "1", "+gmod_derma_vr_bg", "180",
    ];
    let mut args: Vec<Vec<u8>> = values.iter().map(|s| s.as_bytes().to_vec()).collect();
    args[17] = format!("{}x{}", profile.eye_width, profile.eye_height).into_bytes();
    args[19] = profile.foveation.to_string().into_bytes();
    args[23] = profile.refresh_rate.to_string().into_bytes();
    args
}
/// Preserve the old bridge's ordering: VR settings precede +map, and an explicit
/// connect/load/changelevel request never silently becomes gm_construct.
pub fn launch_args(input: &[Vec<u8>], profile: GquestProfile) -> Vec<Vec<u8>> {
    let mut args = Vec::new();
    let mut inserted = false;
    for (index, arg) in input.iter().enumerate() {
        if !inserted && arg == b"+map" {
            args.extend(defaults(profile));
            args.extend([b"+hlvr_isvrplayer".to_vec(), b"1".to_vec()]);
            inserted = true;
        }
        args.push(arg.clone());
        if index == 0 { args.push(b"-vr".to_vec()); }
    }
    if !inserted {
        args.extend(defaults(profile));
        args.extend([b"+hlvr_isvrplayer".to_vec(), b"1".to_vec()]);
    }
    if !input.iter().any(|arg| [b"+map".as_slice(), b"+connect", b"+load", b"+changelevel"].contains(&arg.as_slice())) {
        args.extend([b"+map".to_vec(), b"gm_construct".to_vec()]);
    }
    args
}
pub struct GquestRuntime {
    profile: GquestProfile,
    // Keep allocation sizes independent of any launcher edits to terminators.
    _storage: Vec<Box<[u8]>>,
    argv: Vec<*mut c_char>,
}
#[no_mangle]
pub extern "C" fn gquest_runtime_abi() -> u32 { ABI }
/// # Safety
/// argc must describe a readable array of valid NUL-terminated C strings.
/// The return value is owned and must be destroyed exactly once after launch.
#[no_mangle]
pub unsafe extern "C" fn gquest_runtime_create(argc: i32, argv: *const *const c_char) -> *mut GquestRuntime {
    catch_unwind(|| {
        if !(0..=256).contains(&argc) || (argc != 0 && argv.is_null()) { return ptr::null_mut(); }
        let mut input = Vec::new();
        for index in 0..argc as usize {
            let arg = *argv.add(index);
            if arg.is_null() { return ptr::null_mut(); }
            let arg = CStr::from_ptr(arg).to_bytes();
            if arg.len() > 4096 { return ptr::null_mut(); }
            input.push(arg.to_vec());
        }
        let profile = load_profile();
        let mut storage: Vec<Box<[u8]>> = launch_args(&input, profile).into_iter().map(|mut arg| {
            arg.push(0); arg.into_boxed_slice()
        }).collect();
        let mut argv: Vec<*mut c_char> = storage.iter_mut().map(|arg| arg.as_mut_ptr().cast()).collect();
        argv.push(ptr::null_mut());
        Box::into_raw(Box::new(GquestRuntime { profile, _storage: storage, argv }))
    }).unwrap_or(ptr::null_mut())
}
/// # Safety
/// runtime is null or a live uniquely owned handle returned by create.
#[no_mangle]
pub unsafe extern "C" fn gquest_runtime_destroy(runtime: *mut GquestRuntime) {
    if !runtime.is_null() { let _ = catch_unwind(AssertUnwindSafe(|| drop(Box::from_raw(runtime)))); }
}
/// # Safety
/// runtime must be live; output must point to a writable GquestProfile.
#[no_mangle]
pub unsafe extern "C" fn gquest_runtime_profile(runtime: *const GquestRuntime, output: *mut GquestProfile) -> bool {
    if runtime.is_null() || output.is_null() { return false; }
    output.write((*runtime).profile); true
}
/// # Safety
/// runtime is null or a live handle.
#[no_mangle]
pub unsafe extern "C" fn gquest_runtime_argc(runtime: *const GquestRuntime) -> i32 {
    if runtime.is_null() { 0 } else { ((*runtime).argv.len() - 1) as i32 }
}
/// # Safety
/// runtime must remain alive and must not be accessed concurrently with argv edits.
#[no_mangle]
pub unsafe extern "C" fn gquest_runtime_argv(runtime: *mut GquestRuntime) -> *mut *mut c_char {
    if runtime.is_null() { ptr::null_mut() } else { (*runtime).argv.as_mut_ptr() }
}
#[cfg(test)]
mod tests {
    use super::*;
    fn args(values: &[&str]) -> Vec<Vec<u8>> { values.iter().map(|s| s.as_bytes().to_vec()).collect() }
    #[test]
    fn every_existing_profile_setting_survives_crlf() {
        for (w,h) in [(1032,1104),(1548,1656),(1680,1760)] {
            for ffr in 0..=3 {
                for hz in [72,90] {
                    let p = parse_profile(format!("{w}x{h}\r\n{ffr}\r\n{hz}\r\n").as_bytes());
                    assert_eq!((p.eye_width,p.eye_height,p.foveation,p.refresh_rate), (w,h,ffr,hz));
                }
            }
        }
    }
    #[test]
    fn invalid_profile_cannot_inject_engine_commands() {
        let p = parse_profile(b"1680x1760;quit\n4\n120\n");
        assert_eq!((p.eye_width,p.eye_height,p.foveation,p.refresh_rate),(1032,1104,2,72));
        assert_eq!(parse_profile(&vec![b'x';4097]), GquestProfile::default());
        let p = parse_profile(b"invalid\n0\n90");
        assert_eq!((p.foveation,p.refresh_rate),(0,90));
    }
    #[test]
    fn settings_and_vr_player_precede_map_and_default_level_exists() {
        let actual = launch_args(&args(&["gmod","+map","gm_flatgrass"]),GquestProfile::default());
        let map = actual.iter().position(|s| s == b"+map").unwrap();
        let vr = actual.iter().position(|s| s == b"+hlvr_isvrplayer").unwrap();
        assert!(vr < map);
        for (key,value) in [("+mat_queue_mode","0"),("+gmod_derma_vr_pointer_hand","0"),("+gmod_derma_vr_placement","2")] {
            let index=actual.iter().position(|s|s==key.as_bytes()).unwrap();
            assert!(index<map);assert_eq!(actual[index+1],value.as_bytes());
        }
        assert_eq!(actual[1],b"-vr");
        assert_eq!(actual.last().unwrap(),b"gm_flatgrass");
        let defaults = launch_args(&args(&["gmod"]),GquestProfile::default());
        assert_eq!(&defaults[defaults.len()-2..],&args(&["+map","gm_construct"]));
    }
    #[test]
    fn explicit_level_operations_and_user_argument_bytes_are_preserved() {
        for operation in ["+connect","+load","+changelevel"] {
            let out = launch_args(&args(&["gmod",operation,"example"]), GquestProfile::default());
            assert!(!out.iter().any(|arg|arg == b"gm_construct"));
            assert_eq!(&out[2..4],&args(&[operation,"example"]));
        }
    }
    #[test]
    fn ffi_handles_nulls_keeps_argv_owned_and_null_terminated() {
        unsafe {
            assert_eq!(gquest_runtime_abi(),1);
            assert!(gquest_runtime_create(1, ptr::null()).is_null());
            assert!(gquest_runtime_create(-1, ptr::null()).is_null());
            let original = std::ffi::CString::new("gmod").unwrap();
            let runtime = gquest_runtime_create(1, [original.as_ptr()].as_ptr());
            assert!(!runtime.is_null());
            drop(original);
            let argv = gquest_runtime_argv(runtime);
            assert_eq!(CStr::from_ptr(*argv).to_bytes(),b"gmod");
            assert!((*argv.add(gquest_runtime_argc(runtime) as usize)).is_null());
            let mut profile = GquestProfile::default();
            assert!(gquest_runtime_profile(runtime,&mut profile));
            assert_eq!(std::mem::size_of_val(&profile),24);
            // GDroid may edit argument bytes without changing Rust allocation sizes.
            *(*argv) = b'G' as c_char;
            gquest_runtime_destroy(runtime);
            gquest_runtime_destroy(ptr::null_mut());
        }
    }
}

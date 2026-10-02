//! A hand-written C ABI for the brain: JSON in, JSON out, no generated bindings and no crates.
//! Swift calls it through a C header; C# would call the same functions with P/Invoke (untested, no Windows machine here).
//! Ownership: `focus_brain_new` returns a brain the caller frees with `focus_brain_free`; `focus_brain_step` returns a string the
//! caller frees with `focus_brain_free_string`. A null return from `step` means the event JSON could not be read.
use crate::json::{self, J};
use crate::{wire, Brain};
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::panic::{catch_unwind, AssertUnwindSafe};

#[no_mangle]
pub extern "C" fn focus_brain_new() -> *mut Brain { Box::into_raw(Box::new(Brain::new())) }

/// # Safety
/// `b` must come from `focus_brain_new` and not be used afterwards.
#[no_mangle]
pub unsafe extern "C" fn focus_brain_free(b: *mut Brain) { if !b.is_null() { drop(Box::from_raw(b)); } }

/// Steps the brain. `event_json` is one event, for example `{"WindowChange":{"windowKey":"w:a"}}`. Returns a JSON array of effects.
/// # Safety
/// `b` must be a live brain and `event_json` a NUL-terminated string.
#[no_mangle]
pub unsafe extern "C" fn focus_brain_step(b: *mut Brain, t: f64, event_json: *const c_char) -> *mut c_char {
    if b.is_null() || event_json.is_null() { return std::ptr::null_mut(); }
    let text = match CStr::from_ptr(event_json).to_str() { Ok(s) => s, Err(_) => return std::ptr::null_mut() };
    let brain = &mut *b;
    let out = catch_unwind(AssertUnwindSafe(|| {
        let event = wire::decode_event(&json::parse(text));
        let fx: Vec<J> = brain.step(t, event).iter().map(wire::effect_json).collect();
        json::to_string(&J::Arr(fx))
    }));
    match out { Ok(s) => CString::new(s).map(CString::into_raw).unwrap_or(std::ptr::null_mut()), Err(_) => std::ptr::null_mut() }
}

/// # Safety
/// `s` must come from `focus_brain_step` and not be used afterwards.
#[no_mangle]
pub unsafe extern "C" fn focus_brain_free_string(s: *mut c_char) { if !s.is_null() { drop(CString::from_raw(s)); } }

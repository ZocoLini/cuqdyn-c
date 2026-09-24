#![allow(static_mut_refs)]
#![deny(clippy::unwrap_used, clippy::expect_used)]
pub mod context;
mod models;

use std::ffi::{c_char, c_void, CStr};
use std::slice;

use crate::context::{CuqdynConfigC, CuqdynContext};

#[allow(clippy::missing_safety_doc)]
#[no_mangle]
pub unsafe extern "C" fn build_cuqdyn_context_from_file(filename: *const c_char) -> *const c_void {
    let Ok(filename) = CStr::from_ptr(filename).to_str() else {
        eprintln!("ERROR: config filename has no valid UTF-8 chars");
        return std::ptr::null();
    };

    match CuqdynContext::new_from_file(filename) {
        Ok(context) => Box::into_raw(Box::new(context)) as *mut c_void,
        Err(e) => {
            eprintln!("ERROR: {}", e);
            std::ptr::null()
        }
    }
}

#[allow(clippy::missing_safety_doc)]
#[no_mangle]
pub unsafe extern "C" fn destroy_cuqdyn_context(context: *mut c_void) {
    if !context.is_null() {
        drop(Box::from_raw(context as *mut CuqdynContext));
    }
}

#[allow(clippy::missing_safety_doc)]
#[no_mangle]
pub unsafe extern "C" fn get_cuqdyn_conf(context: *const c_void) -> *const CuqdynConfigC {
    if context.is_null() {
        panic!("Tried to get config with a null context")
    }

    let context = &mut *(context as *mut CuqdynContext);

    context.c_config()
}

#[allow(clippy::missing_safety_doc)]
#[no_mangle]
pub unsafe extern "C" fn eval_f_exprs(
    t: f64,
    y: *mut f64,
    ydot: *mut f64,
    params: *mut f64,
    context: *mut c_void,
) {
    if context.is_null() {
        panic!("Tried to eval states f expr with a null context")
    }

    let context = &mut *(context as *mut CuqdynContext);

    let cuqdyn_conf = context.rs_config();

    let y: &[f64] = slice::from_raw_parts(y, *cuqdyn_conf.ode_expr().y_count() as usize);
    let ydot: &mut [f64] =
        slice::from_raw_parts_mut(ydot, *cuqdyn_conf.ode_expr().y_count() as usize);
    let p: &[f64] = slice::from_raw_parts_mut(params, *cuqdyn_conf.ode_expr().p_count() as usize);

    context.eval_f_exprs(t, y, ydot, p)
}

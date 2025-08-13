#![allow(static_mut_refs)]
pub mod context;
mod models;
mod states_transformers;

use std::ffi::{c_char, c_void, CStr};
use std::{slice};

use crate::context::{CuqdynConfigC, CuqdynContext};

#[allow(clippy::missing_safety_doc)]
#[no_mangle]
pub unsafe extern "C" fn build_cuqdyn_context_from_file(filename: *const c_char) -> *const c_void {
    let filename = CStr::from_ptr(filename)
        .to_str()
        .expect("config filename has no valid UTF-8 chars");

    let context = Box::new(CuqdynContext::new_from_file(filename));

    Box::into_raw(context) as *mut c_void
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
pub unsafe extern "C" fn get_cuqdyn_conf(
    context: *mut c_void,
) -> *const CuqdynConfigC {
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

#[allow(clippy::missing_safety_doc)]
#[no_mangle]
pub unsafe extern "C" fn eval_states_transformer_expr(
    input_state: *const f64,
    output_state: *mut f64,
    context: *mut c_void,
) {
    if context.is_null() {
        panic!("Tried to eval states transformer expr with a null context")
    }
    
    let context = &mut *(context as *mut CuqdynContext);

    let cuqdyn_conf = context.rs_config();

    let input_state =
        slice::from_raw_parts(input_state, *cuqdyn_conf.ode_expr().y_count() as usize);
    let output_state = slice::from_raw_parts_mut(
        output_state,
        *cuqdyn_conf
            .states_transformer()
            .clone()
            .unwrap_or_default()
            .count() as usize,
    );

    context.eval_states_transformer_expr(input_state, output_state);
}

#[cfg(test)]
mod test {
    use crate::context::{CuqdynConfigRs, CuqdynContext};

    #[test]
    fn lotka_volterra_test() {
        let num_exprs = 2;

        let y = vec![1.0, 1.0];
        let mut ydot = vec![0.0; num_exprs];
        let params = vec![1.0, 2.0, 3.0, 4.0];

        let mut context = CuqdynContext::new_from_config(CuqdynConfigRs::lotka_volterra());

        for _ in 0..10_000 {
            context.eval_f_exprs(0.0, &y, &mut ydot, &params);

            assert_eq!(ydot[0], -1.0);
            assert_eq!(ydot[1], 1.0);
        }
    }

    #[test]
    fn logistic_model_test() {
        let num_exprs = 1;

        let y = vec![1.0];
        let mut ydot = vec![0.0; num_exprs];
        let params = vec![1.0, 100.0];

        let mut context = CuqdynContext::new_from_config(CuqdynConfigRs::logistic_growth_expr());

        context.eval_f_exprs(0.0, &y, &mut ydot, &params);
        assert_eq!(ydot[0], 0.99)
    }

    #[test]
    fn div_by_cero() {
        let num_exprs = 1;

        let y = vec![1.0];
        let mut ydot = vec![0.0; num_exprs];
        let params = vec![0.484077, 0.000000]; // p2 is zero to cause division by zero

        let mut context = CuqdynContext::new_from_config(CuqdynConfigRs::logistic_growth_expr());

        context.eval_f_exprs(0.0, &y, &mut ydot, &params);

        assert_eq!(ydot[0], 0.0)
    }
}

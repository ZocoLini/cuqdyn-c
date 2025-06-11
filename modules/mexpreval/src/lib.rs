#![allow(static_mut_refs)]
mod models;
mod states_transformers;
pub mod config;

use crate::config::{CuqdynConfig, CuqdynConfigC};
use crate::models::Model;
use std::slice;
use crate::states_transformers::StatesTransformer;

static mut MODEL: Option<Box<dyn Model>> = None;
static mut STATES_TRANSFORMER: Option<Box<dyn StatesTransformer>> = None;
static mut CUQDYN_CONF: Option<CuqdynConfig> = None;

#[allow(clippy::missing_safety_doc)]
#[no_mangle]
pub unsafe extern "C" fn mexpreval_init(cuqdyn_config: CuqdynConfigC) {
    let cuqdyn_config: CuqdynConfig = cuqdyn_config.into();

    let model_name = &cuqdyn_config.ode_expr()[0];
    let transformer = &cuqdyn_config.states_transformer()[0];
    
    MODEL = Some(models::build_model(model_name, &cuqdyn_config));
    STATES_TRANSFORMER = Some(states_transformers::build_states_transformer(transformer, &cuqdyn_config)); 
    CUQDYN_CONF = Some(cuqdyn_config);
    
}

#[allow(clippy::missing_safety_doc)]
#[no_mangle]
pub unsafe extern "C" fn eval_f_exprs(t: f64, y: *mut f64, ydot: *mut f64, params: *mut f64) {
    let cuqdyn_conf = CUQDYN_CONF.as_ref().unwrap();
    
    let y: &[f64] = slice::from_raw_parts(y, cuqdyn_conf.ode_expr().len());
    let ydot: &mut [f64] = slice::from_raw_parts_mut(ydot, cuqdyn_conf.ode_expr().len());
    let p: &[f64] = slice::from_raw_parts_mut(params, *cuqdyn_conf.p_count());

    MODEL.as_ref().unwrap().eval(t, y, ydot, p)
}

#[allow(clippy::missing_safety_doc)]
#[no_mangle]
pub unsafe extern "C" fn eval_states_transformer_expr(input_state_vec: *mut f64, output_state_vec: *mut f64) {
    let cuqdyn_conf = CUQDYN_CONF.as_ref().unwrap();
    
    let input_state_slice = slice::from_raw_parts(input_state_vec, cuqdyn_conf.ode_expr().len());
    let output_state_slice = slice::from_raw_parts_mut(output_state_vec, cuqdyn_conf.states_transformer().len());
    
    STATES_TRANSFORMER.as_ref().unwrap().transform(input_state_slice, output_state_slice);
}

#[cfg(test)]
mod test {
    use crate::config::CuqdynConfig;
    use crate::{eval_f_exprs, mexpreval_init};

    #[test]
    fn lotka_volterra_test() {
        let num_exprs = 2;

        let mut y = vec![1.0, 1.0];
        let mut ydot = vec![0.0; num_exprs];
        let mut params = vec![1.0, 2.0, 3.0, 4.0];

        unsafe {
            mexpreval_init(CuqdynConfig::lotka_volterra().into());
        }

        for _ in 0..10_000 {
            unsafe { eval_f_exprs(0.0, y.as_mut_ptr(), ydot.as_mut_ptr(), params.as_mut_ptr()) }

            assert_eq!(ydot[0], -1.0);
            assert_eq!(ydot[1], 1.0);
        }
    }

    #[test]
    fn logistic_model_test() {
        let num_exprs = 1;

        let mut y = vec![1.0];
        let mut ydot = vec![0.0; num_exprs];
        let mut params = vec![1.0, 100.0];

        unsafe {
            mexpreval_init(CuqdynConfig::logistic_growth_expr().into());
        }

        unsafe { eval_f_exprs(0.0, y.as_mut_ptr(), ydot.as_mut_ptr(), params.as_mut_ptr()) }
        assert_eq!(ydot[0], 0.99)
    }

    #[test]
    fn bench() {
        let num_exprs = 1;

        let mut y = vec![1.0];
        let mut ydot = vec![0.0; num_exprs];
        let mut params = vec![0.1, 0.2];

        unsafe {
            mexpreval_init(CuqdynConfig::logistic_growth_expr().into());
        }

        for _ in 0..10_000 {
            unsafe { eval_f_exprs(0.0, y.as_mut_ptr(), ydot.as_mut_ptr(), params.as_mut_ptr()) }
        }
    }

    #[test]
    fn div_by_cero() {
        let num_exprs = 1;

        let mut y = vec![1.0];
        let mut ydot = vec![0.0; num_exprs];
        let mut params = vec![0.484077, 0.000000]; // p2 is zero to cause division by zero

        unsafe {
            mexpreval_init(CuqdynConfig::logistic_growth_expr().into());
        }

        unsafe { eval_f_exprs(0.0, y.as_mut_ptr(), ydot.as_mut_ptr(), params.as_mut_ptr()) }

        assert_eq!(ydot[0], 0.0)
    }
}

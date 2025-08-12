#![allow(static_mut_refs)]
pub mod config;
mod models;
mod states_transformers;

use crate::config::{CuqdynConfig, CuqdynConfigC};
use crate::models::Model;
use crate::states_transformers::StatesTransformer;
use std::ffi::{c_char, CStr};
use std::ops::Deref;
use std::{fs, slice};

static mut MODEL: Option<Box<dyn Model>> = None;
static mut STATES_TRANSFORMER: Option<Box<dyn StatesTransformer>> = None;
static mut CUQDYN_CONF: Option<(CuqdynConfig, CuqdynConfigC)> = None;

#[allow(clippy::missing_safety_doc)]
#[no_mangle]
pub unsafe extern "C" fn set_cuqdyn_conf(filename: *const c_char) -> *const CuqdynConfigC {
    let filename = CStr::from_ptr(filename)
        .to_str()
        .expect("config filename has no valid UTF-8 chars");

    let config_xml = fs::read_to_string(filename).expect("Unable to read the config file");
    let cuqdyn_config: CuqdynConfig =
        serde_xml_rs::from_str(&config_xml).expect("Unable to parse config xml");

    mexpreval_init(cuqdyn_config);

    get_cuqdyn_conf()
}

pub unsafe fn mexpreval_init(cuqdyn_config: CuqdynConfig) {
    let model_name = &cuqdyn_config.ode_expr().expr()[0];
    let transformer = if let Some(states_transformer) = cuqdyn_config.states_transformer().as_ref()
    {
        states_transformer
    } else {
        &config::StatesTransformer::default()
    };
    let transformer = transformer.expr().deref().first().map_or("", |v| v);

    MODEL = Some(models::build_model(model_name, &cuqdyn_config));
    STATES_TRANSFORMER = Some(states_transformers::build_states_transformer(
        transformer,
        &cuqdyn_config,
    ));
    CUQDYN_CONF = Some((cuqdyn_config.clone(), cuqdyn_config.into()));
}

#[allow(clippy::missing_safety_doc)]
#[no_mangle]
pub unsafe extern "C" fn get_cuqdyn_conf() -> *const CuqdynConfigC {
    &CUQDYN_CONF
        .as_ref()
        .expect("The configurtion hasn't been initialized")
        .1
}

#[allow(clippy::missing_safety_doc)]
#[no_mangle]
pub unsafe extern "C" fn eval_f_exprs(t: f64, y: *mut f64, ydot: *mut f64, params: *mut f64) {
    let cuqdyn_conf = &CUQDYN_CONF.as_ref().unwrap().0;

    let y: &[f64] = slice::from_raw_parts(y, *cuqdyn_conf.ode_expr().y_count() as usize);
    let ydot: &mut [f64] =
        slice::from_raw_parts_mut(ydot, *cuqdyn_conf.ode_expr().y_count() as usize);
    let p: &[f64] = slice::from_raw_parts_mut(params, *cuqdyn_conf.ode_expr().p_count() as usize);

    MODEL.as_ref().unwrap().eval(t, y, ydot, p)
}

#[allow(clippy::missing_safety_doc)]
#[no_mangle]
pub unsafe extern "C" fn eval_states_transformer_expr(
    input_state_vec: *mut f64,
    output_state_vec: *mut f64,
) {
    let cuqdyn_conf = &CUQDYN_CONF.as_ref().unwrap().0;

    let input_state_slice =
        slice::from_raw_parts(input_state_vec, *cuqdyn_conf.ode_expr().y_count() as usize);
    let output_state_slice = slice::from_raw_parts_mut(
        output_state_vec,
        *cuqdyn_conf
            .states_transformer()
            .clone()
            .unwrap_or_default()
            .count() as usize,
    );

    STATES_TRANSFORMER
        .as_ref()
        .unwrap()
        .transform(input_state_slice, output_state_slice);
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
            mexpreval_init(CuqdynConfig::lotka_volterra());
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
            mexpreval_init(CuqdynConfig::logistic_growth_expr());
        }

        unsafe { eval_f_exprs(0.0, y.as_mut_ptr(), ydot.as_mut_ptr(), params.as_mut_ptr()) }
        assert_eq!(ydot[0], 0.99)
    }

    #[test]
    fn div_by_cero() {
        let num_exprs = 1;

        let mut y = vec![1.0];
        let mut ydot = vec![0.0; num_exprs];
        let mut params = vec![0.484077, 0.000000]; // p2 is zero to cause division by zero

        unsafe {
            mexpreval_init(CuqdynConfig::logistic_growth_expr());
        }

        unsafe { eval_f_exprs(0.0, y.as_mut_ptr(), ydot.as_mut_ptr(), params.as_mut_ptr()) }

        assert_eq!(ydot[0], 0.0)
    }
}

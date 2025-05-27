#![allow(static_mut_refs)]
mod models;

use crate::models::Model;
use std::{ffi::CStr, os::raw::c_char, slice};

#[repr(C)]
#[derive(Debug)]
pub struct OdeExpr {
    y_count: i32,
    p_count: i32,
    exprs: *const *const c_char,
}

impl OdeExpr {
    pub fn new_rs(y_count: i32, p_count: i32, exprs: &[String]) -> Self {
        let mut exprs_ptr: Vec<*const c_char> = Vec::new();
        for expr in exprs {
            let c_str = CStr::from_bytes_with_nul(expr.as_bytes()).unwrap();
            exprs_ptr.push(c_str.as_ptr());
        }

        Self::new(y_count, p_count, exprs_ptr.as_ptr())
    }

    pub fn new(y_count: i32, p_count: i32, exprs: *const *const c_char) -> Self {
        OdeExpr {
            y_count,
            p_count,
            exprs,
        }
    }
}

static mut EVAL_F: Option<Box<dyn Model>> = None;
static mut ODE_EXPR: Option<OdeExpr> = None;

#[allow(clippy::missing_safety_doc)]
#[no_mangle]
pub unsafe extern "C" fn mexpreval_init(ode_expr: OdeExpr) {
    let exprs: &[*const c_char] = slice::from_raw_parts(ode_expr.exprs, ode_expr.y_count as usize);

    let model_name = {
        let ptr = &exprs[0];
        let c_str = CStr::from_ptr(*ptr);
        c_str.to_str().unwrap()
    };

    EVAL_F = Some(models::eval_model_fun(model_name, &ode_expr));
    ODE_EXPR = Some(ode_expr);
}

#[allow(clippy::missing_safety_doc)]
#[no_mangle]
pub unsafe extern "C" fn eval_f_exprs(t: f64, y: *mut f64, ydot: *mut f64, params: *mut f64) {
    let y: &[f64] = slice::from_raw_parts(y, ODE_EXPR.as_ref().unwrap().y_count as usize);
    let ydot: &mut [f64] = slice::from_raw_parts_mut(ydot, ODE_EXPR.as_ref().unwrap().y_count as usize);
    let p: &[f64] = slice::from_raw_parts_mut(params, ODE_EXPR.as_ref().unwrap().p_count as usize);

    EVAL_F.as_ref().unwrap().eval(t, y, ydot, p)
}

#[cfg(test)]
mod test {
    use crate::{eval_f_exprs, mexpreval_init, OdeExpr};
    use std::ffi::CString;
    use std::os::raw::c_char;

    #[test]
    fn lotka_volterra_test() {
        let num_exprs = 2;
        let num_params = 4;

        let mut y = vec![1.0, 1.0];
        let mut ydot = vec![0.0; num_exprs];
        let mut params = vec![1.0, 2.0, 3.0, 4.0];

        let expr_strings = [
            CString::new("y1 * (p1 - p2 * y2)").unwrap(),
            CString::new("-y2 * (p3 - p4 * y1)").unwrap(),
        ];
        let expr_ptrs: Vec<*const c_char> = expr_strings.iter().map(|s| s.as_ptr()).collect();

        unsafe {
            mexpreval_init(OdeExpr::new(
                num_exprs as i32,
                num_params,
                expr_ptrs.as_ptr(),
            ));
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
        let num_params = 2;

        let mut y = vec![1.0];
        let mut ydot = vec![0.0; num_exprs];
        let mut params = vec![1.0, 100.0];

        let expr_strings = [CString::new("p1 * y1 * (1 - y1 / p2)").unwrap()];
        let expr_ptrs: Vec<*const c_char> = expr_strings.iter().map(|s| s.as_ptr()).collect();

        unsafe {
            mexpreval_init(OdeExpr::new(
                num_exprs as i32,
                num_params,
                expr_ptrs.as_ptr(),
            ));
        }

        unsafe { eval_f_exprs(0.0, y.as_mut_ptr(), ydot.as_mut_ptr(), params.as_mut_ptr()) }
        assert_eq!(ydot[0], 0.99)
    }

    #[test]
    fn bench() {
        let num_exprs = 1;
        let num_params = 2;

        let mut y = vec![1.0];
        let mut ydot = vec![0.0; num_exprs];
        let mut params = vec![0.1, 0.2];

        let expr_strings = [CString::new("p1 * y1 * (1 - y1 / p2)").unwrap()];
        let expr_ptrs: Vec<*const c_char> = expr_strings.iter().map(|s| s.as_ptr()).collect();

        unsafe {
            mexpreval_init(OdeExpr::new(
                num_exprs as i32,
                num_params,
                expr_ptrs.as_ptr(),
            ));
        }

        for _ in 0..10_000 {
            unsafe { eval_f_exprs(0.0, y.as_mut_ptr(), ydot.as_mut_ptr(), params.as_mut_ptr()) }
        }
    }

    #[test]
    fn div_by_cero() {
        let num_exprs = 1;
        let num_params = 2;

        let mut y = vec![1.0];
        let mut ydot = vec![0.0; num_exprs];
        let mut params = vec![0.484077, 0.000000]; // p2 is zero to cause division by zero

        let expr_strings = [CString::new("p1 * y1 * (1 - y1 / p2)").unwrap()];
        let expr_ptrs: Vec<*const c_char> = expr_strings.iter().map(|s| s.as_ptr()).collect();

        unsafe {
            mexpreval_init(OdeExpr::new(
                num_exprs as i32,
                num_params,
                expr_ptrs.as_ptr(),
            ));
        }

        unsafe { eval_f_exprs(0.0, y.as_mut_ptr(), ydot.as_mut_ptr(), params.as_mut_ptr()) }

        assert_eq!(ydot[0], 0.0)
    }
}

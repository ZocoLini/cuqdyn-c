#![allow(static_mut_refs)]
mod models;

use meval::{Context, Expr};
use std::cell::OnceCell;
use std::str::FromStr;
use std::sync::LazyLock;
use std::{env, ffi::CStr, os::raw::c_char, slice};

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

static mut EXPRS: Vec<Expr> = Vec::new();
static mut CONTEXT: OnceCell<Context<'static>> = OnceCell::new();
static mut Y: Vec<String> = Vec::new();
static mut P: Vec<String> = Vec::new();
static mut ODE_EXPR: OnceCell<OdeExpr> = OnceCell::new();
static DEF_YDOT: LazyLock<f64> = LazyLock::new(|| {
    env::var("CUQDYN_DEF_YDOT")
        .unwrap_or_else(|_| "0.0".to_string())
        .parse()
        .unwrap_or(0.0)
});

#[allow(clippy::missing_safety_doc)]
#[no_mangle]
pub unsafe extern "C" fn mexpreval_init(ode_expr: OdeExpr) {
    Y.extend(
        (0..ode_expr.y_count)
            .map(|i| format!("y{}", i + 1))
            .collect::<Vec<String>>(),
    );
    P.extend(
        (0..ode_expr.p_count)
            .map(|i| format!("p{}", i + 1))
            .collect::<Vec<String>>(),
    );

    let exprs: &[*const c_char] = slice::from_raw_parts(ode_expr.exprs, ode_expr.y_count as usize);

    for ptr in exprs.iter() {
        let c_str = CStr::from_ptr(*ptr);
        let s = c_str.to_str().unwrap();
        let expr =
            Expr::from_str(s).unwrap_or_else(|e| panic!("Error parsing expresion {}: {}", s, e));

        EXPRS.push(expr);
    }

    let _ = CONTEXT.set(Context::new());
    let _ = ODE_EXPR.set(ode_expr);
}

#[allow(clippy::missing_safety_doc)]
#[no_mangle]
pub unsafe extern "C" fn eval_f_exprs(_t: f64, y: *mut f64, ydot: *mut f64, params: *mut f64) {
    let ctx = CONTEXT.get_mut().unwrap_unchecked();

    let y: &[f64] = slice::from_raw_parts(y, Y.len());
    let ydot: &mut [f64] = slice::from_raw_parts_mut(ydot, Y.len());
    let params: &[f64] = slice::from_raw_parts_mut(params, P.len());

    for (i, y) in y.iter().enumerate() {
        ctx.var(&Y[i], *y);
    }

    for (i, p) in params.iter().enumerate() {
        ctx.var(&P[i], *p);
    }

    for (i, expr) in EXPRS.iter().enumerate() {
        ydot[i] = expr
            .eval_with_context(CONTEXT.get().unwrap_unchecked())
            .unwrap_unchecked();

        if !ydot[i].is_finite() {
            eprintln!(
                "Expression {} evaluated to {} with params {:?}, setting to default value {}",
                i + 1,
                ydot[i],
                params,
                *DEF_YDOT
            );
            ydot[i] = *DEF_YDOT;
        }
    }
}

#[cfg(test)]
mod test {
    use crate::{eval_f_exprs, mexpreval_init, OdeExpr};
    use std::ffi::CString;
    use std::os::raw::c_char;

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

        for _ in 0..10_000_000 {
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

        for _ in 0..10_000_000 {
            unsafe { eval_f_exprs(0.0, y.as_mut_ptr(), ydot.as_mut_ptr(), params.as_mut_ptr()) }
        }

        println!("ydot: {:?}", ydot);
    }
}

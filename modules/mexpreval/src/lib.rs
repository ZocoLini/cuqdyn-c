mod models;

use crate::models::compute_model;
use meval::{Context, Expr};
use std::cell::RefCell;
use std::str::FromStr;
use std::{ffi::CStr, os::raw::c_char, slice};

thread_local! {
    static EXPRS: RefCell<Vec<Expr>> = RefCell::new(Vec::new());
    static CONTEXT: RefCell<Context<'static>> = RefCell::new(Context::new());
}

static Y: [&str; 8] = ["y1", "y2", "y3", "y4", "y5", "y6", "y7", "y8"];
static P: [&str; 8] = ["p1", "p2", "p3", "p4", "p5", "p6", "p7", "p8"];

#[allow(clippy::missing_safety_doc)]
#[no_mangle]
pub unsafe extern "C" fn eval_f_exprs(
    _t: f64,
    y: *mut f64,
    ydot: *mut f64,
    params: *mut f64,
    num_params: usize,
    exprs: *const *const c_char,
    num_exprs: usize,
) {
    let exprs: &[*const c_char] = slice::from_raw_parts(exprs, num_exprs);
    let y: &[f64] = slice::from_raw_parts(y, num_exprs);
    let ydot: &mut [f64] = slice::from_raw_parts_mut(ydot, num_exprs);
    let params: &[f64] = slice::from_raw_parts_mut(params, num_params);

    if exprs.len() > 0 && compute_model(CStr::from_ptr(exprs[0]).to_str().unwrap(), y, ydot, params)  {
        return;
    }

    EXPRS.with(|exprs_cache| {
        let mut exprs_cache = exprs_cache.borrow_mut();

        CONTEXT.with(|ctx| {
            let mut ctx = ctx.borrow_mut();

            for (i, expr) in y.iter().enumerate() {
                ctx.var(Y[i], *expr);
            }

            for (i, param) in params.iter().enumerate() {
                ctx.var(P[i], *param);
            }

            for (i, ptr) in exprs.iter().enumerate() {
                let index = exprs[0].offset_from(*ptr) as usize;

                if exprs_cache.len() <= index {
                    let c_str = CStr::from_ptr(*ptr);
                    let s = c_str.to_str().unwrap();
                    let expr = Expr::from_str(s).unwrap_or_else(|e| panic!("Error parsing expresion {}: {}", s, e));

                    exprs_cache.push(expr);
                }

                let expr = &exprs_cache[index];

                ydot[i] = expr
                    .eval_with_context(&*ctx)
                    .unwrap_or_else(|e| panic!("Error evaluating epresion: {}", e));
            }
        });
    });
}

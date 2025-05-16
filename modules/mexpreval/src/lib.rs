use meval::{Context, Expr};
use std::cell::RefCell;
use std::collections::HashMap;
use std::str::FromStr;
use std::{ffi::CStr, os::raw::c_char, slice};

thread_local! {
    static EXPRS: RefCell<HashMap<*const c_char, Expr>> = RefCell::new(HashMap::new());
    static CONTEXT: RefCell<Context<'static>> = RefCell::new(Context::new())
}

#[allow(clippy::missing_safety_doc)]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn eval_f_exprs(
    _t: f64,
    y: *mut f64,
    ydot: *mut f64,
    params: *mut f64,
    num_params: usize,
    exprs: *const *const c_char,
    num_exprs: usize,
) {
    let y: &[f64] = slice::from_raw_parts(y, num_exprs);
    let ydot: &mut [f64] = slice::from_raw_parts_mut(ydot, num_exprs);
    let params: &[f64] = slice::from_raw_parts_mut(params, num_params);
    let exprs: &[*const c_char] = slice::from_raw_parts(exprs, num_exprs);

    EXPRS.with(|exprs_cache| {
        let mut exprs_cache = exprs_cache.borrow_mut();

        CONTEXT.with(|ctx| {
            let mut ctx = ctx.borrow_mut();

            for (i, expr) in y.iter().enumerate() {
                ctx.var(format!("y{}", i + 1), *expr);
            }

            for (i, param) in params.iter().enumerate() {
                ctx.var(format!("p{}", i + 1), *param);
            }

            for (i, ptr) in exprs.iter().enumerate() {
                let expr = exprs_cache.entry(*ptr).or_insert_with(|| {
                    let c_str = CStr::from_ptr(*ptr);
                    let s = c_str.to_str().unwrap();
                    Expr::from_str(s).unwrap_or_else(|e| panic!("Error parsing expresion {s}: {e}"))
                });

                ydot[i] = expr
                    .eval_with_context(&*ctx)
                    .unwrap_or_else(|e| panic!("Error evaluating epresion: {e}"));
            }
        });
    });
}

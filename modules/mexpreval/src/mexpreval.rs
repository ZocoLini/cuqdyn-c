use meval::{Context, Expr};
use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;
use std::str::FromStr;
#[cfg(debug_assertions)]
use std::time::Instant;
use std::{ffi::CStr, os::raw::c_char, slice};

thread_local! {
    static EXPRS: Rc<RefCell<HashMap<String, Rc<Expr>>>> = Rc::new(RefCell::new(HashMap::new()));
    static CONTEXT: Rc<RefCell<Context<'static>>> = Rc::new(RefCell::new(Context::new()));
}

#[unsafe(no_mangle)]
pub extern "C" fn eval_f_exprs(
    _t: f64,
    y: *mut f64,
    ydot: *mut f64,
    params: *mut f64,
    num_params: usize,
    exprs: *const *const c_char,
    num_exprs: usize,
) {
    #[cfg(debug_assertions)]
    let initial_time = Instant::now();

    let y: &[f64] = unsafe { slice::from_raw_parts(y, num_exprs) };
    let ydot: &mut [f64] = unsafe { slice::from_raw_parts_mut(ydot, num_exprs) };
    let params: &[f64] = unsafe { slice::from_raw_parts_mut(params, num_params) };
    let exprs: &[*const c_char] = unsafe { slice::from_raw_parts(exprs, num_exprs) };

    let exprs_cache = EXPRS.with(Rc::clone);
    let mut exprs_cache = exprs_cache.borrow_mut();

    let parsed_exprs: Vec<Rc<Expr>> = exprs
        .iter()
        .map(|ptr| {
            let c_str = unsafe { CStr::from_ptr(*ptr) };
            let s = c_str.to_str().unwrap();

            exprs_cache
                .entry(s.to_string())
                .or_insert_with(|| {
                    Rc::new(
                        Expr::from_str(s)
                            .unwrap_or_else(|e| panic!("Error parsing expresion {s}: {e}")),
                    )
                })
                .clone()
        })
        .collect();

    let ctx = CONTEXT.with(Rc::clone);
    let mut ctx = ctx.borrow_mut();

    for (i, expr) in y.iter().enumerate() {
        ctx.var(format!("y{}", i + 1), *expr);
    }

    for (i, param) in params.iter().enumerate() {
        ctx.var(format!("p{}", i + 1), *param);
    }
    
    for (i, expr) in parsed_exprs.iter().enumerate() {
        ydot[i] = expr
            .eval_with_context(&*ctx)
            .unwrap_or_else(|e| panic!("Error evaluating epresion: {e}"));
    }

    #[cfg(debug_assertions)]
    {
        let elapsed_time = initial_time.elapsed();
        println!("Elapsed time: {:?}", elapsed_time);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn permormance_test() {}
}

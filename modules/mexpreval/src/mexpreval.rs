use meval::{Context, Expr};
use std::cell::RefCell;
use std::collections::HashMap;
use std::rc::Rc;
use std::str::FromStr;
#[cfg(debug_assertions)]
use std::time::Instant;
use std::{ffi::CStr, os::raw::c_char, slice};

type Realtype = f64;
type NVector = *mut Realtype;

thread_local! {
    static EXPRS: Rc<RefCell<HashMap<String, Rc<Expr>>>> = Rc::new(RefCell::new(HashMap::new()));
    static CONTEXT: Rc<RefCell<Context<'static>>> = Rc::new(RefCell::new(Context::new()));
}

#[unsafe(no_mangle)]
pub extern "C" fn lotka_volterra_f_rs(
    _t: Realtype,
    y: NVector,
    ydot: NVector,
    params: NVector,
    n: usize,
    exprs: *const *const c_char,
) {
    #[cfg(debug_assertions)]
    let initial_time = Instant::now();

    let y: &[Realtype] = unsafe { slice::from_raw_parts(y, n) };
    let ydot: &mut [Realtype] = unsafe { slice::from_raw_parts_mut(ydot, n) };
    let params: &[Realtype] = unsafe { slice::from_raw_parts_mut(params, 4) };
    let exprs: &[*const c_char] = unsafe { slice::from_raw_parts(exprs, n) };

    let exprs_cache = EXPRS.with(Rc::clone);
    let mut exprs_cache = exprs_cache.borrow_mut();

    let parsed_exprs: Vec<Rc<Expr>> = exprs
        .iter()
        .map(|ptr| {
            let c_str = unsafe { CStr::from_ptr(*ptr) };
            let s = c_str.to_str().unwrap();

            exprs_cache
                .entry(s.to_string())
                .or_insert_with(|| Rc::new(Expr::from_str(s).unwrap()))
                .clone()
        })
        .collect();

    let ctx = CONTEXT.with(Rc::clone);
    let mut ctx = ctx.borrow_mut();

    ctx.var("y1", y[0]);
    ctx.var("y2", y[1]);
    ctx.var("p1", params[0]);
    ctx.var("p2", params[1]);
    ctx.var("p3", params[2]);
    ctx.var("p4", params[3]);

    for (i, expr) in parsed_exprs.iter().enumerate() {
        ydot[i] = expr.eval_with_context(&*ctx).unwrap();
    }

    #[cfg(debug_assertions)]
    {
        let elapsed_time = initial_time.elapsed();
        println!("Elapsed time: {:?}", elapsed_time);
    }
}

#[allow(dead_code)]
fn eval_expr(expr: &str) -> Result<f64, meval::Error> {
    meval::eval_str(expr)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_simple_expression() {
        let result = eval_expr("3 + 5 * 2");
        assert_eq!(result.unwrap(), 13.0);
    }
    
    #[test]
    fn permormance_test() {
        
    }
}

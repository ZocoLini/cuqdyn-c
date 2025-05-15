use std::{ffi::CStr, os::raw::c_char, slice};
use std::str::FromStr;

type Realtype = f64;

type NVector = *mut Realtype;

#[unsafe(no_mangle)]
pub extern "C" fn lotka_volterra_f_rs(
    _t: Realtype,
    y: NVector,
    ydot: NVector,
    params: NVector,
    n: usize,
    exprs: *const *const c_char,
) {
    let y: &[Realtype] = unsafe { slice::from_raw_parts(y, n) };
    let ydot: &mut [Realtype] = unsafe { slice::from_raw_parts_mut(ydot, n) };
    let params: &[Realtype] = unsafe { slice::from_raw_parts_mut(params, 4) };
    let exprs: &[*const c_char] = unsafe { slice::from_raw_parts(exprs, n) };

    let parsed_exprs: Vec<meval::Expr> = exprs
        .iter()
        .map(|&ptr| {
            let c_str = unsafe { CStr::from_ptr(ptr) };
            let s = c_str.to_str().unwrap();
            meval::Expr::from_str(s).unwrap()
        })
        .collect();

    let mut context = meval::Context::new();
    context.var("y1", y[0]);
    context.var("y2", y[1]);
    context.var("p1", params[0]);
    context.var("p2", params[1]);
    context.var("p3", params[2]);
    context.var("p4", params[3]);

    for (i, expr) in parsed_exprs.iter().enumerate() {
        ydot[i] = expr.eval_with_context(context.clone()).unwrap();
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
}

use std::{ffi::c_void, slice};

type realtype = f64;

type N_Vector = *mut realtype;

#[unsafe(no_mangle)]
pub extern "C" fn lotka_volterra_f(
    _t: realtype,
    y: N_Vector,
    ydot: N_Vector,
    _user_data: *mut c_void,
    n: usize,
) {
    let y_slice: &[realtype] = unsafe { slice::from_raw_parts(y, n) };
    let ydot_slice: &mut [realtype] = unsafe { slice::from_raw_parts_mut(ydot, n) };

    for i in 0..n {
        if i == 0 {
            ydot_slice[i] = y_slice[0] * (1.0 - 0.1 * y_slice[1]);
        } else if i == 1 {
            ydot_slice[i] = -y_slice[1] * (1.0 - 0.1 * y_slice[0]);
        }
    }
}

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

use criterion::{criterion_group, criterion_main, Criterion};
use mexpreval::{eval_f_exprs, mexpreval_init, OdeExpr};
use std::ffi::CString;
use std::os::raw::c_char;

fn lotka_volterra_bench_eval(c: &mut Criterion) {
    let num_exprs = 2;
    let num_params = 4;

    let mut y = vec![1.0, 2.0];
    let mut ydot = vec![0.0; num_exprs];
    let mut params = vec![0.1, 0.2, 0.3, 0.4];

    let expr_strings = [
        CString::new("y1 * (p1 - p2 * y2)").unwrap(),
        CString::new("-y2 * (p3 - p4 * y1)").unwrap(),
    ];
    let expr_ptrs: Vec<*const c_char> = expr_strings.iter().map(|s| s.as_ptr()).collect();
    
    unsafe { mexpreval_init(OdeExpr::new(num_exprs as i32, num_params, expr_ptrs.as_ptr())); }
    
    c.bench_function("lotka_volterra", |b| {
        b.iter(|| unsafe {
            eval_f_exprs(
                0.0,
                y.as_mut_ptr(),
                ydot.as_mut_ptr(),
                params.as_mut_ptr(),
            )
        });
    });
}

#[allow(dead_code)]
fn lotka_volterra_predefined_bench_eval(c: &mut Criterion) {
    let num_exprs = 2;
    let num_params = 4;

    let mut y = vec![1.0, 2.0];
    let mut ydot = vec![0.0; num_exprs];
    let mut params = vec![0.1, 0.2, 0.3, 0.4];

    let expr_strings = [
        CString::new("lotka-volterra").unwrap(),
    ];
    let expr_ptrs: Vec<*const c_char> = expr_strings.iter().map(|s| s.as_ptr()).collect();

    unsafe { mexpreval_init(OdeExpr::new(num_exprs as i32, num_params, expr_ptrs.as_ptr())); }

    c.bench_function("lotka_volterra_predefined", |b| {
        b.iter(|| unsafe {
            eval_f_exprs(
                0.0,
                y.as_mut_ptr(),
                ydot.as_mut_ptr(),
                params.as_mut_ptr(),
            )
        });
    });
}

fn logistic_model_bench_eval(c: &mut Criterion) {
    let num_exprs = 1;
    let num_params = 2;

    let mut y = vec![0.0];
    let mut ydot = vec![0.0; num_exprs];
    let mut params = vec![0.1, 100.0];

    let expr_strings = [
        CString::new("p1 * y1 * (1 - y1 / p2)").unwrap()
    ];
    let expr_ptrs: Vec<*const c_char> = expr_strings.iter().map(|s| s.as_ptr()).collect();

    unsafe { mexpreval_init(OdeExpr::new(num_exprs as i32, num_params, expr_ptrs.as_ptr())); }
    
    c.bench_function("logistic_model", |b| {
        b.iter(|| unsafe {
            eval_f_exprs(
                0.0,
                y.as_mut_ptr(),
                ydot.as_mut_ptr(),
                params.as_mut_ptr(),
            )
        });
    });
}

fn alpha_pinene_bench_eval(c: &mut Criterion) {
    let num_exprs = 5;
    let num_params = 5;

    let mut y = vec![1.0, 1.0, 1.0, 1.0, 1.0];
    let mut ydot = vec![0.0; num_exprs];
    let mut params = vec![0.1, 0.2, 0.2, 0.2, 0.2];

    let expr_strings = [
        CString::new("-(p1 + p2) * y1").unwrap(),
        CString::new("p1 * y1").unwrap(),
        CString::new("p2 * y1 - (p3 + p4) * y3 + p5 * y5").unwrap(),
        CString::new("p3 * y3").unwrap(),
        CString::new("p4 * y3 - p5 * y5").unwrap(),
    ];
    let expr_ptrs: Vec<*const c_char> = expr_strings.iter().map(|s| s.as_ptr()).collect();

    unsafe { mexpreval_init(OdeExpr::new(num_exprs as i32, num_params, expr_ptrs.as_ptr())); }

    c.bench_function("alpha_pinene", |b| {
        b.iter(|| unsafe {
            eval_f_exprs(
                0.0,
                y.as_mut_ptr(),
                ydot.as_mut_ptr(),
                params.as_mut_ptr(),
            )
        });
    });
}

criterion_group!(benches, lotka_volterra_bench_eval, logistic_model_bench_eval, alpha_pinene_bench_eval);
criterion_main!(benches);

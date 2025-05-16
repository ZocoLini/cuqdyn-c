use criterion::{criterion_group, criterion_main, Criterion};
use mexpreval::eval_f_exprs;
use std::ffi::CString;
use std::os::raw::c_char;

fn bench_eval(c: &mut Criterion) {
    let num_exprs = 2;
    let num_params = 4;

    let mut y = vec![1.0, 2.0];
    let mut ydot = vec![0.0; num_exprs];
    let mut params = vec![0.1, 0.2, 0.3, 0.4];

    let expr_strings = [
        CString::new("p1 * y1 - p2 * y2").unwrap(),
        CString::new("p3 * y2 - p4 * y1").unwrap(),
    ];
    let expr_ptrs: Vec<*const c_char> = expr_strings.iter().map(|s| s.as_ptr()).collect();
    
    c.bench_function("eval_f_exprs", |b| {
        b.iter(|| unsafe {
            eval_f_exprs(
                0.0,
                y.as_mut_ptr(),
                ydot.as_mut_ptr(),
                params.as_mut_ptr(),
                num_params,
                expr_ptrs.as_ptr(),
                num_exprs,
            )
        });
    });
}

criterion_group!(benches, bench_eval);
criterion_main!(benches);

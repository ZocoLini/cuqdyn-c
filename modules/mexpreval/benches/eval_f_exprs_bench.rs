use criterion::{criterion_group, criterion_main, Criterion};
use mexpreval::config::CuqdynConfig;
use mexpreval::{eval_f_exprs, mexpreval_init};

fn lotka_volterra_bench_eval(c: &mut Criterion) {
    let num_exprs = 2;

    let mut y = vec![1.0, 2.0];
    let mut ydot = vec![0.0; num_exprs];
    let mut params = vec![0.1, 0.2, 0.3, 0.4];

    unsafe { mexpreval_init(CuqdynConfig::lotka_volterra_expr().into()); }
    
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

    let mut y = vec![1.0, 2.0];
    let mut ydot = vec![0.0; num_exprs];
    let mut params = vec![0.1, 0.2, 0.3, 0.4];

    unsafe { mexpreval_init(CuqdynConfig::lotka_volterra().into()); }

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

    let mut y = vec![0.0];
    let mut ydot = vec![0.0; num_exprs];
    let mut params = vec![0.1, 100.0];

    unsafe { mexpreval_init(CuqdynConfig::logistic_growth_expr().into()); }
    
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

    let mut y = vec![1.0, 1.0, 1.0, 1.0, 1.0];
    let mut ydot = vec![0.0; num_exprs];
    let mut params = vec![0.1, 0.2, 0.2, 0.2, 0.2];

    unsafe { mexpreval_init(CuqdynConfig::alpha_pinene_expr().into()); }

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

criterion_group!(benches, lotka_volterra_bench_eval, logistic_model_bench_eval, alpha_pinene_bench_eval, lotka_volterra_predefined_bench_eval);
criterion_main!(benches);

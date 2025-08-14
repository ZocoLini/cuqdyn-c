use criterion::{criterion_group, criterion_main, Criterion};
use mexpreval::context::{CuqdynConfigRs, CuqdynContext};

fn lotka_volterra_bench_eval(c: &mut Criterion) {
    let num_exprs = 2;

    let y = vec![1.0, 2.0];
    let mut ydot = vec![0.0; num_exprs];
    let params = vec![0.1, 0.2, 0.3, 0.4];

    let mut context = CuqdynContext::new_from_config(CuqdynConfigRs::lotka_volterra_expr());

    c.bench_function("lotka_volterra", |b| {
        b.iter(|| context.eval_f_exprs(0.0, &y, &mut ydot, &params));
    });
}

#[allow(dead_code)]
fn lotka_volterra_predefined_bench_eval(c: &mut Criterion) {
    let num_exprs = 2;

    let y = vec![1.0, 2.0];
    let mut ydot = vec![0.0; num_exprs];
    let params = vec![0.1, 0.2, 0.3, 0.4];

    let mut context = CuqdynContext::new_from_config(CuqdynConfigRs::lotka_volterra());

    c.bench_function("lotka_volterra_predefined", |b| {
        b.iter(|| context.eval_f_exprs(0.0, &y, &mut ydot, &params));
    });
}

fn logistic_model_bench_eval(c: &mut Criterion) {
    let num_exprs = 1;

    let y = vec![0.0];
    let mut ydot = vec![0.0; num_exprs];
    let params = vec![0.1, 100.0];

    let mut context = CuqdynContext::new_from_config(CuqdynConfigRs::logistic_growth_expr());
    
    c.bench_function("logistic_model", |b| {
        b.iter(|| context.eval_f_exprs(0.0, &y, &mut ydot, &params));
    });
}

fn alpha_pinene_bench_eval(c: &mut Criterion) {
    let num_exprs = 5;

    let y = vec![1.0, 1.0, 1.0, 1.0, 1.0];
    let mut ydot = vec![0.0; num_exprs];
    let params = vec![0.1, 0.2, 0.2, 0.2, 0.2];

    let mut context = CuqdynContext::new_from_config(CuqdynConfigRs::alpha_pinene_expr());

    c.bench_function("alpha_pinene", |b| {
        b.iter(|| context.eval_f_exprs(0.0, &y, &mut ydot, &params));
    });
}

criterion_group!(
    benches,
    lotka_volterra_bench_eval,
    logistic_model_bench_eval,
    alpha_pinene_bench_eval,
    lotka_volterra_predefined_bench_eval
);
criterion_main!(benches);

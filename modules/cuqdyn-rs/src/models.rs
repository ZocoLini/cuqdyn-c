use crate::context::CuqdynConfigRs;
use crate::symbolic::SymbolicJacobian;
use fee::{prelude::*, EmptyResolver, IVRpn, IndexedResolver};
use std::env;

pub trait Model {
    fn eval(&mut self, t: f64, y: &[f64], ydot: &mut [f64], p: &[f64]);
}

struct DefaultModel;
impl Model for DefaultModel {
    fn eval(&mut self, _t: f64, _y: &[f64], _ydot: &mut [f64], _p: &[f64]) {}
}

type ModelContext = Context<
    Unlocked,
    IndexedResolver<Unlocked, f64>,
    EmptyResolver<Unlocked>,
    IndexedResolver<Locked, f64>,
    EmptyResolver<Locked>,
>;

struct GenericModel<'e> {
    exprs: Vec<Expr<IVRpn<'e>>>,
    ctx: ModelContext,
    stack: Vec<f64>,
}

impl<'e> GenericModel<'e> {
    fn new(cuqdyn_conf: &'e CuqdynConfigRs) -> Self {
        let mut var_resolver = fee::IndexedResolver::new();

        let p_count = *cuqdyn_conf.ode_expr().p_count();
        let y_count = *cuqdyn_conf.ode_expr().y_count();

        var_resolver.add_id('p', p_count as usize);
        var_resolver.add_id('y', y_count as usize);

        for i in 0..p_count {
            var_resolver.set('p', i as usize, 0.0);
        }

        for i in 0..y_count {
            var_resolver.set('y', i as usize, 0.0);
        }

        let fn_resolver = fee::EmptyResolver::new();

        let ctx = Context::new(var_resolver, fn_resolver);

        let mut exprs = Vec::new();

        for s in cuqdyn_conf.ode_expr().expr().iter() {
            let expr = Expr::compile(s, &ctx).unwrap_or_else(|_| panic!("unable to compile {}", s));
            exprs.push(expr);
        }

        Self {
            exprs,
            ctx,
            stack: Vec::with_capacity(2),
        }
    }
}

impl Model for GenericModel<'_> {
    fn eval(&mut self, _t: f64, y: &[f64], ydot: &mut [f64], p: &[f64]) {
        for (i, value) in y.iter().enumerate() {
            self.ctx.vars_mut().set('y', i, *value);
        }

        for (i, value) in p.iter().enumerate() {
            self.ctx.vars_mut().set('p', i, *value);
        }

        for (i, expr) in self.exprs.iter().enumerate() {
            ydot[i] = expr
                .eval(&self.ctx, &mut self.stack)
                .unwrap_or_else(|_| panic!("Error evaluating model expression with index {}", i));

            if !ydot[i].is_finite() {
                let def = env::var("CUQDYN_DEF_YDOT")
                    .unwrap_or_else(|_| "0.0".to_string())
                    .parse()
                    .unwrap_or(0.0);

                eprintln!(
                    "Expression {} evaluated to {} with params {:?}, setting to default value {}",
                    i + 1,
                    ydot[i],
                    p,
                    def
                );

                ydot[i] = def;
            }
        }
    }
}

struct LotkaVolterra;

impl Model for LotkaVolterra {
    fn eval(&mut self, _t: f64, y: &[f64], ydot: &mut [f64], p: &[f64]) {
        ydot[0] = y[0] * (p[0] - p[1] * y[1]);
        ydot[1] = y[1] * (p[2] * y[0] - p[3]);
    }
}

struct AlphaPinene;

impl Model for AlphaPinene {
    fn eval(&mut self, _t: f64, y: &[f64], ydot: &mut [f64], p: &[f64]) {
        let x1 = y[0];
        let _x2 = y[1];
        let x3 = y[2];
        let _x4 = y[3];
        let x5 = y[4];

        let p1 = p[0];
        let p2 = p[1];
        let p3 = p[2];
        let p4 = p[3];
        let p5 = p[4];

        ydot[0] = -(p1 + p2) * x1;
        ydot[1] = p1 * x1;
        ydot[2] = p2 * x1 - (p3 + p4) * x3 + p5 * x5;
        ydot[3] = p3 * x3;
        ydot[4] = p4 * x3 - p5 * x5;
    }
}

struct Nfkb;

impl Model for Nfkb {
    fn eval(&mut self, _t: f64, y: &[f64], ydot: &mut [f64], p: &[f64]) {
        ydot[0] = p[19] - p[20] * y[0] - p[16] * y[0];
        ydot[1] =
            p[16] * y[0] - p[18] * y[1] - p[17] * y[1] * y[7] - p[20] * y[1] - p[1] * y[1] * y[9]
                + p[2] * y[3]
                - p[3] * y[1] * y[12]
                + p[4] * y[4];
        ydot[2] = p[18] * y[1] + p[17] * y[1] * y[7] - p[20] * y[2];
        ydot[3] = p[1] * y[1] * y[9] - p[2] * y[3];
        ydot[4] = p[3] * y[1] * y[12] - p[4] * y[4];
        ydot[5] = p[10] * y[12] - p[0] * y[5] * y[9] + p[4] * y[4] - p[22] * y[5];
        ydot[6] = p[22] * p[21] * y[5] - p[0] * y[10] * y[6];
        ydot[7] = p[14] * y[8] - p[15] * y[7];
        ydot[8] = p[12] + p[11] * y[6] - p[13] * y[8];
        ydot[9] =
            -p[1] * y[1] * y[9] - p[0] * y[9] * y[5] + p[8] * y[11] - p[9] * y[9] - p[24] * y[9]
                + p[25] * y[10];
        ydot[10] = -p[0] * y[10] * y[6] + p[24] * p[21] * y[9] - p[25] * p[21] * y[10];
        ydot[11] = p[6] + p[5] * y[6] - p[7] * y[11];
        ydot[12] = p[0] * y[9] * y[5] - p[10] * y[12] - p[3] * y[1] * y[12] + p[23] * y[13];
        ydot[13] = p[0] * y[10] * y[6] - p[23] * p[21] * y[13];
        ydot[14] = p[27] + p[26] * y[6] - p[28] * y[14];
    }
}

pub const LOTKA_VOLTERRA_EXPRS: [&str; 2] = ["y0 * (p0 - p1 * y1)", "y1 * (p2 * y0 - p3)"];

pub const ALPHA_PINENE_EXPRS: [&str; 5] = [
    "-(p0 + p1) * y0",
    "p0 * y0",
    "p1 * y0 - (p2 + p3) * y2 + p4 * y4",
    "p2 * y2",
    "p3 * y2 - p4 * y4",
];

pub const NFKB_EXPRS: [&str; 15] = [
    "p19 - p20 * y0 - p16 * y0",
    "p16 * y0 - p18 * y1 - p17 * y1 * y7 - p20 * y1 - p1 * y1 * y9 + p2 * y3 - p3 * y1 * y12 + p4 * y4",
    "p18 * y1 + p17 * y1 * y7 - p20 * y2",
    "p1 * y1 * y9 - p2 * y3",
    "p3 * y1 * y12 - p4 * y4",
    "p10 * y12 - p0 * y5 * y9 + p4 * y4 - p22 * y5",
    "p22 * p21 * y5 - p0 * y10 * y6",
    "p14 * y8 - p15 * y7",
    "p12 + p11 * y6 - p13 * y8",
    "-p1 * y1 * y9 - p0 * y9 * y5 + p8 * y11 - p9 * y9 - p24 * y9 + p25 * y10",
    "-p0 * y10 * y6 + p24 * p21 * y9 - p25 * p21 * y10",
    "p6 + p5 * y6 - p7 * y11",
    "p0 * y9 * y5 - p10 * y12 - p3 * y1 * y12 + p23 * y13",
    "p0 * y10 * y6 - p23 * p21 * y13",
    "p27 + p26 * y6 - p28 * y14",
];

/// The expressions a model evaluates: the built-in ones carry theirs as
/// constants, the generic one takes them from the config.
fn model_expressions(model: &str, cuqdyn_conf: &CuqdynConfigRs) -> Vec<String> {
    let owned = |exprs: &[&str]| exprs.iter().map(|s| s.to_string()).collect();

    match model {
        "nfkb" => owned(&NFKB_EXPRS),
        "lotka-volterra" => owned(&LOTKA_VOLTERRA_EXPRS),
        "alpha-pinene" | "α-pinene" => owned(&ALPHA_PINENE_EXPRS),
        _ => cuqdyn_conf.ode_expr().expr().to_vec(),
    }
}

/// Differentiates the model, or returns why it could not. The parsed
/// expressions are first checked against the model itself at a few points, so a
/// parser that read them differently from fee, or a built-in model whose
/// constant drifted from its code, falls back to finite differences instead of
/// handing CVODES a wrong Jacobian.
pub fn build_jacobian(
    model_name: &str,
    cuqdyn_conf: &CuqdynConfigRs,
    model: &mut dyn Model,
) -> Result<SymbolicJacobian, String> {
    let y_count = *cuqdyn_conf.ode_expr().y_count() as usize;
    let p_count = *cuqdyn_conf.ode_expr().p_count() as usize;

    let exprs = model_expressions(model_name, cuqdyn_conf);
    let mut jacobian =
        SymbolicJacobian::new(&exprs, y_count, p_count).map_err(|e| e.to_string())?;

    let mut expected = vec![0.0; y_count];
    let mut parsed = vec![0.0; y_count];

    for point in 0..4 {
        // Values in [0.5, 1.5], spread so no two variables coincide.
        let sample = |k: usize, salt: usize| 0.5 + ((k * 7 + point * 3 + salt) % 11) as f64 / 10.0;
        let y: Vec<f64> = (0..y_count).map(|k| sample(k, 0)).collect();
        let p: Vec<f64> = (0..p_count).map(|k| sample(k, 5)).collect();

        model.eval(0.0, &y, &mut expected, &p);
        jacobian.eval_rhs(&y, &p, &mut parsed);

        for (i, (a, b)) in expected.iter().zip(&parsed).enumerate() {
            if a.is_finite() && b.is_finite() && (a - b).abs() > 1e-12 * a.abs().max(1.0) {
                return Err(format!(
                    "expression {} parsed as {} where the model gives {}",
                    i + 1,
                    b,
                    a
                ));
            }
        }
    }

    Ok(jacobian)
}

pub fn build_default_model() -> Box<dyn Model> {
    Box::new(DefaultModel)
}

pub fn build_model(model: &str, cuqdyn_conf: &'static CuqdynConfigRs) -> Box<dyn Model + 'static> {
    match model {
        "nfkb" => Box::new(Nfkb),
        "lotka-volterra" => Box::new(LotkaVolterra),
        "alpha-pinene" | "α-pinene" => Box::new(AlphaPinene),
        _ => Box::new(GenericModel::new(cuqdyn_conf)),
    }
}

#[cfg(test)]
mod tests {
    use crate::context::{CuqdynConfigRs, CuqdynContext};

    /// Central differences of the model RHS, column-major like eval_jacobian.
    fn finite_differences(ctx: &mut CuqdynContext, y: &[f64], p: &[f64]) -> Vec<f64> {
        let n = y.len();
        let mut jac = vec![0.0; n * n];
        let (mut plus, mut minus) = (vec![0.0; n], vec![0.0; n]);

        for j in 0..n {
            let h = 1e-6 * y[j].abs().max(1.0);
            let mut yp = y.to_vec();
            let mut ym = y.to_vec();
            yp[j] += h;
            ym[j] -= h;
            ctx.eval_f_exprs(0.0, &yp, &mut plus, p);
            ctx.eval_f_exprs(0.0, &ym, &mut minus, p);
            for i in 0..n {
                jac[j * n + i] = (plus[i] - minus[i]) / (2.0 * h);
            }
        }

        jac
    }

    fn check(config: CuqdynConfigRs) {
        let n = *config.ode_expr().y_count() as usize;
        let n_p = *config.ode_expr().p_count() as usize;
        let mut ctx = CuqdynContext::new_from_config(config);
        assert!(ctx.has_jacobian());

        let y: Vec<f64> = (0..n).map(|k| 0.3 + 0.17 * k as f64).collect();
        let p: Vec<f64> = (0..n_p).map(|k| 0.2 + 0.05 * k as f64).collect();

        let mut analytic = vec![f64::NAN; n * n];
        assert!(ctx.eval_jacobian(0.0, &y, &mut analytic, &p));
        let numeric = finite_differences(&mut ctx, &y, &p);

        for (k, (a, d)) in analytic.iter().zip(&numeric).enumerate() {
            assert!(
                (a - d).abs() <= 1e-6 * d.abs().max(1.0),
                "entry ({}, {}): analytic {} vs finite differences {}",
                k % n,
                k / n,
                a,
                d
            );
        }
    }

    #[test]
    fn builtin_models_match_finite_differences() {
        check(CuqdynConfigRs::lotka_volterra());
        check(CuqdynConfigRs::alpha_pinene());
        check(CuqdynConfigRs::nfkb());
    }

    #[test]
    fn generic_models_match_finite_differences() {
        check(CuqdynConfigRs::lotka_volterra_expr());
        check(CuqdynConfigRs::alpha_pinene_expr());
        check(CuqdynConfigRs::logistic_growth_expr());
        check(CuqdynConfigRs::nfkb_expr());
    }
}

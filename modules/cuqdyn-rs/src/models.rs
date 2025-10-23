use crate::context::CuqdynConfigRs;
use fee::{prelude::*, EmptyResolver, IVRpn, IndexedResolver};
use std::env;

pub trait Model {
    fn eval(&mut self, t: f64, y: &[f64], ydot: &mut [f64], p: &[f64]);
}

struct DefaultModel;
impl Model for DefaultModel {
    fn eval(&mut self, _t: f64, _y: &[f64], _ydot: &mut [f64], _p: &[f64]) {}
}

struct GenericModel<'e> {
    exprs: Vec<Expr<IVRpn<'e>>>,
    ctx: Context<
        Unlocked,
        IndexedResolver<Unlocked, f64>,
        EmptyResolver<Unlocked>,
        IndexedResolver<Locked, f64>,
        EmptyResolver<Locked>,
    >,
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
            let expr = Expr::compile(s, &ctx).expect(&format!("unable to compile {s}"));
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
        for i in 0..y.len() {
            self.ctx.vars_mut().set('y', i, y[i]);
        }

        for i in 0..p.len() {
            self.ctx.vars_mut().set('p', i, p[i]);
        }

        for (i, expr) in self.exprs.iter().enumerate() {
            ydot[i] = expr
                .eval(&self.ctx, &mut self.stack)
                .expect(&format!("Error evaluating model expression with index {i}"));

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
        ydot[1] = -y[1] * (p[2] - p[3] * y[0]);
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

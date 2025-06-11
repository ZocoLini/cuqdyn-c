use crate::config::CuqdynConfig;
use meval::{Context, Expr};
use std::str::FromStr;
use std::env;

pub trait Model {
    fn eval(&self, t: f64, y: &[f64], ydot: &mut [f64], p: &[f64]);
}

struct GenericModel<'a> {
    exprs: Vec<Expr>,
    ctx: Context<'a>,
    y: Vec<*mut f64>,
    p: Vec<*mut f64>,
}

impl GenericModel<'_> {
    fn new(cuqdyn_conf: &CuqdynConfig) -> Self {
        let mut exprs: Vec<Expr> = Vec::new();

        for s in cuqdyn_conf.ode_expr().iter() {
            let expr =
                Expr::from_str(s).unwrap_or_else(|e| panic!("Error parsing expresion {}: {}", s, e));

            exprs.push(expr);
        }

        let mut ctx = Context::new();

        for i in 0..*cuqdyn_conf.p_count() {
            let var_key = format!("p{}", i + 1);
            ctx.var(&var_key, 0.0);
        }

        for i in 0..cuqdyn_conf.ode_expr().len() {
            let var_key = format!("y{}", i + 1);
            ctx.var(&var_key, 0.0);

        }

        let mut p: Vec<*mut f64> = Vec::new();
        for i in 0..*cuqdyn_conf.p_count() {
            let var_key = format!("p{}", i + 1);
            p.push(ctx.get_var_ptr(&var_key).unwrap())
        }

        let mut y: Vec<*mut f64> = Vec::new();
        for i in 0..cuqdyn_conf.ode_expr().len() {
            let var_key = format!("y{}", i + 1);
            y.push(ctx.get_var_ptr(&var_key).unwrap())
        }

        Self {
            exprs,
            ctx,
            y,
            p
        }
    }
}

impl Model for GenericModel<'_> {
    fn eval(&self, _t: f64, y: &[f64], ydot: &mut [f64], p: &[f64]) {
        unsafe {
            for i in 0..self.y.len() {
                *(self.y[i] as *mut f64) = y[i]
            }

            for i in 0..self.p.len() {
                *(self.p[i] as *mut f64) = p[i]
            }

            for (i, expr) in self.exprs.iter().enumerate() {
                ydot[i] = expr.eval_with_context(&self.ctx).unwrap();

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
}

struct LotkaVolterra;

impl Model for LotkaVolterra {
    fn eval(&self, _t: f64, y: &[f64], ydot: &mut [f64], p: &[f64]) {
        ydot[0] = y[0] * (p[0] - p[1] * y[1]);
        ydot[1] = - y[1] * (p[2] - p[3] * y[0]);
    }
}

struct AlphaPinene;

impl Model for AlphaPinene {
    fn eval(&self, _t: f64, y: &[f64], ydot: &mut [f64], p: &[f64]) {
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

pub fn build_model(model: &str, cuqdyn_conf: &CuqdynConfig) -> Box<dyn Model> {
    match model {
        "lotka-volterra" => Box::new(LotkaVolterra),
        "alpha-pinene" | "α-pinene" => Box::new(AlphaPinene),
        _ => Box::new(GenericModel::new(cuqdyn_conf))
    }
}
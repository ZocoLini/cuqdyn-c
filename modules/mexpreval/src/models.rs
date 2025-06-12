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

struct Nfkb;

impl Model for Nfkb {
    fn eval(&self, _t: f64, y: &[f64], ydot: &mut [f64], p: &[f64]) {
        // p20 - p21 * y1 - p17 * y1
        // p17 * y1 - p19 * y2 - p18 * y2 * y8 - p21 * y2 - p2 * y2 * y10 + p3 * y4 - p4 * y2 * y13 + p5 * y5
        // p19 * y2 + p18 * y2 * y8 - p21 * y3
        // p2 * y2 * y10 - p3 * y4
        // p4 * y2 * y13 - p5 * y5
        // p11 * y13 - p1 * y6 * y10 + p5 * y5 - p23 * y6
        // p23 * p22 * y6 - p1 * y11 * y7
        // p15 * y9 - p16 * y8
        // p13 + p12 * y7 - p14 * y9
        // -p2 * y2 * y10 - p1 * y10 * y6 + p9 * y12 - p10 * y10 - p25 * y10 + p26 * y11
        // -p1 * y11 * y7 + p25 * p22 * y10 - p26 * p22 * y11
        // p7 + p6 * y7 - p8 * y12
        // p1 * y10 * y6 - p11 * y13 - p4 * y2 * y13 + p24 * y14
        // p1 * y11 * y7 - p24 * p22 * y14
        // p28 + p27 * y7 - p29 * y15
        
        ydot[0] = p[19] - p[20] * y[0] - p[16] * y[0];
        ydot[1] = p[16] * y[0] - p[18] * y[1] - p[17] * y[1] * y[7] - p[20] * y[1] - p[1] * y[1] * y[9] + p[2] * y[3] - p[3] * y[1] * y[12] + p[4] * y[4];
        ydot[2] = p[18] * y[1] + p[17] * y[1] * y[7] - p[20] * y[2];
        ydot[3] = p[1] * y[1] * y[9] - p[2] * y[3];
        ydot[4] = p[3] * y[1] * y[12] - p[4] * y[4];
        ydot[5] = p[10] * y[12] - p[0] * y[5] * y[9] + p[4] * y[4] - p[22] * y[5];
        ydot[6] = p[22] * p[21] * y[5] - p[0] * y[10] * y[6];
        ydot[7] = p[14] * y[8] - p[15] * y[7];
        ydot[8] = p[12] + p[11] * y[6] - p[13] * y[8];
        ydot[9] = -p[1] * y[1] * y[9] - p[0] * y[9] * y[5] + p[8] * y[11] - p[9] * y[9] - p[23] * y[9] + p[24] * y[10];
        ydot[10] = -p[0] * y[10] * y[5] + p[23] * p[21] * y[9] - p[24] * p[21] * y[10];
        ydot[11] = p[6] + p[5] * y[6] - p[7] * y[11];
        ydot[12] = p[0] * y[1] * y[9] - p[10] * y[12] - p[3] * y[1] * y[12] + p[21] * y[13];
        ydot[13] = p[0] * y[10] * y[6] - p[23] * p[21] * y[13];
        ydot[14] = p[27] + p[26] * y[6] - p[28] * y[14];
    }
}

pub fn build_model(model: &str, cuqdyn_conf: &CuqdynConfig) -> Box<dyn Model> {
    match model {
        "nfkb" => Box::new(Nfkb),
        "lotka-volterra" => Box::new(LotkaVolterra),
        "alpha-pinene" | "α-pinene" => Box::new(AlphaPinene),
        _ => Box::new(GenericModel::new(cuqdyn_conf))
    }
}
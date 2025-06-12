use crate::config::CuqdynConfig;
use meval::{Context, Expr};
use std::str::FromStr;

pub trait StatesTransformer {
    fn transform(&self, input: &[f64], output: &mut [f64]);
}

struct GenericStatesTransformer<'a> {
    exprs: Vec<Expr>,
    ctx: Context<'a>,
    y: Vec<*mut f64>,
}

impl GenericStatesTransformer<'_> {
    fn new(cuqdyn_conf: &CuqdynConfig) -> Self {
        let mut exprs: Vec<Expr> = Vec::new();

        for s in cuqdyn_conf.states_transformer().iter() {
            let expr =
                Expr::from_str(s).unwrap_or_else(|e| panic!("Error parsing expresion {}: {}", s, e));

            exprs.push(expr);
        }

        let mut ctx = Context::new();

        for i in 0..cuqdyn_conf.ode_expr().len() {
            let var_key = format!("y{}", i + 1);
            ctx.var(&var_key, 0.0);

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
        }
    }
}

impl StatesTransformer for GenericStatesTransformer<'_> {
    fn transform(&self, input: &[f64], output: &mut [f64]) {
        unsafe {
            for i in 0..self.y.len() {
                *(self.y[i] as *mut f64) = input[i]
            }
        }

        for (i, expr) in self.exprs.iter().enumerate() {
            output[i] = expr.eval_with_context(&self.ctx).unwrap();
        }
    }
}

pub fn build_states_transformer(transformer: &str, cuqdyn_conf: &CuqdynConfig) -> Box<dyn StatesTransformer> {
    match transformer {
        _ => Box::new(GenericStatesTransformer::new(cuqdyn_conf))
    }
}
use crate::context::CuqdynConfigRs;
use fee::{prelude::*, EmptyResolver, IVRpn, IndexedResolver};

pub trait StatesTransformer {
    fn transform(&mut self, input: &[f64], output: &mut [f64]);
}

struct DefaultStatesTransformer;

impl StatesTransformer for DefaultStatesTransformer {
    fn transform(&mut self, input: &[f64], output: &mut [f64]) {
        output.copy_from_slice(input);
    }
}

struct GenericStatesTransformer<'e> {
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

impl<'e> GenericStatesTransformer<'e> {
    fn new(cuqdyn_conf: &'e CuqdynConfigRs) -> Self {
        let mut var_resolver = IndexedResolver::new();
        let y_count = *cuqdyn_conf.ode_expr().y_count();
        var_resolver.add_id('y', y_count as usize);

        for i in 0..y_count {
            var_resolver.set('y', i as usize, 0.0);
        }

        let fn_resolver = EmptyResolver::new();

        let ctx = Context::new(var_resolver, fn_resolver);

        let exprs = {
            let mut exprs = Vec::new();
            if let Some(states_transformers) = cuqdyn_conf.states_transformer() {
                for s in states_transformers.expr().iter() {
                    let expr = Expr::compile(s, &ctx).expect(&format!("unable to compile {s}"));
                    exprs.push(expr);
                }
            }
            exprs
        };

        GenericStatesTransformer {
            exprs,
            ctx,
            stack: Vec::new(),
        }
    }
}

impl StatesTransformer for GenericStatesTransformer<'_> {
    fn transform(&mut self, input: &[f64], output: &mut [f64]) {
        for i in 0..input.len() {
            self.ctx.vars_mut().set('y', i, input[i]);
        }

        for (i, expr) in self.exprs.iter().enumerate() {
            output[i] = expr.eval(&self.ctx, &mut self.stack).expect(&format!(
                "Error evaluating states transformer expression with index {i}"
            ));
        }
    }
}

struct NFKBExampleStatesTransformer;

impl StatesTransformer for NFKBExampleStatesTransformer {
    /// y7
    /// y10 + y13
    /// y9
    /// y1 + y2 + y3
    /// y2
    /// y12
    fn transform(&mut self, input: &[f64], output: &mut [f64]) {
        output[0] = input[6]; // y7
        output[1] = input[9] + input[12]; // y10 + y13
        output[2] = input[8]; // y9
        output[3] = input[0] + input[1] + input[2]; // y1 + y2 + y3
        output[4] = input[1]; // y2
        output[5] = input[11]; // y12
    }
}

pub fn build_default_states_transformer() -> Box<dyn StatesTransformer> {
    Box::new(DefaultStatesTransformer)
}

pub fn build_states_transformer(
    transformer: &str,
    cuqdyn_conf: &'static CuqdynConfigRs,
) -> Box<dyn StatesTransformer + 'static> {
    match transformer {
        "nfkb-example" => Box::new(NFKBExampleStatesTransformer),
        _ => Box::new(GenericStatesTransformer::new(cuqdyn_conf)),
    }
}

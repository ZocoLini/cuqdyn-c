trait Model {
    fn compute(y: &[f64], ydot: &mut [f64], params: &[f64]);
}

struct LotkaVolterra;

impl Model for LotkaVolterra {
    fn compute(y: &[f64], ydot: &mut [f64], params: &[f64]) {
        ydot[0] = y[0] * (params[0] - params[1] * y[1]);
        ydot[1] = - y[1] * (params[2] - params[3] * y[0]);
    }
}

pub fn compute_model(model: &str, y: &[f64], ydot: &mut [f64], params: &[f64]) -> bool {
    match model {
        "lotka-volterra" => LotkaVolterra::compute(y, ydot, params),
        _ => return false
    }
    
    true
}
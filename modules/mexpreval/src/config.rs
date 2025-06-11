use getset::Getters;
use std::ffi::CStr;
use std::os::raw::c_char;
use std::slice;

#[repr(C)]
#[derive(Debug)]
pub struct OdeExprC {
    y_count: i32,
    p_count: i32,
    exprs: *const *const c_char,
}

#[repr(C)]
#[derive(Debug)]
pub struct TolerancesC {
    rtol: f64,
    atol_len: i32,
    atol: *const f64,
}

#[repr(C)]
#[derive(Debug)]
pub struct StatesTransformerC {
    count: i32,
    exprs: *const *const c_char,
}

#[repr(C)]
#[derive(Debug)]
pub struct CuqdynConfigC {
    tolerances: TolerancesC,
    ode_expr: OdeExprC,
    states_transformer: StatesTransformerC,
}

impl From<CuqdynConfig> for CuqdynConfigC {
    fn from(value: CuqdynConfig) -> Self {
        let tolerances = TolerancesC {
            rtol: value.rtol,
            atol_len: value.atol.len() as i32,
            atol: value.atol.as_ptr(),
        };

        let ode_exprs = value
            .ode_expr
            .iter()
            .map(|a| a.as_ptr() as *const i8)
            .collect::<Vec<*const c_char>>();
        
        let ode_expr = OdeExprC {
            y_count: value.ode_expr.len() as i32,
            p_count: value.p_count as i32,
            exprs: ode_exprs
                .as_ptr(),
        };

        let obs_exprs = value
            .states_transformer
            .iter()
            .map(|a| a.as_ptr() as *const i8)
            .collect::<Vec<*const c_char>>();
        
        let observables = StatesTransformerC {
            count: value.states_transformer.len() as i32,
            exprs: obs_exprs
                .as_ptr(),
        };

        Self {
            tolerances,
            ode_expr,
            states_transformer: observables,
        }
    }
}

#[derive(Debug, Getters)]
pub struct CuqdynConfig {
    #[get = "pub"]
    rtol: f64,
    #[get = "pub"]
    atol: Vec<f64>,
    #[get = "pub"]
    p_count: usize,
    #[get = "pub"]
    ode_expr: Vec<String>,
    #[get = "pub"]
    states_transformer: Vec<String>,
}

impl CuqdynConfig {
    pub fn lotka_volterra() -> Self {
        Self {
            rtol: 1e-8,
            atol: vec![1e-8, 1e-8],
            p_count: 4,
            ode_expr: vec!["lotka-volterra".to_string()],
            states_transformer: vec![],
        }
    }

    pub fn lotka_volterra_expr() -> Self {
        Self {
            rtol: 1e-8,
            atol: vec![1e-8, 1e-8],
            p_count: 4,
            ode_expr: vec![
                "y1 * (p1 - p2 * y2)".to_string(),
                "-y2 * (p3 - p4 * y1)".to_string(),
            ],
            states_transformer: vec![],
        }
    }

    pub fn alpha_pinene() -> Self {
        Self {
            rtol: 1e-8,
            atol: vec![1e-8, 1e-8, 1e-8, 1e-8, 1e-8],
            p_count: 5,
            ode_expr: vec!["alpha-pinene".to_string()],
            states_transformer: vec![],
        }
    }

    pub fn alpha_pinene_expr() -> Self {
        Self {
            rtol: 1e-8,
            atol: vec![1e-8, 1e-8, 1e-8, 1e-8, 1e-8],
            p_count: 5,
            ode_expr: vec![
                "-(p1 + p2) * y1".to_string(),
                "p1 * y1".to_string(),
                "p2 * y1 - (p3 + p4) * y3 + p5 * y5".to_string(),
                "p3 * y3".to_string(),
                "p4 * y3 - p5 * y5".to_string(),
            ],
            states_transformer: vec![],
        }
    }

    pub fn logistic_growth_expr() -> Self {
        Self {
            rtol: 1e-8,
            atol: vec![1e-8],
            p_count: 2,
            ode_expr: vec!["p1 * y1 * (1 - y1 / p2)".to_string()],
            states_transformer: vec![],
        }
    }

    pub fn nfkb() -> Self {
        Self {
            rtol: 1e-8,
            atol: vec![1e-8, 1e-8],
            p_count: 29,
            ode_expr: vec![
                "p20 - p21 * y1 - p17 * y1".to_string(),
                "p17 * y1 - p19 * y2 - p18 * y2 * y8 - p21 * y2 - p2 * y2 * y10 + p3 * y4 - p4 * y2 * y13 + p5 * y5".to_string(),
                "p19 * y2 + p18 * y2 * y8 - p21 * y3".to_string(),
                "p2 * y2 * y10 - p3 * y4".to_string(),
                "p4 * y2 * y13 - p5 * y5".to_string(),
                "p11 * y13 - p1 * y6 * y10 + p5 * y5 - p23 * y6".to_string(),
                "p23 * p22 * y6 - p1 * y11 * y7".to_string(),
                "p15 * y9 - p16 * y8".to_string(),
                "p13 + p12 * y7 - p14 * y9".to_string(),
                "-p2 * y2 * y10 - p1 * y10 * y6 + p9 * y12 - p10 * y10 - p25 * y10 + p26 * y11".to_string(),
                "-p1 * y11 * y7 + p25 * p22 * y10 - p26 * p22 * y11".to_string(),
                "p7 + p6 * y7 - p8 * y12".to_string(),
                "p1 * y10 * y6 - p11 * y13 - p4 * y2 * y13 + p24 * y14".to_string(),
                "p1 * y11 * y7 - p24 * p22 * y14".to_string(),
                "p28 + p27 * y7 - p29 * y15".to_string(),
            ],
            states_transformer: vec![
                "y7".to_string(),
                "y10 + y13".to_string(),
                "y9".to_string(),
                "y1 + y2 + y3".to_string(),
                "y2".to_string(),
                "y12".to_string(),
            ]
        }
    }
}

impl From<CuqdynConfigC> for CuqdynConfig {
    fn from(value: CuqdynConfigC) -> Self {
        unsafe {
            let atol =
                slice::from_raw_parts(value.tolerances.atol, value.tolerances.atol_len as usize)
                    .to_vec();

            let ode_expr =
                slice::from_raw_parts(value.ode_expr.exprs, value.ode_expr.y_count as usize)
                    .iter()
                    .map(|&a| CStr::from_ptr(a).to_str().unwrap().to_string())
                    .collect::<Vec<String>>();

            let states_transformer = if value.states_transformer.count == 0 {
                slice::from_raw_parts(value.states_transformer.exprs, value.states_transformer.count as usize)
                    .iter()
                    .map(|&a| CStr::from_ptr(a).to_str().unwrap().to_string())
                    .collect::<Vec<String>>()
            } else { 
                Vec::new()
            };

            CuqdynConfig {
                rtol: value.tolerances.rtol,
                atol,
                p_count: value.ode_expr.p_count as usize,
                ode_expr,
                states_transformer,
            }
        }
    }
}

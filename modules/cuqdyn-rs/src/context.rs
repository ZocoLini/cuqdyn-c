use getset::Getters;
use serde::Deserialize;
use std::{
    ffi::{c_void, CString},
    fs,
    ops::Deref,
    os::raw::c_char,
    path::Path,
};

use crate::{
    models::{self, Model},
    states_transformers,
};

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
pub struct Y0C {
    len: i32,
    array: *const f64,
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
    time_scaling: f64,
    y0: Y0C,
    states_transformer: StatesTransformerC,
}

fn default_time_scaling() -> f64 {
    1.0
}

#[derive(Debug, Getters, Deserialize, Clone, PartialEq)]
#[serde(rename = "cuqdyn-config")]
pub struct CuqdynConfigRs {
    #[get = "pub"]
    tolerances: Tolerances,
    #[get = "pub"]
    #[serde(rename = "ode_expr")]
    ode_expr: OdeExpr,
    #[get = "pub"]
    #[serde(rename = "time_scaling", default = "default_time_scaling")]
    time_scaling: f64,
    #[get = "pub"]
    #[serde(default)]
    y0: Option<F64Vec>,
    #[get = "pub"]
    #[serde(rename = "states_transformer")]
    #[serde(default)]
    states_transformer: Option<StatesTransformer>,
}

#[derive(Debug, Getters, Deserialize, Clone, PartialEq)]
pub struct Tolerances {
    #[get = "pub"]
    rtol: f64,
    #[get = "pub"]
    atol: F64Vec,
}

#[derive(Debug, Getters, Deserialize, Clone, PartialEq)]
pub struct OdeExpr {
    #[get = "pub"]
    #[serde(rename = "@y_count")]
    y_count: i32,
    #[get = "pub"]
    #[serde(rename = "@p_count")]
    p_count: i32,
    #[get = "pub"]
    #[serde(rename = "#text")]
    expr: StringVec,
}

#[derive(Debug, Getters, Deserialize, Default, Clone, PartialEq)]
pub struct StatesTransformer {
    #[get = "pub"]
    #[serde(rename = "@count")]
    count: i32,
    #[get = "pub"]
    #[serde(rename = "#text")]
    expr: StringVec,
}

impl CuqdynConfigRs {
    pub fn lotka_volterra() -> Self {
        Self {
            tolerances: Tolerances {
                rtol: 1e-8,
                atol: F64Vec(vec![1e-8, 1e-8]),
            },
            ode_expr: OdeExpr {
                y_count: 2,
                p_count: 4,
                expr: StringVec(vec!["lotka-volterra".to_string()]),
            },
            time_scaling: 1.0,
            y0: None,
            states_transformer: None,
        }
    }

    pub fn lotka_volterra_expr() -> Self {
        Self {
            tolerances: Tolerances {
                rtol: 1e-8,
                atol: F64Vec(vec![1e-8, 1e-8]),
            },
            ode_expr: OdeExpr {
                y_count: 2,
                p_count: 4,
                expr: StringVec(vec![
                    "y0 * (p0 - p1 * y1)".to_string(),
                    "-y1 * (p2 - p3 * y0)".to_string(),
                ]),
            },
            time_scaling: 1.0,
            y0: None,
            states_transformer: None,
        }
    }

    pub fn alpha_pinene() -> Self {
        Self {
            tolerances: Tolerances {
                rtol: 1e-8,
                atol: F64Vec(vec![1e-8, 1e-8, 1e-8, 1e-8, 1e-8]),
            },
            ode_expr: OdeExpr {
                y_count: 5,
                p_count: 5,
                expr: StringVec(vec!["alpha-pinene".to_string()]),
            },
            time_scaling: 1.0,
            y0: None,
            states_transformer: None,
        }
    }

    pub fn alpha_pinene_expr() -> Self {
        Self {
            tolerances: Tolerances {
                rtol: 1e-8,
                atol: F64Vec(vec![1e-8, 1e-8, 1e-8, 1e-8, 1e-8]),
            },
            ode_expr: OdeExpr {
                y_count: 5,
                p_count: 5,
                expr: StringVec(vec![
                    "-(p0 + p1) * y0".to_string(),
                    "p0 * y0".to_string(),
                    "p1 * y0 - (p2 + p3) * y2 + p4 * y4".to_string(),
                    "p2 * y2".to_string(),
                    "p3 * y2 - p4 * y4".to_string(),
                ]),
            },
            time_scaling: 1.0,
            y0: None,
            states_transformer: None,
        }
    }

    pub fn logistic_growth_expr() -> Self {
        Self {
            tolerances: Tolerances {
                rtol: 1e-8,
                atol: F64Vec(vec![1e-8]),
            },
            ode_expr: OdeExpr {
                y_count: 1,
                p_count: 2,
                expr: StringVec(vec!["p0 * y0 * (1 - y0 / p1)".to_string()]),
            },
            time_scaling: 1.0,
            y0: None,
            states_transformer: None,
        }
    }

    pub fn nfkb_expr() -> Self {
        Self {
            tolerances: Tolerances {
                rtol: 1e-8,
                atol: F64Vec(vec![1e-8, 1e-8, 1e-8, 1e-8, 1e-8, 1e-8, 1e-8, 1e-8, 1e-8, 1e-8, 1e-8, 1e-8, 1e-8, 1e-8, 1e-8]),
            },
            ode_expr: OdeExpr {
                y_count: 15,
                p_count: 29,
                expr: StringVec(vec![
                    "p19 - p20 * y0 - p16 * y0".to_string(),
                    "p16 * y0 - p18 * y1 - p17 * y1 * y7 - p20 * y1 - p1 * y1 * y9 + p2 * y3 - p3 * y1 * y12 + p4 * y4".to_string(),
                    "p18 * y1 + p17 * y1 * y7 - p20 * y2".to_string(),
                    "p1 * y1 * y9 - p2 * y3".to_string(),
                    "p3 * y1 * y12 - p4 * y4".to_string(),
                    "p10 * y12 - p0 * y5 * y9 + p4 * y4 - p22 * y5".to_string(),
                    "p22 * p21 * y5 - p0 * y10 * y6".to_string(),
                    "p14 * y8 - p15 * y7".to_string(),
                    "p12 + p11 * y6 - p13 * y8".to_string(),
                    "-p1 * y1 * y9 - p0 * y9 * y5 + p8 * y11 - p9 * y9 - p24 * y9 + p25 * y10".to_string(),
                    "-p0 * y10 * y6 + p24 * p21 * y9 - p25 * p21 * y10".to_string(),
                    "p6 + p5 * y6 - p7 * y11".to_string(),
                    "p0 * y9 * y5 - p10 * y12 - p3 * y1 * y12 + p23 * y13".to_string(),
                    "p0 * y10 * y6 - p23 * p21 * y13".to_string(),
                    "p27 + p26 * y6 - p28 * y14".to_string(),
                ]),
            },
            time_scaling: 0.001,
            y0: Some(F64Vec(vec![0.200000, 0.000000, 0.000000, 0.000000, 0.000000, 0.000316, 0.002296, 0.004783, 0.000003, 0.002507, 0.003436, 0.000003, 0.060000, 0.000079, 0.000003])),
            states_transformer: Some(StatesTransformer {count: 6, expr: StringVec(vec![
                "y6".to_string(),
                "y9 + y12".to_string(),
                "y8".to_string(),
                "y0 + y1 + y2".to_string(),
                "y1".to_string(),
                "y11".to_string(),
            ])}),
        }
    }

    pub fn nfkb() -> Self {
        Self {
            tolerances: Tolerances {
                rtol: 1e-8,
                atol: F64Vec(vec![
                    1e-8, 1e-8, 1e-8, 1e-8, 1e-8, 1e-8, 1e-8, 1e-8, 1e-8, 1e-8, 1e-8, 1e-8, 1e-8,
                    1e-8, 1e-8,
                ]),
            },
            ode_expr: OdeExpr {
                y_count: 15,
                p_count: 29,
                expr: StringVec(vec!["nfkb".to_string()]),
            },
            time_scaling: 0.001,
            y0: Some(F64Vec(vec![
                0.200000, 0.000000, 0.000000, 0.000000, 0.000000, 0.000316, 0.002296, 0.004783,
                0.000003, 0.002507, 0.003436, 0.000003, 0.060000, 0.000079, 0.000003,
            ])),
            states_transformer: Some(StatesTransformer {
                count: 6,
                expr: StringVec(vec!["nfkb-example".to_string()]),
            }),
        }
    }
}

#[derive(Debug, Default, Clone, PartialEq)]
pub struct F64Vec(Vec<f64>);

impl Deref for F64Vec {
    type Target = Vec<f64>;
    fn deref(&self) -> &Self::Target {
        &self.0
    }
}

impl<'de> Deserialize<'de> for F64Vec {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        let s = String::deserialize(deserializer)?;
        let s = s.replace("\n", "");

        let nums = s
            .split(",")
            .map(|x| x.trim().parse::<f64>())
            .collect::<Result<Vec<_>, _>>()
            .map_err(serde::de::Error::custom)?;

        Ok(F64Vec(nums))
    }
}

#[derive(Debug, Default, Clone, PartialEq)]
pub struct StringVec(Vec<String>);

impl Deref for StringVec {
    type Target = Vec<String>;
    fn deref(&self) -> &Self::Target {
        &self.0
    }
}

impl<'de> Deserialize<'de> for StringVec {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: serde::Deserializer<'de>,
    {
        let s = String::deserialize(deserializer)?;

        let items = s.split("\n").map(|x| x.trim().to_string()).collect();

        Ok(StringVec(items))
    }
}

#[derive(Getters)]
pub struct CuqdynContext {
    rs_config: *const c_void,
    #[get = "pub"]
    c_config: CuqdynConfigC,
    model: Box<dyn Model>,
    states_transformer: Box<dyn crate::states_transformers::StatesTransformer>,

    _ode_exprs_vec: Vec<CString>,
    _ode_exprs_pointers: Vec<*const c_char>,
    _obs_exprs_vec: Vec<CString>,
    _obs_exprs_pointers: Vec<*const c_char>,
}

impl CuqdynContext {
    pub fn new_from_file(filename: impl AsRef<Path>) -> Self {
        let config_xml = fs::read_to_string(filename).expect("Unable to read the config file");
        let cuqdyn_config: CuqdynConfigRs =
            serde_xml_rs::from_str(&config_xml).expect("Unable to parse config xml");

        Self::new_from_config(cuqdyn_config)
    }

    pub fn new_from_config(rs_config: CuqdynConfigRs) -> Self {
        rs_config.into()
    }

    pub fn eval_f_exprs(&mut self, t: f64, y: &[f64], ydot: &mut [f64], p: &[f64]) {
        self.model.eval(t, y, ydot, p)
    }

    pub fn eval_states_transformer_expr(&mut self, input_state: &[f64], output_state: &mut [f64]) {
        self.states_transformer.transform(input_state, output_state);
    }

    pub fn rs_config(&self) -> &CuqdynConfigRs {
        unsafe { &*(self.rs_config as *const CuqdynConfigRs) }
    }
}

impl Drop for CuqdynContext {
    fn drop(&mut self) {
        unsafe {
            drop(Box::from_raw(self.rs_config as *mut CuqdynConfigRs));
        }
    }
}

impl From<CuqdynConfigRs> for CuqdynContext {
    fn from(value: CuqdynConfigRs) -> Self {
        let tolerances = TolerancesC {
            rtol: value.tolerances.rtol,
            atol_len: value.tolerances.atol.len() as i32,
            atol: value.tolerances.atol.as_ptr(),
        };

        let ode_exprs = value
            .ode_expr
            .expr
            .iter()
            .map(|a| CString::new(a.as_bytes()).unwrap())
            .collect::<Vec<CString>>();

        let ode_exprs_c = ode_exprs
            .iter()
            .map(|s| s.as_ptr())
            .collect::<Vec<*const c_char>>();

        let ode_expr = OdeExprC {
            y_count: value.ode_expr.y_count as i32,
            p_count: value.ode_expr.p_count as i32,
            exprs: ode_exprs_c.as_ptr(),
        };

        let y0 = if let Some(y0) = value.y0.as_ref() {
            Y0C {
                len: y0.len() as i32,
                array: y0.as_ptr(),
            }
        } else {
            Y0C {
                len: 0,
                array: std::ptr::null(),
            }
        };

        let (obs_exprs, obs_exprs_count) =
            if let Some(states_transformer) = value.states_transformer.as_ref() {
                (
                    states_transformer
                        .expr
                        .iter()
                        .map(|a| CString::new(a.as_bytes()).unwrap())
                        .collect::<Vec<CString>>(),
                    states_transformer.count,
                )
            } else {
                (vec![], 0)
            };

        let obs_exprs_c = obs_exprs
            .iter()
            .map(|s| s.as_ptr())
            .collect::<Vec<*const c_char>>();

        let observables = StatesTransformerC {
            count: obs_exprs_count,
            exprs: if obs_exprs_count >= 1 {
                obs_exprs_c.as_ptr()
            } else {
                std::ptr::null()
            },
        };

        let c_config = CuqdynConfigC {
            tolerances,
            ode_expr,
            time_scaling: value.time_scaling,
            y0,
            states_transformer: observables,
        };

        let rs_config = Box::new(value);
        let rs_config_ptr = Box::into_raw(rs_config) as *mut c_void;

        let mut ctx = Self {
            c_config,
            model: models::build_default_model(),
            states_transformer: states_transformers::build_default_states_transformer(),
            rs_config: rs_config_ptr,
            _ode_exprs_vec: ode_exprs,
            _ode_exprs_pointers: ode_exprs_c,
            _obs_exprs_vec: obs_exprs,
            _obs_exprs_pointers: obs_exprs_c,
        };

        {
            let value = unsafe { &*(rs_config_ptr as *const CuqdynConfigRs) };

            let model_name = value.ode_expr().expr().first().map_or("", |v| v);
            let transformer_name =
                if let Some(states_transformer) = value.states_transformer().as_ref() {
                    states_transformer
                } else {
                    &StatesTransformer::default()
                };
            let transformer = transformer_name.expr().deref().first().map_or("", |v| v);

            let model = crate::models::build_model(model_name, value);
            let states_transformer =
                crate::states_transformers::build_states_transformer(transformer, value);

            ctx.model = model;
            ctx.states_transformer = states_transformer;
        }

        ctx
    }
}

#[cfg(test)]
mod tests {
    use std::{ffi::CStr, slice};

    use super::*;

    #[test]
    fn alpha_pinene_config_file_test() {
        let xml = r#"<?xml version="1.0" encoding="UTF-8" ?>

<cuqdyn-config>
    <tolerances>
        <rtol>1e-8</rtol>
        <atol>1e-8, 1e-8, 1e-8, 1e-8, 1e-8</atol>
    </tolerances>
    <ode_expr y_count="5" p_count="5">
        alpha-pinene
    </ode_expr>
</cuqdyn-config>
        "#;

        let xml_config: CuqdynConfigRs = serde_xml_rs::from_str(xml).unwrap();
        let expected_config = CuqdynConfigRs::alpha_pinene();

        assert_eq!(xml_config, expected_config);
    }

    #[test]
    fn logistic_growth_config_file_test() {
        let xml = r#"<?xml version="1.0" encoding="UTF-8" ?>

<cuqdyn-config>
    <tolerances>
        <rtol>1e-8</rtol>
        <atol>1e-8</atol>
    </tolerances>
    <ode_expr y_count="1" p_count="2">
        p0 * y0 * (1 - y0 / p1)
    </ode_expr>
</cuqdyn-config>
        "#;

        let xml_config: CuqdynConfigRs = serde_xml_rs::from_str(xml).unwrap();
        let expected_config = CuqdynConfigRs::logistic_growth_expr();

        assert_eq!(xml_config, expected_config);
    }

    #[test]
    fn nfkb_config_file_test() {
        let xml = r#"<?xml version="1.0" encoding="UTF-8" ?>

<cuqdyn-config>
    <tolerances>
        <rtol>1e-8</rtol>
        <atol>1e-8, 1e-8, 1e-8, 1e-8, 1e-8, 1e-8, 1e-8, 1e-8, 1e-8, 1e-8, 1e-8, 1e-8, 1e-8, 1e-8, 1e-8</atol>
    </tolerances>
    <ode_expr y_count="15" p_count="29">
        nfkb
    </ode_expr>
    <time_scaling>0.001</time_scaling>
    <y0>
        0.200000, 0.000000, 0.000000, 0.000000, 0.000000, 0.000316, 0.002296, 0.004783, 0.000003, 0.002507, 0.003436, 0.000003, 0.060000, 0.000079, 0.000003
    </y0>
    <states_transformer count="6">
        nfkb-example
    </states_transformer>
</cuqdyn-config>
        "#;

        let xml_config: CuqdynConfigRs = serde_xml_rs::from_str(xml).unwrap();
        let expected_config = CuqdynConfigRs::nfkb();

        assert_eq!(xml_config, expected_config);
    }

    #[test]
    fn comparing_rs_struct_to_c_struct_test() {
        for _ in 0..1_000 {
            let config: CuqdynContext = CuqdynConfigRs::nfkb_expr().into();

            let rs_config = config.rs_config();
            let c_config = config.c_config();

            // ODE Expr

            assert_eq!(c_config.ode_expr.y_count, rs_config.ode_expr.y_count);
            assert_eq!(c_config.ode_expr.p_count, rs_config.ode_expr().p_count);
            unsafe {
                for (i, e) in slice::from_raw_parts(
                    c_config.ode_expr.exprs,
                    c_config.ode_expr.y_count as usize,
                )
                .iter()
                .map(|p| CStr::from_ptr(*p).to_str().unwrap().to_string())
                .enumerate()
                {
                    assert_eq!(e, rs_config.ode_expr.expr[i])
                }
            }

            // Tolerances

            assert_eq!(
                c_config.tolerances.atol_len,
                rs_config.tolerances.atol.len() as i32
            );
            assert_eq!(c_config.tolerances.rtol, rs_config.tolerances.rtol);
            unsafe {
                for (i, tol) in slice::from_raw_parts(
                    c_config.tolerances.atol,
                    c_config.tolerances.atol_len as usize,
                )
                .iter()
                .enumerate()
                {
                    assert_eq!(*tol, rs_config.tolerances.atol[i]);
                }
            }

            // Y0

            if c_config.y0.len == 0 {
                assert!(rs_config.y0().is_none())
            } else {
                unsafe {
                    for (i, y0) in
                        slice::from_raw_parts(c_config.y0.array, c_config.y0.len as usize)
                            .iter()
                            .enumerate()
                    {
                        assert_eq!(*y0, rs_config.y0.as_ref().unwrap()[i]);
                    }
                }
            }

            // States transformer

            if c_config.states_transformer.count == 0 {
                assert!(rs_config.states_transformer().is_none())
            } else {
                unsafe {
                    for (i, e) in slice::from_raw_parts(
                        c_config.states_transformer.exprs,
                        c_config.states_transformer.count as usize,
                    )
                    .iter()
                    .map(|p| CStr::from_ptr(*p).to_str().unwrap().to_string())
                    .enumerate()
                    {
                        assert_eq!(e, rs_config.states_transformer().as_ref().unwrap().expr[i])
                    }
                }
            }
        }
    }

    #[test]
    fn lotka_volterra_test() {
        let num_exprs = 2;

        let y = vec![1.0, 1.0];
        let mut ydot = vec![0.0; num_exprs];
        let params = vec![1.0, 2.0, 3.0, 4.0];

        let mut context = CuqdynContext::new_from_config(CuqdynConfigRs::lotka_volterra());

        for _ in 0..10_000 {
            context.eval_f_exprs(0.0, &y, &mut ydot, &params);

            assert_eq!(ydot[0], -1.0);
            assert_eq!(ydot[1], 1.0);
        }
    }

    #[test]
    fn logistic_model_test() {
        let num_exprs = 1;

        let y = vec![1.0];
        let mut ydot = vec![0.0; num_exprs];
        let params = vec![1.0, 100.0];

        let mut context = CuqdynContext::new_from_config(CuqdynConfigRs::logistic_growth_expr());

        context.eval_f_exprs(0.0, &y, &mut ydot, &params);
        assert_eq!(ydot[0], 0.99)
    }

    #[test]
    fn div_by_cero() {
        let num_exprs = 1;

        let y = vec![1.0];
        let mut ydot = vec![0.0; num_exprs];
        let params = vec![0.484077, 0.000000]; // p2 is zero to cause division by zero

        let mut context = CuqdynContext::new_from_config(CuqdynConfigRs::logistic_growth_expr());

        context.eval_f_exprs(0.0, &y, &mut ydot, &params);

        assert_eq!(ydot[0], 0.0)
    }
}

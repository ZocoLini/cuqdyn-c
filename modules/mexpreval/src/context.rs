use getset::{Getters};
use serde::Deserialize;
use std::{fs, ops::Deref, os::raw::c_char, path::Path};

use crate::models::Model;

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
    y0: Y0C,
    states_transformer: StatesTransformerC,
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
                    "y1 * (p1 - p2 * y2)".to_string(),
                    "-y2 * (p3 - p4 * y1)".to_string(),
                ]),
            },
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
                    "-(p1 + p2) * y1".to_string(),
                    "p1 * y1".to_string(),
                    "p2 * y1 - (p3 + p4) * y3 + p5 * y5".to_string(),
                    "p3 * y3".to_string(),
                    "p4 * y3 - p5 * y5".to_string(),
                ]),
            },
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
                expr: StringVec(vec!["p1 * y1 * (1 - y1 / p2)".to_string()]),
            },
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
                ]),
            },
            y0: Some(F64Vec(vec![0.200000, 0.000000, 0.000000, 0.000000, 0.000000, 0.000316, 0.002296, 0.004783, 0.000003, 0.002507, 0.003436, 0.000003, 0.060000, 0.000079, 0.000003])),
            states_transformer: Some(StatesTransformer {count: 6, expr: StringVec(vec![
                "y7".to_string(),
                "y10 + y13".to_string(),
                "y9".to_string(),
                "y1 + y2 + y3".to_string(),
                "y2".to_string(),
                "y12".to_string(),
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
    #[get = "pub"]
    rs_config: CuqdynConfigRs,
    #[get = "pub"]
    c_config: CuqdynConfigC,
    model: Box<dyn Model>,
    states_transformer: Box<dyn crate::states_transformers::StatesTransformer>,

    _ode_exprs_vec: Vec<*const c_char>,
    _obs_exprs_vec: Vec<*const c_char>,
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
            .map(|a| a.as_ptr() as *const i8)
            .collect::<Vec<*const c_char>>();

        let ode_expr = OdeExprC {
            y_count: value.ode_expr.y_count as i32,
            p_count: value.ode_expr.p_count as i32,
            exprs: ode_exprs.as_ptr(),
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

        let obs_exprs = if let Some(states_transformer) = value.states_transformer.as_ref() {
            states_transformer
                .expr
                .iter()
                .map(|a| a.as_ptr() as *const i8)
                .collect::<Vec<*const c_char>>()
        } else {
            vec![]
        };

        let observables = StatesTransformerC {
            count: obs_exprs.len() as i32,
            exprs: obs_exprs.as_ptr(),
        };

        let c_config = CuqdynConfigC {
            tolerances,
            ode_expr,
            y0,
            states_transformer: observables,
        };

        let model_name = &value.ode_expr().expr().first().map_or("", |v| v);
        let transformer_name = if let Some(states_transformer) = value.states_transformer().as_ref()
        {
            states_transformer
        } else {
            &StatesTransformer::default()
        };
        let transformer = transformer_name.expr().deref().first().map_or("", |v| v);

        let model = crate::models::build_model(model_name, &value);
        let states_transformer =
            crate::states_transformers::build_states_transformer(transformer, &value);

        Self {
            rs_config: value,
            c_config,
            model,
            states_transformer,
            _ode_exprs_vec: ode_exprs,
            _obs_exprs_vec: obs_exprs,
        }
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
        p1 * y1 * (1 - y1 / p2)
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
        let config: CuqdynContext = CuqdynConfigRs::nfkb_expr().into();

        let rs_config = config.rs_config();
        let c_config = config.c_config();

        // ODE Expr

        assert_eq!(c_config.ode_expr.y_count, rs_config.ode_expr.y_count);
        assert_eq!(c_config.ode_expr.p_count, rs_config.ode_expr().p_count);
        unsafe {
            for (i, e) in
                slice::from_raw_parts(c_config.ode_expr.exprs, c_config.ode_expr.y_count as usize)
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
                for (i, y0) in slice::from_raw_parts(c_config.y0.array, c_config.y0.len as usize)
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

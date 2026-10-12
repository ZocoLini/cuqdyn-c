//! Analytic Jacobian of the model right-hand side, df_i/dy_j.
//!
//! Without one, CVODES approximates the Jacobian by finite differences: one
//! extra RHS evaluation per state, plus a set of vector clones, every time it
//! refreshes the Newton matrix. The model is a handful of arithmetic
//! expressions, so it is cheap to differentiate them symbolically once and
//! evaluate the derivatives directly.
//!
//! The parser covers the subset of the fee grammar the models use: numbers,
//! `p<k>` and `y<k>`, `+ - * / ^`, unary minus and parentheses. Anything else
//! is an error, and the caller then leaves CVODES on finite differences. It
//! mirrors fee's precedences, but rather than trust that, the caller checks the
//! parsed expressions against the model at a few points before using them.

use std::fmt;

#[derive(Debug, Clone, PartialEq)]
enum Node {
    Const(f64),
    Y(usize),
    P(usize),
    Neg(Box<Node>),
    Add(Box<Node>, Box<Node>),
    Sub(Box<Node>, Box<Node>),
    Mul(Box<Node>, Box<Node>),
    Div(Box<Node>, Box<Node>),
    Pow(Box<Node>, Box<Node>),
    Ln(Box<Node>),
}

#[derive(Debug, Clone, PartialEq)]
pub struct ParseError(String);

impl fmt::Display for ParseError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(&self.0)
    }
}

/// Same rules as fee: Add/Sub 5, Mul/Div 6, prefix minus 7, Pow 8, and only
/// Pow is right associative.
#[derive(Debug, Clone, Copy, PartialEq)]
enum BinOp {
    Add,
    Sub,
    Mul,
    Div,
    Pow,
}

impl BinOp {
    fn precedence(self) -> u8 {
        match self {
            BinOp::Add | BinOp::Sub => 5,
            BinOp::Mul | BinOp::Div => 6,
            BinOp::Pow => 8,
        }
    }
}

const NEG_PRECEDENCE: u8 = 7;

#[derive(Debug, Clone, Copy, PartialEq)]
enum Token {
    Num(f64),
    Y(usize),
    P(usize),
    Op(BinOp),
    LParen,
    RParen,
}

/// fee's number parser, digit by digit, so a literal rounds to the same f64.
fn parse_number(first: char, chars: &mut std::iter::Peekable<std::str::Chars>) -> f64 {
    let mut value: f64 = 0.0;
    let mut frac = 0.1;
    let mut is_fraction = first == '.';

    if let Some(d) = first.to_digit(10) {
        value = d as f64;
    }

    while let Some(&c) = chars.peek() {
        match c {
            '0'..='9' => {
                chars.next();
                let d = (c as u8 - b'0') as f64;
                if is_fraction {
                    value += d * frac;
                    frac *= 0.1;
                } else {
                    value = value * 10.0 + d;
                }
            }
            '.' if !is_fraction => {
                chars.next();
                is_fraction = true;
            }
            _ => break,
        }
    }

    value
}

fn tokenize(input: &str, y_count: usize, p_count: usize) -> Result<Vec<Token>, ParseError> {
    let mut tokens = Vec::new();
    let mut chars = input.chars().peekable();

    while let Some(c) = chars.next() {
        let token = match c {
            ' ' | '\t' | '\n' | '\r' => continue,
            '(' | '[' => Token::LParen,
            ')' | ']' => Token::RParen,
            '+' => Token::Op(BinOp::Add),
            '-' => Token::Op(BinOp::Sub),
            '*' => Token::Op(BinOp::Mul),
            '/' => Token::Op(BinOp::Div),
            '^' => {
                if chars.peek() == Some(&'^') {
                    return Err(ParseError("bitwise xor is not supported".into()));
                }
                Token::Op(BinOp::Pow)
            }
            '0'..='9' | '.' => Token::Num(parse_number(c, &mut chars)),
            'a'..='z' | 'A'..='Z' | '_' => {
                let mut name = String::from(c);
                while let Some(&d) = chars.peek() {
                    if d.is_alphanumeric() || d == '_' {
                        name.push(d);
                        chars.next();
                    } else {
                        break;
                    }
                }
                if matches!(chars.peek(), Some('(') | Some('[')) {
                    return Err(ParseError(format!("function {} is not supported", name)));
                }
                variable(&name, y_count, p_count)?
            }
            _ => return Err(ParseError(format!("unsupported character {:?}", c))),
        };
        tokens.push(token);
    }

    Ok(tokens)
}

fn variable(name: &str, y_count: usize, p_count: usize) -> Result<Token, ParseError> {
    let (kind, digits) = name.split_at(1);
    let index = digits
        .parse::<usize>()
        .ok()
        .filter(|_| digits.bytes().all(|b| b.is_ascii_digit()));

    match (kind, index) {
        ("y", Some(i)) if i < y_count => Ok(Token::Y(i)),
        ("p", Some(i)) if i < p_count => Ok(Token::P(i)),
        _ => Err(ParseError(format!("unknown variable {}", name))),
    }
}

struct Parser {
    tokens: Vec<Token>,
    pos: usize,
}

impl Parser {
    fn peek(&self) -> Option<Token> {
        self.tokens.get(self.pos).copied()
    }

    fn next(&mut self) -> Option<Token> {
        let token = self.peek();
        self.pos += 1;
        token
    }

    fn operand(&mut self, after_pow: bool) -> Result<Node, ParseError> {
        match self.next() {
            Some(Token::Num(v)) => Ok(Node::Const(v)),
            Some(Token::Y(i)) => Ok(Node::Y(i)),
            Some(Token::P(i)) => Ok(Node::P(i)),
            // fee pops a pending ^ when it meets a prefix minus, so `a ^ -b`
            // does not mean a^(-b) there. Refuse it rather than disagree.
            Some(Token::Op(BinOp::Sub)) if after_pow => {
                Err(ParseError("unary minus right after ^ is ambiguous".into()))
            }
            Some(Token::Op(BinOp::Sub)) => {
                Ok(Node::Neg(Box::new(self.expression(NEG_PRECEDENCE, false)?)))
            }
            Some(Token::LParen) => {
                let inner = self.expression(0, false)?;
                match self.next() {
                    Some(Token::RParen) => Ok(inner),
                    _ => Err(ParseError("missing closing parenthesis".into())),
                }
            }
            other => Err(ParseError(format!(
                "expected an operand, found {:?}",
                other
            ))),
        }
    }

    fn expression(&mut self, min_precedence: u8, after_pow: bool) -> Result<Node, ParseError> {
        let mut lhs = self.operand(after_pow)?;

        while let Some(Token::Op(op)) = self.peek() {
            let precedence = op.precedence();
            if precedence < min_precedence {
                break;
            }
            self.next();

            let next_min = if op == BinOp::Pow {
                precedence
            } else {
                precedence + 1
            };
            let rhs = self.expression(next_min, op == BinOp::Pow)?;

            let (l, r) = (Box::new(lhs), Box::new(rhs));
            lhs = match op {
                BinOp::Add => Node::Add(l, r),
                BinOp::Sub => Node::Sub(l, r),
                BinOp::Mul => Node::Mul(l, r),
                BinOp::Div => Node::Div(l, r),
                BinOp::Pow => Node::Pow(l, r),
            };
        }

        Ok(lhs)
    }
}

fn parse(input: &str, y_count: usize, p_count: usize) -> Result<Node, ParseError> {
    let mut parser = Parser {
        tokens: tokenize(input, y_count, p_count)?,
        pos: 0,
    };
    let node = parser.expression(0, false)?;

    if parser.pos != parser.tokens.len() {
        return Err(ParseError(format!(
            "unexpected trailing input in {:?}",
            input
        )));
    }

    Ok(node)
}

/// fee's power: integral exponents go through powi.
fn pow(base: f64, exponent: f64) -> f64 {
    if exponent.fract() == 0.0 && exponent.abs() <= i32::MAX as f64 {
        base.powi(exponent as i32)
    } else {
        base.powf(exponent)
    }
}

fn is_const(node: &Node, value: f64) -> bool {
    matches!(node, Node::Const(v) if *v == value)
}

/// Folds constants and drops the zeros and ones differentiation leaves behind,
/// so that an entry that is identically zero is recognised as such.
fn simplify(node: Node) -> Node {
    use Node::*;

    match node {
        Neg(a) => match simplify(*a) {
            Const(v) => Const(-v),
            Neg(inner) => *inner,
            a => Neg(Box::new(a)),
        },
        Add(a, b) => match (simplify(*a), simplify(*b)) {
            (Const(x), Const(y)) => Const(x + y),
            (a, b) if is_const(&a, 0.0) => b,
            (a, b) if is_const(&b, 0.0) => a,
            (a, b) => Add(Box::new(a), Box::new(b)),
        },
        Sub(a, b) => match (simplify(*a), simplify(*b)) {
            (Const(x), Const(y)) => Const(x - y),
            (a, b) if is_const(&b, 0.0) => a,
            (a, b) if is_const(&a, 0.0) => simplify(Neg(Box::new(b))),
            (a, b) => Sub(Box::new(a), Box::new(b)),
        },
        Mul(a, b) => match (simplify(*a), simplify(*b)) {
            (Const(x), Const(y)) => Const(x * y),
            (a, b) if is_const(&a, 0.0) || is_const(&b, 0.0) => Const(0.0),
            (a, b) if is_const(&a, 1.0) => b,
            (a, b) if is_const(&b, 1.0) => a,
            (a, b) => Mul(Box::new(a), Box::new(b)),
        },
        Div(a, b) => match (simplify(*a), simplify(*b)) {
            (Const(x), Const(y)) => Const(x / y),
            (a, _) if is_const(&a, 0.0) => Const(0.0),
            (a, b) if is_const(&b, 1.0) => a,
            (a, b) => Div(Box::new(a), Box::new(b)),
        },
        Pow(a, b) => match (simplify(*a), simplify(*b)) {
            (Const(x), Const(y)) => Const(pow(x, y)),
            (_, b) if is_const(&b, 0.0) => Const(1.0),
            (a, b) if is_const(&b, 1.0) => a,
            (a, b) => Pow(Box::new(a), Box::new(b)),
        },
        Ln(a) => match simplify(*a) {
            Const(v) => Const(v.ln()),
            a => Ln(Box::new(a)),
        },
        leaf => leaf,
    }
}

/// d node / d y_var, unsimplified.
fn derive(node: &Node, var: usize) -> Node {
    use Node::*;
    let b = |n: Node| Box::new(n);

    match node {
        Const(_) | P(_) => Const(0.0),
        Y(i) => Const(if *i == var { 1.0 } else { 0.0 }),
        Neg(a) => Neg(b(derive(a, var))),
        Add(u, v) => Add(b(derive(u, var)), b(derive(v, var))),
        Sub(u, v) => Sub(b(derive(u, var)), b(derive(v, var))),
        Mul(u, v) => Add(
            b(Mul(b(derive(u, var)), v.clone())),
            b(Mul(u.clone(), b(derive(v, var)))),
        ),
        Div(u, v) => Div(
            b(Sub(
                b(Mul(b(derive(u, var)), v.clone())),
                b(Mul(u.clone(), b(derive(v, var)))),
            )),
            b(Mul(v.clone(), v.clone())),
        ),
        Pow(u, v) => {
            let dv = simplify(derive(v, var));
            if is_const(&dv, 0.0) {
                // u^c -> c * u^(c - 1) * u'
                Mul(
                    b(Mul(
                        v.clone(),
                        b(Pow(u.clone(), b(Sub(v.clone(), b(Const(1.0)))))),
                    )),
                    b(derive(u, var)),
                )
            } else {
                // u^v -> u^v * (v' ln u + v u' / u)
                Mul(
                    b(node.clone()),
                    b(Add(
                        b(Mul(b(dv), b(Ln(u.clone())))),
                        b(Div(b(Mul(v.clone(), b(derive(u, var)))), u.clone())),
                    )),
                )
            }
        }
        Ln(u) => Div(b(derive(u, var)), u.clone()),
    }
}

#[derive(Debug, Clone, Copy)]
enum Instr {
    Const(f64),
    Y(usize),
    P(usize),
    Neg,
    Add,
    Sub,
    Mul,
    Div,
    Pow,
    Ln,
}

/// An expression flattened to postfix, evaluated on a caller-provided stack.
#[derive(Debug, Clone)]
struct Program(Vec<Instr>);

impl Program {
    fn compile(node: &Node) -> Self {
        fn emit(node: &Node, out: &mut Vec<Instr>) {
            match node {
                Node::Const(v) => out.push(Instr::Const(*v)),
                Node::Y(i) => out.push(Instr::Y(*i)),
                Node::P(i) => out.push(Instr::P(*i)),
                Node::Neg(a) | Node::Ln(a) => {
                    emit(a, out);
                    out.push(if matches!(node, Node::Neg(_)) {
                        Instr::Neg
                    } else {
                        Instr::Ln
                    });
                }
                Node::Add(a, b)
                | Node::Sub(a, b)
                | Node::Mul(a, b)
                | Node::Div(a, b)
                | Node::Pow(a, b) => {
                    emit(a, out);
                    emit(b, out);
                    out.push(match node {
                        Node::Add(..) => Instr::Add,
                        Node::Sub(..) => Instr::Sub,
                        Node::Mul(..) => Instr::Mul,
                        Node::Div(..) => Instr::Div,
                        _ => Instr::Pow,
                    });
                }
            }
        }

        let mut out = Vec::new();
        emit(node, &mut out);
        Program(out)
    }

    fn eval(&self, y: &[f64], p: &[f64], stack: &mut Vec<f64>) -> f64 {
        stack.clear();

        for instr in &self.0 {
            let value = match *instr {
                Instr::Const(v) => v,
                Instr::Y(i) => y[i],
                Instr::P(i) => p[i],
                Instr::Neg | Instr::Ln => {
                    let a = stack.pop().unwrap_or(f64::NAN);
                    if matches!(instr, Instr::Neg) {
                        -a
                    } else {
                        a.ln()
                    }
                }
                _ => {
                    let b = stack.pop().unwrap_or(f64::NAN);
                    let a = stack.pop().unwrap_or(f64::NAN);
                    match instr {
                        Instr::Add => a + b,
                        Instr::Sub => a - b,
                        Instr::Mul => a * b,
                        Instr::Div => a / b,
                        _ => pow(a, b),
                    }
                }
            };
            stack.push(value);
        }

        stack.pop().unwrap_or(f64::NAN)
    }
}

/// The Jacobian of y' = f(y, p), with its structurally nonzero entries
/// compiled ahead of time.
#[derive(Debug, Clone)]
pub struct SymbolicJacobian {
    rhs: Vec<Program>,
    /// (column-major index into the n x n matrix, d f_i / d y_j)
    entries: Vec<(usize, Program)>,
    stack: Vec<f64>,
}

impl SymbolicJacobian {
    pub fn new<S: AsRef<str>>(
        exprs: &[S],
        y_count: usize,
        p_count: usize,
    ) -> Result<Self, ParseError> {
        if exprs.len() != y_count {
            return Err(ParseError(format!(
                "{} expressions for {} states",
                exprs.len(),
                y_count
            )));
        }

        let mut rhs = Vec::with_capacity(y_count);
        let mut entries = Vec::new();

        for (i, expr) in exprs.iter().enumerate() {
            let node = parse(expr.as_ref(), y_count, p_count)?;

            for j in 0..y_count {
                let d = simplify(derive(&node, j));
                if !is_const(&d, 0.0) {
                    entries.push((j * y_count + i, Program::compile(&d)));
                }
            }

            rhs.push(Program::compile(&node));
        }

        Ok(Self {
            rhs,
            entries,
            stack: Vec::with_capacity(16),
        })
    }

    /// Structurally nonzero entries, out of n_states^2.
    #[cfg(test)]
    pub fn nonzeros(&self) -> usize {
        self.entries.len()
    }

    /// f(y, p) from the parsed expressions, to check them against the model.
    pub fn eval_rhs(&mut self, y: &[f64], p: &[f64], ydot: &mut [f64]) {
        for (out, program) in ydot.iter_mut().zip(&self.rhs) {
            *out = program.eval(y, p, &mut self.stack);
        }
    }

    /// Fills `jac`, column-major n x n, with df_i/dy_j. A non-finite entry is
    /// set to zero: the RHS replaces a non-finite value by a constant, whose
    /// derivative is zero.
    pub fn eval(&mut self, y: &[f64], p: &[f64], jac: &mut [f64]) {
        jac.iter_mut().for_each(|v| *v = 0.0);

        for (index, program) in &self.entries {
            let value = program.eval(y, p, &mut self.stack);
            jac[*index] = if value.is_finite() { value } else { 0.0 };
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn jac_of(exprs: &[&str], y_count: usize, p_count: usize, y: &[f64], p: &[f64]) -> Vec<f64> {
        let mut jac = SymbolicJacobian::new(exprs, y_count, p_count).unwrap();
        let mut out = vec![f64::NAN; y_count * y_count];
        jac.eval(y, p, &mut out);
        out
    }

    #[test]
    fn precedence_matches_fee() {
        let cases = [
            ("-y0^2", -9.0),
            ("-y0*2", -6.0),
            ("2^3^2", 512.0),
            ("y0 - y0 - y0", -3.0),
            ("y0 / 3 / 2", 0.5),
            ("p0 * y0 * (1 - y0 / p1)", 2.0 * 3.0 * (1.0 - 3.0 / 4.0)),
            ("0 - p0 * y0", -6.0),
            ("1.5 + .5", 2.0),
        ];

        for (expr, expected) in cases {
            let mut jac = SymbolicJacobian::new(&[expr], 1, 2).unwrap();
            let mut ydot = [0.0];
            jac.eval_rhs(&[3.0], &[2.0, 4.0], &mut ydot);
            assert_eq!(ydot[0], expected, "{}", expr);
        }
    }

    #[test]
    fn unsupported_input_is_an_error() {
        for expr in [
            "y0 % 2", "abs(y0)", "y0 ^ -1", "t * y0", "y5", "y0 < 1", "(y0", "y0 y0",
        ] {
            assert!(SymbolicJacobian::new(&[expr], 1, 1).is_err(), "{}", expr);
        }
    }

    #[test]
    fn lotka_volterra_jacobian() {
        let (y, p) = ([2.0, 3.0], [0.5, 0.25, 0.75, 1.5]);
        let jac = jac_of(
            &["y0 * (p0 - p1 * y1)", "y1 * (p2 * y0 - p3)"],
            2,
            4,
            &y,
            &p,
        );

        // Column-major: [df0/dy0, df1/dy0, df0/dy1, df1/dy1]
        assert_eq!(
            jac,
            vec![
                p[0] - p[1] * y[1],
                p[2] * y[1],
                -p[1] * y[0],
                p[2] * y[0] - p[3]
            ]
        );
    }

    #[test]
    fn powers_and_quotients() {
        let (y, p) = ([2.0, 3.0], [5.0]);
        let jac = jac_of(&["y0^3 / y1", "y0 ^ y1 + p0 ^ 2"], 2, 1, &y, &p);

        let close = |a: f64, b: f64| (a - b).abs() <= 1e-12 * b.abs().max(1.0);
        assert!(close(jac[0], 3.0 * 4.0 / 3.0));
        assert!(close(jac[2], -8.0 / 9.0));
        assert!(close(jac[1], 3.0 * 4.0));
        assert!(close(jac[3], 8.0 * 2.0_f64.ln()));
    }

    #[test]
    fn zero_entries_are_dropped() {
        let jac =
            SymbolicJacobian::new(&["0 - p0 * y0", "p0 * y0 - p1 * y1", "p1 * y1"], 3, 2).unwrap();
        assert_eq!(jac.nonzeros(), 4);
    }
}

//! Prints the expected output of tests/programs/math.scm from the libm
//! crate, the fdlibm port (snail shell math) follows bit for bit:
//!
//!   cargo run -q --offline --manifest-path crates/snail-scheme-support/Cargo.toml \
//!     --example math-reference > tests/programs/math.out
//!
//! It draws the same inputs as the test: chosen ones, then a sweep.

fn text(number: f64) -> String {
    if number.is_nan() {
        return "+nan.0".into();
    }
    if number.is_infinite() {
        return if number > 0.0 {
            "+inf.0".into()
        } else {
            "-inf.0".into()
        };
    }
    let mut text = format!("{number:?}");
    if let Some(index) = text.find('e') {
        if text.as_bytes()[index + 1] != b'-' {
            text.insert(index + 1, '+');
        }
    }
    text
}

// Park-Miller, as the test draws: x' = 48271 x mod (2^31 - 1).
struct Draws(i64);

impl Draws {
    fn next(&mut self) -> i64 {
        self.0 = self.0 * 48271 % 2147483647;
        self.0
    }
    // Any double: 31 high bits, 31 low bits and a sign.
    fn bits(&mut self) -> f64 {
        let value = f64::from_bits(((self.next() as u64) << 32) | ((self.next() as u64) << 1));
        if self.next() % 2 == 0 { value } else { -value }
    }
    // Uniform in (-range, range).
    fn within(&mut self, range: f64) -> f64 {
        (self.next() as f64 / 2147483647.0 * 2.0 - 1.0) * range
    }
}

fn mix(hash: i64, value: f64) -> i64 {
    let step = |hash: i64, word: i64| (hash * 31 + word) % 2147483647;
    if value.is_nan() {
        return step(hash, 1);
    }
    let bits = value.to_bits();
    step(step(hash, (bits >> 32) as i64), (bits & 0xffff_ffff) as i64)
}

const SPECIALS: [f64; 32] = [
    0.0,
    -0.0,
    1.0,
    -1.0,
    0.5,
    -0.5,
    2.0,
    3.0,
    0.1,
    1e-10,
    5e-324,
    2.2250738585072014e-308,
    1.5707963267948966,
    3.141592653589793,
    10.0,
    100.0,
    1e6,
    1e22,
    1e300,
    1.7976931348623157e308,
    -1e22,
    1647100.0,
    3400000.5,
    7000001.25,
    16777215.75,
    1e15,
    5.319372648326541e255,
    8.98846567431158e307,
    -2.5e100,
    f64::INFINITY,
    f64::NEG_INFINITY,
    f64::NAN,
];

fn unary(name: &str, f: fn(f64) -> f64, range: f64) {
    for x in SPECIALS {
        println!("{name} {} {}", text(x), text(f(x)));
    }
    let mut draws = Draws(name.len() as i64 + 1);
    let mut hash = 0;
    for _ in 0..20000 {
        hash = mix(hash, f(draws.bits()));
        hash = mix(hash, f(draws.within(range)));
    }
    println!("{name} sweep {hash}");
}

fn binary(name: &str, f: fn(f64, f64) -> f64, range: f64) {
    for x in SPECIALS {
        for y in [
            0.0,
            -0.0,
            1.0,
            -1.0,
            0.5,
            2.0,
            3.0,
            -3.0,
            f64::INFINITY,
            f64::NAN,
        ] {
            println!("{name} {} {} {}", text(x), text(y), text(f(x, y)));
        }
    }
    let mut draws = Draws(name.len() as i64 + 1);
    let mut hash = 0;
    for _ in 0..20000 {
        hash = mix(hash, f(draws.bits(), draws.bits()));
        hash = mix(hash, f(draws.within(range), draws.within(range)));
    }
    println!("{name} sweep {hash}");
}

fn main() {
    unary("sin", libm::sin, 1e3);
    unary("cos", libm::cos, 1e3);
    unary("tan", libm::tan, 1e3);
    unary("asin", libm::asin, 1.0);
    unary("acos", libm::acos, 1.0);
    unary("atan", libm::atan, 1e3);
    unary("exp", libm::exp, 800.0);
    unary("log", libm::log, 1e3);
    binary("atan2", libm::atan2, 1e3);
    binary("expt", libm::pow, 30.0);
}

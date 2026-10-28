//! Scalar real mathematics, with scalar C signatures for Wasm.
//! No Snail-Core roots, allocation, callbacks or resource state cross this boundary.

// ---- Binary64 trigonometry ----

#[unsafe(export_name = "snail:math/sin")]
pub extern "C" fn sin(value: f64) -> f64 {
    value.sin()
}

#[unsafe(export_name = "snail:math/cos")]
pub extern "C" fn cos(value: f64) -> f64 {
    value.cos()
}

#[unsafe(export_name = "snail:math/atan")]
pub extern "C" fn atan(value: f64) -> f64 {
    value.atan()
}

#[unsafe(export_name = "snail:math/tan")]
pub extern "C" fn tan(value: f64) -> f64 {
    value.tan()
}

#[unsafe(export_name = "snail:math/asin")]
pub extern "C" fn asin(value: f64) -> f64 {
    value.asin()
}

#[unsafe(export_name = "snail:math/acos")]
pub extern "C" fn acos(value: f64) -> f64 {
    value.acos()
}

#[unsafe(export_name = "snail:math/atan2")]
pub extern "C" fn atan2(y: f64, x: f64) -> f64 {
    y.atan2(x)
}

// ---- Exponentials and logarithms ----

#[unsafe(export_name = "snail:math/exp")]
pub extern "C" fn exp(value: f64) -> f64 {
    value.exp()
}

#[unsafe(export_name = "snail:math/log")]
pub extern "C" fn log(value: f64) -> f64 {
    value.ln()
}

#[unsafe(export_name = "snail:math/pow")]
pub extern "C" fn pow(base: f64, exponent: f64) -> f64 {
    base.powf(exponent)
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn zero_signs_and_nonfinite_inputs() {
        for zero in [0.0_f64, -0.0_f64] {
            assert_eq!(sin(zero).to_bits(), zero.to_bits());
            assert_eq!(atan(zero).to_bits(), zero.to_bits());
            assert_eq!(cos(zero), 1.0);
        }
        for value in [f64::INFINITY, f64::NEG_INFINITY, f64::NAN] {
            assert!(sin(value).is_nan() && cos(value).is_nan());
        }
        assert_eq!(atan(f64::INFINITY), std::f64::consts::FRAC_PI_2);
        assert_eq!(atan(f64::NEG_INFINITY), -std::f64::consts::FRAC_PI_2);
        assert!(atan(f64::NAN).is_nan());
    }

    #[test]
    fn inverse_domains_and_signed_zero_quadrants() {
        for zero in [0.0_f64, -0.0_f64] {
            assert_eq!(tan(zero).to_bits(), zero.to_bits());
            assert_eq!(asin(zero).to_bits(), zero.to_bits());
            assert_eq!(atan2(zero, 1.0).to_bits(), zero.to_bits());
            assert_eq!(atan2(zero, -1.0), std::f64::consts::PI.copysign(zero));
        }
        assert!(asin(2.0).is_nan() && acos(-2.0).is_nan());
        assert!(tan(f64::INFINITY).is_nan());
    }

    #[test]
    fn real_exponents_and_logarithm_domain() {
        assert_eq!(exp(0.0), 1.0);
        assert_eq!(exp(f64::NEG_INFINITY), 0.0);
        assert_eq!(log(1.0), 0.0);
        assert_eq!(log(0.0), f64::NEG_INFINITY);
        assert!(log(-1.0).is_nan());
        assert_eq!(pow(-2.0, 3.0), -8.0);
        assert_eq!(pow(4.0, 0.5), 2.0);
        assert!(pow(-1.0, 0.5).is_nan());
    }
}

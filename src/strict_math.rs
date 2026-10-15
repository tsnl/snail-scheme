//! Scalar real mathematics, with the same C signatures on native and Wasm.
//! No Scheme roots, allocation, callbacks or resource state cross this boundary.

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
}

//! Numeric tokens describe exact digits without owning Lofi values.
//! Lofi builds and normalizes Integers/Rationals, then applies promotion.

// ---- Lexical exactness remains distinct from rounded binary64 ----

// Signed numerator digits and unsigned nonzero denominator digits are valid
// ASCII in radix 2, 8, 10 or 16. Scale multiplies the ratio by a power of ten.
// Keep an inexact request separate until Lofi rounds the complete ratio;
// a lexical minus sign on zero survives there even though exact zero has no sign.
#[derive(Debug, PartialEq)]
pub(crate) struct Exact {
    pub(crate) numerator: String,
    pub(crate) denominator: String,
    pub(crate) radix: u32,
    pub(crate) scale: i64,
    pub(crate) inexact: bool,
}

#[derive(Debug, PartialEq)]
pub(crate) enum Scalar {
    Integer(i64),
    Real(f64),
    Exact(Exact),
}

#[derive(Debug, PartialEq)]
pub(crate) enum Number {
    Scalar(Scalar),
    Rectangular(Scalar, Scalar),
    Polar(Scalar, Scalar, bool),
}

impl Scalar {
    // Tags 1/2 hold machine scalars; 5/6 hold exact digits with an optional #i.
    // Tokens reserves 0 for nonnumbers and 4 for explicit numeric errors.
    pub(crate) fn kind(&self) -> i32 {
        match self {
            Self::Integer(_) => 1,
            Self::Real(_) => 2,
            Self::Exact(value) => {
                if value.inexact {
                    6
                } else {
                    5
                }
            }
        }
    }

    pub(crate) fn exact(&self) -> Result<&Exact, String> {
        match self {
            Self::Exact(value) => Ok(value),
            _ => Err("numeric component has no exact digit fields".into()),
        }
    }
}

impl Number {
    // Compound tags retain both validated components before Lofi applies
    // rectangular normalization or the exact polar-axis shortcuts.
    pub(crate) fn kind(&self) -> i32 {
        match self {
            Self::Scalar(value) => value.kind(),
            Self::Rectangular(..) => 3,
            Self::Polar(_, _, exact) => {
                if *exact {
                    8
                } else {
                    7
                }
            }
        }
    }

    pub(crate) fn component(&self, part: u32) -> Result<&Scalar, String> {
        match (self, part) {
            (Self::Scalar(value), 0)
            | (Self::Rectangular(value, _), 0)
            | (Self::Rectangular(_, value), 1)
            | (Self::Polar(value, _, _), 0)
            | (Self::Polar(_, value, _), 1) => Ok(value),
            _ => Err("numeric component index out of range".into()),
        }
    }
}

impl Exact {
    pub(crate) fn text(&self, term: u32) -> Result<&str, String> {
        match term {
            0 => Ok(&self.numerator),
            1 => Ok(&self.denominator),
            _ => Err("exact numeric term index out of range".into()),
        }
    }
}

// ---- Prefixes apply once to every component of the token ----

pub(crate) fn parse(text: &str, radix: u32) -> Result<Option<Number>, String> {
    let Some((text, radix, exactness)) = prefixes(text, radix) else {
        return Ok(None);
    };
    if let Some((radius, angle)) = text.split_once('@') {
        return components(radius, angle, radix, exactness)
            .map(|pair| pair.map(|(r, a)| Number::Polar(r, a, exactness == Some(true))));
    }
    if let Some(body) = text.strip_suffix(['i', 'I']) {
        return rectangular(body, radix, exactness);
    }
    Ok(real(text, radix, exactness)?.map(Number::Scalar))
}

fn prefixes(mut text: &str, mut radix: u32) -> Option<(&str, u32, Option<bool>)> {
    if !matches!(radix, 2 | 8 | 10 | 16) {
        return None;
    }
    let (mut exactness, mut radix_seen) = (None, false);
    while let Some([b'#', prefix]) = text.as_bytes().get(..2) {
        match prefix.to_ascii_lowercase() {
            b'e' | b'i' if exactness.is_none() => {
                exactness = Some(prefix.eq_ignore_ascii_case(&b'e'))
            }
            b'b' | b'o' | b'd' | b'x' if !radix_seen => {
                radix = match prefix.to_ascii_lowercase() {
                    b'b' => 2,
                    b'o' => 8,
                    b'x' => 16,
                    _ => 10,
                };
                radix_seen = true;
            }
            _ => return None,
        }
        text = &text[2..];
    }
    Some((text, radix, exactness))
}

fn components(
    left: &str,
    right: &str,
    radix: u32,
    exactness: Option<bool>,
) -> Result<Option<(Scalar, Scalar)>, String> {
    match (
        real(left, radix, exactness)?,
        real(right, radix, exactness)?,
    ) {
        (Some(left), Some(right)) => Ok(Some((left, right))),
        _ => Ok(None),
    }
}

fn rectangular(body: &str, radix: u32, exactness: Option<bool>) -> Result<Option<Number>, String> {
    let split = body.char_indices().rfind(|(at, character)| {
        *at > 0
            && matches!(character, '+' | '-')
            && !(radix == 10 && matches!(body.as_bytes()[at - 1], b'e' | b'E'))
    });
    let (real, imaginary) = split.map_or(("0", body), |(at, _)| body.split_at(at));
    if !imaginary.starts_with(['+', '-']) {
        return Ok(None);
    }
    let imaginary = match imaginary {
        "+" => "+1",
        "-" => "-1",
        _ => imaginary,
    };
    components(real, imaginary, radix, exactness)
        .map(|pair| pair.map(|(r, i)| Number::Rectangular(r, i)))
}

// ---- Integers and ratios retain validated digits beyond machine range ----

fn unsigned_digits(text: &str, radix: u32) -> bool {
    !text.is_empty()
        && text
            .chars()
            .all(|character| character.to_digit(radix).is_some())
}

fn signed_digits(text: &str, radix: u32) -> bool {
    unsigned_digits(text.strip_prefix(['+', '-']).unwrap_or(text), radix)
}

fn exact(numerator: &str, denominator: &str, radix: u32, scale: i64, inexact: bool) -> Scalar {
    Scalar::Exact(Exact {
        numerator: numerator.into(),
        denominator: denominator.into(),
        radix,
        scale,
        inexact,
    })
}

fn integer(text: &str, radix: u32, inexact: bool) -> Scalar {
    match i64::from_str_radix(text, radix) {
        Ok(value) if !inexact => Scalar::Integer(value),
        Ok(value) => Scalar::Real(if value == 0 && text.starts_with('-') {
            -0.0
        } else {
            value as f64
        }),
        Err(_) => exact(text, "1", radix, 0, inexact),
    }
}

fn ratio(
    numerator: &str,
    denominator: &str,
    radix: u32,
    inexact: bool,
) -> Result<Option<Scalar>, String> {
    if !signed_digits(numerator, radix) || !unsigned_digits(denominator, radix) {
        return Ok(None);
    }
    if denominator.bytes().all(|byte| byte == b'0') {
        return Err("zero denominator in numeric token".into());
    }
    Ok(Some(exact(numerator, denominator, radix, 0, inexact)))
}

fn real(text: &str, radix: u32, exactness: Option<bool>) -> Result<Option<Scalar>, String> {
    if let Some((numerator, denominator)) = text.split_once('/') {
        return ratio(numerator, denominator, radix, exactness == Some(false));
    }
    if signed_digits(text, radix) {
        return Ok(Some(integer(text, radix, exactness == Some(false))));
    }
    if radix != 10 {
        return Ok(None);
    }
    if exactness == Some(true) {
        return exact_decimal(text);
    }
    Ok(crate::parse_float(text).map(Scalar::Real))
}

// ---- Exact decimal places are powers of ten, never rounded floats ----

fn decimal_parts(text: &str) -> Option<(&str, &str)> {
    if !text.contains(['.', 'e', 'E']) {
        return None;
    }
    let unsigned = text.strip_prefix(['+', '-']).unwrap_or(text);
    let (mantissa, exponent) = unsigned.split_once(['e', 'E']).unwrap_or((unsigned, "0"));
    let (whole, fraction) = mantissa.split_once('.').unwrap_or((mantissa, ""));
    let has_digits = !whole.is_empty() || !fraction.is_empty();
    let digits_only = whole
        .bytes()
        .chain(fraction.bytes())
        .all(|digit| digit.is_ascii_digit());
    (has_digits && digits_only && signed_digits(exponent, 10)).then_some((mantissa, exponent))
}

fn exact_decimal(text: &str) -> Result<Option<Scalar>, String> {
    match decimal_parts(text) {
        Some((mantissa, exponent)) => decimal_value(text, mantissa, exponent).map(Some),
        None if ["+inf.0", "-inf.0", "+nan.0", "-nan.0"]
            .iter()
            .any(|name| text.eq_ignore_ascii_case(name)) =>
        {
            Err("nonfinite number has no exact value".into())
        }
        None => Ok(None),
    }
}

fn decimal_value(text: &str, mantissa: &str, exponent: &str) -> Result<Scalar, String> {
    let digits = mantissa.replace('.', "");
    if digits.bytes().all(|byte| byte == b'0') {
        return Ok(Scalar::Integer(0));
    }
    let places = mantissa.split_once('.').map_or(0, |(_, tail)| tail.len());
    let scale = decimal_scale(exponent, places)?;
    let signed = if text.starts_with('-') {
        format!("-{digits}")
    } else {
        digits
    };
    Ok(exact(&signed, "1", 10, scale, false))
}

fn decimal_scale(exponent: &str, places: usize) -> Result<i64, String> {
    // The effective scale must fit, even when subtracting decimal places moves
    // an exponent just above I64_MAX into range. i128 covers every usize offset.
    exponent
        .parse::<i128>()
        .ok()
        .and_then(|exponent| exponent.checked_sub(i128::try_from(places).ok()?))
        .and_then(|scale| i64::try_from(scale).ok())
        .filter(|scale| scale.checked_abs().is_some())
        .ok_or_else(|| "exact decimal exponent exceeds supported allocation index range".into())
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn exact_tokens_retain_every_digit_and_decimal_place() {
        for (text, numerator, denominator, radix, scale, inexact) in [
            (
                "9223372036854775808",
                "9223372036854775808",
                "1",
                10,
                0,
                false,
            ),
            (
                "#x20000000000000000",
                "20000000000000000",
                "1",
                16,
                0,
                false,
            ),
            (
                "#e9007199254740993.1",
                "90071992547409931",
                "1",
                10,
                -1,
                false,
            ),
            ("#e12.5e-3", "125", "1", 10, -4, false),
            ("#i-0/2", "-0", "2", 10, 0, true),
            ("#x#i-A/B", "-A", "B", 16, 0, true),
        ] {
            assert_eq!(
                parse(text, 10).unwrap(),
                Some(Number::Scalar(exact(
                    numerator,
                    denominator,
                    radix,
                    scale,
                    inexact
                ))),
                "{text}"
            );
        }
    }

    #[test]
    fn complete_grammar_precedes_normalization_and_promotion() {
        assert!(matches!(
            parse("1/2+3/4i", 10).unwrap(),
            Some(Number::Rectangular(..))
        ));
        assert!(matches!(
            parse("#e1/2@0.0", 10).unwrap(),
            Some(Number::Polar(_, _, true))
        ));
        for text in [
            "1/-2",
            "1/+2",
            "1/2/3",
            "#i#e0@1",
            "0@junk",
            "1@2@0",
            "#x#b10",
            "1e",
            "--1",
            "#e0e+",
            "#e0e1e2",
            "#e0.0.0",
            "#e.e1",
            "#e0e+999x",
        ] {
            assert_eq!(parse(text, 10).unwrap(), None, "{text}");
        }
        for text in [
            "0/0",
            "1/000",
            "#e+inf.0",
            "#e-nan.0",
            "#e1e9223372036854775808",
        ] {
            assert!(parse(text, 10).is_err(), "{text}");
        }
        assert_eq!(
            parse("#e0e999999999999999999999", 10).unwrap(),
            Some(Number::Scalar(Scalar::Integer(0)))
        );
        assert_eq!(
            parse("FF", 16).unwrap(),
            Some(Number::Scalar(Scalar::Integer(255)))
        );
    }

    #[test]
    fn exact_decimal_range_applies_after_fractional_places() {
        assert_eq!(decimal_scale("9223372036854775808", 1), Ok(i64::MAX));
        assert_eq!(decimal_scale("-9223372036854775807", 0), Ok(-i64::MAX));
        assert!(decimal_scale("9223372036854775808", 0).is_err());
        assert!(decimal_scale("-9223372036854775807", 1).is_err());
        assert!(decimal_scale("9999999999999999999999999999999999999999999", 0).is_err());
        assert_eq!(
            parse("#e.1e9223372036854775808", 10).unwrap(),
            Some(Number::Scalar(exact("1", "1", 10, i64::MAX, false)))
        );
    }
}

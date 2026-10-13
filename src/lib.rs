//! Rust services for the application binary interface (ABI).
//!
//! Every exported primitive borrows a rooted argument vector and returns one
//! owned result handle. Rust sees table indices, never WasmGC pointers. The
//! runtime compiles to Wasm and uses the Scheme module’s engine-visible root
//! table. A node owns one instance; the engine collects its Scheme memory.

// Ordinary cargo tests exercise helpers independently of a Wasm engine.
#![cfg_attr(not(target_arch = "wasm32"), allow(dead_code))]

pub mod abi;
mod artifacts;
mod datum;
mod hash;
mod host;
mod interop_example;
mod platform;
mod symbols;
mod text;
mod unicode;

use crate::abi::{Arguments, Kind, PORT_KIND, Root};
use num_complex::Complex64;

// ---- Module initialization ----

// Export a reactor initializer so wasm-ld does not wrap each exported function
// in constructor/destructor calls. The linked Wasm entry calls it once, before
// Scheme or Rust runs. All callable Rust services share this runtime.
#[cfg(target_arch = "wasm32")]
#[unsafe(no_mangle)]
pub unsafe extern "C" fn _initialize() {
    unsafe extern "C" {
        fn __wasm_call_ctors();
    }
    unsafe { __wasm_call_ctors() };
}

// ---- Foreign call boundaries ----

fn arguments(raw: u32, name: &str, min: usize, max: usize) -> Arguments {
    // The generated wrapper owns this argument-vector root for the whole call.
    let args = unsafe { Arguments::borrow(raw) };
    args.check(name, min, max)
        .unwrap_or_else(|error| fail_message(&error));
    args
}

fn finish(result: Result<Root, String>) -> u32 {
    result
        .unwrap_or_else(|error| fail_message(&error))
        .into_handle()
}

fn fail_message(message: &str) -> ! {
    #[cfg(target_arch = "wasm32")]
    unsafe {
        #[link(wasm_import_module = "snail.platform")]
        unsafe extern "C" {
            #[link_name = "diagnostics/report-error"]
            fn report_error(pointer: *const u8, length: usize) -> !;
        }
        report_error(message.as_ptr(), message.len())
    }
    #[cfg(not(target_arch = "wasm32"))]
    panic!("snail-scheme: {message}")
}

#[unsafe(export_name = "snail:eof-object")]
pub extern "C" fn eof_object(raw: u32) -> u32 {
    arguments(raw, "eof-object", 0, 0);
    Root::eof().into_handle()
}

// ---- Binary values and UTF-8 ----

fn nonnegative(value: &Root) -> Result<usize, String> {
    usize::try_from(value.as_integer()?)
        .map_err(|_| "expected a nonnegative index or length".into())
}

fn slice_range(args: &Arguments, length: usize) -> Result<std::ops::Range<usize>, String> {
    bounds(args, length, 1)
}

fn bounds(args: &Arguments, length: usize, first: usize) -> Result<std::ops::Range<usize>, String> {
    let start = if args.len() > first {
        nonnegative(&args.get(first)?)?
    } else {
        0
    };
    let end = if args.len() > first + 1 {
        nonnegative(&args.get(first + 1)?)?
    } else {
        length
    };
    if start <= end && end <= length {
        Ok(start..end)
    } else {
        Err("slice index out of range".into())
    }
}

fn bytes(value: &Root, range: std::ops::Range<usize>) -> Result<Vec<u8>, String> {
    if value.kind() != Kind::Bytevector {
        return Err("expected a bytevector".into());
    }
    range.map(|index| value.byte_at(index)).collect()
}

#[unsafe(export_name = "snail:bytevector-copy")]
pub extern "C" fn bytevector_copy(raw: u32) -> u32 {
    let args = arguments(raw, "bytevector-copy", 1, 3);
    finish((|| {
        let value = args.get(0)?;
        Ok(Root::bytevector(&bytes(
            &value,
            slice_range(&args, value.len()?)?,
        )?))
    })())
}

#[unsafe(export_name = "snail:bytevector-append")]
pub extern "C" fn bytevector_append(raw: u32) -> u32 {
    let args = arguments(raw, "bytevector-append", 0, usize::MAX);
    finish((|| {
        let mut result = Vec::new();
        for index in 0..args.len() {
            let value = args.get(index)?;
            result.extend(bytes(&value, 0..value.len()?)?);
        }
        Ok(Root::bytevector(&result))
    })())
}

#[unsafe(export_name = "snail:utf8->string")]
pub extern "C" fn utf8_to_string(raw: u32) -> u32 {
    let args = arguments(raw, "utf8->string", 1, 3);
    finish((|| {
        let value = args.get(0)?;
        let bytes = bytes(&value, slice_range(&args, value.len()?)?)?;
        Ok(Root::string(
            std::str::from_utf8(&bytes).map_err(|e| e.to_string())?,
        ))
    })())
}

#[unsafe(export_name = "snail:string->utf8")]
pub extern "C" fn string_to_utf8(raw: u32) -> u32 {
    let args = arguments(raw, "string->utf8", 1, 3);
    finish((|| {
        let value = args.get(0)?;
        if value.kind() != Kind::String {
            return Err("expected a string".into());
        }
        let text = slice_range(&args, value.len()?)?
            .map(|i| value.char_at(i))
            .collect::<Result<String, _>>()?;
        Ok(Root::bytevector(text.as_bytes()))
    })())
}

fn string_text(value: &Root) -> Result<String, String> {
    if value.kind() != Kind::String {
        return Err("expected a string".into());
    }
    value.text()
}

// ---- Numeric text ----

#[unsafe(export_name = "snail:string->number")]
pub extern "C" fn string_to_number(raw: u32) -> u32 {
    finish(parse_number(&arguments(raw, "string->number", 1, 2)))
}
#[unsafe(export_name = "snail:number->string")]
pub extern "C" fn number_to_string(raw: u32) -> u32 {
    finish(format_number(&arguments(raw, "number->string", 1, 2)))
}

fn radix(args: &Arguments) -> Result<u32, String> {
    let radix = if args.len() == 2 {
        args.get(1)?.as_integer()?
    } else {
        10
    };
    if matches!(radix, 2 | 8 | 10 | 16) {
        Ok(radix as u32)
    } else {
        Err("unsupported numeric radix".into())
    }
}

fn parse_number(args: &Arguments) -> Result<Root, String> {
    let text = string_text(&args.get(0)?)?;
    Ok(datum::number(&text, radix(args)?)?
        .map(|number| number.root())
        .unwrap_or_else(|| Root::boolean(false)))
}

fn format_number(args: &Arguments) -> Result<Root, String> {
    let radix = radix(args)?;
    let value = args.get(0)?;
    Ok(Root::string(&number_text(&value, radix)?))
}

fn number_text(value: &Root, radix: u32) -> Result<String, String> {
    Ok(match value.kind() {
        Kind::Integer => integer_text(value.as_integer()?, radix),
        Kind::Real if radix == 10 => float_text(value.as_real()?),
        Kind::Real => return Err("inexact number requires decimal radix".into()),
        Kind::Complex => {
            let real = number_text(&value.real_part()?, radix)?;
            let imag = number_text(&value.imag_part()?, radix)?;
            let sign = if imag.starts_with(['+', '-']) {
                ""
            } else {
                "+"
            };
            format!("{real}{sign}{imag}i")
        }
        _ => return Err("expected a number".into()),
    })
}

fn integer_text(number: i64, radix: u32) -> String {
    let magnitude = number.unsigned_abs();
    let digits = match radix {
        2 => format!("{magnitude:b}"),
        8 => format!("{magnitude:o}"),
        16 => format!("{magnitude:x}"),
        _ => magnitude.to_string(),
    };
    if number < 0 {
        format!("-{digits}")
    } else {
        digits
    }
}

fn parse_float(text: &str) -> Option<f64> {
    if text.eq_ignore_ascii_case("+inf.0") {
        Some(f64::INFINITY)
    } else if text.eq_ignore_ascii_case("-inf.0") {
        Some(f64::NEG_INFINITY)
    } else if text.eq_ignore_ascii_case("+nan.0") || text.eq_ignore_ascii_case("-nan.0") {
        Some(f64::NAN)
    } else if text.contains(['.', 'e', 'E']) {
        text.parse().ok()
    } else {
        None
    }
}

fn float_text(number: f64) -> String {
    if number.is_nan() {
        "+nan.0".into()
    } else if number == f64::INFINITY {
        "+inf.0".into()
    } else if number == f64::NEG_INFINITY {
        "-inf.0".into()
    } else {
        finite_float_text(number)
    }
}

fn finite_float_text(number: f64) -> String {
    let mut text = format!("{number:?}");
    // Match the bootstrap writer's explicit positive exponent. Both spellings
    // read identically, but compiler output is compared byte for byte.
    if let Some(index) = text.find('e') {
        if text.as_bytes()[index + 1] != b'-' {
            text.insert(index + 1, '+');
        }
    }
    text
}

// ---- Inexact mathematics ----

#[unsafe(export_name = "snail:inexact")]
pub extern "C" fn inexact(raw: u32) -> u32 {
    let args = arguments(raw, "inexact", 1, 1);
    finish(args.get(0).and_then(|value| {
        if value.kind() == Kind::Complex {
            complex_root(complex_value(&value)?)
        } else {
            Ok(Root::real(value.as_real()?))
        }
    }))
}

#[unsafe(export_name = "snail:exact")]
pub extern "C" fn exact(raw: u32) -> u32 {
    let args = arguments(raw, "exact", 1, 1);
    finish(args.get(0).and_then(exact_number))
}

fn exact_number(value: Root) -> Result<Root, String> {
    match value.kind() {
        Kind::Integer => Ok(value),
        Kind::Complex => Root::complex(
            &exact_number(value.real_part()?)?,
            &exact_number(value.imag_part()?)?,
        ),
        _ => exact_integer(value.as_real()?).map(Root::integer),
    }
}

fn exact_integer(value: f64) -> Result<i64, String> {
    if value.is_finite()
        && value.fract() == 0.0
        && (-9223372036854775808.0..9223372036854775808.0).contains(&value)
    {
        Ok(value as i64)
    } else {
        Err("exact number outside supported integer range".into())
    }
}

#[unsafe(export_name = "snail:numerator")]
pub extern "C" fn numerator(raw: u32) -> u32 {
    let args = arguments(raw, "numerator", 1, 1);
    finish(args.get(0).and_then(|value| {
        if value.kind() == Kind::Integer {
            Ok(value)
        } else {
            Ok(Root::real(real_fraction(value.as_real()?)?.0))
        }
    }))
}

#[unsafe(export_name = "snail:denominator")]
pub extern "C" fn denominator(raw: u32) -> u32 {
    let args = arguments(raw, "denominator", 1, 1);
    finish(args.get(0).and_then(|value| {
        if value.kind() == Kind::Integer {
            Ok(Root::integer(1))
        } else {
            Ok(Root::real(real_fraction(value.as_real()?)?.1))
        }
    }))
}

fn real_fraction(value: f64) -> Result<(f64, f64), String> {
    if !value.is_finite() {
        return Err("expected a finite real number".into());
    }
    if value == 0.0 {
        return Ok((value, 1.0));
    }
    let bits = value.to_bits();
    let exponent = ((bits >> 52) & 0x7ff) as i32;
    let mantissa = (bits & ((1 << 52) - 1)) | if exponent == 0 { 0 } else { 1 << 52 };
    let zeros = mantissa.trailing_zeros();
    let power = exponent.max(1) - 1023 - 52 + zeros as i32;
    let numerator = (mantissa >> zeros) as f64 * value.signum() * 2.0_f64.powi(power.max(0));
    let denominator = 2.0_f64.powi((-power).max(0));
    if denominator.is_infinite() {
        return Err("denominator exceeds supported real range".into());
    }
    Ok((numerator, denominator))
}

#[unsafe(export_name = "snail:floor")]
pub extern "C" fn floor(raw: u32) -> u32 {
    let args = arguments(raw, "floor", 1, 1);
    finish(args.get(0).and_then(|value| round_real(value, f64::floor)))
}

#[unsafe(export_name = "snail:ceiling")]
pub extern "C" fn ceiling(raw: u32) -> u32 {
    let args = arguments(raw, "ceiling", 1, 1);
    finish(args.get(0).and_then(|value| round_real(value, f64::ceil)))
}

#[unsafe(export_name = "snail:truncate")]
pub extern "C" fn truncate(raw: u32) -> u32 {
    let args = arguments(raw, "truncate", 1, 1);
    finish(args.get(0).and_then(|value| round_real(value, f64::trunc)))
}

#[unsafe(export_name = "snail:round")]
pub extern "C" fn round(raw: u32) -> u32 {
    let args = arguments(raw, "round", 1, 1);
    finish(
        args.get(0)
            .and_then(|value| round_real(value, f64::round_ties_even)),
    )
}

fn round_real(value: Root, operation: fn(f64) -> f64) -> Result<Root, String> {
    if value.kind() == Kind::Integer {
        Ok(value)
    } else {
        Ok(Root::real(operation(value.as_real()?)))
    }
}

#[unsafe(export_name = "snail:expt")]
pub extern "C" fn expt(raw: u32) -> u32 {
    let args = arguments(raw, "expt", 2, 2);
    finish(power(&args))
}

fn power(args: &Arguments) -> Result<Root, String> {
    let base = args.get(0)?;
    let exponent = args.get(1)?;
    if let Some(result) = exact_power(&base, &exponent)? {
        return Ok(result);
    }
    inexact_power(&base, &exponent)
}

// None means this representation needs inexact math; an exact overflow remains
// an error. In particular, exponent zero does not excuse an invalid base.
fn exact_power(base: &Root, exponent: &Root) -> Result<Option<Root>, String> {
    if exponent.kind() != Kind::Integer {
        return Ok(None);
    }
    let exponent = exponent.as_integer()?;
    if exponent < 0 {
        return Ok(None);
    }
    let exponent = exponent as u64;
    match base.kind() {
        Kind::Integer => {
            integer_power(base.as_integer()?, exponent).map(|value| Some(Root::integer(value)))
        }
        Kind::Complex => {
            let real = base.real_part()?;
            let imag = base.imag_part()?;
            if real.kind() != Kind::Integer || imag.kind() != Kind::Integer {
                return Ok(None);
            }
            let (real, imag) =
                complex_integer_power((real.as_integer()?, imag.as_integer()?), exponent)?;
            Root::complex(&Root::integer(real), &Root::integer(imag)).map(Some)
        }
        _ => Ok(None),
    }
}

fn inexact_power(base: &Root, exponent: &Root) -> Result<Root, String> {
    if base.kind() == Kind::Complex || exponent.kind() == Kind::Complex {
        return complex_root(complex_value(base)?.powc(complex_value(exponent)?));
    }
    let (base, exponent) = (base.as_real()?, exponent.as_real()?);
    let result = base.powf(exponent);
    if result.is_nan() && base.is_finite() && exponent.is_finite() {
        complex_root(Complex64::new(base, 0.0).powc(Complex64::new(exponent, 0.0)))
    } else {
        Ok(Root::real(result))
    }
}

fn integer_power(mut base: i64, mut exponent: u64) -> Result<i64, String> {
    let mut result = 1_i64;
    while exponent != 0 {
        if exponent & 1 != 0 {
            result = result.checked_mul(base).ok_or("exact integer overflow")?;
        }
        exponent >>= 1;
        if exponent != 0 {
            base = base.checked_mul(base).ok_or("exact integer overflow")?;
        }
    }
    Ok(result)
}

fn complex_integer_product(a: (i64, i64), b: (i64, i64)) -> Result<(i64, i64), String> {
    let real = (a.0 as i128 * b.0 as i128).checked_sub(a.1 as i128 * b.1 as i128);
    let imag = (a.0 as i128 * b.1 as i128).checked_add(a.1 as i128 * b.0 as i128);
    let component = |value: Option<i128>| {
        value
            .and_then(|n| i64::try_from(n).ok())
            .ok_or_else(|| String::from("exact integer overflow"))
    };
    Ok((component(real)?, component(imag)?))
}

fn complex_integer_power(mut base: (i64, i64), mut exponent: u64) -> Result<(i64, i64), String> {
    let mut result = (1, 0);
    while exponent != 0 {
        if exponent & 1 != 0 {
            result = complex_integer_product(result, base)?;
        }
        exponent >>= 1;
        if exponent != 0 {
            base = complex_integer_product(base, base)?;
        }
    }
    Ok(result)
}

#[unsafe(export_name = "snail:exact-integer-sqrt")]
pub extern "C" fn exact_integer_sqrt(raw: u32) -> u32 {
    let args = arguments(raw, "exact-integer-sqrt", 1, 1);
    finish((|| {
        let value = args.get(0)?.as_integer()?;
        let sqrt = value
            .checked_isqrt()
            .ok_or("expected a nonnegative exact integer")?;
        Ok(Root::values(&[
            Root::integer(sqrt),
            Root::integer(value - sqrt * sqrt),
        ]))
    })())
}

// Snail has i64 integers and binary64 reals. Complex components keep their
// exactness in Wasm arithmetic; transcendental operations use native binary64.
// Arguments stay rooted across result allocation; only copied f64 values enter
// the math operations. finish transfers the separately owned result root.

fn complex_value(value: &Root) -> Result<Complex64, String> {
    Ok(Complex64::new(
        value.real_part()?.as_real()?,
        value.imag_part()?.as_real()?,
    ))
}

fn complex_root(value: Complex64) -> Result<Root, String> {
    Root::complex(&Root::real(value.re), &Root::real(value.im))
}

fn unary_math(
    value: Root,
    real: fn(f64) -> f64,
    complex: fn(Complex64) -> Complex64,
) -> Result<Root, String> {
    if value.kind() == Kind::Complex {
        return complex_root(complex(complex_value(&value)?));
    }
    let input = value.as_real()?;
    let result = real(input);
    if result.is_nan() && input.is_finite() {
        complex_root(complex(Complex64::new(input, 0.0)))
    } else {
        Ok(Root::real(result))
    }
}

#[unsafe(export_name = "snail:make-polar")]
pub extern "C" fn make_polar(raw: u32) -> u32 {
    let args = arguments(raw, "make-polar", 2, 2);
    finish((|| {
        complex_root(Complex64::from_polar(
            args.get(0)?.as_real()?,
            args.get(1)?.as_real()?,
        ))
    })())
}

#[unsafe(export_name = "snail:magnitude")]
pub extern "C" fn magnitude(raw: u32) -> u32 {
    let args = arguments(raw, "magnitude", 1, 1);
    finish(
        args.get(0)
            .and_then(|value| complex_value(&value))
            .map(|value| Root::real(value.norm())),
    )
}

#[unsafe(export_name = "snail:angle")]
pub extern "C" fn angle(raw: u32) -> u32 {
    let args = arguments(raw, "angle", 1, 1);
    finish(
        args.get(0)
            .and_then(|value| complex_value(&value))
            .map(|value| Root::real(value.arg())),
    )
}

#[unsafe(export_name = "snail:acos")]
pub extern "C" fn acos(raw: u32) -> u32 {
    let args = arguments(raw, "acos", 1, 1);
    finish(
        args.get(0)
            .and_then(|value| unary_math(value, f64::acos, Complex64::acos)),
    )
}

#[unsafe(export_name = "snail:asin")]
pub extern "C" fn asin(raw: u32) -> u32 {
    let args = arguments(raw, "asin", 1, 1);
    finish(
        args.get(0)
            .and_then(|value| unary_math(value, f64::asin, Complex64::asin)),
    )
}

#[unsafe(export_name = "snail:cos")]
pub extern "C" fn cos(raw: u32) -> u32 {
    let args = arguments(raw, "cos", 1, 1);
    finish(
        args.get(0)
            .and_then(|value| unary_math(value, f64::cos, Complex64::cos)),
    )
}

#[unsafe(export_name = "snail:exp")]
pub extern "C" fn exp(raw: u32) -> u32 {
    let args = arguments(raw, "exp", 1, 1);
    finish(
        args.get(0)
            .and_then(|value| unary_math(value, f64::exp, Complex64::exp)),
    )
}

#[unsafe(export_name = "snail:finite?")]
pub extern "C" fn finite(raw: u32) -> u32 {
    let args = arguments(raw, "finite?", 1, 1);
    finish(
        args.get(0)
            .and_then(|value| complex_value(&value))
            .map(|value| Root::boolean(value.is_finite())),
    )
}

#[unsafe(export_name = "snail:infinite?")]
pub extern "C" fn infinite(raw: u32) -> u32 {
    let args = arguments(raw, "infinite?", 1, 1);
    finish(
        args.get(0)
            .and_then(|value| complex_value(&value))
            .map(|value| Root::boolean(value.re.is_infinite() || value.im.is_infinite())),
    )
}

#[unsafe(export_name = "snail:nan?")]
pub extern "C" fn nan(raw: u32) -> u32 {
    let args = arguments(raw, "nan?", 1, 1);
    finish(
        args.get(0)
            .and_then(|value| complex_value(&value))
            .map(|value| Root::boolean(value.is_nan())),
    )
}

#[unsafe(export_name = "snail:sin")]
pub extern "C" fn sin(raw: u32) -> u32 {
    let args = arguments(raw, "sin", 1, 1);
    finish(
        args.get(0)
            .and_then(|value| unary_math(value, f64::sin, Complex64::sin)),
    )
}

#[unsafe(export_name = "snail:sqrt")]
pub extern "C" fn sqrt(raw: u32) -> u32 {
    let args = arguments(raw, "sqrt", 1, 1);
    finish(
        args.get(0)
            .and_then(|value| unary_math(value, f64::sqrt, Complex64::sqrt)),
    )
}

#[unsafe(export_name = "snail:tan")]
pub extern "C" fn tan(raw: u32) -> u32 {
    let args = arguments(raw, "tan", 1, 1);
    finish(
        args.get(0)
            .and_then(|value| unary_math(value, f64::tan, Complex64::tan)),
    )
}

#[unsafe(export_name = "snail:atan")]
pub extern "C" fn atan(raw: u32) -> u32 {
    finish(arctangent(&arguments(raw, "atan", 1, 2)))
}

fn arctangent(args: &Arguments) -> Result<Root, String> {
    if args.len() == 1 {
        return unary_math(args.get(0)?, f64::atan, Complex64::atan);
    }
    let y = args.get(0)?.as_real()?;
    Ok(Root::real(y.atan2(args.get(1)?.as_real()?)))
}

#[unsafe(export_name = "snail:log")]
pub extern "C" fn log(raw: u32) -> u32 {
    finish(logarithm(&arguments(raw, "log", 1, 2)))
}

fn logarithm(args: &Arguments) -> Result<Root, String> {
    if args.len() == 1 {
        return unary_math(args.get(0)?, f64::ln, Complex64::ln);
    }
    let base = args.get(1)?;
    let value = args.get(0)?;
    if base.kind() == Kind::Complex
        || value.kind() == Kind::Complex
        || value.as_real()? < 0.0
        || base.as_real()? < 0.0
    {
        return complex_root(complex_value(&value)?.ln() / complex_value(&base)?.ln());
    }
    Ok(Root::real(value.as_real()?.log(base.as_real()?)))
}

// ---- Unicode and substring search ----

#[unsafe(export_name = "snail:char-alphabetic?")]
pub extern "C" fn char_alphabetic(raw: u32) -> u32 {
    let args = arguments(raw, "char-alphabetic?", 1, 1);
    finish(
        args.get(0)
            .and_then(|v| v.as_character())
            .map(|c| Root::boolean(c.is_alphabetic())),
    )
}
#[unsafe(export_name = "snail:char-numeric?")]
pub extern "C" fn char_numeric(raw: u32) -> u32 {
    let args = arguments(raw, "char-numeric?", 1, 1);
    finish(
        args.get(0)
            .and_then(|v| v.as_character())
            .map(|c| Root::boolean(unicode::digit_value(c).is_some())),
    )
}
#[unsafe(export_name = "snail:char-whitespace?")]
pub extern "C" fn char_whitespace(raw: u32) -> u32 {
    let args = arguments(raw, "char-whitespace?", 1, 1);
    finish(
        args.get(0)
            .and_then(|v| v.as_character())
            .map(|c| Root::boolean(c.is_whitespace())),
    )
}
#[unsafe(export_name = "snail:char-ci=?")]
pub extern "C" fn char_ci_equal(raw: u32) -> u32 {
    finish(compare_folded_chars(&arguments(
        raw,
        "char-ci=?",
        2,
        usize::MAX,
    )))
}

fn compare_folded_chars(args: &Arguments) -> Result<Root, String> {
    let mut previous = args.get(0)?.as_character()?;
    let mut equal = true;
    for index in 1..args.len() {
        let current = args.get(index)?.as_character()?;
        equal &= text::fold_character(previous) == text::fold_character(current);
        previous = current;
    }
    Ok(Root::boolean(equal))
}

#[unsafe(export_name = "snail:string-contains")]
pub extern "C" fn string_contains(raw: u32) -> u32 {
    finish(find_substring(&arguments(raw, "string-contains", 2, 3)))
}

fn find_substring(args: &Arguments) -> Result<Root, String> {
    let text = args.get(0)?;
    let pattern = args.get(1)?;
    if text.kind() != Kind::String || pattern.kind() != Kind::String {
        return Err("string-contains: expected strings".into());
    }
    let start = if args.len() == 3 {
        usize::try_from(args.get(2)?.as_integer()?).map_err(|_| "negative start index")?
    } else {
        0
    };
    let length = text.len()?;
    if start > length {
        return Err("string-contains: start index out of range".into());
    }
    // Only the pattern is copied; the haystack stays in the GC heap.
    let pattern = (0..pattern.len()?)
        .map(|i| pattern.char_at(i))
        .collect::<Result<Vec<_>, _>>()?;
    let found = find_characters(length, &pattern, start, |i| text.char_at(i))?;
    Ok(found
        .map(|i| Root::integer(i as i64))
        .unwrap_or_else(|| Root::boolean(false)))
}

fn find_characters(
    length: usize,
    pattern: &[char],
    start: usize,
    mut at: impl FnMut(usize) -> Result<char, String>,
) -> Result<Option<usize>, String> {
    if pattern.len() > length - start {
        return Ok(None);
    }
    for offset in start..=length - pattern.len() {
        let mut matches = true;
        for (index, expected) in pattern.iter().enumerate() {
            if at(offset + index)? != *expected {
                matches = false;
                break;
            }
        }
        if matches {
            return Ok(Some(offset));
        }
    }
    Ok(None)
}

// ---- Datum printing ----

enum PrintTask {
    Value(Root),
    Tail {
        value: Root,
        slow: Root,
        advance: bool,
    },
    Text(&'static str),
    Leave,
}

/// Pending work avoids Rust recursion. A list tail uses Floyd's cycle check,
/// so a long flat list does not retain or scan every earlier pair as an ancestor.
fn format_value(value: Root, display: bool) -> Result<String, String> {
    let mut output = String::new();
    let mut pending = vec![PrintTask::Value(value)];
    let mut active = Vec::new();
    while let Some(task) = pending.pop() {
        match task {
            PrintTask::Text(text) => output.push_str(text),
            PrintTask::Leave => {
                active.pop();
            }
            PrintTask::Value(value) => {
                print_value(value, display, &mut output, &mut pending, &mut active)?
            }
            PrintTask::Tail {
                value,
                slow,
                advance,
            } => print_tail(value, slow, advance, &mut output, &mut pending, &mut active)?,
        }
    }
    Ok(output)
}

fn print_tail(
    value: Root,
    slow: Root,
    advance: bool,
    output: &mut String,
    pending: &mut Vec<PrintTask>,
    active: &mut Vec<Root>,
) -> Result<(), String> {
    if value.kind() == Kind::Nil {
        return Ok(());
    }
    if value.kind() != Kind::Pair {
        output.push_str(" . ");
        pending.push(PrintTask::Value(value));
        return Ok(());
    }
    if value.same(&slow) || active.iter().any(|ancestor| value.same(ancestor)) {
        output.push_str(" . #<cycle>");
        return Ok(());
    }
    let slow = if advance { slow.cdr()? } else { slow };
    output.push(' ');
    pending.push(PrintTask::Tail {
        value: value.cdr()?,
        slow,
        advance: !advance,
    });
    active.push(value.clone());
    pending.push(PrintTask::Leave);
    pending.push(PrintTask::Value(value.car()?));
    Ok(())
}

fn print_value(
    value: Root,
    display: bool,
    output: &mut String,
    pending: &mut Vec<PrintTask>,
    active: &mut Vec<Root>,
) -> Result<(), String> {
    match value.kind() {
        Kind::Unspecified => output.push_str("#<unspecified>"),
        Kind::Uninitialized => output.push_str("#<uninitialized>"),
        Kind::Nil => output.push_str("()"),
        Kind::Eof => output.push_str("#<eof>"),
        Kind::Boolean => output.push_str(if value.as_bool()? { "#t" } else { "#f" }),
        Kind::Integer => output.push_str(&value.as_integer()?.to_string()),
        Kind::Real => output.push_str(&float_text(value.as_real()?)),
        Kind::Complex => output.push_str(&number_text(&value, 10)?),
        Kind::Character => print_character(output, value.as_character()?, display),
        Kind::String if !display => quote_string(output, &value.text()?),
        Kind::Symbol if !display => print_symbol(output, &value.text()?),
        Kind::String | Kind::Symbol => output.push_str(&value.text()?),
        Kind::Pair | Kind::Vector => print_container(value, output, pending, active)?,
        Kind::Bytevector => {
            output.push_str("#u8(");
            for i in 0..value.len()? {
                if i > 0 {
                    output.push(' ');
                }
                output.push_str(&value.byte_at(i)?.to_string());
            }
            output.push(')');
        }
        Kind::Procedure => output.push_str("#<procedure>"),
        Kind::Record => output.push_str("#<record>"),
        Kind::Storage => output.push_str("#<storage>"),
        Kind::Extension => output.push_str(if value.extension_parts()?.0 == PORT_KIND {
            "#<port>"
        } else {
            "#<extension>"
        }),
        Kind::Values => output.push_str("#<values>"),
    }
    Ok(())
}

fn print_container(
    value: Root,
    output: &mut String,
    pending: &mut Vec<PrintTask>,
    active: &mut Vec<Root>,
) -> Result<(), String> {
    if active.iter().any(|ancestor| value.same(ancestor)) {
        output.push_str("#<cycle>");
        return Ok(());
    }
    active.push(value.clone());
    pending.push(PrintTask::Leave);
    pending.push(PrintTask::Text(")"));
    if value.kind() == Kind::Pair {
        output.push('(');
        pending.push(PrintTask::Tail {
            value: value.cdr()?,
            slow: value.clone(),
            advance: false,
        });
        pending.push(PrintTask::Value(value.car()?));
    } else {
        output.push_str("#(");
        for index in (0..value.len()?).rev() {
            pending.push(PrintTask::Value(value.at(index)?));
            if index > 0 {
                pending.push(PrintTask::Text(" "));
            }
        }
    }
    Ok(())
}

fn print_character(output: &mut String, character: char, display: bool) {
    if display {
        output.push(character);
        return;
    }
    output.push_str("#\\");
    match character {
        ' ' => output.push_str("space"),
        '\n' => output.push_str("newline"),
        '\t' => output.push_str("tab"),
        '\r' => output.push_str("return"),
        _ => output.push(character),
    }
}

fn quote_string(output: &mut String, text: &str) {
    output.push('"');
    for character in text.chars() {
        match character {
            '"' => output.push_str("\\\""),
            '\\' => output.push_str("\\\\"),
            '\n' => output.push_str("\\n"),
            '\r' => output.push_str("\\r"),
            '\t' => output.push_str("\\t"),
            c if c.is_control() => output.push_str(&format!("\\x{:x};", c as u32)),
            c => output.push(c),
        }
    }
    output.push('"');
}

fn print_symbol(output: &mut String, text: &str) {
    if datum::identifier(text) && matches!(datum::number(text, 10), Ok(None)) {
        output.push_str(text);
        return;
    }
    output.push('|');
    for character in text.chars() {
        match character {
            '|' | '\\' => {
                output.push('\\');
                output.push(character);
            }
            c if c.is_control() => output.push_str(&format!("\\x{:x};", c as u32)),
            c => output.push(c),
        }
    }
    output.push('|');
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn numeric_text_preserves_sign_radix_and_nonfinite_values() {
        assert_eq!(integer_text(i64::MIN, 16), "-8000000000000000");
        assert_eq!(
            datum::number("#Xff", 10).unwrap(),
            Some(datum::Number::Integer(255))
        );
        assert_eq!(datum::number("λ", 8).unwrap(), None);
        assert_eq!(float_text(-0.0), "-0.0");
        assert_eq!(float_text(f64::INFINITY), "+inf.0");
        assert_eq!(float_text(9.223372036854776e18), "9.223372036854776e+18");
        assert_eq!(float_text(1.25e-18), "1.25e-18");
        assert!(parse_float("+nan.0").unwrap().is_nan());
        assert_eq!(parse_float("3"), None);
        assert_eq!(parse_float("3.5"), Some(3.5));
        assert_eq!(parse_float("+INF.0"), Some(f64::INFINITY));
    }

    #[test]
    fn exact_powers_check_overflow_and_keep_complex_components() {
        assert_eq!(integer_power(-2, 63).unwrap(), i64::MIN);
        assert!(integer_power(2, 63).is_err());
        assert_eq!(complex_integer_power((3, 4), 2).unwrap(), (-7, 24));
        assert_eq!(
            complex_integer_power((0, 1), i64::MAX as u64).unwrap(),
            (0, -1)
        );
        assert!(complex_integer_product((i64::MIN, i64::MIN), (i64::MIN, i64::MIN)).is_err());
    }

    #[test]
    fn substring_search_counts_scalars_without_copying_the_haystack() {
        let text: Vec<_> = "aλ😀λ".chars().collect();
        let find = |pattern: &str, start| {
            find_characters(
                text.len(),
                &pattern.chars().collect::<Vec<_>>(),
                start,
                |i| Ok(text[i]),
            )
            .unwrap()
        };
        assert_eq!(find("λ", 0), Some(1));
        assert_eq!(find("λ", 2), Some(3));
        assert_eq!(find("λ", 4), None);
        assert_eq!(find("", 4), Some(4));
        assert_eq!(find("😀λ", 0), Some(2));
    }

    #[test]
    fn printed_strings_and_characters_keep_scheme_escaping() {
        let mut text = String::new();
        quote_string(&mut text, "λ\n\"\\");
        assert_eq!(text, "\"λ\\n\\\"\\\\\"");
        text.clear();
        print_character(&mut text, '\n', false);
        assert_eq!(text, "#\\newline");
        text.clear();
        print_character(&mut text, '😀', true);
        assert_eq!(text, "😀");
        text.clear();
        print_symbol(&mut text, "x |\\\n");
        assert_eq!(text, "|x \\|\\\\\\xa;|");
    }
}

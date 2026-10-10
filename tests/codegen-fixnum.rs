//! A matched code-generation probe, not the runtime's numeric implementation.
//! Words use 32-bit fixnum tags; i64::MIN reports a type/range failure.

#[unsafe(no_mangle)]
pub extern "C" fn probe_rust_add(a: u32, b: u32) -> i64 {
    if a & b & 1 == 0 {
        return i64::MIN;
    }
    let sum = i64::from((a as i32) >> 1) + i64::from((b as i32) >> 1);
    if (-1_073_741_824..=1_073_741_823).contains(&sum) {
        sum
    } else {
        i64::MIN
    }
}

// ---- Tests ----

unsafe extern "C" {
    fn probe_via_rust(a: u32, b: u32) -> i64;
    fn probe_via_llvm(a: u32, b: u32) -> i64;
}

fn expected(a: u32, b: u32) -> i64 {
    let sum = (i64::from(a as i32) + i64::from(b as i32) - 2) / 2;
    if a % 2 == 1 && b % 2 == 1 && sum >= -(1 << 30) && sum < (1 << 30) {
        sum
    } else {
        i64::MIN
    }
}

fn check(a: u32, b: u32) {
    let a = std::hint::black_box(a);
    let b = std::hint::black_box(b);
    let expected = expected(a, b);
    // The generated callers use the same scalar ABI and never access memory.
    assert_eq!(unsafe { probe_via_rust(a, b) }, expected);
    assert_eq!(unsafe { probe_via_llvm(a, b) }, expected);
}

fn main() {
    let edges = [0, 1, 3, 0x7fff_fffd, 0x7fff_ffff, 0x8000_0001, 0xffff_ffff];
    for a in edges {
        for b in edges {
            check(a, b);
        }
    }
    let mut word = 0x1234_5678_u32;
    for _ in 0..65_536 {
        let next = word.wrapping_mul(1_664_525).wrapping_add(1_013_904_223);
        check(word, next.rotate_left(13));
        word = next;
    }
    println!("checked 65585 input pairs");
}

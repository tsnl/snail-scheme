use r7rs_wasm_reference::{input, report};
use std::hint::black_box;
use std::time::Instant;

// ---- Continuation-passing Takeuchi ----

// The three closure shapes become explicit owned continuation records.
// The trampoline preserves every call and tail transition, without a host stack.
type K = Box<Continuation>;
enum Continuation {
    Done,
    First {
        x: i64,
        y: i64,
        z: i64,
        next: K,
    },
    Second {
        first: i64,
        x: i64,
        y: i64,
        z: i64,
        next: K,
    },
    Third {
        first: i64,
        second: i64,
        next: K,
    },
}
enum Step {
    Call(i64, i64, i64, K),
    Return(i64, K),
}

fn call(x: i64, y: i64, z: i64, next: K) -> Step {
    if y >= x {
        Step::Return(z, next)
    } else {
        Step::Call(x - 1, y, z, Box::new(Continuation::First { x, y, z, next }))
    }
}

// Exhaustive continuation invocation is one atomic machine transition.
fn resume(value: i64, continuation: Continuation) -> Step {
    match continuation {
        Continuation::Done => unreachable!("driver handles final return"),
        Continuation::First { x, y, z, next } => Step::Call(
            y - 1,
            z,
            x,
            Box::new(Continuation::Second {
                first: value,
                x,
                y,
                z,
                next,
            }),
        ),
        Continuation::Second {
            first,
            x,
            y,
            z,
            next,
        } => Step::Call(
            z - 1,
            x,
            y,
            Box::new(Continuation::Third {
                first,
                second: value,
                next,
            }),
        ),
        Continuation::Third {
            first,
            second,
            next,
        } => Step::Call(first, second, value, next),
    }
}

fn run(x: i64, y: i64, z: i64) -> i64 {
    let mut step = Step::Call(x, y, z, Box::new(Continuation::Done));
    loop {
        step = match step {
            Step::Call(x, y, z, continuation) => call(x, y, z, continuation),
            Step::Return(value, continuation) => {
                if matches!(*continuation, Continuation::Done) {
                    return value;
                }
                resume(value, *continuation)
            }
        };
    }
}

// ---- Benchmark driver ----

fn main() -> std::io::Result<()> {
    let values = input()?;
    let (count, x, y, z) = (
        values[0].number(),
        values[1].integer(),
        values[2].integer(),
        values[3].integer(),
    );
    let (start, mut result) = (Instant::now(), 0);
    for _ in 0..count {
        result = black_box(run(black_box(x), black_box(y), black_box(z)));
    }
    assert_eq!(result, values[4].integer());
    report("cpstak", count, start, result);
    Ok(())
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn captures_and_resumes_all_three_operands() {
        assert_eq!(run(6, 4, 2), 3);
        assert_eq!(run(10, 6, 3), 4);
        assert_eq!(run(1, 2, 3), 3);
    }
}

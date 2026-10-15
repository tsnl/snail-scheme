use r7rs_wasm_reference::{input, report};
use std::hint::black_box;
use std::rc::Rc;
use std::time::Instant;

// ---- Captured Fibonacci operands ----

type K = Rc<Continuation>;
enum Continuation {
    Done,
    First { n: i64, next: K },
    Second { first: i64, next: K },
}
enum Step {
    Call(i64, K),
    Return(i64, K),
}

fn capture(current: &K) -> K {
    #[cfg(test)]
    tests::record_capture();
    Rc::clone(current)
}

// Preserve Peano addition: y successor/predecessor transitions are real work.
fn addc(mut x: i64, mut y: i64) -> i64 {
    while y != 0 {
        #[cfg(test)]
        tests::record_peano_step();
        x = black_box(x + 1);
        y -= 1;
    }
    x
}

fn call(n: i64, continuation: K) -> Step {
    #[cfg(test)]
    tests::record_call(n);
    if n == 0 || n == 1 {
        Step::Return(n, continuation)
    } else {
        let current = Rc::new(Continuation::First {
            n,
            next: continuation,
        });
        Step::Call(n - 1, capture(&current))
    }
}

fn resume(value: i64, continuation: K) -> Step {
    match continuation.as_ref() {
        Continuation::Done => unreachable!("driver handles final return"),
        Continuation::First { n, next } => {
            let current = Rc::new(Continuation::Second {
                first: value,
                next: next.clone(),
            });
            Step::Call(n - 2, capture(&current))
        }
        Continuation::Second { first, next } => Step::Return(addc(*first, value), next.clone()),
    }
}

fn run(n: i64) -> i64 {
    let mut step = Step::Call(n, Rc::new(Continuation::Done));
    loop {
        step = match step {
            Step::Call(n, continuation) => call(n, continuation),
            Step::Return(value, continuation) => {
                #[cfg(test)]
                tests::record_invocation();
                if matches!(continuation.as_ref(), Continuation::Done) {
                    return value;
                }
                resume(value, continuation)
            }
        };
    }
}

// ---- Benchmark driver ----

fn main() -> std::io::Result<()> {
    let values = input()?;
    let (count, n) = (values[0].number(), values[1].integer());
    assert!(n >= 0, "fibc input must be nonnegative");
    let (start, mut result) = (Instant::now(), 0);
    for _ in 0..count {
        result = black_box(run(black_box(n)));
    }
    assert_eq!(result, values[2].integer());
    report("fibc", count, start, result);
    Ok(())
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;
    #[derive(Default)]
    struct Trace {
        calls: Vec<i64>,
        captures: usize,
        invocations: usize,
        peano: usize,
    }
    thread_local! { static TRACE: RefCell<Trace> = RefCell::new(Trace::default()); }
    pub(super) fn record_call(n: i64) {
        TRACE.with(|t| t.borrow_mut().calls.push(n));
    }
    pub(super) fn record_capture() {
        TRACE.with(|t| t.borrow_mut().captures += 1);
    }
    pub(super) fn record_invocation() {
        TRACE.with(|t| t.borrow_mut().invocations += 1);
    }
    pub(super) fn record_peano_step() {
        TRACE.with(|t| t.borrow_mut().peano += 1);
    }
    fn direct(n: i64, calls: &mut Vec<i64>) -> i64 {
        calls.push(n);
        if n < 2 {
            n
        } else {
            direct(n - 1, calls) + direct(n - 2, calls)
        }
    }
    #[test]
    fn complete_call_order_and_peano_work() {
        TRACE.with(|t| *t.borrow_mut() = Trace::default());
        assert_eq!(run(10), 55);
        let mut expected = Vec::new();
        direct(10, &mut expected);
        TRACE.with(|t| {
            let t = t.borrow();
            assert_eq!(t.calls, expected);
            assert_eq!(
                (t.calls.len(), t.captures, t.invocations, t.peano),
                (177, 176, 177, 130)
            );
        });
    }
    #[test]
    fn fibonacci_and_peano_addition() {
        assert_eq!((run(0), run(1), run(10)), (0, 1, 55));
        assert_eq!(addc(3, 4), 7);
    }
}

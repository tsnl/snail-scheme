use r7rs_wasm_reference::{input, report};
use std::hint::black_box;
use std::rc::Rc;
use std::time::Instant;

// ---- Captured return continuations ----

// Each capture shares its enclosing continuation through Rc. Invocation
// resumes the captured operand-evaluation point; no host-stack call/cc is used.
type K = Rc<Continuation>;
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

// Every supplied continuation is also the active return context in this
// source's nested traversal. A capture shares that immutable context; it does
// not add a return frame. Invocation replaces the state and releases its old
// context. These handles support this one-shot dynamic extent, not general
// multi-shot Scheme continuations.
fn capture(current: &K) -> K {
    #[cfg(test)]
    tests::record_capture();
    Rc::clone(current)
}

fn call(x: i64, y: i64, z: i64, next: K) -> Step {
    #[cfg(test)]
    tests::record_call(x, y, z);
    if y >= x {
        Step::Return(z, next)
    } else {
        let result = capture(&next);
        let current = Rc::new(Continuation::First {
            x,
            y,
            z,
            next: result,
        });
        Step::Call(x - 1, y, z, capture(&current))
    }
}

// Exhaustive continuation invocation is one atomic machine transition.
fn resume(value: i64, continuation: K) -> Step {
    match continuation.as_ref() {
        Continuation::Done => unreachable!("driver handles final return"),
        Continuation::First { x, y, z, next } => {
            let current = Rc::new(Continuation::Second {
                first: value,
                x: *x,
                y: *y,
                z: *z,
                next: next.clone(),
            });
            Step::Call(*y - 1, *z, *x, capture(&current))
        }
        Continuation::Second {
            first,
            x,
            y,
            z,
            next,
        } => {
            let current = Rc::new(Continuation::Third {
                first: *first,
                second: value,
                next: next.clone(),
            });
            Step::Call(*z - 1, *x, *y, capture(&current))
        }
        Continuation::Third {
            first,
            second,
            next,
        } => Step::Call(*first, *second, value, next.clone()),
    }
}

fn run(x: i64, y: i64, z: i64) -> i64 {
    let identity = Rc::new(Continuation::Done);
    let mut step = Step::Call(x, y, z, capture(&identity));
    loop {
        step = match step {
            Step::Call(x, y, z, continuation) => call(x, y, z, continuation),
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
    report("ctak", count, start, result);
    Ok(())
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    use std::cell::RefCell;
    #[derive(Default)]
    struct Trace {
        calls: Vec<(i64, i64, i64)>,
        captures: usize,
        invocations: usize,
    }
    thread_local! { static TRACE: RefCell<Trace> = RefCell::new(Trace::default()); }
    pub(super) fn record_call(x: i64, y: i64, z: i64) {
        TRACE.with(|t| t.borrow_mut().calls.push((x, y, z)));
    }
    pub(super) fn record_capture() {
        TRACE.with(|t| t.borrow_mut().captures += 1);
    }
    pub(super) fn record_invocation() {
        TRACE.with(|t| t.borrow_mut().invocations += 1);
    }
    #[test]
    fn exact_source_call_and_capture_trace() {
        TRACE.with(|t| *t.borrow_mut() = Trace::default());
        assert_eq!(run(2, 1, 0), 1);
        TRACE.with(|t| {
            let t = t.borrow();
            assert_eq!(
                t.calls,
                vec![(2, 1, 0), (1, 1, 0), (0, 0, 2), (-1, 2, 1), (0, 2, 1)]
            );
            assert_eq!((t.captures, t.invocations), (5, 4));
        });
    }
    #[test]
    fn captures_and_resumes_all_three_operands() {
        assert_eq!(run(6, 4, 2), 3);
        assert_eq!(run(10, 6, 3), 4);
        assert_eq!(run(1, 2, 3), 3);
    }
}

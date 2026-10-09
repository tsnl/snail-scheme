//! Scheme values are private to Rust. Generated code only handles a `Vm` pointer.

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Value {
    Nil,
    Bool(bool),
    Integer(i64),
    Float(f64),
    Char(char),
    Heap(usize),
    Eof,
    Unspecified,
    Uninitialized,
}

impl Value {
    pub fn is_true(self) -> bool {
        self != Self::Bool(false)
    }

    pub fn integer(self) -> Result<i64, String> {
        match self {
            Self::Integer(n) => Ok(n),
            _ => Err("expected an exact integer".into()),
        }
    }

    pub fn index(self) -> Result<usize, String> {
        usize::try_from(self.integer()?).map_err(|_| "expected a nonnegative index".into())
    }
}

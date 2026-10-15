use std::fmt::{self, Display};

// ---- Owned integer lists ----

// Every Cons is a separately owned cell. Taking a suffix borrows existing
// cells; constructing a result allocates fresh cells, as in the source lists.
#[derive(Debug, PartialEq, Eq)]
pub enum List {
    Nil,
    Cons(i64, Box<List>),
}

impl List {
    pub fn cons(value: i64, rest: Self) -> Self {
        Self::Cons(value, Box::new(rest))
    }
    pub fn from_values(values: &[i64]) -> Self {
        values
            .iter()
            .rev()
            .fold(Self::Nil, |rest, &value| Self::cons(value, rest))
    }
    pub fn len(&self) -> usize {
        let (mut rest, mut length) = (self, 0);
        while let Self::Cons(_, next) = rest {
            length += 1;
            rest = next;
        }
        length
    }
    pub fn is_empty(&self) -> bool {
        matches!(self, Self::Nil)
    }
    pub fn tail(&self) -> &Self {
        match self {
            Self::Cons(_, rest) => rest,
            Self::Nil => panic!("empty list has no tail"),
        }
    }
    pub fn values(&self) -> Vec<i64> {
        let (mut rest, mut values) = (self, Vec::new());
        while let Self::Cons(value, next) = rest {
            values.push(*value);
            rest = next;
        }
        values
    }
}

impl Display for List {
    fn fmt(&self, output: &mut fmt::Formatter<'_>) -> fmt::Result {
        let mut rest = self;
        write!(output, "(")?;
        while let Self::Cons(value, next) = rest {
            write!(output, "{value}")?;
            if !next.is_empty() {
                write!(output, " ")?;
            }
            rest = next;
        }
        write!(output, ")")
    }
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn borrowed_suffix_keeps_original_cells() {
        let list = List::from_values(&[3, 2, 1]);
        assert_eq!(list.tail().values(), vec![2, 1]);
        assert_eq!(list.values(), vec![3, 2, 1]);
    }
}

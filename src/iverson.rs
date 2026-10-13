//! Unboxed numeric tensors for `(snail-scheme iverson-ghost)`.
//! Dtype selects concrete storage and monomorphized whole-operation kernels.
//! Object tensors stay in Scheme GC storage so object cycles remain visible.

use crate::abi::{Kind, Root};
use std::{cell::RefCell, collections::BTreeMap, rc::Rc};

// ---- Dtypes and immutable storage ----

pub(crate) const ARRAY_KIND: u32 = 2;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Dtype {
    F64,
    F32,
    I32,
}

impl Dtype {
    fn from_code(code: i64) -> Result<Self, String> {
        match code {
            0 => Ok(Self::F64),
            1 => Ok(Self::F32),
            2 => Ok(Self::I32),
            _ => Err("unsupported numeric array dtype".into()),
        }
    }
    fn code(self) -> i64 {
        match self {
            Self::F64 => 0,
            Self::F32 => 1,
            Self::I32 => 2,
        }
    }
}

#[derive(Clone, Debug)]
enum Data {
    F64(Rc<[f64]>),
    F32(Rc<[f32]>),
    I32(Rc<[i32]>),
}

fn checked_i32(value: f64) -> Result<i32, String> {
    if value.is_finite()
        && value.fract() == 0.0
        && (i32::MIN as f64..=i32::MAX as f64).contains(&value)
    {
        // Bounds and integrality above make Wasm's trapping conversion safe.
        // Avoid Rust's saturating cast, which needs an extra Wasm proposal.
        Ok(unsafe { value.to_int_unchecked::<i32>() })
    } else {
        Err("i32 conversion requires an integer in range".into())
    }
}

impl Data {
    fn dtype(&self) -> Dtype {
        match self {
            Self::F64(_) => Dtype::F64,
            Self::F32(_) => Dtype::F32,
            Self::I32(_) => Dtype::I32,
        }
    }
    fn len(&self) -> usize {
        match self {
            Self::F64(x) => x.len(),
            Self::F32(x) => x.len(),
            Self::I32(x) => x.len(),
        }
    }
    fn number(&self, i: usize) -> f64 {
        match self {
            Self::F64(x) => x[i],
            Self::F32(x) => x[i] as f64,
            Self::I32(x) => x[i] as f64,
        }
    }
    fn root(&self, i: usize) -> Root {
        match self {
            Self::I32(x) => Root::integer(x[i] as i64),
            _ => Root::real(self.number(i)),
        }
    }
    fn from_numbers(dtype: Dtype, values: Vec<f64>) -> Result<Self, String> {
        Ok(match dtype {
            Dtype::F64 => Self::F64(values.into()),
            Dtype::F32 => Self::F32(
                values
                    .into_iter()
                    .map(|x| x as f32)
                    .collect::<Vec<_>>()
                    .into(),
            ),
            Dtype::I32 => Self::I32(
                values
                    .into_iter()
                    .map(checked_i32)
                    .collect::<Result<Vec<_>, _>>()?
                    .into(),
            ),
        })
    }
    fn cast(&self, dtype: Dtype) -> Result<Self, String> {
        if dtype == self.dtype() {
            return Ok(self.clone());
        }
        Self::from_numbers(dtype, (0..self.len()).map(|i| self.number(i)).collect())
    }
}

#[derive(Clone, Debug)]
struct Array {
    shape: Vec<usize>,
    data: Data,
}

fn element_count(shape: &[usize]) -> Result<usize, String> {
    if shape.contains(&0) {
        return Ok(0);
    }
    shape.iter().try_fold(1usize, |n, &d| {
        n.checked_mul(d)
            .ok_or_else(|| "array shape overflow".into())
    })
}

fn zeros<T: Copy + Default>(count: usize) -> Result<Vec<T>, String> {
    let mut data = Vec::new();
    data.try_reserve_exact(count)
        .map_err(|_| "array allocation failed")?;
    data.resize(count, T::default());
    Ok(data)
}

impl Array {
    fn new(shape: Vec<usize>, data: Data) -> Result<Self, String> {
        if element_count(&shape)? != data.len() {
            return Err("array shape does not match data length".into());
        }
        Ok(Self { shape, data })
    }
    fn reshape(&self, shape: Vec<usize>) -> Result<Self, String> {
        if element_count(&shape)? != self.data.len() {
            return Err("reshape must preserve element count".into());
        }
        Ok(Self {
            shape,
            data: self.data.clone(),
        })
    }
    fn cast(&self, dtype: Dtype) -> Result<Self, String> {
        Self::new(self.shape.clone(), self.data.cast(dtype)?)
    }
}

// ---- Numeric ownership and Scheme GC boundaries ----

struct Arrays {
    next: u32,
    live: BTreeMap<u32, Array>,
}

// The registry owns numeric memory, never ABI roots or Scheme wrappers.
// Cleanup holds only (kind, id); IDs are fresh, so delayed notices are safe.
// Reshape shares Rc storage; output buffers are immutable after publication.
thread_local! {
    static ARRAYS: RefCell<Arrays> = RefCell::new(Arrays { next: 0, live: BTreeMap::new() });
}

fn publish(array: Array) -> Result<Root, String> {
    let id = ARRAYS.with_borrow_mut(|arrays| {
        let id = arrays.next;
        arrays.next = id.checked_add(1).ok_or("array resource IDs exhausted")?;
        arrays.live.insert(id, array);
        Ok::<_, String>(id)
    })?;
    // End the registry borrow before allocating the owning GC wrapper.
    Ok(unsafe { Root::from_raw_extension(ARRAY_KIND, id) })
}

// Array cleanup belongs to this library, independently of platform port handlers.
#[unsafe(export_name = "snail:drop-array")]
pub extern "C" fn drop_array(id: u32) {
    ARRAYS.with_borrow_mut(|arrays| arrays.live.remove(&id));
}

fn concrete(value: &Root) -> Result<Array, String> {
    let (kind, id) = value.extension_parts()?;
    if kind != ARRAY_KIND {
        return Err("expected an iverson-ghost array".into());
    }
    ARRAYS.with_borrow(|arrays| {
        arrays
            .live
            .get(&id)
            .cloned()
            .ok_or_else(|| "invalid array resource".into())
    })
}

fn operand(value: &Root, dtype: Option<Dtype>) -> Result<Array, String> {
    if matches!(value.kind(), Kind::Integer | Kind::Real | Kind::Complex) {
        Array::new(
            vec![],
            Data::from_numbers(dtype.unwrap_or(Dtype::F64), vec![value.as_real()?])?,
        )
    } else {
        concrete(value)
    }
}

fn operands(a: &Root, b: &Root) -> Result<(Array, Array), String> {
    let dtype = if a.kind() == Kind::Extension {
        concrete(a)?.data.dtype()
    } else if b.kind() == Kind::Extension {
        concrete(b)?.data.dtype()
    } else {
        Dtype::F64
    };
    Ok((operand(a, Some(dtype))?, operand(b, Some(dtype))?))
}

fn dimensions(value: &Root) -> Result<Vec<usize>, String> {
    (0..value.len()?)
        .map(|i| {
            usize::try_from(value.at(i)?.as_integer()?)
                .map_err(|_| "expected a nonnegative array dimension".into())
        })
        .collect()
}

fn numeric_data(value: &Root, dtype: Dtype) -> Result<Data, String> {
    Data::from_numbers(
        dtype,
        (0..value.len()?)
            .map(|i| value.at(i)?.as_real())
            .collect::<Result<_, _>>()?,
    )
}

// ---- Broadcasting and row-major indexing ----

fn trailing_dimension(shape: &[usize], depth: usize) -> usize {
    shape
        .len()
        .checked_sub(depth + 1)
        .map(|i| shape[i])
        .unwrap_or(1)
}

fn broadcast_shape(a: &[usize], b: &[usize]) -> Result<Vec<usize>, String> {
    let mut shape = Vec::new();
    for depth in 0..a.len().max(b.len()) {
        let (x, y) = (trailing_dimension(a, depth), trailing_dimension(b, depth));
        shape.push(match (x, y) {
            _ if x == y || y == 1 => x,
            (1, _) => y,
            _ => return Err("incompatible broadcast shapes".into()),
        });
    }
    shape.reverse();
    Ok(shape)
}

fn row_strides(shape: &[usize]) -> Result<Vec<usize>, String> {
    let (mut stride, mut result) = (1usize, Vec::new());
    for &dimension in shape.iter().rev() {
        result.push(stride);
        stride = stride
            .checked_mul(dimension)
            .ok_or("array stride overflow")?;
    }
    result.reverse();
    Ok(result)
}

fn broadcast_strides(shape: &[usize], rank: usize) -> Result<Vec<usize>, String> {
    let mut result = vec![0; rank - shape.len()];
    for (&dimension, stride) in shape.iter().zip(row_strides(shape)?) {
        result.push(if dimension == 1 { 0 } else { stride });
    }
    Ok(result)
}

// Only nonempty kernels call this, so every divisor is positive.
fn offset(mut index: usize, shape: &[usize], strides: &[usize]) -> usize {
    let mut address = 0;
    for (&dimension, &stride) in shape.iter().zip(strides).rev() {
        address += (index % dimension) * stride;
        index /= dimension;
    }
    address
}

// ---- Arithmetic for each physical element type ----

#[derive(Clone, Copy, PartialEq, Eq)]
enum Arithmetic {
    Add,
    Sub,
    Mul,
    Div,
}

impl Arithmetic {
    fn from_code(code: i64) -> Result<Self, String> {
        match code {
            0 => Ok(Self::Add),
            1 => Ok(Self::Sub),
            2 => Ok(Self::Mul),
            3 => Ok(Self::Div),
            _ => Err("unknown array arithmetic operation".into()),
        }
    }
}

// Shape/index loops are instantiated for three physical types, not Scheme callbacks.
// i32 arithmetic wraps modulo 2^32; true division and mean first widen to f64.
trait Element: Copy + Default {
    fn arithmetic(self, op: Arithmetic, b: Self) -> Self;
    fn from_index(index: usize) -> Self;
}
impl Element for f64 {
    fn arithmetic(self, op: Arithmetic, b: Self) -> Self {
        match op {
            Arithmetic::Add => self + b,
            Arithmetic::Sub => self - b,
            Arithmetic::Mul => self * b,
            Arithmetic::Div => self / b,
        }
    }
    fn from_index(index: usize) -> Self {
        index as Self
    }
}
impl Element for f32 {
    fn arithmetic(self, op: Arithmetic, b: Self) -> Self {
        match op {
            Arithmetic::Add => self + b,
            Arithmetic::Sub => self - b,
            Arithmetic::Mul => self * b,
            Arithmetic::Div => self / b,
        }
    }
    fn from_index(index: usize) -> Self {
        index as Self
    }
}
impl Element for i32 {
    fn arithmetic(self, op: Arithmetic, b: Self) -> Self {
        match op {
            Arithmetic::Add => self.wrapping_add(b),
            Arithmetic::Sub => self.wrapping_sub(b),
            Arithmetic::Mul => self.wrapping_mul(b),
            Arithmetic::Div => unreachable!("i32 division widens"),
        }
    }
    fn from_index(index: usize) -> Self {
        index as Self
    }
}

fn iota_values<T: Element>(count: usize) -> Result<Vec<T>, String> {
    let mut data = zeros(count)?;
    for (i, value) in data.iter_mut().enumerate() {
        *value = T::from_index(i);
    }
    Ok(data)
}

fn iota(dtype: Dtype, count: usize) -> Result<Array, String> {
    if dtype == Dtype::I32 && count > i32::MAX as usize + 1 {
        return Err("i32 iota length out of range".into());
    }
    let data = match dtype {
        Dtype::F64 => Data::F64(iota_values(count)?.into()),
        Dtype::F32 => Data::F32(iota_values(count)?.into()),
        Dtype::I32 => Data::I32(iota_values(count)?.into()),
    };
    Array::new(vec![count], data)
}

fn dense_binary<T: Element>(op: Arithmetic, a: &[T], b: &[T], data: &mut [T]) {
    for (i, value) in data.iter_mut().enumerate() {
        *value =
            a[if a.len() == 1 { 0 } else { i }].arithmetic(op, b[if b.len() == 1 { 0 } else { i }]);
    }
}

fn binary_values<T: Element>(
    op: Arithmetic,
    a: &[T],
    b: &[T],
    shape: &[usize],
    sa: &[usize],
    sb: &[usize],
) -> Result<Vec<T>, String> {
    let mut data = zeros(element_count(shape)?)?;
    if data.is_empty() {
        return Ok(data);
    }
    if [a.len(), b.len()]
        .iter()
        .all(|&n| n == 1 || n == data.len())
    {
        dense_binary(op, a, b, &mut data);
    } else {
        for (i, value) in data.iter_mut().enumerate() {
            *value = a[offset(i, shape, sa)].arithmetic(op, b[offset(i, shape, sb)]);
        }
    }
    Ok(data)
}

fn same_dtype(a: &Array, b: &Array) -> Result<(), String> {
    if a.data.dtype() == b.data.dtype() {
        Ok(())
    } else {
        Err("array dtype mismatch; use astype explicitly".into())
    }
}

fn binary(op: Arithmetic, a: &Array, b: &Array) -> Result<Array, String> {
    same_dtype(a, b)?;
    if op == Arithmetic::Div && a.data.dtype() == Dtype::I32 {
        return binary(op, &a.cast(Dtype::F64)?, &b.cast(Dtype::F64)?);
    }
    let shape = broadcast_shape(&a.shape, &b.shape)?;
    if element_count(&shape)? == 0 {
        return Array::new(shape, Data::from_numbers(a.data.dtype(), vec![])?);
    }
    let (sa, sb) = (
        broadcast_strides(&a.shape, shape.len())?,
        broadcast_strides(&b.shape, shape.len())?,
    );
    let data = match (&a.data, &b.data) {
        (Data::F64(x), Data::F64(y)) => {
            Data::F64(binary_values(op, x, y, &shape, &sa, &sb)?.into())
        }
        (Data::F32(x), Data::F32(y)) => {
            Data::F32(binary_values(op, x, y, &shape, &sa, &sb)?.into())
        }
        (Data::I32(x), Data::I32(y)) => {
            Data::I32(binary_values(op, x, y, &shape, &sa, &sb)?.into())
        }
        _ => unreachable!("dtype checked"),
    };
    Array::new(shape, data)
}

// ---- Structural operations and reductions ----

fn transpose_values<T: Element>(
    source: &[T],
    shape: &[usize],
    strides: &[usize],
) -> Result<Vec<T>, String> {
    let mut data = zeros(source.len())?;
    for (i, value) in data.iter_mut().enumerate() {
        *value = source[offset(i, shape, strides)];
    }
    Ok(data)
}

fn transpose(a: &Array) -> Result<Array, String> {
    let shape: Vec<_> = a.shape.iter().rev().copied().collect();
    if shape.len() < 2 || a.data.len() == 0 {
        return a.reshape(shape);
    }
    let strides: Vec<_> = row_strides(&a.shape)?.into_iter().rev().collect();
    let data = match &a.data {
        Data::F64(x) => Data::F64(transpose_values(x, &shape, &strides)?.into()),
        Data::F32(x) => Data::F32(transpose_values(x, &shape, &strides)?.into()),
        Data::I32(x) => Data::I32(transpose_values(x, &shape, &strides)?.into()),
    };
    Array::new(shape, data)
}

fn reduction_count(a: &Array, axis: Option<usize>) -> Result<usize, String> {
    match axis {
        None => Ok(a.data.len()),
        Some(axis) => a
            .shape
            .get(axis)
            .copied()
            .ok_or_else(|| "array axis out of range".into()),
    }
}

fn sum_values<T: Element>(
    source: &[T],
    shape: &[usize],
    axis: Option<usize>,
) -> Result<Vec<T>, String> {
    let Some(axis) = axis else {
        return Ok(vec![
            source
                .iter()
                .fold(T::default(), |s, &x| s.arithmetic(Arithmetic::Add, x)),
        ]);
    };
    let mut output = shape.to_vec();
    let width = output.remove(axis);
    let mut data = zeros(element_count(&output)?)?;
    if data.is_empty() || width == 0 {
        return Ok(data);
    }
    let inner = element_count(&shape[axis + 1..])?;
    for (i, value) in data.iter_mut().enumerate() {
        let base = i / inner * width * inner + i % inner;
        *value = (0..width).fold(T::default(), |s, k| {
            s.arithmetic(Arithmetic::Add, source[base + k * inner])
        });
    }
    Ok(data)
}

fn reduce(a: &Array, axis: Option<usize>, mean: bool) -> Result<Array, String> {
    let count = reduction_count(a, axis)?;
    if mean && count == 0 {
        return Err("mean of an empty reduction".into());
    }
    if mean && a.data.dtype() == Dtype::I32 {
        return reduce(&a.cast(Dtype::F64)?, axis, true);
    }
    let mut shape = if axis.is_some() {
        a.shape.clone()
    } else {
        vec![]
    };
    if let Some(axis) = axis {
        shape.remove(axis);
    }
    let data = match &a.data {
        Data::F64(x) => Data::F64(sum_values(x, &a.shape, axis)?.into()),
        Data::F32(x) => Data::F32(sum_values(x, &a.shape, axis)?.into()),
        Data::I32(x) => Data::I32(sum_values(x, &a.shape, axis)?.into()),
    };
    let sum = Array::new(shape, data)?;
    if !mean {
        return Ok(sum);
    }
    let divisor = Array::new(
        vec![],
        Data::from_numbers(sum.data.dtype(), vec![count as f64])?,
    )?;
    binary(Arithmetic::Div, &sum, &divisor)
}

fn matrix_values<T: Element>(
    a: &[T],
    b: &[T],
    rows: usize,
    width: usize,
    cols: usize,
) -> Result<Vec<T>, String> {
    let mut data: Vec<T> = zeros(element_count(&[rows, cols])?)?;
    for row in 0..rows {
        for k in 0..width {
            for col in 0..cols {
                let i = row * cols + col;
                data[i] = data[i].arithmetic(
                    Arithmetic::Add,
                    a[row * width + k].arithmetic(Arithmetic::Mul, b[k * cols + col]),
                );
            }
        }
    }
    Ok(data)
}

fn matmul(a: &Array, b: &Array) -> Result<Array, String> {
    same_dtype(a, b)?;
    if a.shape.len() != 2 || b.shape.len() != 2 || a.shape[1] != b.shape[0] {
        return Err("matmul requires compatible rank-two arrays".into());
    }
    let (m, k, n) = (a.shape[0], a.shape[1], b.shape[1]);
    let data = match (&a.data, &b.data) {
        (Data::F64(x), Data::F64(y)) => Data::F64(matrix_values(x, y, m, k, n)?.into()),
        (Data::F32(x), Data::F32(y)) => Data::F32(matrix_values(x, y, m, k, n)?.into()),
        (Data::I32(x), Data::I32(y)) => Data::I32(matrix_values(x, y, m, k, n)?.into()),
        _ => unreachable!("dtype checked"),
    };
    Array::new(vec![m, n], data)
}

// ---- Gather and functional scatter ----

fn index_array(value: &Root) -> Result<Array, String> {
    if value.kind() != Kind::Extension {
        return Err("indices must be an i32 array".into());
    }
    let array = concrete(value)?;
    if array.data.dtype() != Dtype::I32 {
        return Err("indices must be an i32 array".into());
    }
    Ok(array)
}

fn indices(index: &Array, length: usize) -> Result<&[i32], String> {
    let Data::I32(values) = &index.data else {
        return Err("indices must be an i32 array".into());
    };
    if values.iter().any(|&i| i < 0 || i as usize >= length) {
        return Err("gather/scatter index out of range".into());
    }
    Ok(values)
}

fn gather_values<T: Copy>(source: &[T], indices: &[i32]) -> Vec<T> {
    indices.iter().map(|&i| source[i as usize]).collect()
}

fn gather(source: &Array, index: &Array) -> Result<Array, String> {
    let ix = indices(index, source.data.len())?;
    let data = match &source.data {
        Data::F64(x) => Data::F64(gather_values(x, ix).into()),
        Data::F32(x) => Data::F32(gather_values(x, ix).into()),
        Data::I32(x) => Data::I32(gather_values(x, ix).into()),
    };
    Array::new(index.shape.clone(), data)
}

fn scatter_values<T: Element>(base: &[T], indices: &[i32], updates: &[T], add: bool) -> Vec<T> {
    let mut data = base.to_vec();
    for (k, &index) in indices.iter().enumerate() {
        let value = updates[if updates.len() == 1 { 0 } else { k }];
        data[index as usize] = if add {
            data[index as usize].arithmetic(Arithmetic::Add, value)
        } else {
            value
        };
    }
    data
}

fn scatter(base: &Array, index: &Array, updates: &Array, add: bool) -> Result<Array, String> {
    same_dtype(base, updates)?;
    if updates.shape != index.shape && !updates.shape.is_empty() {
        return Err("scatter updates must match index shape or be scalar".into());
    }
    let ix = indices(index, base.data.len())?;
    let data = match (&base.data, &updates.data) {
        (Data::F64(x), Data::F64(y)) => Data::F64(scatter_values(x, ix, y, add).into()),
        (Data::F32(x), Data::F32(y)) => Data::F32(scatter_values(x, ix, y, add).into()),
        (Data::I32(x), Data::I32(y)) => Data::I32(scatter_values(x, ix, y, add).into()),
        _ => unreachable!("dtype checked"),
    };
    Array::new(base.shape.clone(), data)
}

// ---- Compiler primitives through owned ABI roots ----

#[unsafe(export_name = "snail:%iverson-array")]
pub extern "C" fn array(raw: u32) -> u32 {
    let args = crate::arguments(raw, "%iverson-array", 3, 3);
    crate::finish((|| {
        let dtype = Dtype::from_code(args.get(0)?.as_integer()?)?;
        publish(Array::new(
            dimensions(&args.get(1)?)?,
            numeric_data(&args.get(2)?, dtype)?,
        )?)
    })())
}

#[unsafe(export_name = "snail:%iverson-array?")]
pub extern "C" fn is_array(raw: u32) -> u32 {
    let args = crate::arguments(raw, "%iverson-array?", 1, 1);
    crate::finish((|| {
        let value = args.get(0)?;
        Ok(Root::boolean(
            value.kind() == Kind::Extension && value.extension_parts()?.0 == ARRAY_KIND,
        ))
    })())
}

#[unsafe(export_name = "snail:%iverson-dtype")]
pub extern "C" fn dtype(raw: u32) -> u32 {
    let args = crate::arguments(raw, "%iverson-dtype", 1, 1);
    crate::finish((|| {
        Ok(Root::integer(
            operand(&args.get(0)?, None)?.data.dtype().code(),
        ))
    })())
}

#[unsafe(export_name = "snail:%iverson-shape")]
pub extern "C" fn shape(raw: u32) -> u32 {
    let args = crate::arguments(raw, "%iverson-shape", 1, 1);
    crate::finish((|| {
        let shape = operand(&args.get(0)?, None)?.shape;
        Ok(Root::vector(
            &shape
                .iter()
                .map(|&d| Root::integer(d as i64))
                .collect::<Vec<_>>(),
        ))
    })())
}

#[unsafe(export_name = "snail:%iverson-data")]
pub extern "C" fn data(raw: u32) -> u32 {
    let args = crate::arguments(raw, "%iverson-data", 1, 1);
    crate::finish((|| {
        let array = operand(&args.get(0)?, None)?;
        Ok(Root::vector(
            &(0..array.data.len())
                .map(|i| array.data.root(i))
                .collect::<Vec<_>>(),
        ))
    })())
}

#[unsafe(export_name = "snail:%iverson-ref")]
pub extern "C" fn at(raw: u32) -> u32 {
    let args = crate::arguments(raw, "%iverson-ref", 2, 2);
    crate::finish((|| {
        let array = operand(&args.get(0)?, None)?;
        let i =
            usize::try_from(args.get(1)?.as_integer()?).map_err(|_| "array index out of range")?;
        if i >= array.data.len() {
            return Err("array index out of range".into());
        }
        Ok(array.data.root(i))
    })())
}

#[unsafe(export_name = "snail:%iverson-iota")]
pub extern "C" fn sequence(raw: u32) -> u32 {
    let args = crate::arguments(raw, "%iverson-iota", 2, 2);
    crate::finish((|| {
        let dtype = Dtype::from_code(args.get(0)?.as_integer()?)?;
        let count =
            usize::try_from(args.get(1)?.as_integer()?).map_err(|_| "negative iota length")?;
        publish(iota(dtype, count)?)
    })())
}

#[unsafe(export_name = "snail:%iverson-reshape")]
pub extern "C" fn reshape(raw: u32) -> u32 {
    let args = crate::arguments(raw, "%iverson-reshape", 2, 2);
    crate::finish((|| {
        publish(operand(&args.get(1)?, None)?.reshape(dimensions(&args.get(0)?)?)?)
    })())
}

#[unsafe(export_name = "snail:%iverson-cast")]
pub extern "C" fn cast(raw: u32) -> u32 {
    let args = crate::arguments(raw, "%iverson-cast", 2, 2);
    crate::finish((|| {
        publish(operand(&args.get(1)?, None)?.cast(Dtype::from_code(args.get(0)?.as_integer()?)?)?)
    })())
}

#[unsafe(export_name = "snail:%iverson-transpose")]
pub extern "C" fn reverse_axes(raw: u32) -> u32 {
    let args = crate::arguments(raw, "%iverson-transpose", 1, 1);
    crate::finish((|| publish(transpose(&operand(&args.get(0)?, None)?)?))())
}

#[unsafe(export_name = "snail:%iverson-binary")]
pub extern "C" fn arithmetic(raw: u32) -> u32 {
    let args = crate::arguments(raw, "%iverson-binary", 3, 3);
    crate::finish((|| {
        let op = Arithmetic::from_code(args.get(0)?.as_integer()?)?;
        let (a, b) = operands(&args.get(1)?, &args.get(2)?)?;
        publish(binary(op, &a, &b)?)
    })())
}

#[unsafe(export_name = "snail:%iverson-reduce")]
pub extern "C" fn reduction(raw: u32) -> u32 {
    let args = crate::arguments(raw, "%iverson-reduce", 3, 3);
    crate::finish((|| {
        let code = args.get(0)?.as_integer()?;
        if !(0..=1).contains(&code) {
            return Err("unknown array reduction".into());
        }
        let axis = args.get(2)?.as_integer()?;
        let axis = if axis == -1 {
            None
        } else {
            Some(usize::try_from(axis).map_err(|_| "array axis out of range")?)
        };
        publish(reduce(&operand(&args.get(1)?, None)?, axis, code == 1)?)
    })())
}

#[unsafe(export_name = "snail:%iverson-matmul")]
pub extern "C" fn matrix_product(raw: u32) -> u32 {
    let args = crate::arguments(raw, "%iverson-matmul", 2, 2);
    crate::finish((|| {
        publish(matmul(
            &concrete(&args.get(0)?)?,
            &concrete(&args.get(1)?)?,
        )?)
    })())
}

#[unsafe(export_name = "snail:%iverson-gather")]
pub extern "C" fn indexed_gather(raw: u32) -> u32 {
    let args = crate::arguments(raw, "%iverson-gather", 2, 2);
    crate::finish((|| {
        publish(gather(
            &operand(&args.get(0)?, None)?,
            &index_array(&args.get(1)?)?,
        )?)
    })())
}

#[unsafe(export_name = "snail:%iverson-scatter")]
pub extern "C" fn indexed_scatter(raw: u32) -> u32 {
    let args = crate::arguments(raw, "%iverson-scatter", 4, 4);
    crate::finish((|| {
        let base = operand(&args.get(1)?, None)?;
        let updates = args.get(3)?;
        if !matches!(
            updates.kind(),
            Kind::Integer | Kind::Real | Kind::Complex | Kind::Extension
        ) {
            return Err("scatter update dtype mismatch; use astype explicitly".into());
        }
        let updates = operand(&updates, Some(base.data.dtype()))?;
        let code = args.get(0)?.as_integer()?;
        if !(0..=1).contains(&code) {
            return Err("unknown scatter operation".into());
        }
        publish(scatter(
            &base,
            &index_array(&args.get(2)?)?,
            &updates,
            code == 1,
        )?)
    })())
}

// ---- Tests ----

#[cfg(test)]
mod tests {
    use super::*;
    fn array(dtype: Dtype, shape: &[usize], values: &[f64]) -> Array {
        Array::new(
            shape.to_vec(),
            Data::from_numbers(dtype, values.to_vec()).unwrap(),
        )
        .unwrap()
    }
    fn numbers(a: &Array) -> Vec<f64> {
        (0..a.data.len()).map(|i| a.data.number(i)).collect()
    }

    #[test]
    fn storage_width_and_ownership() {
        for dtype in [Dtype::F64, Dtype::F32, Dtype::I32] {
            let a = iota(dtype, 6).unwrap();
            let b = a.reshape(vec![2, 3]).unwrap();
            match (&a.data, &b.data) {
                (Data::F64(x), Data::F64(y)) => assert!(Rc::ptr_eq(x, y)),
                (Data::F32(x), Data::F32(y)) => assert!(Rc::ptr_eq(x, y)),
                (Data::I32(x), Data::I32(y)) => assert!(Rc::ptr_eq(x, y)),
                _ => unreachable!(),
            }
            assert!(a.reshape(vec![7]).is_err());
        }
        assert_eq!(
            numbers(&array(Dtype::F32, &[1], &[16_777_217.])),
            [16_777_216.]
        );
        assert!(Data::from_numbers(Dtype::I32, vec![1.5]).is_err());
        assert!(Data::from_numbers(Dtype::I32, vec![f64::NAN]).is_err());
        assert_eq!(element_count(&[0, usize::MAX, usize::MAX]).unwrap(), 0);
        assert!(element_count(&[usize::MAX, 2]).is_err());
    }

    #[test]
    fn typed_arithmetic_broadcasting_and_tails() {
        for dtype in [Dtype::F64, Dtype::F32, Dtype::I32] {
            let a = array(dtype, &[2, 1], &[1., 2.]);
            let b = array(dtype, &[3], &[10., 20., 30.]);
            assert_eq!(
                numbers(&binary(Arithmetic::Add, &a, &b).unwrap()),
                [11., 21., 31., 12., 22., 32.]
            );
            for n in 0..=5 {
                assert_eq!(
                    numbers(
                        &binary(
                            Arithmetic::Mul,
                            &iota(dtype, n).unwrap(),
                            &array(dtype, &[], &[2.])
                        )
                        .unwrap()
                    ),
                    (0..n).map(|i| i as f64 * 2.).collect::<Vec<_>>()
                );
            }
        }
        let a = array(Dtype::I32, &[1], &[i32::MAX as f64]);
        assert_eq!(
            numbers(&binary(Arithmetic::Add, &a, &array(Dtype::I32, &[], &[1.])).unwrap()),
            [i32::MIN as f64]
        );
        assert!(binary(Arithmetic::Add, &a, &a.cast(Dtype::F64).unwrap()).is_err());
        assert_eq!(broadcast_shape(&[0, 3], &[1, 3]).unwrap(), [0, 3]);
        assert!(broadcast_shape(&[0], &[2]).is_err());
    }

    #[test]
    fn reductions_and_matrix_product() {
        for dtype in [Dtype::F64, Dtype::F32, Dtype::I32] {
            let a = array(dtype, &[2, 3], &[1., 2., 3., 4., 5., 6.]);
            let b = array(dtype, &[3, 3], &[1., 2., 3., 4., 5., 6., 7., 8., 9.]);
            assert_eq!(numbers(&transpose(&a).unwrap()), [1., 4., 2., 5., 3., 6.]);
            assert_eq!(
                numbers(&matmul(&a, &b).unwrap()),
                [30., 36., 42., 66., 81., 96.]
            );
            assert_eq!(numbers(&reduce(&a, Some(0), false).unwrap()), [5., 7., 9.]);
            assert_eq!(numbers(&reduce(&a, Some(1), true).unwrap()), [2., 5.]);
            let empty = array(dtype, &[2, 0, 3], &[]);
            assert_eq!(numbers(&reduce(&empty, Some(1), false).unwrap()), [0.; 6]);
            assert!(reduce(&empty, Some(1), true).is_err());
            assert_eq!(reduce(&empty, Some(2), true).unwrap().data.len(), 0);
            assert_eq!(
                numbers(&matmul(&array(dtype, &[2, 0], &[]), &array(dtype, &[0, 3], &[])).unwrap()),
                [0.; 6]
            );
        }
    }

    #[test]
    fn gather_and_duplicate_scatter_indices() {
        let ix = array(Dtype::I32, &[3], &[2., 0., 2.]);
        for dtype in [Dtype::F64, Dtype::F32, Dtype::I32] {
            let a = array(dtype, &[3], &[10., 20., 30.]);
            let updates = array(dtype, &[3], &[1., 2., 3.]);
            assert_eq!(numbers(&gather(&a, &ix).unwrap()), [30., 10., 30.]);
            assert_eq!(
                numbers(&scatter(&a, &ix, &updates, false).unwrap()),
                [2., 20., 3.]
            );
            assert_eq!(
                numbers(&scatter(&a, &ix, &updates, true).unwrap()),
                [12., 20., 34.]
            );
            assert_eq!(numbers(&a), [10., 20., 30.]);
            assert!(gather(&a, &array(Dtype::I32, &[1], &[-1.])).is_err());
            assert!(gather(&a, &array(Dtype::I32, &[1], &[3.])).is_err());
            assert!(gather(&a, &ix.cast(Dtype::F64).unwrap()).is_err());
        }
    }
}

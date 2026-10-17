// These are transport boundary cases, not benchmark measurements.
export const scalars = [
  ['i64-min', 'i64', -(1n << 63n)], ['i64-max', 'i64', (1n << 63n) - 1n],
  ['f32-zero', 'f32', -0], ['f32-subnormal', 'f32', 2 ** -149],
  ['f32-max', 'f32', (2 - 2 ** -23) * 2 ** 127],
  ['f64-roundtrip', 'f64', 1.0000000000000002], ['f64-max', 'f64', Number.MAX_VALUE],
  ['f64-subnormal', 'f64', Number.MIN_VALUE], ['f64-infinity', 'f64', Infinity],
  ['f64-nan', 'f64', NaN], ['bool', 'bool', true], ['char', 'char', '😀']
];

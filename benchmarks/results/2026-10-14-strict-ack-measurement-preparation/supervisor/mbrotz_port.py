"""The original complex Mandelbrot loop over a closed pair of F64 components."""

import math
import struct

from data_ports import replace


# ---- Complex operations retain their original component arithmetic ----

STRICT_TYPE = '''(define-data Complex64
  (complex64 (real F64 complex64-real) (imag F64 complex64-imag)))
'''
CHEZ_STORAGE = '''(define (complex64 real imag) (vector real imag))
(define (complex64-real value) (vector-ref value 0))
(define (complex64-imag value) (vector-ref value 1))
(define (i64->f64 value) (inexact value))
'''
COMPLEX_OPERATIONS = '''(define (complex64-add left right)
  (complex64 (+ (complex64-real left) (complex64-real right))
             (+ (complex64-imag left) (complex64-imag right))))
(define (complex64-scale value scale)
  (complex64 (* (complex64-real value) scale)
             (* (complex64-imag value) scale)))
(define (complex64-multiply left right)
  (let ((a (complex64-real left)) (b (complex64-imag left))
        (c (complex64-real right)) (d (complex64-imag right)))
    (complex64 (- (* a c) (* b d)) (+ (* a d) (* b c)))))
'''
# The source literal is shared, whereas arithmetic results are fresh values.
# Every outer matrix slot is overwritten before it can expose the empty row.
SETUP = '''(define mbrot-z-origin (complex64 -1.0 -0.5))
(define mbrot-empty-row (make-vector 0 0))
'''


def strict_prelude():
    return STRICT_TYPE + COMPLEX_OPERATIONS + SETUP


def chez_helpers():
    return CHEZ_STORAGE + COMPLEX_OPERATIONS + SETUP


# ---- Mechanical edits leave the complex escape and matrix loops intact ----


def kernel(source):
    edits = (
        ('(+ z0 (* z step))', '(complex64-add z0 (complex64-scale z step))', 1),
        ('(+ (* z z) z0)', '(complex64-add (complex64-multiply z z) z0)', 1),
        ('(real-part z)', '(complex64-real z)', 1),
        ('(imag-part z)', '(complex64-imag z)', 1),
        ('(make-rectangular ', '(complex64 ', 1),
        ('(inexact ', '(i64->f64 ', 2),
        ('-1.0-0.5i', 'mbrot-z-origin', 1),
        ('((matrix (make-vector n)))', '((matrix (make-vector n mbrot-empty-row)))', 1),
        ('i (make-vector n))', 'i (make-vector n 0))', 1),
    )
    for before, after, count in edits:
        source = replace(source, before, after, count)
    return source


def worker(call):
    # The original numeric predicate fails on its initial #f for zero/negative
    # repeats. Reject those before this homogeneous I64 loop can expose zero.
    return f'''(if (<= count 0) (unreachable)
    (let loop ((i 0) (result 0))
      (if (< i count) (loop (+ i 1) {call}) result)))'''


# ---- Separate probes expose complete grids, store order and components ----

PROBES = '''(define (trace-pixel-store! matrix x y value)
  (emit-store x y value)
  (vector-set! (vector-ref matrix x) y value))
(define (probe-grid size)
  (let ((matrix (test size)))
    (emit-i64 (vector-length matrix))
    (let rows ((x 0))
      (unless (= x (vector-length matrix))
        (let ((row (vector-ref matrix x)))
          (emit-i64 (vector-length row))
          (let columns ((y 0))
            (unless (= y (vector-length row))
              (emit-i64 (vector-ref row y)) (columns (+ y 1)))))
        (rows (+ x 1))))))
(define (probe-operation operation a b c d)
  (let ((left (complex64 a b)) (right (complex64 c d)))
    (if (= operation 0) left
        (if (= operation 1) (complex64-add left right)
            (if (= operation 2) (complex64-multiply left right)
                (complex64-scale left c))))))
(define (probe-real operation a b c d)
  (complex64-real (probe-operation operation a b c d)))
(define (probe-imag operation a b c d)
  (complex64-imag (probe-operation operation a b c d)))
(define (probe-count real imag step x y)
  (count (complex64 real imag) step (complex64 x y)))
'''
STRICT_PROBE_INTERFACE = '''(define-extern emit-i64 "probe" "i64" (-> I64 Unit))
(define-extern emit-store "probe" "store" (-> I64 I64 I64 Unit))
(: probe-grid (-> I64 Unit))
(: probe-real (-> I64 F64 F64 F64 F64 F64))
(: probe-imag (-> I64 F64 F64 F64 F64 F64))
(: probe-count (-> F64 F64 F64 F64 F64 I64))
'''
ORIGINAL_PROBE_ALIASES = '''(define complex64 make-rectangular)
(define complex64-real real-part)
(define complex64-imag imag-part)
(define complex64-add +)
(define complex64-multiply *)
(define complex64-scale *)
'''
CHEZ_PROBE_INTERFACE = '''(define output-values '())
(define output-stores '())
(define (emit-i64 value) (set! output-values (cons value output-values)))
(define (emit-store x y value)
  (set! output-stores (cons (list x y value) output-stores)))
(define (f64-bits value)
  (let ((bytes (make-bytevector 8)))
    (bytevector-ieee-double-native-set! bytes 0 value)
    (bytevector-u64-native-ref bytes 0)))
(let ((mode (read)))
  (cond
   ((= mode 0) (probe-grid (read))
    (write (list (reverse output-values) (reverse output-stores))))
   ((= mode 1)
    (let* ((operation (read)) (a (read)) (b (read)) (c (read)) (d (read)))
      (write (list (f64-bits (probe-real operation a b c d))
                   (f64-bits (probe-imag operation a b c d))))))
   (else
    (let* ((real (read)) (imag (read)) (step (read)) (x (read)) (y (read)))
      (write (probe-count real imag step x y)))))
  (newline))
'''
PROBE_HOST = '''import fs from 'node:fs';
const [artifact, specification] = process.argv.slice(2);
const config = JSON.parse(fs.readFileSync(specification, 'utf8'));
const matrix = [], stores = [];
const {instance} = await WebAssembly.instantiate(fs.readFileSync(artifact), {probe: {
  i64: value => matrix.push(Number(value)),
  store: (x, y, value) => stores.push([Number(x), Number(y), Number(value)]),
}});
instance.exports.main();
function bits(value) {
  const bytes = new DataView(new ArrayBuffer(8));
  bytes.setFloat64(0, value, true);
  return bytes.getBigUint64(0, true).toString();
}
let actual;
if (config.mode === 'grid') {
  instance.exports['probe-grid'](BigInt(config.size));
  actual = {matrix, stores};
} else if (config.mode === 'components') {
  const arguments_ = [BigInt(config.operation), ...config.inputs];
  actual = ['probe-real', 'probe-imag'].map(name => bits(instance.exports[name](...arguments_)));
} else {
  actual = Number(instance.exports['probe-count'](...config.inputs));
}
console.log(JSON.stringify(actual));
'''


def probe_kernel(source):
    source = replace(source, '(vector-ref (vector-ref matrix 0) 0)', 'matrix')
    return replace(source, '(vector-set! (vector-ref matrix x)\n                            y',
                   '(trace-pixel-store! matrix x y')


def strict_probe(source):
    return ('(import (snail strict))\n' + strict_prelude() + STRICT_PROBE_INTERFACE
            + probe_kernel(source) + PROBES + '(unit)\n')


def chez_probe(source, adapted):
    helpers = chez_helpers() if adapted else ORIGINAL_PROBE_ALIASES
    return ('(import (chezscheme))\n' + helpers + probe_kernel(source)
            + PROBES + CHEZ_PROBE_INTERFACE)


def probe_input(case):
    if case['mode'] == 'grid':
        return f"0\n{case['size']}\n"
    prefix = [1, case['operation']] if case['mode'] == 'components' else [2]
    return '\n'.join(map(str, [*prefix, *case['inputs']])) + '\n'


def chez_output(case, value):
    if case['mode'] == 'grid':
        return dict(matrix=value[0], stores=value[1])
    return list(map(str, value)) if case['mode'] == 'components' else value


# ---- Exact component and independent complete-grid expectations ----


def bits(value):
    return str(struct.unpack('>Q', struct.pack('>d', value))[0])


def escape_count(real, imag, step, x, y):
    cr, ci = real + x * step, imag + y * step
    zr, zi = cr, ci
    for count in range(64):
        if zr * zr + zi * zi > 16.0:
            return count
        zr, zi = (zr * zr - zi * zi) + cr, (zr * zi + zi * zr) + ci
    return 64


def grid_expected(size):
    pixels = [[escape_count(-1.0, -0.5, 0.005, float(x), float(y))
               for y in range(size)] for x in range(size)]
    matrix = [size, *(value for row in pixels for value in [size, *row])]
    stores = [[x, y, pixels[x][y]] for y in reversed(range(size)) for x in reversed(range(size))]
    return dict(matrix=matrix, stores=stores)


def fixtures():
    grids = [dict(label=f'grid-{size}', mode='grid', size=size, expected=grid_expected(size))
             for size in (0, 1, 2, 3, 8, 75)]
    components = [
        ('rectangular', 0, [1.25, -2.5, 0.0, 0.0], [1.25, -2.5]),
        ('rectangular-signed-zero', 0, [0.0, -0.0, 0.0, 0.0], [0.0, -0.0]),
        ('sum', 1, [1.25, -2.5, -3.0, 4.0], [-1.75, 1.5]),
        ('sum-rounding', 1, [1e16, -0.0, 1.0, 0.0], [1e16, 0.0]),
        ('product', 2, [3.0, 4.0, -5.0, 6.0], [-39.0, -2.0]),
        ('product-signed-zero', 2, [-0.0, 0.0, 2.0, -3.0], [0.0, 0.0]),
        ('product-subnormal', 2, [1e-154, 1e-154, 1e-154, 1e-154], [0.0, 2e-308]),
        ('product-overflow', 2, [1e308, 0.0, 1e308, 0.0], [math.inf, 0.0]),
        ('scale', 3, [3.0, -4.0, 0.125, 0.0], [0.375, -0.5]),
        ('scale-signed-zero', 3, [-0.0, 0.0, -2.0, 0.0], [0.0, -0.0]),
    ]
    components = [dict(label=label, mode='components', operation=operation, inputs=inputs,
                       expected=list(map(bits, expected))) for label, operation, inputs, expected in components]
    points = [('origin', [0.0, 0.0, 0.0, 0.0, 0.0], 64),
              ('period-two', [-1.0, 0.0, 0.0, 0.0, 0.0], 64),
              ('on-radius', [4.0, 0.0, 0.0, 0.0, 0.0], 1),
              ('outside-radius', [math.nextafter(4.0, math.inf), 0.0, 0.0, 0.0, 0.0], 0),
              ('inside-radius', [math.nextafter(4.0, 0.0), 0.0, 0.0, 0.0, 0.0], 1),
              ('imaginary-radius', [0.0, 4.0, 0.0, 0.0, 0.0], 1),
              ('first-pixel', [-1.0, -0.5, 0.005, 0.0, 0.0], 5),
              ('signed-zero-point', [-0.0, -0.0, -0.0, 0.0, 0.0], 64)]
    counts = [dict(label=label, mode='count', inputs=inputs, expected=expected)
              for label, inputs, expected in points]
    return grids + components + counts

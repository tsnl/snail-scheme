(import
 (lofi base))

;; Include signed zeros, subnormals, finite extremes, infinities and NaN payloads.
;; Stay inside Wasm so a host's floating-value conversions cannot canonicalize NaNs.
(def check-f32
     (lambda (bits)
       (if (= (f32->bits (bits->f32 bits)) bits) (unit) (unreachable))))
(def check-f64
     (lambda (bits)
       (if (= (f64->bits (bits->f64 bits)) bits) (unit) (unreachable))))
(def each-f32
     (lambda (values)
       (if (null? values) (unit)
           (begin (check-f32 (car values)) (each-f32 (cdr values))))))
(def each-f64
     (lambda (values)
       (if (null? values) (unit)
           (begin (check-f64 (car values)) (each-f64 (cdr values))))))
(each-f32
 (vector->list
  (vector 0
          -2147483648
          1
          -2147483647
          1065353216
          2139095039
          2139095040
          -8388608
          2143289345
          2139095041
          -4194303)))
(each-f64
 (vector->list
  (vector (ann 0 I64)
          (ann -9223372036854775808 I64)
          (ann 1 I64)
          (ann -9223372036854775807 I64)
          (ann 4607182418800017408 I64)
          (ann 9218868437227405311 I64)
          (ann 9218868437227405312 I64)
          (ann -4503599627370496 I64)
          (ann 9221120237041090561 I64)
          (ann 9218868437227405313 I64)
          (ann -2251799813685247 I64))))
(if (if (= (bits->f32 1065353216) (ann 1.0 F32))
        (= (bits->f64 (ann 4607182418800017408 I64)) (ann 1.0 F64)) #f)
    42 (unreachable))

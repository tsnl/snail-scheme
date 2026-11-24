;; Unsigned and signed scalar fields in little-endian binary files.
(define-library (snail shell little-endian)
  (export u16 i16 u32 i32-le)
  (import
   (snail core base))
  (begin
    (define (byte (b Bytes) (i I64)) (→ I64) (i32->i64 (u8->i32 (array-ref b i))))
    (define (u16 (b Bytes) (i I64)) (→ I64) (+ (byte b i) (* 256 (byte b (+ i 1)))))
    (define (i16 (b Bytes) (i I64)) (→ I64)
      (let ((n (u16 b i))) (if (< n 32768) n (- n 65536))))
    (define (u32 (b Bytes) (i I64)) (→ I64) (+ (u16 b i) (* 65536 (u16 b (+ i 2)))))
    (define (i32-le (b Bytes) (i I64)) (→ I64)
      (let ((n (u32 b i))) (if (< n 2147483648) n (- n 4294967296))))))

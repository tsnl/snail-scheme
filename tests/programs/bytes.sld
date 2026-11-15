(import
 (snail core base)
 (snail core io))

(define (checksum (bytes Bytes)) (→ I64)
  (array-fold (lambda (total byte) (+ total (i32->i64 (u8->i32 byte)))) 0 bytes))

(define (bytes) (→ (Array U8)) (array-generate 300 (lambda (i) (i32->u8 (i64->i32 i)))))

(define (main) (→ Unit) (! output-port)
  (display (array-ref (bytes) 255))
  (newline)
  (display (array-ref (bytes) 256))
  (newline)
  (display (checksum (bytes)))
  (newline)
  (display (+ (ann 250 U8) 10))
  (newline)
  (unit))

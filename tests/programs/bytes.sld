(import
 (snail core base)
 (snail core io))

(define (checksum (bytes Bytes)) (→ I64)
  (vector-fold (lambda (total byte) (+ total (i32->i64 (u8->i32 byte)))) 0 bytes))

(define (bytes) (→ (Vector U8)) (vector-generate 300 (lambda (i) (i32->u8 (i64->i32 i)))))

(define (main) (→ Unit) (! output-port)
  (display (vector-ref (bytes) 255))
  (newline)
  (display (vector-ref (bytes) 256))
  (newline)
  (display (checksum (bytes)))
  (newline)
  (display (+ (ann 250 U8) 10))
  (newline)
  (unit))

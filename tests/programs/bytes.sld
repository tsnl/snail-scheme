(import
 (snail core base)
 (snail core io))

(define (checksum (bytes Bytes)) (→ I64)
  (array-fold (lambda (total byte) (+ total (i32->i64 (u8->i32 byte)))) 0 bytes))

(define (bytes) (→ (Array U8)) (array-generate 300 (lambda (i) (i32->u8 (i64->i32 i)))))

(define (main (out OutputPort)) (→ Unit)
  (display out (array-ref (bytes) 255))
  (newline out)
  (display out (array-ref (bytes) 256))
  (newline out)
  (display out (checksum (bytes)))
  (newline out)
  (display out (+ (ann 250 U8) 10))
  (newline out)
  (unit))

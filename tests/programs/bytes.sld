(import
 (snail-core base)
 (snail-core io))

(: checksum (-> Bytes I64))
(define (checksum bytes)
  (vector-fold (lambda (total byte) (+ total (i32->i64 (u8->i32 byte)))) 0 bytes))

(define bytes (vector-generate 300 (lambda (i) (i32->u8 (i64->i32 i)))))
(display (vector-ref bytes 255))
(newline)
(display (vector-ref bytes 256))
(newline)
(display (checksum bytes))
(newline)
(display (+ (ann 250 U8) 10))
(newline)

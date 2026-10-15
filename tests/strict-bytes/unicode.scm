(import (snail strict) (snail bytes))
(: encode-scalar (-> I64 I64))
(define (encode-scalar scalar)
  (let ((bytes (string->utf8 (string (integer->char scalar)))))
    (let loop ((index 0) (weight 1) (packed (* (bytevector-length bytes) 4294967296)))
      (if (= index (bytevector-length bytes)) packed
          (loop (+ index 1) (* weight 256) (+ packed (* weight (bytevector-u8-ref bytes index))))))))
(: decode-scalar (-> I64 I64))
(define (decode-scalar packed)
  (let ((bytes (make-bytevector (quotient packed 4294967296))))
    (let loop ((index 0) (payload (remainder packed 4294967296)))
      (if (= index (bytevector-length bytes))
          (let ((text (utf8->string bytes)))
            (if (= (string-length text) 1) (char->integer (string-ref text 0)) (unreachable)))
          (begin
            (bytevector-u8-set! bytes index (remainder payload 256))
            (loop (+ index 1) (quotient payload 256)))))))
0

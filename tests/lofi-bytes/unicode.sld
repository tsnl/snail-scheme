(import
 (lofi base)
 (lofi bytes))

(def encode-scalar (-> I64 I64)
     (lambda (scalar)
       (begin (let bytes (string->utf8 (string (integer->char scalar))))
              (begin
                (def loop
                     (lambda (index weight packed)
                       (if (= index (bytevector-length bytes))
                           packed
                           (loop (+ index (ann 1 I64)) (* weight (ann 256 I64)) (+ packed (* weight (bytevector-u8-ref bytes index)))))))
                (loop (ann 0 I64) (ann 1 I64) (* (bytevector-length bytes) (ann 4294967296 I64)))))))

(def decode-scalar (-> I64 I64)
     (lambda (packed)
       (begin (let bytes (make-bytevector (quotient packed (ann 4294967296 I64))))
              (begin
                (def loop
                     (lambda (index payload)
                       (if (= index (bytevector-length bytes))
                           (begin (let text (utf8->string bytes))
                                  (if (= (string-length text) (ann 1 I64)) (char->integer (string-ref text (ann 0 I64))) (unreachable)))
                           (begin
                             (bytevector-u8-set! bytes index (remainder payload (ann 256 I64)))
                             (loop (+ index (ann 1 I64)) (quotient payload (ann 256 I64)))))))
                (loop (ann 0 I64) (remainder packed (ann 4294967296 I64)))))))
(ann 0 I64)

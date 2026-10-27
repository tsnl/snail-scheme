;; The syntax a `generate-library` recipe returns, and the bytes its
;; producer writes for the compiler.
(import
 (snail-core base)
 (snail-core io)
 (snail-core number)
 (snail-core datum)
 (snail-core syntax))

(define (bytes-text bytes)
  (string-join (map (lambda (byte) (show (u8->i32 byte))) (vector->list bytes)) " "))

;; (f "λ" -7 1.5 #\a #t #u8(0 200)): λ's code takes two bytes.
(define example
  (form "f" (list (StringSyntax "λ") (IntegerSyntax -7) (FloatSyntax "1.5") (CharSyntax #\a) (BooleanSyntax #t)
                  (BytesSyntax (list->vector (list (i32->u8 0) (i32->u8 200)))))))

(write-line (bytes-text (syntax->bytes example)))

;; A datum becomes the same syntax, and a float without a point gains one.
(define datum
  (datum-list (list (SymbolDatum "f") (StringDatum "λ") (NumberDatum (number-from-i64 -7)) (NumberDatum (number-from-f64 1.5))
                    (CharDatum #\a) (BooleanDatum #t) (BytesDatum (list->vector (list (i32->u8 0) (i32->u8 200)))))))

(write-line (bytes-text (syntax->bytes (datum->syntax datum))))
(write-line (bytes-text (syntax->bytes (datum->syntax (NumberDatum (number-from-f64 2.0))))))

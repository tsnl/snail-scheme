;; The syntax a `generate-library` recipe returns, and the bytes its
;; producer writes for the compiler.
(import
 (snail core base)
 (snail core io)
 (snail shell syntax))

(define bytes-text
  (lambda (bytes)
    (string-join (map (lambda (byte) (show (u8->i32 byte))) (vector->list bytes)) " ")))

;; (f "λ" -7 1.5 #\a #t #u8(0 200)): λ's code takes two bytes.
(define example
  (form "f"
        (list (StringSyntax "λ")
              (IntegerSyntax -7)
              (FloatSyntax "1.5")
              (CharSyntax #\a)
              (BooleanSyntax #t)
              (BytesSyntax (list->vector (list (i32->u8 0) (i32->u8 200)))))))

(write-line (bytes-text (syntax->bytes example)))

(write-line (bytes-text (syntax->bytes (FloatSyntax "2.0"))))

;; The syntax a `generate-library` recipe returns, and the bytes its
;; producer writes for the compiler.
(import
 (snail core base)
 (snail core io)
 (snail shell syntax))

(define (bytes-text (bytes (Vector U8))) (→ String)

  (string-join (map (lambda (byte) (show (u8->i32 byte))) (vector->list bytes)) " "))

;; (f "λ" -7 1.5 #\a #t #u8(0 200)): λ's code takes two bytes.
(define (example) (→ Syntax)
  (form "f"
        (list (String-syntax "λ")
              (Integer-syntax -7)
              (Float-syntax "1.5")
              (Char-syntax #\a)
              (Boolean-syntax #t)
              (Bytes-syntax (list->vector (list (i32->u8 0) (i32->u8 200)))))))

(define (main) (→ Unit) (! Output-port)
  (write-line (bytes-text (syntax->bytes (example))))
  (write-line (bytes-text (syntax->bytes (Float-syntax "2.0"))))
  (unit))

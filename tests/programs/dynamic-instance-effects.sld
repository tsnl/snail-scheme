(import
 (snail core base)
 (snail core io))

(effect log
  ((message (Fn String → Unit))))

(typeclass (ReadValue e T R)
  (: read-value (Fn T R → R ! e)))

(instance (ReadValue (!) I64 String)
  (define read-value (lambda (value fallback) (i64->string value))))

(instance (ReadValue (! log) String String)
  (define read-value
    (lambda (value fallback) (message value)
            value)))

(instance (ReadValue (! log dyn-cast) Any String)
  (dispatch I64 String))

(define (describe (value Any)) (→ String) (! log dyn-cast) (read-value value "fallback"))

(handle dyn-cast
    ((conversion-failed (lambda (_) (write-line "unexpected conversion failure"))))
  (handle log
      ((message (lambda (text) (write-line (string-append "logged: " text)))))
    (write-line (describe 42))
    (write-line (describe "hello"))))

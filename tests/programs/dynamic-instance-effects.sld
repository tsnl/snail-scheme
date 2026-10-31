(import
 (snail core base)
 (snail core io))

(effect log
  ((message (-> String Unit))))

(typeclass (ReadValue e T R)
  (: read-value (-> T R R ! e)))

(instance (ReadValue (!) I64 String)
  (define (read-value value fallback) (i64->string value)))

(instance (ReadValue (! log) String String)
  (define (read-value value fallback)
    (message value)
    value))

(instance (ReadValue (! log) Any String)
  (dispatch I64 String))

(: describe (-> Any String ! log))
(define (describe value) (read-value value "fallback"))

(handle log
    ((message (lambda (text) (write-line (string-append "logged: " text)))))
  (write-line (describe 42))
  (write-line (describe "hello")))

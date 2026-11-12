(import
 (snail core base)
 (snail core io)
 (scheme runtime))

;; Calling an erased Scheme procedure retains its fixed effect signature.
(define (invoke (procedure Any) (arguments (List Any))) (→ Any) (! output-port mut)
  (call procedure arguments))

(import
 (snail core base)
 (snail core io)
 (scheme runtime))

;; Calling an erased Scheme procedure retains its fixed effect signature.
(define (invoke (procedure Any) (arguments (List Any))) (→ Any) (! console mut)
  (call procedure arguments))

(import
 (snail core base)
 (snail core io)
 (scheme runtime))

;; Calling an erased Scheme procedure retains its fixed effect signature.
(: invoke (impl (Fn Any (List Any) -> Any ! console mut)))
(define (invoke procedure arguments)
  (call procedure arguments))

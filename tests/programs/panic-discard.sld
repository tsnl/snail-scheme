(import
 (snail core base)
 (snail core io))

;; Panic's unconstrained result is never produced, so discarding it needs
;; no destructor or effect annotation. The following code stays typechecked.
(define (choose (fail Bool)) (→ I64)
  (if fail
      (begin (panic "discarded fatal result") 0)
      42))

(define (main (out OutputPort)) (→ Unit) (! mut)
  (write-line out (show (choose #f))))

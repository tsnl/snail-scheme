(import
 (snail core base)
 (snail core io))

;; A type variable may stand for a function that performs `mut`, and
;; specialization erases rows before the backend sees them, so a
;; conversion must name its types where it is written.
(define (box (value A)) (→ Any) (∀ (A)) (Any value))

(define (noisy (out OutputPort)) (→ Unit) (! mut)
  (write-line out "hi"))

(define (main (out OutputPort)) (→ Unit)
  ((ann (match (downcast (Fn OutputPort → Unit) (box noisy))
          ((Some value) value)
          ((None) (panic "type mismatch")))
        (Fn OutputPort → Unit))
   out)
  (unit))

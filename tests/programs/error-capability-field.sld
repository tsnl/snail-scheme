(import
 (snail core base)
 (snail core io))

;; Every field of a capability is a function.
(capability Sized
  ((size I64)))

(define (main (out OutputPort)) (→ Unit)
  (write-line out "unreachable"))

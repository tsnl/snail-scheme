;; A script: its statements run in order as its entry, whose effects are
;; inferred, and each statement's value is dropped. A definition may come
;; after a statement that uses it.
(import
 (snail core base)
 (snail core io))

(define (main (out OutputPort)) (→ Unit) (! mut)
  (write-line out (greeting))
  (+ 1 2)
  (write-line out "statements run in order")
  (unit))

(define (greeting) (→ String) "hello from a script")


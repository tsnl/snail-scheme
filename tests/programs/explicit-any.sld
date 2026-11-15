(import
 (snail core base)
 (snail core io))

(record Point
  ((x I64)))
(record Other
  ((x I64)))
(record Trace
  ((text String)))

(define (assert (value Bool)) (→ Unit)
  (unless value (panic "Any assertion failed")))

(define (input (trace Trace) (label String) (value Any)) (→ Any) (! mut)
  (set! (● trace text) (string-append (● trace text) label))
  value)

(define (main) (→ Unit) (! mut output-port)
  (assert (match (downcast I64 (Any 42)) ((Some 42) #t) (_ #f)))
  (assert (match (downcast I64 (Any "42")) ((None) #t) (_ #f)))
  ;; Equal Wasm layouts do not make distinct nominal types interchangeable.
  (assert (match (downcast Other (Any (new Point (x 3)))) ((None) #t) (_ #f)))
  (assert (match (downcast Point (Any (new Point (x 3)))) ((Some (Point 3)) #t) (_ #f)))
  ;; An Any constructor boxes its exact input type, including Any itself.
  (assert (match (downcast Any (Any (Any 7)))
            ((Some inner) (match (downcast I64 inner) ((Some 7) #t) (_ #f)))
            (_ #f)))
  (assert (match (downcast Any (Any 7)) ((None) #t) (_ #f)))
  ;; Both operands run once, left to right, even when the first cast fails.
  (let ((trace (new Trace (text ""))))
    (match (new Pair (first (downcast I64 (input trace "L" (Any #f))))
                (second (downcast String (input trace "R" (Any "right")))))
      ((Pair (None) (Some "right")) (unit))
      (_ (panic "downcast result")))
    (assert (string=? (● trace text) "LR")))
  (write-line "explicit Any passed"))

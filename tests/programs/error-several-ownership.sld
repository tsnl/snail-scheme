(import
 (snail core base))

;; Ownership is checked an item at a time, so each item that misuses a
;; linear value is reported, though the first stops its own item.
(define (duplicate (value T)) (→ (Pair T T)) (∀ (T))
  (new Pair (first value) (second value)))

(define (fine (n I64)) (→ I64)
  (+ n 1))

(define (forget (value T)) (→ Unit) (∀ (T))
  (unit))

(define main
  (lambda ()
    (duplicate (fine 1))
    (unit)))

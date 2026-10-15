(import (scheme base) (scheme write)
        (snail-scheme iverson-ghost)
        (rename (only (snail-scheme core) %iverson-iota) (%iverson-iota primitive-iota)))

;; ---- First-class primitives and binding identity ----

(define (check expected actual)
  (unless (equal? expected actual) (error "array rebinding mismatch" expected actual)))

(define original-iota primitive-iota)
(define (sequence) (primitive-iota 2 3))
(define (replace-iota)
  (set! primitive-iota (lambda (kind count) (array '(1) '(77) 'i32))))

(check '#(0 1 2) (array->vector (sequence)))
(check '#(0 1 2) (array->vector (apply original-iota '(2 3))))
(replace-iota)
(check '#(77) (array->vector (sequence)))
(check '#(77) (array->vector (iota 3 'i32)))
(check '#(0 1 2) (array->vector (original-iota 2 3)))
(set! primitive-iota original-iota)
(check '#(0 1 2) (array->vector (sequence)))
(display "iverson rebinding checks passed\n")

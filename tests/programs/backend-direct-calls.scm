(import (scheme base) (scheme write)
        (rename (only (scheme base) vector-length) (vector-length imported-size)))

;; ---- Operand effects and mutation through the same imported binding ----

(define (check actual expected)
  (unless (equal? actual expected) (error "direct call mismatch" actual expected)))
(define effects '())
(define (record value) (set! effects (cons value effects)) value)
(define items (vector 1 2))
(vector-set! items (record 0) (record 3))
(check effects '(3 0))
(check (vector-ref items 0) 3)
(define original-size imported-size)
(check (imported-size items) 2)
(check (vector-length (begin (set! imported-size (lambda (item) 91)) items)) 91)
(check (imported-size items) 91)
(set! vector-length original-size)
(check (imported-size items) 2)

;; Spelling alone is insufficient, and known adapters preserve multiple results.
(check (let ((vector-ref (lambda (items index) 23))) (vector-ref items 0)) 23)
(check (call-with-values (lambda () (values 2 3)) list) '(2 3))
(check (call-with-values (lambda () (values)) list) '())

;; ---- The statically known apply adapter still performs a dynamic tail call ----

(define (tail n) (if (= n 0) 17 (apply tail (list (- n 1)))))
(check (tail 200000) 17)
(display "direct call checks passed\n")

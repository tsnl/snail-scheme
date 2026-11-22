(import
 (snail core base)
 (snail core io))

(record Count
  ((value I64)))

;; The callback uses e, while its caller also writes.
(define (announce (out OutputPort) (action (Fn → A ! e))) (→ A) (! mut e) (∀ (A e))
  (write-line out "calling")
  (action))

;; The shared rigid tail is also preserved when both rows have a known label.
(define (counted (count Count) (action (Fn → I64 ! mut e))) (→ I64) (! mut e) (∀ (e))
  (set! (● count value) (+ (● count value) 1))
  (action))

(define (main (out OutputPort)) (→ Unit) (! mut)
  (display out (announce out (lambda () 7)))
  (newline out)
  (let ((count (new Count (value 0))))
    (display out (counted count (lambda () (+ 41 (● count value)))))
    (newline out))
  ;; An inferred callback row remains constrained by its concrete effects.
  (announce out (lambda () (write-line out "effect retained")))
  (unit))

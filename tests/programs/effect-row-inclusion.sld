(import
 (snail core base)
 (snail core io))

(effect Value
  ((value (Fn → I64))))

;; The callback uses e, while its caller also has console permission.
(define (announce (out OutputPort) (action (Fn → A ! e))) (→ A) (! mut e) (∀ (A e))
  (write-line out "calling")
  (action))

;; The shared rigid tail is also preserved when both rows have known labels.
(define (with-value (out OutputPort) (action (Fn → I64 ! Value e))) (→ I64) (! mut Value e) (∀ (e))
  (write-line out "calling")
  (action))

(define (choose) (→ I64) (! Value) (value))

(define (main (out OutputPort)) (→ Unit) (! mut)
  (display out (announce out (lambda () 7)))
  (newline out)
  (display out (handle Value
                   ((value (lambda () 42)))
                 (with-value out choose)))
  (newline out)
  ;; An inferred callback row remains constrained by its concrete effects.
  (announce out (lambda () (write-line out "effect retained")))
  (unit))

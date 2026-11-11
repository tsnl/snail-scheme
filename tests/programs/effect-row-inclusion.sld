(import
 (snail core base)
 (snail core io))

(effect Value
  ((value (dyn (Fn → I64)))))

;; The callback uses e, while its caller also has console permission.
(define (announce (action (dyn (Fn → A ! e)))) (→ A) (! console e) (∀ A e)
  (write-line "calling")
  (action))

;; The shared rigid tail is also preserved when both rows have known labels.
(define (with-value (action (dyn (Fn → I64 ! Value e)))) (→ I64) (! console Value e) (∀ e)
  (write-line "calling")
  (action))

(define (choose) (→ I64) (! Value) (value))

(display (announce (lambda () 7)))
(newline)
(display (handle Value
             ((value (lambda () 42)))
           (with-value choose)))
(newline)

;; An inferred callback row remains constrained by its concrete effects.
(announce (lambda () (write-line "effect retained")))

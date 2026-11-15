(import
 (snail core base)
 (snail core io))

(effect Value
  ((value (Fn → I64))))

;; The callback uses e, while its caller also has console permission.
(define (announce (action (Fn → A ! E))) (→ A) (! Output-port E) (∀ (A E))
  (write-line "calling")
  (action))

;; The shared rigid tail is also preserved when both rows have known labels.
(define (with-value (action (Fn → I64 ! Value E))) (→ I64) (! Output-port Value E) (∀ (E))
  (write-line "calling")
  (action))

(define (choose) (→ I64) (! Value) (value))

(define (main) (→ Unit) (! Output-port)
  (display (announce (lambda () 7)))
  (newline)
  (display (handle Value
               ((value (lambda () 42)))
             (with-value choose)))
  (newline)
  ;; An inferred callback row remains constrained by its concrete effects.
  (announce (lambda () (write-line "effect retained")))
  (unit))

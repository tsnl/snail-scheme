(import
 (snail core base)
 (snail core io))

(effect Value
  ((value (-> I64))))

;; The callback uses e, while its caller also has console permission.
(: announce (All (A e) (-> (-> A ! e) A ! console e)))
(define (announce action)
  (write-line "calling")
  (action))

;; The shared rigid tail is also preserved when both rows have known labels.
(: with-value (All (e) (-> (-> I64 ! Value e) I64 ! console Value e)))
(define (with-value action)
  (write-line "calling")
  (action))

(: choose (-> I64 ! Value))
(define (choose) (value))

(display (announce (lambda () 7)))
(newline)
(display (handle Value
             ((value (lambda () 42)))
           (with-value choose)))
(newline)

;; An inferred callback row remains constrained by its concrete effects.
(announce (lambda () (write-line "effect retained")))

(import
 (snail core base))

;; A generic function may hold a value of its type variable across a yield,
;; so a use that may yield must allow dropping each linear type it binds.
(effect audit
  ((note (dyn (Fn String -> Unit)))))

(effect Ask
  ((ctl ask (dyn (Fn -> I64)))))

(struct Handle
  ((name String)))

(instance (Drop (! audit) Handle)
  (define (drop handle)
    (match handle
      ((Handle name) (note name)))))

(: hold (All (A e) (impl (Fn A (dyn (Fn -> Unit ! e)) -> A ! e))))
(define (hold value action)
  (action)
  value)

(: use (impl (Fn -> Handle ! Ask)))
(define (use)
  (hold (Handle "h") (lambda () (ask) (unit))))

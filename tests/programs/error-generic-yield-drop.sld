(import
 (snail core base))

;; A generic function may hold a value of its type variable across a yield,
;; so a use that may yield must allow dropping each linear type it binds.
(effect audit
  ((note (-> String Unit))))

(effect Ask
  ((ctl ask (-> I64))))

(struct Handle
  ((name String)))

(instance (Drop (! audit) Handle)
  (define (drop handle)
    (match handle
      ((Handle name) (note name)))))

(: hold (All (A e) (-> A (-> Unit ! e) A ! e)))
(define (hold value action)
  (action)
  value)

(: use (-> Handle ! Ask))
(define (use)
  (hold (Handle "h") (lambda () (ask) (unit))))

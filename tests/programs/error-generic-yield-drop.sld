(import
 (snail core base))

;; A generic function may hold a value of its type variable across a yield,
;; so a use that may yield must allow dropping each linear type it binds.
(effect audit
  ((note (dyn (Fn String → Unit)))))

(effect Ask
  ((ctl ask (dyn (Fn → I64)))))

(struct Handle
  ((name String)))

(instance (Drop (! audit) Handle)
  (define drop
    (lambda (handle) (match handle
                       ((Handle name) (note name))))))

(define (hold (value A) (action (dyn (Fn → Unit ! e)))) (→ A) (! e) (∀ A e)
  (action)
  value)

(define (use) (→ Handle) (! Ask)
  (hold (Handle "h") (lambda () (ask) (unit))))

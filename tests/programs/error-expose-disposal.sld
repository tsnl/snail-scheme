(import
 (snail core base))
(effect Cleanup ((finish (Fn I64 → Unit))))
(record Resource
  ((value I64)))
(instance (Drop (! Cleanup) Resource)
  (define (drop (resource Resource)) (→ Unit) (! Cleanup)
    (match resource ((Resource value) (finish value)))))
(define (create) (→ (Rc Resource)) (rc (new Resource (value 1))))
(expose create "create")

(define-library (owned handle)
  (export log say Handle Handle-name-set)
  (import
   (snail core base))
  (begin
    ;; A handle says its name when it is released.
    (effect log
      ((say (Fn String → Unit))))

    (record Handle
      ((name String)))

    (instance (Drop (! log) Handle)
      (define (drop (handle Handle)) (→ Unit) (! log)
        (match handle
          ((Handle name) (say name)))))))

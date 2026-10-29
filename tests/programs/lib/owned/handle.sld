(define-library (owned handle)
  (export log say Handle Handle-name-set)
  (import
   (snail core base))
  (begin
    ;; A handle says its name when it is released.
    (effect log
      ((say (-> String Unit))))

    (struct Handle
      ((name String)))

    (instance (Drop (! log) Handle)
      (define (drop handle)
        (match handle
          ((Handle name) (say name)))))))

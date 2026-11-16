;; Top-level values for `global-values.sld`: one read through a function
;; here, one exported and read where it is imported.
(define-library (sample settings)
  (export
   Settings
   settings
   port
   visits)
  (import
   (snail core base))
  (begin

    (record Settings
      ((name String)
       (visits I64)))

    (define settings (new Settings (name "sample") (visits 0)))

    (define port (→ I64) (+ 8000 80))

    (define (visits) (→ I64) (! mut)
      (set! (● settings visits) (+ (● settings visits) 1))
      (● settings visits))))

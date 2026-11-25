(import
 (snail core base)
 (only (snail core forms) Funcref))

(extern get-callback "test" "get" (Fn → Funcref))
(define (value (callback Funcref)) (→ I64) 0)
(define (main) (→ Unit)
  (let ((memo (cache value))) (memo (get-callback)) (unit)))

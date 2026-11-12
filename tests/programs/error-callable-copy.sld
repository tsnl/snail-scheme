(import
 (snail core base))

(define (duplicate (function (Fn I64 → I64)))
      (→ (Pair (Fn I64 → I64) (Fn I64 → I64)))
      (Pair function function))

(import
 (snail core base))

(enum Choice
  (Left ((value I64)))
  (Right ((value I64))))

(define wrong (→ I64) (Left-value (Right 3)))

(define (main) (→ I64)
  wrong)

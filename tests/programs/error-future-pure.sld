(import
 (snail core base)
 (snail shell future))

(define (inspect (future (Future I64))) (→ (Poll I64))
  (poll future))

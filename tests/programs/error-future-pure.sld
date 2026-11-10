(import
 (snail core base)
 (snail shell future))

(: inspect (impl (Fn (Future I64) -> (Poll I64))))
(define (inspect future)
  (poll future))

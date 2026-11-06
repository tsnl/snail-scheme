(import
 (snail core base)
 (snail shell future))

(: inspect (-> (Future I64) (Poll I64)))
(define (inspect future)
  (poll future))

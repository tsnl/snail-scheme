(import
 (snail core base)
 (snail shell future)
 (snail shell async))

(: step (impl (Fn (Future I64) -> (Completion I64) ! mut)))
(define (step future)
  (await-future future))

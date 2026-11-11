(import
 (snail core base)
 (snail shell future)
 (snail shell async))

(define (step (future (Future I64))) (→ (Completion I64)) (! mut)
  (await-future future))

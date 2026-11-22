(import
 (snail shell ui page)
 (notes application)
 (only (snail shell page) Events)
 (only (snail shell page) PageStorage))

(define (main (events Events) (storage PageStorage)) (→ Unit) (! mut host tasks)
  (run-interface events storage (notes))
  (unit))

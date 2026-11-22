(import
 (snail core base)
 (snail shell ui page)
 (notes application)
 (only (snail shell page) Events)
 (only (snail shell page) PageStorage))

(define (main (events Events) (storage PageStorage)) (→ Unit) (! mut)
  (run-interface events storage (notes))
  (unit))

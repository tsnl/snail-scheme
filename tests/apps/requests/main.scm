(import
 (snail core base)
 (requests application)
 (only (snail shell page) Events)
 (only (snail shell page) PageStorage))

(define (main (events Events) (storage PageStorage)) (→ Unit) (! mut)
  (run-requests events storage)
  (unit))

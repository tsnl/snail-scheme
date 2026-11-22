(import
 (requests application)
 (only (snail shell page) Events)
 (only (snail shell page) PageStorage))

(define (main (events Events) (storage PageStorage)) (→ Unit) (! mut host tasks)
  (run-requests events storage)
  (unit))

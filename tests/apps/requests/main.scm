(import
 (snail core base)
 (requests application)
 (only (snail shell page) Events)
 (only (snail shell page) PageStorage)
 (only (snail shell task) tasks)
 (only (snail core forms) host))

(define (main (events Events) (storage PageStorage)) (→ Unit) (! mut host tasks)
  (run-requests events storage)
  (unit))

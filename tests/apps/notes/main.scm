(import
 (snail core base)
 (snail shell ui page)
 (notes application)
 (only (snail shell page) Events)
 (only (snail shell page) PageStorage)
 (only (snail shell task) tasks)
 (only (snail core forms) host))

(define (main (events Events) (storage PageStorage)) (→ Unit) (! mut host tasks)
  (run-interface events storage (notes))
  (unit))

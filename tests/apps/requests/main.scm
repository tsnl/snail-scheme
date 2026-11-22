(import
 (snail core base)
 (requests application)
 (only (snail shell dom) Dom)
 (only (snail shell fetch) Fetch)
 (only (snail shell page) Events)
 (only (snail shell page) PageStorage))

(define (main (dom Dom) (fetch Fetch) (events Events) (storage PageStorage)) (→ Unit)
  (run-requests dom fetch events storage)
  (unit))

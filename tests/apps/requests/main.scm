(import
 (snail core base)
 (requests application)
 (only (snail shell dom) Dom)
 (only (snail shell fetch) Fetch)
 (only (snail shell page) Events)
 (only (snail shell page) PageStorage))

(define (main (mut Mut) (dom Dom) (fetch Fetch) (events Events) (storage PageStorage)) (→ Unit)
  (run-requests mut dom fetch events storage)
  (unit))

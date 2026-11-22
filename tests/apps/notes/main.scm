(import
 (snail core base)
 (snail shell ui page)
 (notes application)
 (only (snail shell dom) Dom)
 (only (snail shell fetch) Fetch)
 (only (snail shell page) Events)
 (only (snail shell page) PageStorage))

(define (main (dom Dom) (fetch Fetch) (events Events) (storage PageStorage)) (→ Unit)
  (run-interface dom fetch events storage (notes))
  (unit))

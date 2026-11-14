(import
 (snail core base))

(record Work
  ((run (FnOnce → Unit))))

(define (run (work (Rc Work))) (→ Unit) (! mut)
  ((● work run)))

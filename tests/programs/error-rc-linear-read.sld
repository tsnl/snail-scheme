(import
 (snail core base))

(struct Work
  ((run (FnOnce → Unit))))

(define (run (work (Rc Work))) (→ Unit) (! mut)
  ((● work run)))

(import
 (snail core base))

(define (use (work (FnOnce → Unit))) (→ Unit)
  (call-once work))

(expose use "use")

(import
 (snail core base))

(define (use (work (dyn (FnOnce → Unit)))) (→ Unit)
  (call-once work))

(expose use "use")

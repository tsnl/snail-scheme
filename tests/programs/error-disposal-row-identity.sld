(import
 (snail core base)
 (snail core io))
(struct (Box T)
  ((value T)))
(struct Both
  ((output (Box (Fn → Unit ! output-port)))
   (files (Box (Fn → Unit ! fs)))))
(define (forget (both Both)) (→ Unit) (! output-port) (unit))

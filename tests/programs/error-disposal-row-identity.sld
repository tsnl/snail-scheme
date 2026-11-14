(import
 (snail core base)
 (snail core io))
(record (Box T)
  ((value T)))
(record Both
  ((output (Box (Fn → Unit ! output-port)))
   (files (Box (Fn → Unit ! fs)))))
(define (forget (both Both)) (→ Unit) (! output-port) (unit))

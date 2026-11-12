(import
 (snail core base)
 (snail core io))

(effect Pause
  ((ctl pause (Fn I64 → I64))))

(define (twice (function (Fn I64 → I64 ! Pause)))
  (→ I64)
  (! Pause)
  (+ (function 1) (function 2)))

(define (main) (→ Unit) (! output-port)
  (write-line
   (show
    (handle Pause ((pause (lambda (value resume) (resume (+ value 10)))))
      (twice (lambda (value) (pause value))))))
  (unit))

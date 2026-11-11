(import
 (snail core base)
 (snail core io))

(effect Pause
  ((ctl pause (impl (Fn I64 -> I64)))))

(: twice
   (All (F)
        (requires (Copy F) (Fn F I64 -> I64 ! Pause))
        (impl (Fn F -> I64 ! Pause))))
(define (twice function)
  (+ (function 1) (function 2)))

(write-line
 (show
  (handle Pause ((pause (lambda (value resume) (resume (+ value 10)))))
    (twice (lambda (value) (pause value))))))

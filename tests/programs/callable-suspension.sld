(import
 (snail core base)
 (snail core io))

(effect Pause
  ((ctl pause (impl (Fn I64 → I64)))))

(define (twice (function F)) (→ I64) (! Pause) (∀ F) (⊨ (Copy F) (Fn F I64 → I64 ! Pause))
  (+ (function 1) (function 2)))

(write-line
 (show
  (handle Pause ((pause (lambda (value resume) (resume (+ value 10)))))
    (twice (lambda (value) (pause value))))))

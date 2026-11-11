(import
 (snail core base)
 (snail core io))

(struct Token
  ((label String)))

(instance (Drop (! console) Token)
  (define (drop token)
    (match token
      ((Token label) (write-line label)))))

(: offset (impl (Fn Token I64 -> (dyn (FnOnce I64 -> I64 ! console)))))
(define (offset token amount)
  (once (lambda (value)
          (drop token)
          (+ amount value))))

(let ((work (offset (Token "called") 4)))
  (write-line (show (work 5))))
(drop (offset (Token "dropped") 100))

;; Several arguments and an owned argument retain their original types.
(let ((work (once (lambda (first last) (string-append first last)))))
  (write-line (work "left" "right")))

(: consume-job (impl (Fn (dyn (FnOnce -> Unit ! console)) -> I64 ! console)))
(define (consume-job job)
  (job)
  7)

(let ((work (once consume-job)))
  (write-line (show (work (once (lambda () (write-line "argument")))))))

(effect Pause
  ((ctl pause (dyn (Fn -> I64)))))

(: suspended (impl (Fn Token -> (dyn (FnOnce I64 -> I64 ! Pause console)))))
(define (suspended token)
  (once (lambda (value)
          (let ((answer (pause)))
            (drop token)
            (+ value answer)))))

(write-line
 (show
  (handle Pause ((pause (lambda (resume) (resume 10))))
    (let ((work (suspended (Token "resumed"))))
      (work 5)))))

(write-line
 (show
  (handle Pause ((pause (lambda (resume) (drop resume) -1)))
    (let ((work (suspended (Token "abandoned"))))
      (work 5)))))

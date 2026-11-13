(import
 (snail core base)
 (snail core io))

(struct Token
  ((label String)))

(instance (Drop (! output-port) Token)
  (define drop
    (lambda (token) (match token
                      ((Token label) (write-line label))))))

(define (offset (token Token) (amount I64)) (→ (FnOnce I64 → I64 ! output-port))
  (once (lambda (value)
          (drop token)
          (+ amount value))))

(define (consume-job (job (FnOnce → Unit ! output-port))) (→ I64) (! output-port)
  (job)
  7)

(effect Pause
  ((ctl pause (Fn → I64))))

(define (suspended (token Token)) (→ (FnOnce I64 → I64 ! Pause output-port))
  (once (lambda (value)
          (let ((answer (pause)))
            (drop token)
            (+ value answer)))))

(define (main) (→ Unit) (! output-port)
  (let ((work (offset (Token "called") 4)))
    (write-line (show (work 5))))
  (drop (offset (Token "dropped") 100))
  ;; Several arguments and an owned argument retain their original types.
  (let ((work (once (lambda (first last) (string-append first last)))))
    (write-line (work "left" "right")))
  (let ((work (once consume-job)))
    (write-line (show (work (once (lambda () (write-line "argument")))))))
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
  (unit))

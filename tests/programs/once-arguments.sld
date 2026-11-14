(import
 (snail core base)
 (snail core io))

(record Token
  ((label String)))

(instance (Drop (! output-port) Token)
  (define (drop (token Token)) (→ Unit) (! output-port)
    (match token
      ((Token label) (write-line label)))))

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
  (let ((work (offset (new Token (label "called")) 4)))
    (write-line (show (work 5))))
  (drop (offset (new Token (label "dropped")) 100))
  ;; Several arguments and an owned argument retain their original types.
  (let ((work (once (lambda (first last) (string-append first last)))))
    (write-line (work "left" "right")))
  (let ((work (once consume-job)))
    (write-line (show (work (once (lambda () (write-line "argument")))))))
  (write-line
   (show
    (handle Pause ((pause (lambda (resume) (resume 10))))
      (let ((work (suspended (new Token (label "resumed")))))
        (work 5)))))
  (write-line
   (show
    (handle Pause ((pause (lambda (resume) (drop resume) -1)))
      (let ((work (suspended (new Token (label "abandoned")))))
        (work 5)))))
  (unit))

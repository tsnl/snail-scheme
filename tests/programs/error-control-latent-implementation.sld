(import
 (snail core base))

;; An implementation may yield only to the control effects its
;; operation's type names, Gen here, since only those are tested for
;; where the operation is performed.
(effect Abort
  ((ctl abort (dyn (Fn I64 → I64)))))

(effect Gen
  ((ctl yield (dyn (Fn I64 → Unit)))))

(effect Ask
  ((ask (dyn (Fn → I64 ! Gen)))))

(define (answer) (→ I64)
  (handle Abort ((abort (lambda (value resume) (drop resume) value)))
    (handle Gen ((yield (lambda (value resume) (resume (unit)))))
      (handle Ask ((ask (lambda () (abort 0))))
        (+ (ask) 1)))))

(answer)

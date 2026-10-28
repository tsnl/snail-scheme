(import
 (snail core base))

;; An implementation may yield only to the control effects its
;; operation's type names, Gen here, since only those are tested for
;; where the operation is performed.
(effect Abort
  ((ctl abort (-> I64 I64))))

(effect Gen
  ((ctl yield (-> I64 Unit))))

(effect Ask
  ((ask (-> I64 ! Gen))))

(: answer (-> I64))
(define (answer)
  (handle Abort ((abort (lambda (value resume) (drop resume) value)))
    (handle Gen ((yield (lambda (value resume) (resume (unit)))))
      (handle Ask ((ask (lambda () (abort 0))))
        (+ (ask) 1)))))

(answer)

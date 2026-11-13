(import
 (snail core base))

;; An implementation of an operation declared without ctl returns to its
;; caller in the handled body, which expects a yield there only to the
;; control effects the operation's type names, and ask's names none.
(effect Abort
  ((ctl abort (Fn I64 → I64))))

(effect Ask
  ((ask (Fn → I64))))

(define (answer) (→ I64)
  (handle Abort ((abort (lambda (value resume) (drop resume) value)))
    (handle Ask ((ask (lambda () (abort 0))))
      (+ (ask) 1))))

(define (main) (→ Unit)

  (answer)
  (unit))

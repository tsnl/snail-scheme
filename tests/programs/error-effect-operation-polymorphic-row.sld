(import
 (snail core base)
 (snail core io))

;; A row variable is refused as a type variable is. Here the
;; implementation could call the thunk it is given, whose effects no
;; caller of run is charged: Gen would yield to no handler at all.
(effect Gen
  ((ctl yield (Fn I64 → I64))))

(effect Run
  ((run (∀ (e) (Fn (Fn → Unit ! e) → Unit)))))

(define (go) (→ I64)
  (handle Run ((run (lambda (thunk) (thunk))))
    (run (lambda () (write-line (string-append "got " (show (yield 1))))))
    42))

(define main
  (lambda ()
    (write-line (show (go)))
    (unit)))

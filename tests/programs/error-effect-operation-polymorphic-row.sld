(import
 (snail core base)
 (snail core io))

;; A row variable is refused as a type variable is. Here the
;; implementation could call the thunk it is given, whose effects no
;; caller of run is charged: Gen would yield to no handler at all.
(effect Gen
  ((ctl yield (dyn (Fn I64 → I64)))))

(effect Run
  ((run (∀ (e) (dyn (Fn (dyn (Fn → Unit ! e)) → Unit))))))

(define (go) (→ I64)
  (handle Run ((run (lambda (thunk) (thunk))))
    (run (lambda () (write-line (string-append "got " (show (yield 1))))))
    42))

(write-line (show (go)))

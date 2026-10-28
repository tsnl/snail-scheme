(import
 (snail core base)
 (snail core io))

;; A row variable is refused as a type variable is. Here the
;; implementation could call the thunk it is given, whose effects no
;; caller of run is charged: Gen would yield to no handler at all.
(effect Gen
  ((ctl yield (-> I64 I64))))

(effect Run
  ((run (All (e) (-> (-> Unit ! e) Unit)))))

(: go (-> I64))
(define (go)
  (handle Run ((run (lambda (thunk) (thunk))))
    (run (lambda () (write-line (string-append "got " (show (yield 1))))))
    42))

(write-line (show (go)))

(import
 (snail-core base)
 (snail-core io))

;; With an Async handler on each side of Io's, fetch's await goes to the
;; inner one, which is in scope where fetch is performed, and not to the
;; one outside Io's handler, where fetch's implementation was installed.
(effect Async
  ((ctl await (-> I64 I64))))

(effect Io
  ((fetch (-> I64 I64 ! Async))))

(write-line
 (show
  (handle Async
      ((await (lambda (ticket resume) (write-line "outer Async") (resume (+ ticket 1000)))))
    (handle Io
        ((fetch (lambda (ticket) (await ticket))))
      (handle Async
          ((await (lambda (ticket resume) (write-line "inner Async") (resume (+ ticket 1)))))
        (fetch 10))))))

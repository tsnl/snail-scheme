(import
 (snail core base))

;; A default is held to its operation's latent row, as a definition is to
;; its signature's: every performer is charged that row, so a default
;; that never performs it would cost each of them for nothing.
(effect Async
  ((ctl await (Fn I64 → I64))))

(effect Clock
  ((sleep-until (Fn I64 → I64 ! Async)))
  (default
    ((sleep-until (lambda (deadline) deadline)))))

(define main
  (lambda ()
    (unit)
    (unit)))

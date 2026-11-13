(import
 (snail core base))

;; An abortive implementation releases `resume` explicitly, with `drop`.
(effect Stop
  ((ctl stop (Fn I64 → I64))))

(define main
  (lambda ()
    (handle Stop ((stop (lambda (code resume) code)))
      (stop 1))
    (unit)))

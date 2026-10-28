(import
 (snail core base))

;; An abortive implementation releases `resume` explicitly, with `drop`.
(effect Stop
  ((ctl stop (-> I64 I64))))

(handle Stop ((stop (lambda (code resume) code)))
  (stop 1))

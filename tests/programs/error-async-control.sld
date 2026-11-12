(import
 (snail core base)
 (snail shell future)
 (snail shell async))

(effect pause
  ((ctl stop (Fn → Unit))))

(define main
  (lambda ()
    (handle pause
        ((stop (lambda (resume) (resume (unit)))))
      (drop (dispatch (once (lambda () (stop))))))
    (unit)))

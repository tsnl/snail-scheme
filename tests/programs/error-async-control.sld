(import
 (snail core base)
 (only (snail core forms) host)
 (snail shell future)
 (snail shell async)
 (only (snail shell task) tasks))

(effect pause
  ((ctl stop (Fn → Unit))))

(define (main) (→ Unit) (! host mut completion tasks)

  (handle pause
      ((stop (lambda (resume) (resume (unit)))))
    (dispatch (lambda () (stop))))
  (unit))

(import
 (snail core base)
 (snail shell future)
 (snail shell async))

(effect pause
  ((ctl stop (-> Unit))))

(handle pause
    ((stop (lambda (resume) (resume (unit)))))
  (drop (dispatch (once (lambda () (stop))))))

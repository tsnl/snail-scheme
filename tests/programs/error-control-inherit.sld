(import
 (snail core base)
 (only (snail core primitive) inherit-handlers))

;; A procedure closed over its handlers may run after their handles have
;; returned, so it may not yield to one.
(effect Stop
  ((ctl stop (Fn → Unit))))

(define (main) (→ Unit)

  (handle Stop ((stop
                 (lambda (resume) (inherit-handlers (lambda () (unit))))))
    (inherit-handlers (lambda () (stop))))
  (unit))

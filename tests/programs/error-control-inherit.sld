(import
 (snail core base)
 (only (snail core primitive) inherit-handlers))

;; A procedure closed over its handlers may run after their handles have
;; returned, so it may not yield to one.
(effect Stop
  ((ctl stop (-> Unit))))

(drop
 (handle Stop ((stop (lambda (resume) (drop resume) (inherit-handlers (once (lambda () (unit)))))))
   (inherit-handlers (once (lambda () (stop))))))

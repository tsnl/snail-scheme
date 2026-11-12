(import
 (snail core base)
 (snail core io))

(effect Pause
  ((ctl pause (dyn (Fn → Unit)))))

(effect Stop
  ((ctl stop (dyn (Fn → Unit)))))

(struct Resource
  ((name String)))

;; This method is reached only by cleanup of a suspended frame. New
;; cleanup batches must receive the same restriction checks as ordinary code.
(instance (Drop (! output-port) Resource)
  (define drop
    (lambda (resource) (unsafe-total (lambda () (stop)))
            (match resource
              ((Resource name) (write-line name))))))

(define (work) (→ Unit) (! Pause output-port)
  (let ((resource (Resource "resource")))
    (pause)
    (match resource
      ((Resource name) (write-line name)))))

(handle Pause ((pause (lambda (resume) (drop resume))))
  (work))

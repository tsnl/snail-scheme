(import
 (snail core base)
 (snail core io))

(effect Pause
  ((ctl pause (-> Unit))))

(effect Stop
  ((ctl stop (-> Unit))))

(struct Resource
  ((name String)))

;; This method is reached only by cleanup of a suspended frame. New
;; cleanup batches must receive the same restriction checks as ordinary code.
(instance (Drop (! console) Resource)
  (define (drop resource)
    (unsafe-total (lambda () (stop)))
    (match resource
      ((Resource name) (write-line name)))))

(: work (-> Unit ! Pause console))
(define (work)
  (let ((resource (Resource "resource")))
    (pause)
    (match resource
      ((Resource name) (write-line name)))))

(handle Pause ((pause (lambda (resume) (drop resume))))
  (work))

(import
 (snail core base)
 (snail core io))

(effect Pause
  ((ctl pause (Fn → Unit))))

(effect Stop
  ((ctl stop (Fn → Unit))))

(record Resource
  ((name String)))

;; This method is reached only by cleanup of a suspended frame. New
;; cleanup batches must receive the same restriction checks as ordinary code.
(instance (Drop (! output-port) Resource)
  (define (drop (resource Resource)) (→ Unit) (! output-port)
    (unsafe-total (lambda () (stop)))
    (match resource
      ((Resource name) (write-line name)))))

(define (work) (→ Unit) (! Pause output-port)
  (let ((resource (new Resource (name "resource"))))
    (pause)
    (match resource
      ((Resource name) (write-line name)))))

(define (main) (→ Unit) (! output-port)

  (handle Pause ((pause (lambda (resume) (drop resume))))
    (work))
  (unit))

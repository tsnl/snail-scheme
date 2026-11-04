(import
 (snail core base)
 (snail core io))

(effect Pause
  ((ctl pause (-> Unit))))

(struct Resource
  ((name String)))

(instance (Drop (! console) Resource)
  (define (drop resource)
    (match resource
      ((Resource name) (write-line (string-append "released " name))))))

;; No ordinary call requests Resource's Drop method. Only lowering the
;; suspended ownership scope discovers it, after emission has started.
(: work (-> String Unit ! Pause console))
(define (work name)
  (let ((resource (Resource name)))
    (pause)
    (match resource
      ((Resource name) (write-line (string-append "used " name))))))

(handle Pause ((pause (lambda (resume) (drop resume))))
  (work "cancelled"))

(handle Pause ((pause (lambda (resume) (resume (unit)))))
  (work "resumed"))

(import
 (snail core base)
 (snail core io))

(effect Pause
  ((ctl pause (dyn (Fn → Unit)))))

(struct Resource
  ((name String)))

(define (released-name (name String)) (→ String)
  (string-append "released " name))

(instance (Drop (! console) Resource)
  (define drop
    (lambda (resource) (match resource
                         ((Resource name)
                          (write-line (unsafe-total (lambda () (released-name name)))))))))

;; No ordinary call requests Resource's Drop method. Only lowering the
;; suspended ownership scope discovers it. Its restriction check must see
;; released-name's concrete body, discovered in that same cleanup batch.
(define (work (name String)) (→ Unit) (! Pause console)
  (let ((resource (Resource name)))
    (pause)
    (match resource
      ((Resource name) (write-line (string-append "used " name))))))

(handle Pause ((pause (lambda (resume) (drop resume))))
  (work "cancelled"))

(handle Pause ((pause (lambda (resume) (resume (unit)))))
  (work "resumed"))

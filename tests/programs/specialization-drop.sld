(import
 (snail core base)
 (snail core io))

(effect Pause
  ((ctl pause (dyn (Fn -> Unit)))))

(struct Resource
  ((name String)))

(: released-name (impl (Fn String -> String)))
(define (released-name name)
  (string-append "released " name))

(instance (Drop (! console) Resource)
  (define (drop resource)
    (match resource
      ((Resource name)
       (write-line (unsafe-total (lambda () (released-name name))))))))

;; No ordinary call requests Resource's Drop method. Only lowering the
;; suspended ownership scope discovers it. Its restriction check must see
;; released-name's concrete body, discovered in that same cleanup batch.
(: work (impl (Fn String -> Unit ! Pause console)))
(define (work name)
  (let ((resource (Resource name)))
    (pause)
    (match resource
      ((Resource name) (write-line (string-append "used " name))))))

(handle Pause ((pause (lambda (resume) (drop resume))))
  (work "cancelled"))

(handle Pause ((pause (lambda (resume) (resume (unit)))))
  (work "resumed"))

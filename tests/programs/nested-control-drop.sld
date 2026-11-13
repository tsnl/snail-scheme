(import
 (snail core base)
 (snail core io))

(effect Audit ((note (Fn String → Unit))))
(effect Pause ((ctl pause (Fn → Unit))))
(effect Inner ((ctl inner (Fn → Unit))))

(struct Resource
  ((name String)))

(instance (Drop (! Audit) Resource)
  (define (drop (resource Resource)) (→ Unit) (! Audit)
    (match resource ((Resource name) (note name)))))

;; An outer suspension saves the inner control handler as a frame. Dropping
;; that frame keeps the inner handler, with the outer drop-site context.
(define (work) (→ Unit) (! Pause Audit output-port)
  (handle Inner ((inner (lambda (resume) (resume (unit)))))
    (let ((resource (Resource "nested")))
      (pause)
      (inner)
      (drop resource))))

(enum Step (Done) (More ((next (FnOnce Unit → Step ! Audit output-port)))))

(define (start) (→ Step) (! Audit output-port)
  (handle Pause ((pause (lambda (resume) (More resume))))
    (work)
    (Done)))

(define (main) (→ Unit) (! output-port)
  (let ((step
         (handle Audit ((note (lambda (name) (write-line (string-append "allocation: " name)))))
           (start))))
    (handle Audit ((note (lambda (name) (write-line (string-append "drop: " name)))))
      (drop step)))
  (write-line "closed")
  (unit))

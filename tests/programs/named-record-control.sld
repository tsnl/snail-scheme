(import
 (snail core base)
 (snail core io))

(record Resource
  ((name String)))

(instance (Drop (! output-port) Resource)
  (define (drop (resource Resource)) (→ Unit) (! output-port)
    (match resource ((Resource name) (write-line (string-append "drop " name))))))

(record (Forward T)
  ((owner T)
   (marker I64)))

(record (Backward T)
  ((marker I64)
   (owner T)))

(effect Pause ((ctl pause (Fn → Unit))))

(define (forward-linear) (→ Unit) (! Pause output-port)
  (let ((value (new Forward
                 (owner (new Resource (name "forward linear")))
                 (marker (begin (pause) 1)))))
    (write-line "complete")
    (drop value)))

(define (backward-linear) (→ Unit) (! Pause output-port)
  (let ((value (new Backward
                 (owner (new Resource (name "backward linear")))
                 (marker (begin (pause) 1)))))
    (write-line "complete")
    (drop value)))

(define (forward-counted) (→ Unit) (! Pause mut output-port)
  (let ((value (new Forward
                 (owner (rc (new Resource (name "forward counted"))))
                 (marker (begin (pause) 1)))))
    (write-line "complete")
    (drop value)))

(define (backward-counted) (→ Unit) (! Pause mut output-port)
  (let ((value (new Backward
                 (owner (rc (new Resource (name "backward counted"))))
                 (marker (begin (pause) 1)))))
    (write-line "complete")
    (drop value)))

(define (exercise (work (Fn → Unit ! Pause e))) (→ Unit) (! e) (∀ (e))
  (handle Pause ((pause (lambda (resume) (drop resume)))) (work))
  (handle Pause ((pause (lambda (resume) (resume (unit))))) (work)))

(define (main) (→ Unit) (! mut output-port)
  (exercise forward-linear)
  (exercise backward-linear)
  (exercise forward-counted)
  (exercise backward-counted))

(import
 (snail core base)
 (snail core io))

(record Resource
  ((value I64)))

(instance (Drop (! output-port) Resource)
  (define (drop (resource Resource)) (→ Unit) (! output-port)
    (match resource ((Resource value) (display value) (newline)))))

(effect Pause ((ctl pause (Fn → Unit))))

(effect ReadValue ((read-value (Fn → I64))))

(enum Step (Done) (More ((next (FnOnce Unit → Step ! mut output-port)))))

(define (start) (→ Step) (! mut output-port)
  (handle Pause ((pause (lambda (resume) (More resume))))
    (handle ReadValue
        ((read-value
          (let ((resource (rc (new Resource (value 12)))))
            (ann (lambda () (● resource value)) (Fn → I64 ! mut output-port)))))
      (pause)
      (display (read-value)) (newline)
      (Done))))

(define (main) (→ Unit) (! mut output-port)
  (let ((step (start)))
    (display 20) (newline)
    (match step ((Done) (unit)) ((More resume) (drop (resume (unit))))))
  (display 21)
  (newline)
  (let ((step (start)))
    (display 30) (newline)
    (drop step))
  (display 31)
  (newline)
  (unit))

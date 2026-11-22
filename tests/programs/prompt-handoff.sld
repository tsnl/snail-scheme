(import
 (snail core base)
 (snail core io)
 (snail shell task))

;; `resume` is a value: a generator started by one task is finished by
;; another, which is handed the rest of it through a mailbox.
(define yielding (→ (Prompt I64 Unit)) (make-prompt))

(enum Step
  (Done)
  (Yielded
   ((value I64)
    (next (Fn Unit → Step)))))

(define (start (body (Fn → Unit))) (→ Step)
  (with-prompt yielding
               (lambda ()
                 (body)
                 (Done))
               (lambda (value resume) (Yielded value resume))))

(define (drain (out OutputPort) (name String) (step Step)) (→ Unit)
  (match step
    ((Done) (write-line out (string-append name ": done")))
    ((Yielded value next)
     (write-line out (string-append name ": " (show value)))
     (drain out name (next (unit))))))

(define (main (mut Mut) (out OutputPort)) (→ Unit)
  (let ((box (ann (make-mailbox mut) (Mailbox Step))))
    (dispatch (lambda () (drain out "second task" (mailbox-receive box))))
    (match (start (lambda ()
                    (suspend yielding 1)
                    (write-line out "between values")
                    (sleep 1)
                    (suspend yielding 2)))
      ((Yielded value next)
       (write-line out (string-append "first task: " (show value)))
       (mailbox-post box (next (unit))))
      ((Done) (unit))))
  (unit))

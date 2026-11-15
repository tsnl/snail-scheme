(import
 (snail core base)
 (snail core io)
 (only (snail core forms) host)
 (only (snail core primitive) inherit-handlers))

;; A resumption called from a thunk closed over the handlers where its
;; operation was performed, which include a handle inside the one it
;; resumes. The handler leaves the resumption in a slot for the thunk.
(effect Reading ((read-number (Fn → I64))))

(enum Step
  (Done ((value I64)))
  (More ((invoke (Fn → Step ! host)))))

(record Slot
  ((next (Option (Fn Unit → Step ! mut)))))

(effect Pause
  ((ctl pause (Fn (Fn → Step ! host) → Unit))))

(define (start (slot Slot)) (→ Step) (! mut)
  (handle Pause ((pause (lambda (invoke resume)
                          (set! (● slot next) (Some resume))
                          (More invoke))))
    (handle Reading ((read-number (lambda () 7)))
      (pause (inherit-handlers (lambda () (resumed slot))))
      (Done (read-number)))))

(define (resumed (slot Slot)) (→ Step) (! mut)
  (match (● slot next)
    ((Some next) (next (unit)))
    ((None) (panic "not paused"))))

(define (show-step (step Step)) (→ Unit) (! host output-port)
  (match step
    ((Done value) (write-line (show value)))
    ((More invoke) (show-step (invoke)))))

(define (main) (→ Unit) (! host mut output-port)
  (show-step (start (new Slot (next (None))))))

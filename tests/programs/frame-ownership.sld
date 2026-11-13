(import
 (snail core base)
 (snail core io))

(effect Audit ((note (Fn I64 → Unit))))
(effect Pause ((ctl pause (Fn → Unit))))
(effect Abort ((ctl stop (Fn → Never))))

(struct Resource
  ((number I64)))

(instance (Drop (! Audit) Resource)
  (define (drop (resource Resource)) (→ Unit) (! Audit)
    (match resource ((Resource number) (note number)))))

(enum Step
  (Done)
  (More ((next (FnOnce Unit → Step ! Audit mut)))))

;; Two aliases own separate credits for one resource. Each suspension moves
;; those credits into a frame; resume and cancellation must consume them once.
(define (work) (→ Unit) (! Pause Audit mut)
  (let* ((linear (Resource 1))
         (shared (rc (Resource 2)))
         (alias shared))
    (pause)
    (pause)
    (drop linear)
    (note (+ (● shared number) (● alias number)))))

(define (start) (→ Step) (! Audit mut)
  (handle Pause ((pause (lambda (resume) (More resume))))
    (work)
    (Done)))

;; The owner has no source read in the Never continuation. It still belongs
;; to cancellation after pause, or to direct cleanup when stop aborts.
(define (abandon) (→ Never) (! Pause Abort Audit)
  (let ((unread (Resource 3)))
    (pause)
    (stop)))

(enum Abandoned
  (Stopped)
  (Waiting ((next (FnOnce Unit → Abandoned ! Audit)))))

(define (start-abandon) (→ Abandoned) (! Audit)
  (handle Pause ((pause (lambda (resume) (Waiting resume))))
    (handle Abort ((stop (lambda () (Stopped))))
      (absurd (abandon)))))

(define (finish (step Step)) (→ Unit) (! Audit mut)
  (match step
    ((Done) (unit))
    ((More next) (finish (next (unit))))))

(define (main) (→ Unit) (! output-port mut)
  (handle Audit ((note (lambda (number) (write-line (show number)))))
    (drop (start))
    (match (start)
      ((Done) (unit))
      ((More next) (drop (next (unit)))))
    (finish (start))
    (drop (start-abandon))
    (match (start-abandon)
      ((Stopped) (unit))
      ((Waiting next) (drop (next (unit))))))
  (unit))

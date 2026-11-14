(import
 (snail core base)
 (snail core io))

(effect Audit ((note (Fn I64 → Unit))))
(effect Pause ((ctl pause (Fn → Unit))))
(effect Abort ((ctl stop (Fn → Never))))

(record Resource
  ((number I64)))

(instance (Drop (! Audit) Resource)
  (define (drop (resource Resource)) (→ Unit) (! Audit)
    (match resource ((Resource number) (note number)))))

(enum Step
  (Done)
  (More ((next (FnOnce Unit → Step ! Audit mut)))))

;; Two aliases own separate credits for one resource. Each suspension moves
;; those credits into a frame; resume and cancellation must consume them once.
;; Cancellation must finalize 2 before dropping 1. The old backup closure
;; delayed 2 until its own captures were released, incorrectly printing 1 first.
(define (work) (→ Unit) (! Pause Audit mut)
  (let* ((linear (new Resource (number 1)))
         (shared (rc (new Resource (number 2))))
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
  (let ((unread (new Resource (number 3))))
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

(record Observer
  ((weak (WeakRc Resource))))

(instance (Drop (! Audit mut) Observer)
  (define (drop (observer Observer)) (→ Unit) (! Audit mut)
    (match observer
      ((Observer weak)
       (match (weak-rc-upgrade weak)
         ((Some alive) (note 9))
         ((None) (note 0)))))))

;; Parameter owners are released in reverse order. The newer shared owner
;; must be dead before the older observer runs, on cancel or direct abort.
(define (observed (observer Observer) (shared (Rc Resource)) (abort Bool))
  (→ Unit) (! Pause Abort Audit mut)
  (if abort (absurd (stop)) (pause))
  (drop observer)
  (drop shared))

(define (start-observed (abort Bool)) (→ Step) (! Audit mut)
  (handle Pause ((pause (lambda (resume) (More resume))))
    (handle Abort ((stop (lambda () (Done))))
      (new-observed abort)
      (Done))))

;; Tail transfer releases this constructing scope before observed starts;
;; no outer counted alias may mask the cancellation order being tested.
(define (new-observed (abort Bool)) (→ Unit) (! Pause Abort Audit mut)
  (let ((shared (rc (new Resource (number 5)))))
    (observed (new Observer (weak (rc-downgrade shared))) shared abort)))

(record Finish
  ((step Step)))

(instance (Drop (! Audit mut) Finish)
  (define (drop (resource Finish)) (→ Unit) (! Audit mut)
    (match resource
      ((Finish step) (note 6) (finish step) (note 7)))))

;; Cancellation may run a finalizer that resumes an independent saved
;; computation. The cancelling continuation must already own no frames.
(define (start-finish) (→ Step) (! Audit mut)
  (handle Pause ((pause (lambda (resume) (More resume))))
    (let ((resource (rc (new Finish (step (start))))))
      (pause)
      (drop resource))
    (Done)))

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
      ((Waiting next) (drop (next (unit)))))
    (drop (start-observed #f))
    (drop (start-observed #t))
    (drop (start-finish)))
  (unit))

(import
 (snail core base)
 (snail core io))

;; A struct with a mutable field has identity: `counter` and `same` below
;; are one counter, so a write through either is seen through both.
;; Reading or writing `count` performs mut; reading `name`, which is
;; immutable, does not. The book's ownership chapter includes the text
;; between ANCHOR and ANCHOR_END.
;; ANCHOR: counter
(struct Counter
  ((name String)
   (count mut I64)))

(: bump! (-> Counter Unit ! mut))
(define (bump! counter)
  (Counter-count-set! counter (+ (Counter-count counter) 1)))
;; ANCHOR_END: counter

(: label (-> Counter String))
(define (label counter)
  (Counter-name counter))

(let* ((counter (Counter "clicks" 0))
       (same counter))
  (bump! counter)
  (bump! same)
  (write-line (string-append (label counter) " " (i64->string (Counter-count counter))))
  (write-line (i64->string (Counter-count-replace! same 10)))
  (write-line (i64->string (Counter-count counter))))

;; A generic mutable field may hold linear content, which leaves only by
;; being swapped out, so the slot stays unrestricted and may be named
;; twice: the work item runs once, through whichever name swaps it first.
(type Work (Once (-> Unit ! console)))

(struct (Slot A)
  ((content mut A)))

(: run-content! (-> (Slot (Option Work)) Unit ! console mut))
(define (run-content! slot)
  (match (Slot-content-replace! slot (None))
    ((Some work) (call-once work))
    ((None) (write-line "empty"))))

(let* ((slot (Slot (Some (once (lambda () (write-line "ran"))))))
       (alias slot))
  (run-content! slot)
  (run-content! alias))

;; A linear struct may have mutable fields too. A field operation on a
;; linear local works in place and leaves it live, so the task's tries are
;; counted before it is matched apart, its mutable position skipped, to run
;; its work.
(struct Task
  ((work Work)
   (tries mut I64)))

(let ((task (Task (once (lambda () (write-line "task ran"))) 0)))
  (Task-tries-set! task (+ (Task-tries task) 1))
  (write-line (string-append "tries " (i64->string (Task-tries task))))
  (match task
    ((Task work _) (call-once work))))

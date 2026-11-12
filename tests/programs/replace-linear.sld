(import
 (snail core base)
 (snail core io))

;; A replacement consumes a linear record and answers it with one field
;; replaced. The record has one owner, so the compiled code writes the
;; field where it is; an unrestricted record is copied instead, since
;; someone else may hold it. The book's ownership chapter includes the
;; text between ANCHOR and ANCHOR_END.
;; ANCHOR: retry
(struct Job
  ((name String)
   (attempts I64)
   (work (FnOnce → Unit ! output-port))))

(define (retry (job Job)) (→ Job)
  (Job-attempts-set job (+ (● job attempts) 1)))
;; ANCHOR_END: retry

(define (run (job Job)) (→ Unit) (! output-port)
  (match job
    ((Job name attempts work)
     (write-line (string-append name " after " (i64->string attempts) " retries"))
     (call-once work))))

;; A generic body is checked with A linear, and specialized at an
;; unrestricted A it copies, since the caller may still hold the record.
(struct (Labelled A)
  ((item A)
   (label String)))

(define (relabel (labelled (Labelled A))) (→ (Labelled A)) (∀ A)
  (Labelled-label-set labelled "relabelled"))

;; A replacement is a function too, and consumes the record it is given.
(define (bump (replace (Fn Job I64 → Job)) (job Job)) (→ Job)
  (replace job 5))

(run (retry (retry (Job "build" 0 (once (lambda () (write-line "built")))))))
(run (bump Job-attempts-set (Job "deploy" 0 (once (lambda () (write-line "deployed"))))))
(let* ((original (Labelled 1 "original")) (changed (relabel original)))
  (write-line (string-append (● original label) ", " (● changed label))))
(match (relabel (Labelled (Job "test" 0 (once (lambda () (write-line "tested")))) "job"))
  ((Labelled job label)
   (write-line label)
   (run job)))

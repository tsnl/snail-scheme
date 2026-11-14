(import
 (snail core base)
 (snail core io))

;; A replacement consumes a linear record and answers it with one field
;; replaced. The record has one owner, so the compiled code writes the
;; field where it is; an unrestricted record is copied instead, since
;; someone else may hold it. The book's ownership chapter includes the
;; text between ANCHOR and ANCHOR_END.
;; ANCHOR: retry
(record Job
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
(record (Labelled A)
  ((item A)
   (label String)))

(define (relabel (labelled (Labelled A))) (→ (Labelled A)) (∀ (A))
  (Labelled-label-set labelled "relabelled"))

;; A replacement is a function too, and consumes the record it is given.
(define (bump (replace (Fn Job I64 → Job)) (job Job)) (→ Job)
  (replace job 5))

(define (main) (→ Unit) (! output-port)
  (run (retry (retry (new Job
                       (name "build")
                       (attempts 0)
                       (work (once (lambda () (write-line "built"))))))))
  (run (bump Job-attempts-set
             (new Job
               (name "deploy")
               (attempts 0)
               (work (once (lambda () (write-line "deployed")))))))
  (let* ((original (new Labelled (item 1) (label "original"))) (changed (relabel original)))
    (write-line (string-append (● original label) ", " (● changed label))))
  (match (relabel (new Labelled
                    (item (new Job
                            (name "test")
                            (attempts 0)
                            (work (once (lambda () (write-line "tested"))))))
                    (label "job")))
    ((Labelled job label)
     (write-line label)
     (run job)))
  (unit))

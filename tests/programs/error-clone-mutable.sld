(import
 (snail core base))

;; A clone could only share a mutable field's content, so glue does not
;; copy a record with one.
(struct Job
  ((work (FnOnce Unit))
   (runs mut I64)))

(: copies (-> Job (Pair Job Job)))
(define (copies job)
  (clone job))

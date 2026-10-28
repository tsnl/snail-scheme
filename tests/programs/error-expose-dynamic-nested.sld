(import
 (snail core base))

;; A function inside a parameter's fields is as opaque to a TypeId as a
;; function parameter.
(struct Job
  ((name String)
   (run (-> I64 I64))))

(: job-name (-> Job String))
(define (job-name job)
  (Job-name job))

(expose job-name "job-name" dynamic)

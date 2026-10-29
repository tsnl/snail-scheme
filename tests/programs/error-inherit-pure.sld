(import
 (snail core base)
 (only (snail core forms) host))

;; Calling work closed over its handlers performs whatever its handlers
;; and the host do, which a total function may not.
(: run (-> (Once (-> Unit ! host)) Unit))
(define (run work)
  (work))

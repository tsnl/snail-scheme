(import
 (snail core base)
 (siegework world)
 (siegework colony)
 (siegework simulation))

;; The same deterministic simulation on both revisions, without rendering,
;; host events or engine startup in the timed region.
(define (colony (seed I64)) (→ I64)
  (let* ((world (new-world seed))
         (started (match (act world (Build (Extractor) (● world land starter) #f))
                    ((Ok world) world)
                    ((Err _) (panic "the starting extractor must be buildable")))))
    (let loop ((world started) (remaining 2000))
      (if (or (= remaining 0) (not (playing? world)))
          (+ (* (● world tick) 1000000)
             (+ (* (● world ledger kills) 1000) (● world hub health)))
          (loop (advance world) (- remaining 1))))))

(define (simulate (count I64)) (→ I64)
  (let loop ((left count) (checksum 0))
    (if (= left 0) checksum
        (loop (- left 1) (+ checksum (colony (+ 1 (modulo left 8))))))))

(expose simulate "simulate")
(define (main) (→ Unit) (unit))

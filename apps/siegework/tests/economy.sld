;; A scripted colony: build an extractor on the starter deposit and check
;; that ore flows back to the hub and is conserved, then that the first wave
;; arrives.
(import
 (lofi base)
 (lofi io)
 (siegework grid)
 (siegework world))

(: run (-> World I64 World))
(define (run world ticks)
  (if (= ticks 0) world (run (advance world) (- ticks 1))))

(: expect-ok (-> (Result World String) World))
(define (expect-ok result)
  (match result
    ((Ok world) world)
    ((Err message) (panic message))))

(: summary (-> World String))
(define (summary world)
  (string-join (list (string-append "tick " (show (World-tick world)))
                     (string-append "ore " (show (World-ore world)))
                     (string-append "buildings " (show (length (World-buildings world))))
                     (string-append "workers " (show (length (World-workers world))))
                     (string-append "enemies " (show (length (World-enemies world)))))
               ", "))

;; Ore in the bank, carried by workers, stocked in extractors and left in
;; deposits. Only spending changes it before enemies destroy anything.
(: total-ore (-> World I64))
(define (total-ore world)
  (+ (World-ore world)
     (+ (fold-left + 0 (map Worker-ore (World-workers world)))
        (+ (fold-left + 0 (map Building-stock (World-buildings world)))
           (fold-left + 0 (map Deposit-reserve (World-deposits world)))))))

(: first-deposit (-> World Cell))
(define (first-deposit world)
  (match (World-deposits world)
    ((Cons deposit _) (Deposit-cell deposit))
    ((Nil) (panic "no deposits"))))

(let ()
  (define world (new-world 7))
  (define before (total-ore world))
  (write-line (summary world))
  (define world (expect-ok (place world (Extractor) (first-deposit world))))
  (write-line (World-message world))
  (define world (run world 300))
  (write-line (summary world))
  (write-line (string-append "ore conserved: " (show (= (total-ore world) (- before 25)))))
  (define world (run world 400))
  (write-line (summary world)))

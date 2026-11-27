(import
 (snail core base)
 (snail core io)
 (only (snail shell app) frame-pacer pace-frame!))

(define (check (yes Bool) (why String)) (→ Unit) (unless yes (panic why)))

;; Feed integer timestamps from a fixed-rate display and require exactly
;; thirty presentations per second, including on non-divisible refresh rates.
(define (display-rate (hz I64)) (→ Unit)
  (let ((p (frame-pacer 30)))
    (check (match (pace-frame! p 0) ((Some 0) #t) (_ #f)) "first refresh")
    (let loop ((i 1) (previous 0) (drawn 0) (last 0) (count 0))
      (if (> i (* 3 hz)) (check (= count 90) "presentation rate")
          (let ((stamp (quotient (+ (* i 1000) (quotient hz 2)) hz)))
            (match (pace-frame! p (i64->i32 (- stamp previous)))
              ((Some ms)
               (check (= (i32->i64 ms) (- stamp drawn)) "lost display time")
               (check (and (>= (- i last) (quotient hz 30))
                           (<= (- i last) (quotient (+ hz 29) 30))) "uneven display slots")
               (loop (+ i 1) stamp stamp i (+ count 1)))
              (_ (loop (+ i 1) stamp drawn last count))))))))

(define (main (out OutputPort)) (→ Unit)
  (for-each display-rate (list 30 60 72 75 90 120 144 165))
  (let ((p (frame-pacer 30)))
    (pace-frame! p 0)
    (check (match (pace-frame! p 200) ((Some 200) #t) (_ #f)) "missed presentation")
    (check (match (pace-frame! p 17) ((None) #t) (_ #f)) "burst after a stall")
    (check (match (pace-frame! p 16) ((Some 33) #t) (_ #f)) "failed to resume cadence"))
  (write-line out "Fixed presentation rate on eight display refresh rates"))

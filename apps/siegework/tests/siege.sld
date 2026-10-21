;; Waves against two colonies from the same seed: one defended by guns
;; beside the hub, one not.
(import
 (lofi base)
 (lofi io)
 (siegework grid)
 (siegework world))

(: run (-> World I64 World))
(define (run world ticks)
  (if (or (= ticks 0) (not (match (World-outcome world) ((Playing) #t) (_ #f))))
      world
      (run (advance world) (- ticks 1))))

(: order (-> World Kind Cell World))
(define (order world kind cell)
  (match (place world kind cell)
    ((Ok world) world)
    ((Err message) (panic message))))

(: report (-> String World Unit ! console))
(define (report name world)
  (write-line (string-append name ": tick " (show (World-tick world))
                             ", buildings " (show (length (World-buildings world)))
                             ", nests " (show (length (World-nests world)))
                             ", " (match (World-outcome world) ((Playing) "playing") ((Won) "won") ((Lost) "lost")))))

;; Guns on the open cells beside the hub, with ore to pay for them.
(: defended (-> World World))
(define (defended world)
  (let loop ((cells (neighbors (world-hub world))) (world (World-ore-set world 200)))
    (match cells
      ((Nil) world)
      ((Cons cell rest) (match (place world (Gun) cell)
                          ((Ok next) (loop rest next))
                          ((Err _) (loop rest world)))))))

(report "undefended" (run (new-world 11) 6000))
(report "defended" (run (defended (new-world 11)) 2000))

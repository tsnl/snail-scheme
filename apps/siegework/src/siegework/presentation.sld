;; Pure display values derived from committed model time. Neither camera
;; animation nor the GPU interpolation clock advances these game rules.
(define-library (siegework presentation)
  (export DifficultyReadout project-difficulty difficulty-number difficulty-elapsed
          difficulty-span difficulty-summary difficulty-help elapsed-time-text result-statistics)
  (import
   (scheme base)
   (browser application)
   (siegework model)
   (only (lofi core) datatype I32)
   (only (lofi base) string-append))
  (begin

    ;; ---- Active time and honest final totals from the authoritative ledgers ----

    (define (elapsed-time-text tick)
      (let ((seconds (quotient tick simulation-ticks-per-second)))
        (string-append (integer-text (quotient seconds 60)) ":"
                       (if (< (remainder seconds 60) 10) "0" "")
                       (integer-text (remainder seconds 60)))))
    (define (result-statistics world)
      (string-append "Time " (elapsed-time-text (world-tick world)) " · Kills " (integer-text (world-kills world))
                     "\nOre mined " (integer-text (world-produced world)) " · Net spent " (integer-text (world-spent world))
                     "\nBuildings " (integer-text (list-size (world-buildings world))) " · Lost " (integer-text (world-lost world))
                     "\nDrones " (integer-text (list-size (world-bots world))) " · Lost " (integer-text (world-casualties world))
                     "\nNests cleared " (integer-text (- 3 (living-nests (world-nests world)))) "/3 · Ore lost " (integer-text (world-lost-ore world))
                     "\nBank " (integer-text (world-credits world)) " ore · Seed " (integer-text (world-seed world))))

    ;; ---- A model interval becomes one consistent readout ----

    (define DifficultyReadout
      (datatype ()
        (difficulty-readout
         (number I32 difficulty-number)
         (elapsed I32 difficulty-elapsed)
         (span I32 difficulty-span)
         (summary String difficulty-summary)
         (help String difficulty-help))))
    (define (ceiling-seconds ticks)
      (quotient (+ ticks (- simulation-ticks-per-second 1)) simulation-ticks-per-second))
    (define (bounded-elapsed tick start span)
      (if (< tick start) 0 (if (> (- tick start) span) span (- tick start))))
    (define (project-difficulty window tick)
      (let ((number (+ 1 (difficulty-tier window))) (end (difficulty-end window)))
        (if (= end 0)
            (difficulty-readout number 1 1 "Maximum difficulty" "Maximum difficulty reached")
            (let* ((span (- end (difficulty-start window)))
                   (elapsed (bounded-elapsed tick (difficulty-start window) span))
                   (seconds (integer-text (ceiling-seconds (- span elapsed)))))
              (difficulty-readout number elapsed span (string-append "Difficulty rises in " seconds "s")
                                  (string-append "Difficulty " (integer-text number) "; increases in " seconds " seconds"))))))))

;; Orders dismiss the first step immediately; completed extractors leave a
;; permanent deposit-centered survey, even if the structure is later destroyed.
(define-library (siegework guidance)
  (export extractor-start? starter-deposit)
  (import
   (scheme base)
   (siegework model)
   (siegework terrain)
   (siegework planning))
  (begin
    (define (extraction-survey? seed surveys)
      (and (not (null? surveys))
           (or (> (deposit-rate seed (survey-x (car surveys)) (survey-y (car surveys))) 0)
               (extraction-survey? seed (cdr surveys)))))
    (define (extractor-start? world)
      (and (= (world-outcome world) 0) (= (count-mines (world-buildings world)) 0)
           (not (extraction-survey? (world-seed world) (world-surveys world)))))
    ;; Share the planner's eligibility, yield preference and stable tie break.
    ;; The actual order still checks prices and colony capacity.
    (define (starter-deposit world)
      (if (extractor-start? world) (known-deposit world) -1))))

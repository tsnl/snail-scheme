;; Optional colony purchasing uses only current observation and public orders.
;; Manual and automatic orders share prices, kit ownership, routes and workers.
(define-library (siegework planning)
  (export plan-world known-deposit)
  (import
   (scheme base)
   (scheme immutable)
   (siegework model)
   (siegework terrain))
  (begin

    ;; ---- Known opportunities and a small construction budget ----

    (define (count-kind buildings kind armed)
      (if (null? buildings) 0
          (+ (if (and (ready? (car buildings))
                      (if armed (armed? (car buildings)) (= (building-kind (car buildings)) kind))) 1 0)
             (count-kind (cdr buildings) kind armed))))
    (define (assembling? bots)
      (and (not (null? bots)) (or (= (bot-job (car bots)) 6) (assembling? (cdr bots)))))
    (define (budget? world kind)
      (and (>= (world-credits world) 40) (affordable-kit? world (building-cost kind))
           (or (>= (world-credits world) (+ 40 (building-cost kind)))
               (local-affordable? world (world-buildings world) (building-cost kind)))))
    (define (available-deposit? world x y)
      (and (visible? world x y) (> (deposit-rate (world-seed world) x y) 0)
           (null? (building-at (world-buildings world) x y)) (safe-site? world x y)))
    (define (known-deposit world) (find-known-deposit world 0 -1))
    (define (find-known-deposit world index best)
      (if (= index (* map-width map-height)) best
          (let ((x (index-x index)) (y (index-y index)))
            (find-known-deposit world (+ index 1)
                                (if (and (available-deposit? world x y)
                                         (or (< best 0) (> (deposit-rate (world-seed world) x y)
                                                           (deposit-rate (world-seed world) (index-x best) (index-y best))))) index best)))))
    (define (spaced? buildings kind x y)
      (or (null? buildings)
          (and (or (not (= (building-kind (car buildings)) kind))
                   (not (within? x y (building-x (car buildings)) (building-y (car buildings)) (if (= kind 3) 4 2))))
               (spaced? (cdr buildings) kind x y))))

    ;; ---- Greedy sight gain counts unknown cells without reading their contents ----

    (define (sight-gain world x y index)
      (if (= index 225) 0
          (let ((a (+ x (- (remainder index 15) 7))) (b (+ y (- (quotient index 15) 7))))
            (+ (if (and (inside? a b) (within? x y a b 7)
                        (not (surveyed? (world-surveys world) a b))) 1 0)
               (sight-gain world x y (+ index 1))))))
    (define (deposit-service world x y index)
      (if (= index (* map-width map-height)) 0
          (let ((a (index-x index)) (b (index-y index)))
            (+ (if (and (visible? world a b) (> (deposit-rate (world-seed world) a b) 0)
                        (within? x y a b 4) (spaced? (world-buildings world) 3 a b)) 35 0)
               (deposit-service world x y (+ index 1))))))

    ;; ---- Defense covers known approaches to the hub and owned operations ----

    (define (gun-covers? world building x y)
      (and (ready? building) (armed? building) (within? x y (building-x building) (building-y building) 8)
           (observed-shot? (world-seed world) (world-surveys world)
                           (cell-x (building-x building)) (cell-y (building-y building)) (cell-x x) (cell-y y))))
    (define (coverage world buildings x y)
      (if (null? buildings) 0
          (+ (if (gun-covers? world (car buildings) x y) 1 0) (coverage world (cdr buildings) x y))))
    (define (desired-coverage world) (+ 2 (threat-tier (world-tick world))))
    (define (guard-point world x y a b)
      (if (and (visible? world a b) (ground? (world-seed world) a b) (within? x y a b 8)
               (< (coverage world (world-buildings world) a b) (desired-coverage world))
               (observed-shot? (world-seed world) (world-surveys world) (cell-x x) (cell-y y) (cell-x a) (cell-y b)))
          (- (+ 1 (desired-coverage world)) (coverage world (world-buildings world) a b)) 0))
    (define (guard-asset world x y a b)
      (+ (* 4 (guard-point world x y (+ a 4) b))
         (+ (guard-point world x y a (- b 3)) (guard-point world x y a (+ b 3)))))
    (define (guard-buildings world x y buildings)
      (if (null? buildings) 0
          (+ (if (and (ready? (car buildings)) (not (armed? (car buildings))))
                 (guard-asset world x y (building-x (car buildings)) (building-y (car buildings))) 0)
             (guard-buildings world x y (cdr buildings)))))
    (define (site-score world kind x y)
      (if (= kind 3) (+ (sight-gain world x y 0) (deposit-service world x y 0))
          (+ (guard-asset world x y hub-x hub-y) (guard-buildings world x y (world-buildings world)))))
    (define (choose-site world kind index best score)
      (if (= index (* map-width map-height)) best
          (let* ((x (index-x index)) (y (index-y index))
                 (legal (and (= (placement-reason world kind x y) 0) (spaced? (world-buildings world) kind x y)))
                 (value (if legal (site-score world kind x y) 0))
                 (better (and (> value score) (safe-site? world x y))))
            (choose-site world kind (+ index 1) (if better index best) (if better value score)))))
    (define (build-focus world kind code)
      (if (not (budget? world kind)) (world-plan-set world 2)
          (let ((site (choose-site world kind 0 -1 (if (= kind 3) 31 0))))
            (if (< site 0) (if (= kind 2) (build-focus world 3 5) (world-plan-set world 7))
                (world-plan-set (automatic-world world kind (index-x site) (index-y site)) code)))))

    ;; ---- Extraction first; focus decides the next discretionary investment ----

    (define (develop-colony world deposit)
      (let ((mines (count-mines (world-buildings world))) (workers (list-size (world-bots world))))
        (cond ((and (or (< workers 3) (and (>= deposit 0) (< workers (+ mines 3))))
                    (< workers 12) (>= (world-credits world) 65))
               (world-plan-set (fabricate-world world) 3))
              ((and (>= deposit 0) (>= workers (+ mines 2)) (budget? world 1))
               (world-plan-set (automatic-world world 1 (index-x deposit) (index-y deposit)) 4))
              ((and (> mines 0) (< (count-kind (world-buildings world) 2 #t) (+ 1 (threat-tier (world-tick world))))) (build-focus world 2 6))
              ((= (world-focus world) 1) (build-focus world 3 5))
              (else (build-focus world 2 6)))))
    (define (plan-world world)
      (cond ((or (= (world-focus world) 0) (not (= (world-outcome world) 0)) (= (world-paused world) 1)) world)
            ((pending-move? (world-buildings world)) (world-plan-set world 9))
            ((pending-build? (world-buildings world)) (world-plan-set world 1))
            ((assembling? (world-bots world)) (world-plan-set world 3))
            ((not (= (remainder (world-tick world) 10) 0)) world)
            (else (develop-colony world (known-deposit world)))))))

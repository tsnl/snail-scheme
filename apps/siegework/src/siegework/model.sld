;; Siegework's complete simulation. Every operation returns a new World; no
;; simulation state lives in a module global, browser object, or GPU resource.
(define-library (siegework model)
  (export World initial-world world-tick world-outcome world-credits world-hull
          world-kills world-mine world-bot world-turrets world-enemies world-next-id
          make-world Mine make-mine mine-x mine-y mine-level mine-stock
          Bot make-bot bot-x bot-y bot-cargo bot-homeward
          Turret make-turret turret-x turret-y turret-cooldown
          Enemy make-enemy enemy-id enemy-x enemy-y enemy-hp enemy-boss
          advance-world extract-world fortify-world upgrade-world repair-world
          cell-x cell-y distance list-size
          board-columns board-rows cell-size board-width board-height hub-x hub-y
          near-deposit-x near-deposit-y far-deposit-x far-deposit-y
          extractor-cost artillery-cost max-hull max-turrets
          ticks-per-second beast-arrival-tick beast-warning-tick run-end-tick beast-hp
          outcome-active outcome-lost outcome-repelled outcome-exterminated)
  (import
   (scheme base)
   (scheme immutable)
   (only (lofi core) ann I32))
  (begin

    ;; ---- Map geometry ----

    (define board-columns (ann 24 I32))
    (define board-rows (ann 14 I32))
    (define cell-size (ann 40 I32))
    (define cell-center (quotient cell-size 2))
    (define board-width (* board-columns cell-size))
    (define board-height (* board-rows cell-size))
    (define hub-x (ann 140 I32))
    (define hub-y (ann 300 I32))
    (define near-deposit-x (ann 8 I32))
    (define near-deposit-y (ann 3 I32))
    (define far-deposit-x (ann 18 I32))
    (define far-deposit-y (ann 10 I32))
    (define defense-first-column (ann 4 I32))
    (define defense-column-limit (ann 22 I32))
    (define defense-first-row (ann 1 I32))
    (define defense-row-limit (ann 13 I32))

    ;; ---- Economy ----

    (define initial-credits (ann 110 I32))
    (define max-hull (ann 100 I32))
    (define extractor-cost (ann 30 I32))
    (define artillery-cost (ann 45 I32))
    (define upgrade-cost (ann 55 I32))
    (define repair-cost (ann 30 I32))
    (define repair-hull (ann 35 I32))
    (define max-turrets (ann 8 I32))
    (define mine-stock-limit (ann 120 I32))
    (define ore-per-level (ann 4 I32))
    (define bot-speed (ann 8 I32))
    (define near-cargo-per-level (ann 24 I32))
    (define far-cargo-per-level (ann 60 I32))

    ;; ---- Waves and combat ----

    (define ticks-per-second (ann 10 I32))
    (define first-wave-tick (ann 200 I32))
    (define last-wave-tick (ann 800 I32))
    (define wave-period (ann 60 I32))
    (define wave-phase (ann 20 I32))
    (define beast-warning-tick (ann 650 I32))
    (define beast-arrival-tick (ann 850 I32))
    (define run-end-tick (ann 1200 I32))
    (define spawn-x (ann 920 I32))
    (define first-lane-y (ann 180 I32))
    (define lane-count (ann 3 I32))
    (define lane-spacing (ann 120 I32))
    (define raider-initial-hp (ann 28 I32))
    (define raider-hp-growth (ann 8 I32))
    (define raider-growth-period (ann 200 I32))
    (define beast-hp (ann 620 I32))
    (define raider-speed (ann 3 I32))
    (define beast-speed (ann 2 I32))
    (define approach-turn-x (ann 160 I32))
    (define artillery-range (ann 220 I32))
    (define artillery-damage (ann 18 I32))
    (define artillery-period (ann 8 I32))
    (define hub-damage-range (ann 45 I32))
    (define raider-damage (ann 3 I32))
    (define beast-damage (ann 12 I32))
    (define kill-reward (ann 12 I32))

    ;; ---- Run outcomes ----

    (define outcome-active (ann 0 I32))
    (define outcome-lost (ann 1 I32))
    (define outcome-repelled (ann 2 I32))
    (define outcome-exterminated (ann 3 I32))

    ;; ---- Immutable world values ----

    (define-immutable-record Mine make-mine
      (x I32 mine-x mine-x-set)
      (y I32 mine-y mine-y-set)
      (level I32 mine-level mine-level-set)
      (stock I32 mine-stock mine-stock-set))
    (define-immutable-record Bot make-bot
      (x I32 bot-x bot-x-set)
      (y I32 bot-y bot-y-set)
      (cargo I32 bot-cargo bot-cargo-set)
      (homeward I32 bot-homeward bot-homeward-set))
    (define-immutable-record Turret make-turret
      (x I32 turret-x turret-x-set)
      (y I32 turret-y turret-y-set)
      (cooldown I32 turret-cooldown turret-cooldown-set))
    (define-immutable-record Enemy make-enemy
      (id I32 enemy-id enemy-id-set)
      (x I32 enemy-x enemy-x-set)
      (y I32 enemy-y enemy-y-set)
      (hp I32 enemy-hp enemy-hp-set)
      (boss I32 enemy-boss enemy-boss-set))
    (define-immutable-record World make-world
      (tick I32 world-tick world-tick-set)
      (outcome I32 world-outcome world-outcome-set)
      (credits I32 world-credits world-credits-set)
      (hull I32 world-hull world-hull-set)
      (kills I32 world-kills world-kills-set)
      (mine Mine world-mine world-mine-set)
      (bot Bot world-bot world-bot-set)
      (turrets (List Turret) world-turrets world-turrets-set)
      (enemies (List Enemy) world-enemies world-enemies-set)
      (next-id I32 world-next-id world-next-id-set))
    (define (initial-world)
      (make-world 0 outcome-active initial-credits max-hull 0 (make-mine 0 0 0 0)
                  (make-bot hub-x hub-y 0 0) (empty-list) (empty-list) 1))
    (define (cell-x x) (+ (* x cell-size) cell-center))
    (define (cell-y y) (+ (* y cell-size) cell-center))
    (define (absolute x) (if (< x 0) (- 0 x) x))
    (define (distance x y a b) (+ (absolute (- x a)) (absolute (- y b))))
    (define (list-size xs) (if (null? xs) (ann 0 I32) (+ 1 (list-size (cdr xs)))))
    (define (minimum a b) (if (< a b) a b))
    (define (approach value target speed)
      (if (< value target) (+ value (minimum speed (- target value)))
          (- value (minimum speed (- value target)))))

    ;; ---- Commands validate against the authoritative prior value ----

    (define (active? world) (= (world-outcome world) outcome-active))
    (define (ore? x y)
      (or (and (= x near-deposit-x) (= y near-deposit-y))
          (and (= x far-deposit-x) (= y far-deposit-y))))
    (define (extract-world world x y)
      (if (and (active? world) (= (mine-level (world-mine world)) 0)
               (>= (world-credits world) extractor-cost) (ore? x y))
          (world-mine-set (world-credits-set world (- (world-credits world) extractor-cost))
                          (make-mine x y 1 0)) world))
    (define (occupied? turrets x y)
      (and (not (null? turrets))
           (or (and (= (turret-x (car turrets)) x) (= (turret-y (car turrets)) y))
               (occupied? (cdr turrets) x y))))
    (define (fortify-world world x y)
      (if (and (active? world) (>= (world-credits world) artillery-cost)
               (< (list-size (world-turrets world)) max-turrets)
               (>= x defense-first-column) (< x defense-column-limit)
               (>= y defense-first-row) (< y defense-row-limit)
               (not (ore? x y)) (not (occupied? (world-turrets world) x y)))
          (world-turrets-set (world-credits-set world (- (world-credits world) artillery-cost))
                             (append (world-turrets world) (list (make-turret x y 0)))) world))
    (define (upgrade-world world)
      (let ((mine (world-mine world)))
        (if (and (active? world) (= (mine-level mine) 1) (>= (world-credits world) upgrade-cost))
            (world-mine-set (world-credits-set world (- (world-credits world) upgrade-cost))
                            (mine-level-set mine 2)) world)))
    (define (repair-world world)
      (if (and (active? world) (< (world-hull world) max-hull) (>= (world-credits world) repair-cost))
          (world-hull-set (world-credits-set world (- (world-credits world) repair-cost))
                          (minimum max-hull (+ (world-hull world) repair-hull))) world))

    ;; ---- Extraction and automatic hauling ----

    (define (produce mine tick)
      (if (and (> (mine-level mine) 0) (= (remainder tick ticks-per-second) 0))
          (mine-stock-set mine (minimum mine-stock-limit (+ (mine-stock mine) (* ore-per-level (mine-level mine))))) mine))
    (define (travel bot x y)
      (if (= (bot-x bot) x) (bot-y-set bot (approach (bot-y bot) y bot-speed))
          (bot-x-set bot (approach (bot-x bot) x bot-speed))))
    (define (haul world)
      (let* ((mine (produce (world-mine world) (world-tick world)))
             (world (world-mine-set world mine)) (bot (world-bot world)))
        (if (= (mine-level mine) 0) world
            (if (= (bot-homeward bot) 1) (haul-home world bot) (haul-mine world bot mine)))))
    (define (haul-home world bot)
      (if (and (= (bot-x bot) hub-x) (= (bot-y bot) hub-y))
          (world-bot-set (world-credits-set world (+ (world-credits world) (bot-cargo bot)))
                         (make-bot hub-x hub-y 0 0))
          (world-bot-set world (travel bot hub-x hub-y))))
    (define (haul-mine world bot mine)
      (let ((x (cell-x (mine-x mine))) (y (cell-y (mine-y mine))))
        (if (and (= (bot-x bot) x) (= (bot-y bot) y) (> (mine-stock mine) 0))
            (let ((cargo (minimum (mine-stock mine)
                                  (* (mine-level mine) (if (= (mine-x mine) far-deposit-x)
                                                           far-cargo-per-level near-cargo-per-level)))))
              (world-bot-set (world-mine-set world (mine-stock-set mine (- (mine-stock mine) cargo)))
                             (make-bot x y cargo 1)))
            (world-bot-set world (travel bot x y)))))

    ;; ---- Escalating waves and a final siege beast ----

    (define (spawn world boss)
      (let* ((id (world-next-id world)) (y (+ first-lane-y (* (remainder id lane-count) lane-spacing)))
             (hp (if (= boss 1) beast-hp
                     (+ raider-initial-hp (* raider-hp-growth (quotient (world-tick world) raider-growth-period))))))
        (world-next-id-set
         (world-enemies-set world (append (world-enemies world) (list (make-enemy id spawn-x y hp boss))))
         (+ id 1))))
    (define (spawn-due world)
      (let ((tick (world-tick world)))
        (cond ((= tick beast-arrival-tick) (spawn world 1))
              ((and (>= tick first-wave-tick) (<= tick last-wave-tick)
                    (= (remainder tick wave-period) wave-phase)) (spawn world 0))
              (else world))))
    (define (march enemies)
      (if (null? enemies) enemies
          (let* ((enemy (car enemies)) (speed (if (= (enemy-boss enemy) 1) beast-speed raider-speed))
                 (x (enemy-x enemy)) (y (enemy-y enemy)))
            (cons (if (> x approach-turn-x) (enemy-x-set enemy (approach x approach-turn-x speed))
                      (enemy-y-set enemy (approach y hub-y speed)))
                  (march (cdr enemies))))))
    (define (hit-nearest enemies x y)
      (if (null? enemies) enemies
          (let ((enemy (car enemies)))
            (if (and (> (enemy-hp enemy) 0) (< (distance x y (enemy-x enemy) (enemy-y enemy)) artillery-range))
                (cons (enemy-hp-set enemy (- (enemy-hp enemy) artillery-damage)) (cdr enemies))
                (cons enemy (hit-nearest (cdr enemies) x y))))))
    (define (fire turrets enemies)
      (if (null? turrets) enemies
          (let ((turret (car turrets)))
            (fire (cdr turrets)
                  (if (= (turret-cooldown turret) 0)
                      (hit-nearest enemies (cell-x (turret-x turret)) (cell-y (turret-y turret))) enemies)))))
    (define (cool turrets)
      (if (null? turrets) turrets
          (cons (turret-cooldown-set (car turrets) (remainder (+ 1 (turret-cooldown (car turrets))) artillery-period))
                (cool (cdr turrets)))))
    (define (survivors enemies)
      (if (null? enemies) enemies
          (if (> (enemy-hp (car enemies)) 0) (cons (car enemies) (survivors (cdr enemies)))
              (survivors (cdr enemies)))))
    (define (siege-damage enemies)
      (if (null? enemies) 0
          (+ (if (< (distance (enemy-x (car enemies)) (enemy-y (car enemies)) hub-x hub-y) hub-damage-range)
                 (if (= (enemy-boss (car enemies)) 1) beast-damage raider-damage) 0)
             (siege-damage (cdr enemies)))))
    (define (fight world)
      (let* ((before (world-enemies world)) (after (survivors (fire (world-turrets world) (march before))))
             (kills (- (list-size before) (list-size after)))
             (damage (if (= (remainder (world-tick world) ticks-per-second) 0) (siege-damage after) 0)))
        (world-hull-set
         (world-kills-set (world-credits-set
                           (world-enemies-set (world-turrets-set world (cool (world-turrets world))) after)
                           (+ (world-credits world) (* kills kill-reward))) (+ (world-kills world) kills))
         (- (world-hull world) damage))))
    (define (finish world)
      (world-outcome-set world
                         (cond ((<= (world-hull world) 0) outcome-lost)
                               ((and (>= (world-tick world) beast-arrival-tick) (null? (world-enemies world))) outcome-exterminated)
                               ((>= (world-tick world) run-end-tick) outcome-repelled) (else outcome-active))))
    (define (advance-world world)
      (if (active? world) (finish (fight (spawn-due (haul (world-tick-set world (+ 1 (world-tick world))))))) world))))

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
          cell-x cell-y distance list-size)
  (import
   (scheme base)
   (scheme immutable)
   (only (lofi core) ann I32))
  (begin

    ;; ---- Immutable values and rules of the fixed map ----

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
      (make-world 0 0 110 100 0 (make-mine 0 0 0 0)
                  (make-bot 140 300 0 0) (empty-list) (empty-list) 1))
    (define (cell-x x) (+ (* x 40) 20))
    (define (cell-y y) (+ (* y 40) 20))
    (define (absolute x) (if (< x 0) (- 0 x) x))
    (define (distance x y a b) (+ (absolute (- x a)) (absolute (- y b))))
    (define (list-size xs) (if (null? xs) (ann 0 I32) (+ 1 (list-size (cdr xs)))))
    (define (minimum a b) (if (< a b) a b))
    (define (approach value target speed)
      (if (< value target) (+ value (minimum speed (- target value)))
          (- value (minimum speed (- value target)))))

    ;; ---- Commands validate against the authoritative prior value ----

    (define (active? world) (= (world-outcome world) 0))
    (define (ore? x y) (or (and (= x 8) (= y 3)) (and (= x 18) (= y 10))))
    (define (extract-world world x y)
      (if (and (active? world) (= (mine-level (world-mine world)) 0)
               (>= (world-credits world) 30) (ore? x y))
          (world-mine-set (world-credits-set world (- (world-credits world) 30))
                          (make-mine x y 1 0)) world))
    (define (occupied? turrets x y)
      (and (not (null? turrets))
           (or (and (= (turret-x (car turrets)) x) (= (turret-y (car turrets)) y))
               (occupied? (cdr turrets) x y))))
    (define (fortify-world world x y)
      (if (and (active? world) (>= (world-credits world) 45)
               (< (list-size (world-turrets world)) 8) (>= x 4) (< x 22) (>= y 1) (< y 13)
               (not (ore? x y)) (not (occupied? (world-turrets world) x y)))
          (world-turrets-set (world-credits-set world (- (world-credits world) 45))
                             (append (world-turrets world) (list (make-turret x y 0)))) world))
    (define (upgrade-world world)
      (let ((mine (world-mine world)))
        (if (and (active? world) (= (mine-level mine) 1) (>= (world-credits world) 55))
            (world-mine-set (world-credits-set world (- (world-credits world) 55))
                            (mine-level-set mine 2)) world)))
    (define (repair-world world)
      (if (and (active? world) (< (world-hull world) 100) (>= (world-credits world) 30))
          (world-hull-set (world-credits-set world (- (world-credits world) 30))
                          (minimum 100 (+ (world-hull world) 35))) world))

    ;; ---- Extraction and automatic hauling ----

    (define (produce mine tick)
      (if (and (> (mine-level mine) 0) (= (remainder tick 10) 0))
          (mine-stock-set mine (minimum 120 (+ (mine-stock mine) (* 4 (mine-level mine))))) mine))
    (define (travel bot x y)
      (if (= (bot-x bot) x) (bot-y-set bot (approach (bot-y bot) y 8))
          (bot-x-set bot (approach (bot-x bot) x 8))))
    (define (haul world)
      (let* ((mine (produce (world-mine world) (world-tick world)))
             (world (world-mine-set world mine)) (bot (world-bot world)))
        (if (= (mine-level mine) 0) world
            (if (= (bot-homeward bot) 1) (haul-home world bot) (haul-mine world bot mine)))))
    (define (haul-home world bot)
      (if (and (= (bot-x bot) 140) (= (bot-y bot) 300))
          (world-bot-set (world-credits-set world (+ (world-credits world) (bot-cargo bot)))
                         (make-bot 140 300 0 0))
          (world-bot-set world (travel bot 140 300))))
    (define (haul-mine world bot mine)
      (let ((x (cell-x (mine-x mine))) (y (cell-y (mine-y mine))))
        (if (and (= (bot-x bot) x) (= (bot-y bot) y) (> (mine-stock mine) 0))
            (let ((cargo (minimum (mine-stock mine) (* (mine-level mine) (if (= (mine-x mine) 18) 60 24)))))
              (world-bot-set (world-mine-set world (mine-stock-set mine (- (mine-stock mine) cargo)))
                             (make-bot x y cargo 1)))
            (world-bot-set world (travel bot x y)))))

    ;; ---- Escalating waves and a final siege beast ----

    (define (spawn world boss)
      (let* ((id (world-next-id world)) (y (+ 180 (* (remainder id 3) 120)))
             (hp (if (= boss 1) 620 (+ 28 (* 8 (quotient (world-tick world) 200))))))
        (world-next-id-set
         (world-enemies-set world (append (world-enemies world) (list (make-enemy id 920 y hp boss))))
         (+ id 1))))
    (define (spawn-due world)
      (let ((tick (world-tick world)))
        (cond ((= tick 850) (spawn world 1))
              ((and (>= tick 200) (<= tick 800) (= (remainder tick 60) 20)) (spawn world 0))
              (else world))))
    (define (march enemies)
      (if (null? enemies) enemies
          (let* ((enemy (car enemies)) (speed (if (= (enemy-boss enemy) 1) 2 3))
                 (x (enemy-x enemy)) (y (enemy-y enemy)))
            (cons (if (> x 160) (enemy-x-set enemy (approach x 160 speed))
                      (enemy-y-set enemy (approach y 300 speed)))
                  (march (cdr enemies))))))
    (define (hit-nearest enemies x y)
      (if (null? enemies) enemies
          (let ((enemy (car enemies)))
            (if (and (> (enemy-hp enemy) 0) (< (distance x y (enemy-x enemy) (enemy-y enemy)) 220))
                (cons (enemy-hp-set enemy (- (enemy-hp enemy) 18)) (cdr enemies))
                (cons enemy (hit-nearest (cdr enemies) x y))))))
    (define (fire turrets enemies)
      (if (null? turrets) enemies
          (let ((turret (car turrets)))
            (fire (cdr turrets)
                  (if (= (turret-cooldown turret) 0)
                      (hit-nearest enemies (cell-x (turret-x turret)) (cell-y (turret-y turret))) enemies)))))
    (define (cool turrets)
      (if (null? turrets) turrets
          (cons (turret-cooldown-set (car turrets) (remainder (+ 1 (turret-cooldown (car turrets))) 8))
                (cool (cdr turrets)))))
    (define (survivors enemies)
      (if (null? enemies) enemies
          (if (> (enemy-hp (car enemies)) 0) (cons (car enemies) (survivors (cdr enemies)))
              (survivors (cdr enemies)))))
    (define (siege-damage enemies)
      (if (null? enemies) 0
          (+ (if (< (distance (enemy-x (car enemies)) (enemy-y (car enemies)) 140 300) 45)
                 (if (= (enemy-boss (car enemies)) 1) 12 3) 0)
             (siege-damage (cdr enemies)))))
    (define (fight world)
      (let* ((before (world-enemies world)) (after (survivors (fire (world-turrets world) (march before))))
             (kills (- (list-size before) (list-size after)))
             (damage (if (= (remainder (world-tick world) 10) 0) (siege-damage after) 0)))
        (world-hull-set
         (world-kills-set (world-credits-set
                           (world-enemies-set (world-turrets-set world (cool (world-turrets world))) after)
                           (+ (world-credits world) (* kills 12))) (+ (world-kills world) kills))
         (- (world-hull world) damage))))
    (define (finish world)
      (world-outcome-set world
                         (cond ((<= (world-hull world) 0) 1)
                               ((and (>= (world-tick world) 850) (null? (world-enemies world))) 3)
                               ((>= (world-tick world) 1200) 2) (else 0))))
    (define (advance-world world)
      (if (active? world) (finish (fight (spawn-due (haul (world-tick-set world (+ 1 (world-tick world))))))) world))))

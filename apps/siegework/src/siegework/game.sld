(define-library (siegework game)
  (export application-entry)
  (import (scheme base) (scheme immutable) (application reducer) (application bridge)
          (browser application) (siegework model) (siegework codec)
          (only (lofi core) ann -> I32)
          (only (lofi base) string-append i32->i64 unreachable))
  (begin

    ;; ---- Commands are lexical bindings; all reducers return Transition World ----

    (application match-app (state World 1) (initial-world)
                 (advance (state) (no-effects (advance-world state)))
                 (extract (state (x I32) (y I32)) (no-effects (extract-world state x y)))
                 (fortify (state (x I32) (y I32)) (no-effects (fortify-world state x y)))
                 (upgrade (state) (no-effects (upgrade-world state)))
                 (repair (state) (no-effects (repair-world state)))
                 (new-run (state) (no-effects (initial-world))))

    (define match-target (destination match-owner match-app))

    ;; ---- The client has a separate persistent owner ----

    (define-immutable-record Client make-client
      (tool I32 client-tool with-client-tool) (x I32 client-x with-client-x)
      (y I32 client-y with-client-y))
    (application client-app (state Client 1) (make-client 1 8 3)
                 (move (state (x I32) (y I32))
                       (no-effects (if (and (>= x 0) (< x 24) (>= y 0) (< y 14))
                                       (make-client (client-tool state) x y) state)))
                 (nudge (state (dx I32) (dy I32))
                        (no-effects (make-client (client-tool state)
                                                 (clamp (+ (client-x state) dx) 0 23) (clamp (+ (client-y state) dy) 0 13))))
                 (choose (state (tool I32))
                         (no-effects (if (and (>= tool 1) (<= tool 2)) (with-client-tool state tool) state)))
                 (confirm (state)
                          (transition state (list (enqueue match-target
                                                           (if (= (client-tool state) 1) (extract (client-x state) (client-y state))
                                                               (fortify (client-x state) (client-y state)))))))
                 (improve (state) (transition state (list (enqueue match-target (upgrade)))))
                 (mend (state) (transition state (list (enqueue match-target (repair)))))
                 (restart (state) (transition state (list (enqueue match-target (new-run))))))
    (define (clamp value low high) (if (< value low) low (if (> value high) high value)))
    (define (encode-client client)
      (vector 1 (client-tool client) (client-x client) (client-y client)))
    (define decode-client
      (ann (lambda (words)
             (when (or (not (= (vector-ref words (i32->i64 0)) 1))
                       (< (vector-ref words (i32->i64 1)) 1) (> (vector-ref words (i32->i64 1)) 2)
                       (< (vector-ref words (i32->i64 2)) 0) (> (vector-ref words (i32->i64 2)) 23)
                       (< (vector-ref words (i32->i64 3)) 0) (> (vector-ref words (i32->i64 3)) 13)) (unreachable))
             (make-client (vector-ref words (i32->i64 1)) (vector-ref words (i32->i64 2)) (vector-ref words (i32->i64 3))))
           (-> (Vector I32) Client)))

    ;; ---- Pure presentation: quads and a status string ----

    (define (rect x y w h color) (quad x y w h color 255))
    (define (tile x y color) (rect (+ (* x 40) 3) (+ (* y 40) 3) 34 34 color))
    (define (grid index)
      (if (= index 24) (empty-list)
          (cons (rect (* index 40) 0 1 560 2373432)
                (if (< index 14) (cons (rect 0 (* index 40) 960 1 2373432) (grid (+ index 1)))
                    (grid (+ index 1))))))
    (define (turret-quads turrets)
      (if (null? turrets) (empty-list)
          (let ((turret (car turrets)))
            (cons (tile (turret-x turret) (turret-y turret) 16036940)
                  (cons (rect (+ (cell-x (turret-x turret)) 2) (- (cell-y (turret-y turret)) 4) 25 8 16769709)
                        (turret-quads (cdr turrets)))))))
    (define (enemy-quads enemies)
      (if (null? enemies) (empty-list)
          (let* ((enemy (car enemies)) (size (if (= (enemy-boss enemy) 1) 44 18)))
            (cons (rect (- (enemy-x enemy) (quotient size 2)) (- (enemy-y enemy) (quotient size 2))
                        size size (if (= (enemy-boss enemy) 1) 13640083 15750780))
                  (cons (rect (- (enemy-x enemy) (quotient size 2)) (- (enemy-y enemy) (+ 5 (quotient size 2)))
                              (quotient (* size (enemy-hp enemy)) (if (= (enemy-boss enemy) 1) 620 60)) 3 16760503)
                        (enemy-quads (cdr enemies)))))))
    (define (economy-quads world)
      (let ((mine (world-mine world)) (bot (world-bot world)))
        (append (list (tile 8 3 3244661) (tile 18 10 3244661))
                (if (= (mine-level mine) 0) (empty-list)
                    (list (tile (mine-x mine) (mine-y mine) 5692863)
                          (rect (- (bot-x bot) 7) (- (bot-y bot) 7) 14 14 11599863)
                          (rect (- (bot-x bot) 7) (- (bot-y bot) 12) (quotient (bot-cargo bot) 2) 3 16036940))))))
    (define (view world client)
      (append (list (rect 0 0 960 560 1055781))
              (append (grid 0)
                      (append (economy-quads world)
                              (append (list (rect 118 278 44 44 14871019)
                                            (rect 116 330 (quotient (* (world-hull world) 48) 100) 4 5692863))
                                      (append (turret-quads (world-turrets world))
                                              (append (enemy-quads (world-enemies world))
                                                      (list (quad (+ (* (client-x client) 40) 1) (+ (* (client-y client) 40) 1) 38 38
                                                                  (if (= (client-tool client) 1) 5692863 16036940) 75)))))))))
    (define (status world client)
      (string-append
       (cond ((= (world-outcome world) 1) "HUB LOST — begin another run")
             ((= (world-outcome world) 2) "SIEGE REPELLED — your hub survived")
             ((= (world-outcome world) 3) "THREAT EXTERMINATED — the field is yours")
             ((>= (world-tick world) 850) "THE SIEGE BEAST HAS ARRIVED")
             ((>= (world-tick world) 650) "WARNING · giant approaching at 85s")
             (else "BUILD YOUR ECONOMY · FORTIFY THE APPROACH"))
       "\n" (integer-text (world-credits world)) " ore   ·   " (integer-text (world-hull world))
       "% hub   ·   " (integer-text (quotient (world-tick world) 10)) "/120s   ·   "
       (integer-text (world-kills world)) " threats defeated"
       "   ·   cargo " (integer-text (bot-cargo (world-bot world))) "\n"
       (if (= (client-tool client) 1) "EXTRACTOR · 30 ore · choose a turquoise deposit"
           "ARTILLERY · 45 ore · protect the hub and eastern approach")
       "   [" (integer-text (client-x client)) ", " (integer-text (client-y client)) "]"))

    ;; ---- App-owned schema codecs compose with the shared scalar driver ----

    (define game
      (program match-app client-app world-words 4 decode-world encode-world
               decode-client encode-client view status))
    (define application-entry (ann (lambda (operation a b c) (run-program game operation a b c))
                                   (-> I32 I32 I32 I32 I32)))))

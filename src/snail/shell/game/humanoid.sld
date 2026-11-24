;; A gait is measured in distance travelled. Turning in place and pressing
;; forward into a wall leave the feet planted. Aim and sitting ease in
;; independently of stride so an actor can raise an arm while walking.
(define-library (snail shell game humanoid)
  (export Activity
          Standing
          Striding
          Bracing
          Riding
          Gait Gait-seat-set
          between-gaits
          resting
          animate
          Pose
          pose
          Humanoid
          humanoid-pose)
  (import
   (snail core base)
   (snail shell math)
   (snail shell wire)
   (snail shell graphics animation))
  (begin
    (enum Activity (Standing) (Striding) (Bracing) (Riding))
    (record Gait
      ((phase F64)
       (stride F64)
       (arm F64)
       (seat F64))
      (deriving Serialize Deserialize))

    (define resting (→ Gait) (new Gait (phase 0.0) (stride 0.0) (arm 0.0) (seat 0.0)))

    (define (between-gaits (a Gait) (b Gait) (t F64)) (→ Gait)
      (let ((mix (lambda ((x F64) (y F64)) (→ F64) (+ x (* t (- y x))))))
        (new Gait (phase (mix (● a phase) (● b phase))) (stride (mix (● a stride) (● b stride)))
             (arm (mix (● a arm) (● b arm))) (seat (mix (● a seat) (● b seat))))))

    (define (approach (v F64) (target F64) (amount F64)) (→ F64)
      (+ v (max (negate amount) (min amount (- target v)))))

    (define (animate (g Gait) (activity Activity) (metres F64) (dt F64)) (→ Gait)
      (let ((seated (match activity ((Riding) #t) (_ #f)))
            (moving (and (> metres 0.001) (match activity ((Striding) #t) ((Bracing) #t) (_ #f)))))
        (new Gait (phase (if moving (+ (● g phase) (* metres 4.2)) (● g phase)))
             (stride (approach (● g stride) (if moving 1.0 0.0) (* dt 8.0)))
             (arm (approach (● g arm) (match activity ((Bracing) 1.0) (_ 0.0)) (* dt 11.0)))
             (seat (approach (● g seat) (if seated 1.0 0.0) (* dt 7.0))))))

    ;; Clip names and the spine branch come from the asset's author. The gait
    ;; controls their weights; its stride phase advances in metres, not time.
    (record Humanoid
      ((rig Rig)
       (idle Clip)
       (walk Clip)
       (brace Clip)
       (drive Clip)
       (upper-body (List I64))))
    (define (sample-loop (rig Rig) (clip Clip) (seconds F64)) (→ (Array Transform))
      (sample-pose rig clip (clip-time clip seconds #t)))
    (define (locomotion (h Humanoid) (g Gait) (clock F64)) (→ (Array Transform))
      (let* ((rig (● h rig)) (weight (f64->f32 (● g stride))) (walk (● h walk))
             (phase (* (/ (● g phase) (* 2.0 pi)) (● walk duration))))
        (cond ((<= weight 0.0) (sample-loop rig (● h idle) clock))
              ((>= weight 1.0) (sample-loop rig walk phase))
              (else (blend-poses (sample-loop rig (● h idle) clock)
                                 (sample-loop rig walk phase)
                                 weight)))))
    (define (humanoid-pose (h Humanoid) (g Gait) (clock F64) (action-time F64))
      (→ (Array Transform))
      (let ((rig (● h rig)) (seat (f64->f32 (● g seat))) (arm (f64->f32 (● g arm))))
        (if (>= seat 1.0) (sample-loop rig (● h drive) clock)
            (let* ((feet (locomotion h g clock))
                   (armed (if (<= arm 0.0) feet
                              (blend-branch feet
                                            (sample-pose rig (● h brace) action-time)
                                            arm
                                            (● h upper-body)))))
              (if (<= seat 0.0)
                  armed
                  (blend-poses armed (sample-loop rig (● h drive) clock) seat))))))

    ;; Offsets in metres in the rig's own space. The feet move in
    ;; opposition, the trailing arm balances the leading leg.
    (record Pose
      ((step F64)
       (left-lift F64)
       (right-lift F64)
       (bob F64)
       (reach F64)
       (seat F64)))

    (define (pose (g Gait)) (→ Pose)
      (let ((s (* (sin (● g phase)) (● g stride)))
            (c (* (cos (● g phase)) (● g stride))))
        (new Pose (step (* s 0.29)) (left-lift (* 0.17 (max 0.0 c)))
             (right-lift (* 0.17 (max 0.0 (negate c)))) (bob (* 0.06 (abs c)))
             (reach (● g arm)) (seat (● g seat)))))))

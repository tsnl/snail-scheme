(define-library (counter application)
  (export CounterApplication)
  (import
   (snail core base)
   (snail shell app)
   (snail shell wire))
  (begin
    (struct Counter
      ((count I64)
       (width I32)
       (height I32)))

    (struct Save
      ((count I64))
      (deriving Serialize Deserialize))

    (define (greeting) (→ String) "hello")

    (define (add-action) (→ I32) 1)

    (define (start (seed I32) (width I32) (height I32)) (→ Counter)
      (Counter 0 width height))

    (define (step (counter Counter) (input Input)) (→ Counter)
      (match input
        ((Press 1 _) (Counter-count-set counter (+ (● counter count) 1)))
        ((Resize width height) (Counter (● counter count) width height))
        (_ counter)))

    ;; One box, its batch versioned by the count, under a fixed camera.
    (define (draw (counter Counter)) (→ Frame)
      (Frame (Camera (Vec3 4.0 4.0 4.0) (Vec3 0.0 0.0 0.0) (Perspective 0.8))
             (Light (Vec3 0.3 1.0 0.5) 0.8 0.3)
             (rgb 16 20 28)
             1.0
             (list (Batch 1 (i64->i32 (● counter count)) (Solid)
                          (lambda ()
                            (list (item (Box)
                                        (Vec3 0.0 0.0 0.0)
                                        (Vec3 1.0 1.0 1.0)
                                        0.0
                                        (rgb 143 209 143))))))
             (Nil)))

    (define (panels (counter Counter)) (→ (List Panel))
      (list (Panel "counter" (At (TopLeft) 0)
                   (list (label "greeting" (greeting))
                         (label "count" (i64->string (● counter count)))
                         (button "add" "Add" (add-action))))))

    (define (save (counter Counter)) (→ Save)
      (Save (● counter count)))

    (define (restore (saved Save)) (→ Counter)
      (Counter (● saved count) 0 0))

    (type CounterApplication (SceneApplication Counter))

    (define-page-state Counter)

    (instance (Scene Counter)
      (define (scene-initialize (seed I32) (width I32) (height I32)) (→ Counter)
        (start seed width height))
      (define (scene-update (state Counter) (input Input)) (→ Counter)
        (step state input))
      (define (scene-view (state Counter)) (→ Frame)
        (draw state))
      (define (scene-hud (state Counter)) (→ (List Panel))
        (panels state))
      (define (scene-save (state Counter)) (→ Bytes)
        (serialize (save state)))
      (define (scene-restore (bytes Bytes)) (→ Counter)
        (restore (deserialize bytes))))))

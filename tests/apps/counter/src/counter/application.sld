(define-library (counter application)
  (export CounterApplication)
  (import
   (snail core base)
   (snail shell app)
   (snail shell wire))
  (begin
    (record Counter
      ((count I64)
       (width I32)
       (height I32)))

    (record Save
      ((count I64))
      (deriving Serialize Deserialize))

    (define (greeting) (→ String) "hello")

    (define (add-action) (→ I32) 1)

    (define (start (seed I32) (width I32) (height I32)) (→ Counter)
      (new Counter (count 0) (width width) (height height)))

    (define (step (counter Counter) (input Input)) (→ Counter)
      (match input
        ((Press 1 _) (Counter-count-set counter (+ (● counter count) 1)))
        ((Resize width height)
         (new Counter (count (● counter count)) (width width) (height height)))
        (_ counter)))

    ;; One box, its batch versioned by the count, under a fixed camera.
    (define (draw (counter Counter)) (→ Frame)
      (new Frame
        (camera (new Camera
                  (eye (new Vec3 (x 4.0) (y 4.0) (z 4.0)))
                  (target (new Vec3 (x 0.0) (y 0.0) (z 0.0)))
                  (projection (Perspective 0.8))))
        (light (new Light (direction (new Vec3 (x 0.3) (y 1.0) (z 0.5))) (sun 0.8) (ambient 0.3)))
        (background (rgb 16 20 28))
        (motion 1.0)
        (batches (list (new Batch (key 1) (version (i64->i32 (● counter count))) (style (Solid))
                            (items (lambda ()
                                     (list (item (Box)
                                                 (new Vec3 (x 0.0) (y 0.0) (z 0.0))
                                                 (new Vec3 (x 1.0) (y 1.0) (z 1.0))
                                                 0.0
                                                 (rgb 143 209 143))))))))
        (pictures (Nil))))

    (define (panels (counter Counter)) (→ (List Panel))
      (list (new Panel (key "counter") (place (At (TopLeft) 0))
                 (widgets (list (label "greeting" (greeting))
                                (label "count" (i64->string (● counter count)))
                                (button "add" "Add" (add-action)))))))

    (define (save (counter Counter)) (→ Save)
      (new Save (count (● counter count))))

    (define (restore (saved Save)) (→ Counter)
      (new Counter (count (● saved count)) (width 0) (height 0)))

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

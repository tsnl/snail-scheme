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

    (define greeting (→ String) "hello")

    (define add-action (→ I32) 1)

    (define (start (seed I32) (width I32) (height I32)) (→ Counter)
      (Counter 0 width height))

    (define (step (counter Counter) (input Input)) (→ Counter)
      (match input
        ((Press 1 _) (Counter-count-set counter (+ (::count counter) 1)))
        ((Resize width height) (Counter (::count counter) width height))
        (_ counter)))

    ;; One box, its batch versioned by the count, under a fixed camera.
    (define (draw (counter Counter)) (→ Frame)
      (Frame (Camera (Vec3 4.0 4.0 4.0) (Vec3 0.0 0.0 0.0) (Perspective 0.8))
             (Light (Vec3 0.3 1.0 0.5) 0.8 0.3)
             (rgb 16 20 28)
             1.0
             (list (Batch 1 (i64->i32 (::count counter)) (Solid)
                          (lambda ()
                            (list (item (Box)
                                        (Vec3 0.0 0.0 0.0)
                                        (Vec3 1.0 1.0 1.0)
                                        0.0
                                        (rgb 143 209 143))))))
             (Nil)))

    (define (panels (counter Counter)) (→ (List Panel))
      (list (Panel "counter" (At (TopLeft) 0)
                   (list (label "greeting" greeting)
                         (label "count" (i64->string (::count counter)))
                         (button "add" "Add" add-action)))))

    (define (save (counter Counter)) (→ Save)
      (Save (::count counter)))

    (define (restore (saved Save)) (→ Counter)
      (Counter (::count saved) 0 0))

    (type CounterApplication (SceneApplication Counter))

    (define-page-state Counter)

    (instance (Scene Counter)
      (define scene-initialize (lambda (seed width height) (start seed width height)))
      (define scene-update (lambda (state input) (step state input)))
      (define scene-view (lambda (state) (draw state)))
      (define scene-hud (lambda (state) (panels state)))
      (define scene-save (lambda (state) (serialize (save state))))
      (define scene-restore (lambda (bytes) (restore (deserialize bytes)))))))

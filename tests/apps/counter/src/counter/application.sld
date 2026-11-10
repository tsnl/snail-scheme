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

    (: greeting String)
    (define greeting "hello")

    (: add-action I32)
    (define add-action 1)

    (: start (impl (Fn I32 I32 I32 -> Counter)))
    (define (start seed width height)
      (Counter 0 width height))

    (: step (impl (Fn Counter Input -> Counter)))
    (define (step counter input)
      (match input
        ((Press 1 _) (Counter-count-set counter (+ (::count counter) 1)))
        ((Resize width height) (Counter (::count counter) width height))
        (_ counter)))

    ;; One box, its batch versioned by the count, under a fixed camera.
    (: draw (impl (Fn Counter -> Frame)))
    (define (draw counter)
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

    (: panels (impl (Fn Counter -> (List Panel))))
    (define (panels counter)
      (list (Panel "counter" (At (TopLeft) 0)
                   (list (label "greeting" greeting)
                         (label "count" (i64->string (::count counter)))
                         (button "add" "Add" add-action)))))

    (: save (impl (Fn Counter -> Save)))
    (define (save counter)
      (Save (::count counter)))

    (: restore (impl (Fn Save -> Counter)))
    (define (restore saved)
      (Counter (::count saved) 0 0))

    (type CounterApplication (SceneApplication Counter))

    (define-page-state Counter)

    (instance (Scene Counter)
      (define (scene-initialize seed width height) (start seed width height))
      (define (scene-update state input) (step state input))
      (define (scene-view state) (draw state))
      (define (scene-hud state) (panels state))
      (define (scene-save state) (serialize (save state)))
      (define (scene-restore bytes) (restore (deserialize bytes))))))

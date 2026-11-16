;; A scene run by the page's host as a script is: main runs the scene under
;; (snail target browser)'s handlers, as the scheduler's first task, beside
;; a sleeping child. The HUD shows the count, which tells the check what
;; the scene's state is.
(import
 (snail core base)
 (only (snail core forms) host)
 (snail shell task)
 (snail shell app)
 (snail shell wire))

;; A task keeps its handlers across its waits, and a child inherits them.
(effect Marker
  ((marker (Fn → I32))))

(record Counter
  ((count I64)))

(record Save
  ((count I64))
  (deriving Serialize Deserialize))

;; Press 1 counts and Press 2 traps.
(define (step (counter Counter) (input Input)) (→ Counter)
  (match input
    ((Press 1 _) (new Counter (count (+ (● counter count) 1))))
    ((Press 2 _) (panic "a deliberate update trap"))
    (_ counter)))

(define (draw (counter Counter)) (→ Frame)
  (new Frame
    (camera (new Camera
              (eye (new Vec3 (x 4.0) (y 4.0) (z 4.0)))
              (target (new Vec3 (x 0.0) (y 0.0) (z 0.0)))
              (projection (Perspective 0.8))))
    (light (new Light (direction (new Vec3 (x 0.3) (y 1.0) (z 0.5))) (sun 0.8) (ambient 0.3)))
    (background (rgb 16 20 28))
    (motion 1.0)
    (batches (Nil))
    (pictures (Nil))))

(define (panels (counter Counter)) (→ (List Panel))
  (list (new Panel (key "counter") (place (At (TopLeft) 0))
             (widgets (list (label "count" (i64->string (● counter count))))))))

(define (counter) (→ (SceneHandler Counter))
  (new SceneHandler
    (initialize (lambda (seed width height) (new Counter (count 0))))
    (update step)
    (view draw)
    (hud panels)
    (save (lambda (counter) (serialize (new Save (count (● counter count))))))
    (restore (lambda (bytes) (new Counter (count (● (ann (deserialize bytes) Save) count)))))))

(define (main) (→ Unit) (! mut host screen events storage tasks)
  (handle Marker
      ((marker (lambda () 17)))
    (dispatch (lambda ()
                (yield)
                (unless (= (marker) 17)
                  (panic "a child lost its inherited handler"))
                (sleep 100000)))
    (run-scene (counter))))

;; A scene run by the page's host as a script is: main runs the scene under
;; (snail target browser)'s handlers, as the scheduler's first task, beside
;; a sleeping child. The HUD shows the count, which tells the check what
;; the scene's state is, and the buttons the check clicks.
(import
 (snail core base)
 (snail shell task)
 (snail shell app)
 (snail shell wire)
 (only (snail core io) Clock)
 (only (snail shell gpu) Gpu)
 (only (snail shell page) Events)
 (only (snail shell page) PageStorage))

(record Counter
  ((count I64)
   (hovered I32)
   (leaving? Bool)))

(define (counting (count I64)) (→ Counter)
  (new Counter (count count) (hovered 0) (leaving? #t)))

(record Save
  ((count I64))
  (deriving Serialize Deserialize))

;; A key or Press 1 counts, Press 2 traps, and Press 3 removes its own
;; button; the HUD shows the action of the button under the pointer.
(define (step (counter Counter) (input Input)) (→ Counter)
  (match input
    ((KeyDown _ _) (counting (+ (● counter count) 1)))
    ((Press 1 _) (counting (+ (● counter count) 1)))
    ((Press 2 _) (panic "a deliberate update trap"))
    ((Press 3 _)
     (new Counter (count (● counter count)) (hovered (● counter hovered)) (leaving? #f)))
    ((Hover action _)
     (new Counter (count (● counter count)) (hovered action) (leaving? (● counter leaving?))))
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
    (batches (Nil))))

(define (panels (counter Counter)) (→ (List Panel))
  (list (new Panel (key "counter") (place (At (TopLeft) 0))
             (widgets (append (list (label "count" (i64->string (● counter count)))
                                    (label "hovered" (show (● counter hovered)))
                                    (button "add" "Add" 1)
                                    (button "trap" "Trap" 2))
                              (if (● counter leaving?) (list (button "leave" "Leave" 3)) (Nil)))))))

(define (counter (gpu Gpu)) (→ (SceneHandler Counter Frames))
  (new SceneHandler
    (initialize (lambda (seed width height) (counting 0)))
    (update step)
    (start start-frames)
    (draw (lambda (counter frames) (draw-frame gpu (draw counter) frames)))
    (hud panels)
    (image-url (lambda (drawing image) ""))
    (save (lambda (counter) (serialize (new Save (count (● counter count))))))
    (restore (lambda (bytes) (counting (● (ann (deserialize bytes) Save) count))))))

(define (main (gpu Gpu) (events Events) (storage PageStorage) (clock Clock))
  (→ Unit)
  (! mut)
  ;; A task keeps what it closed over across its waits.
  (let ((marker 17))
    (dispatch (lambda ()
                (yield)
                (unless (= marker 17)
                  (panic "a child lost what it closed over"))
                (sleep 100000)))
    (run-scene gpu events storage clock (counter gpu))))

(import
 (snail core base)
 (only (snail core forms) host)
 (snail shell task)
 (snail shell app)
 (snail shell application)
 (snail shell page)
 (snail shell wire))

;; A mismatch here is a broken test-host invariant.
(define-syntax fixture-convert
  (syntax-rules ()
    ((_ value target)
     (match (downcast target value)
       ((Some checked) checked)
       ((None) (panic "fixture payload has the wrong type"))))))

;; Each task retains the private handler across its waits on storage and
;; events. Its default, the host's, lets the runner detect a leaked handler
;; between turns.
(effect Marker
  ((marker (Fn → I32)))
  (default
    ((marker host-marker))))

(extern host-marker "snail.test" "marker" (Fn → I32))

;; The runtime drains children after a normal root return. Explicit reload
;; closes that scope after the root has handed over, including this case.
;; Each root is a task, as the shared page loop is.
(extern background-boot "snail.runtime.browser.events" "boot" (Fn I32 → Unit ! events))
(extern background-ready "snail.runtime.browser.events" "ready" (Fn → Unit ! events))
(extern background-poll "snail.runtime.browser.events" "poll" (Fn → I32 ! events))
(define (background-main (scheduler Scheduler) (context PageRun)) (→ I64) (! mut host events)
  (start-page context scheduler (once (lambda ()
                                        (background-boot 2)
                                        (background-poll) ; Resize.
                                        (background-poll) ; Frame.
                                        (background-ready) ; Acknowledge presentation explicitly.
                                        (dispatch-local (once (lambda () (sleep 100000))))
                                        (unit)))))
(expose background-main "background_main")

(define (unpresented-main (scheduler Scheduler) (context PageRun)) (→ I64) (! mut host events)
  (start-page context scheduler (once (lambda ()
                                        (background-boot 2)
                                        (dispatch-local (once (lambda () (sleep 100000))))
                                        (unit)))))
(expose unpresented-main "unpresented_main")

;; Tasks beside the loop cannot enter its protocol: each of these traps.
(define (child-load) (→ Unit) (! storage tasks)
  (load-save)
  (unit))
(define (child-store) (→ Unit) (! storage tasks)
  (store-save #u8(20)))
(define (child-event) (→ Unit) (! events tasks)
  (next-event)
  (unit))
(define (child-boot) (→ Unit) (! events)
  (background-boot 99))

(define (child-commit) (→ Unit) (! mut events page)
  (commit-page (new Counter (count 999) (resizes 0))))

(define (spawn-child (scheduler Scheduler) (context PageRun) (which I32))
  (→ Unit) (! mut host storage events)
  (handle page ((current-page (lambda () context)))
    (dispatch-in scheduler
                 (once (lambda ()
                         (match which
                           (0 (child-load))
                           (1 (child-store))
                           (2 (child-event))
                           (4 (child-commit))
                           (5 (report-ready))
                           (_ (child-boot)))))))
  (unit))
(expose spawn-child "spawn_child")

(record Counter
  ((count I64)
   (resizes I32)))

(record Save
  ((count I64))
  (deriving Serialize Deserialize))

(define (initial (seed I32) (width I32) (height I32)) (→ Counter)
  (new Counter (count 0) (resizes 0)))

(define (step (counter Counter) (input Input)) (→ Counter)
  (match input
    ((Press 1 _) (Counter-count-set counter (+ (● counter count) 1)))
    ((Press 2 _) (panic "a deliberate update trap"))
    ((Elapsed elapsed) (Counter-count-set counter (+ (● counter count) (i32->i64 elapsed))))
    ((Resize _ _) (Counter-resizes-set counter (+ (● counter resizes) 1)))
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

(define (save-counter (counter Counter)) (→ Save)
  (new Save (count (● counter count))))

(define (restore-counter (saved Save)) (→ Counter)
  (new Counter (count (● saved count)) (resizes 0)))

(define (inspect-count (state Any)) (→ I64)
  (● (fixture-convert state Counter) count))

(define (inspect-resizes (state Any)) (→ I32)
  (● (fixture-convert state Counter) resizes))

(define (other-state) (→ Any)
  (Any (ann 5 I64)))

(define (read-marker) (→ I32) (! Marker)
  (marker))

(expose read-marker "marker")
(expose inspect-count "count")
(expose inspect-resizes "resizes")
(expose other-state "other")

(define-page-state Counter)

(instance (Scene Counter)
  (define (scene-initialize (seed I32) (width I32) (height I32)) (→ Counter)
    (initial seed width height))
  (define (scene-update (state Counter) (input Input)) (→ Counter)
    (step state input))
  (define (scene-view (state Counter)) (→ Frame)
    (draw state))
  (define (scene-hud (state Counter)) (→ (List Panel))
    (panels state))
  (define (scene-save (state Counter)) (→ Bytes)
    (serialize (save-counter state)))
  (define (scene-restore (bytes Bytes)) (→ Counter)
    (restore-counter (deserialize bytes))))

(record TestApplication
  ())

(instance (Application (! mut host screen events storage tasks page) TestApplication)
  (define (start (entry (Entry TestApplication)))
    (→ Unit)
    (! mut host screen events storage tasks page)
    (handle Marker
        ((marker (lambda () 17)))
      (dispatch-local (once (lambda ()
                              (yield)
                              (unless (= (marker) 17)
                                (panic "a child lost its inherited handler"))
                              (sleep 100000))))
      (start (ann (new Entry) (Entry (SceneApplication Counter)))))))

(define-page-entry TestApplication)

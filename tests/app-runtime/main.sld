(import
 (snail core base)
 (snail shell task)
 (snail shell app)
 (snail shell application)
 (snail shell page)
 (snail shell wire))

;; A mismatch here is a broken test-host invariant. Guest conversions that
;; are expected to fail use dyn-cast handlers in the dedicated fixtures.
(define-syntax fixture-convert
  (syntax-rules ()
    ((_ value target)
     (match (try-convert value target)
       ((Ok checked) checked)
       ((Err _) (panic "fixture payload has the wrong type"))))))

;; Each task retains the private handler across its waits on storage and
;; events. Its default, the host's, lets the runner detect a leaked handler
;; between turns.
(effect Marker
  ((marker (dyn (Fn → I32))))
  (default
    ((marker host-marker))))

(extern host-marker "snail.test" "marker" (impl (Fn → I32)))

;; The runtime drains children after a normal root return. Explicit reload
;; closes that scope after the root has handed over, including this case.
;; Each root is a task, as the shared page loop is.
(extern background-boot "snail.runtime.browser.events" "boot" (impl (Fn I32 → Unit ! events)))
(extern background-ready "snail.runtime.browser.events" "ready" (impl (Fn → Unit ! events)))
(extern background-poll "snail.runtime.browser.events" "poll" (impl (Fn → I32 ! events)))
(define (background-main (handover (Option Any))) (→ I64) (! mut events)
  (start-page handover (once (lambda ()
                               (background-boot 2)
                               (background-poll) ; Resize.
                               (background-poll) ; Frame.
                               (background-ready) ; Acknowledge presentation explicitly.
                               (dispatch-local (once (lambda () (sleep 100000))))
                               (unit)))))
(expose background-main "background_main")

(define (unpresented-main (handover (Option Any))) (→ I64) (! mut events)
  (start-page handover (once (lambda ()
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

(define (child-commit) (→ Unit) (! mut events)
  (commit-page (Counter 999 0)))

(define (spawn-child (which I32)) (→ Unit) (! mut storage events)
  (dispatch-local (once (lambda ()
                          (match which
                            (0 (child-load))
                            (1 (child-store))
                            (2 (child-event))
                            (4 (child-commit))
                            (5 (report-ready))
                            (_ (child-boot)))))))
(expose spawn-child "spawn_child")

(struct Counter
  ((count I64)
   (resizes I32)))

(struct Save
  ((count I64))
  (deriving Serialize Deserialize))

(define (initial (seed I32) (width I32) (height I32)) (→ Counter)
  (Counter 0 0))

(define (step (counter Counter) (input Input)) (→ Counter)
  (match input
    ((Press 1 _) (Counter-count-set counter (+ (::count counter) 1)))
    ((Press 2 _) (panic "a deliberate update trap"))
    ((Elapsed elapsed) (Counter-count-set counter (+ (::count counter) (i32->i64 elapsed))))
    ((Resize _ _) (Counter-resizes-set counter (+ (::resizes counter) 1)))
    (_ counter)))

(define (draw (counter Counter)) (→ Frame)
  (Frame (Camera (Vec3 4.0 4.0 4.0) (Vec3 0.0 0.0 0.0) (Perspective 0.8))
         (Light (Vec3 0.3 1.0 0.5) 0.8 0.3)
         (rgb 16 20 28)
         1.0
         (Nil)
         (Nil)))

(define (panels (counter Counter)) (→ (List Panel))
  (list (Panel "counter" (At (TopLeft) 0)
               (list (label "count" (i64->string (::count counter)))))))

(define (save-counter (counter Counter)) (→ Save)
  (Save (::count counter)))

(define (restore-counter (saved Save)) (→ Counter)
  (Counter (::count saved) 0))

(define (inspect-count (state Any)) (→ I64)
  (::count (fixture-convert state Counter)))

(define (inspect-resizes (state Any)) (→ I32)
  (::resizes (fixture-convert state Counter)))

(define (other-state) (→ Any)
  (type-convert (ann 5 I64) Any))

(define (read-marker) (→ I32) (! Marker)
  (marker))

(expose read-marker "marker")
(expose inspect-count "count")
(expose inspect-resizes "resizes")
(expose other-state "other")

(define-page-state Counter)

(instance (Scene Counter)
  (define scene-initialize (lambda (seed width height) (initial seed width height)))
  (define scene-update (lambda (state input) (step state input)))
  (define scene-view (lambda (state) (draw state)))
  (define scene-hud (lambda (state) (panels state)))
  (define scene-save (lambda (state) (serialize (save-counter state))))
  (define scene-restore (lambda (bytes) (restore-counter (deserialize bytes)))))

(struct TestApplication
  ())

(instance (Application (! mut screen events storage tasks) TestApplication)
  (define start
    (lambda (entry) (handle Marker
                        ((marker (lambda () 17)))
                      (dispatch-local (once (lambda ()
                                              (yield)
                                              (unless (= (marker) 17)
                                                (panic "a child lost its inherited handler"))
                                              (sleep 100000))))
                      (start (ann (Entry) (Entry (SceneApplication Counter))))))))

(define-page-entry TestApplication)

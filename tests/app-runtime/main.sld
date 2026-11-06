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
  ((marker (-> I32)))
  (default
    ((marker host-marker))))

(extern host-marker "snail.test" "marker" (-> I32))

;; The runtime drains children after a normal root return. Explicit reload
;; closes that scope after the root has handed over, including this case.
;; Each root is a task, as the shared page loop is.
(extern background-boot "snail.runtime.browser.events" "boot" (-> I32 Unit ! events))
(extern background-ready "snail.runtime.browser.events" "ready" (-> Unit ! events))
(extern background-poll "snail.runtime.browser.events" "poll" (-> I32 ! events))
(: background-main (-> (Option Any) I64 ! mut events))
(define (background-main handover)
  (start-page handover (once (lambda ()
                               (background-boot 2)
                               (background-poll) ; Resize.
                               (background-poll) ; Frame.
                               (background-ready) ; Acknowledge presentation explicitly.
                               (dispatch-local (once (lambda () (sleep 100000))))
                               (unit)))))
(expose background-main "background_main")

(: unpresented-main (-> (Option Any) I64 ! mut events))
(define (unpresented-main handover)
  (start-page handover (once (lambda ()
                               (background-boot 2)
                               (dispatch-local (once (lambda () (sleep 100000))))
                               (unit)))))
(expose unpresented-main "unpresented_main")

;; Tasks beside the loop cannot enter its protocol: each of these traps.
(: child-load (-> Unit ! storage tasks))
(define (child-load)
  (load-save)
  (unit))
(: child-store (-> Unit ! storage tasks))
(define (child-store)
  (store-save #u8(20)))
(: child-event (-> Unit ! events tasks))
(define (child-event)
  (next-event)
  (unit))
(: child-boot (-> Unit ! events))
(define (child-boot)
  (background-boot 99))

(: child-commit (-> Unit ! mut events))
(define (child-commit)
  (commit-page (Counter 999 0)))

(: spawn-child (-> I32 Unit ! mut storage events))
(define (spawn-child which)
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

(: initial (-> I32 I32 I32 Counter))
(define (initial seed width height)
  (Counter 0 0))

(: step (-> Counter Input Counter))
(define (step counter input)
  (match input
    ((Press 1 _) (Counter-count-set counter (+ (Counter-count counter) 1)))
    ((Press 2 _) (panic "a deliberate update trap"))
    ((Elapsed elapsed) (Counter-count-set counter (+ (Counter-count counter) (i32->i64 elapsed))))
    ((Resize _ _) (Counter-resizes-set counter (+ (Counter-resizes counter) 1)))
    (_ counter)))

(: draw (-> Counter Frame))
(define (draw counter)
  (Frame (Camera (Vec3 4.0 4.0 4.0) (Vec3 0.0 0.0 0.0) (Perspective 0.8))
         (Light (Vec3 0.3 1.0 0.5) 0.8 0.3)
         (rgb 16 20 28)
         1.0
         (Nil)
         (Nil)))

(: panels (-> Counter (List Panel)))
(define (panels counter)
  (list (Panel "counter" (At (TopLeft) 0)
               (list (label "count" (i64->string (Counter-count counter)))))))

(: save-counter (-> Counter Save))
(define (save-counter counter)
  (Save (Counter-count counter)))

(: restore-counter (-> Save Counter))
(define (restore-counter saved)
  (Counter (Save-count saved) 0))

(: inspect-count (-> Any I64))
(define (inspect-count state)
  (Counter-count (fixture-convert state Counter)))

(: inspect-resizes (-> Any I32))
(define (inspect-resizes state)
  (Counter-resizes (fixture-convert state Counter)))

(: other-state (-> Any))
(define (other-state)
  (type-convert (ann 5 I64) Any))

(: read-marker (-> I32 ! Marker))
(define (read-marker)
  (marker))

(expose read-marker "marker")
(expose inspect-count "count")
(expose inspect-resizes "resizes")
(expose other-state "other")

(define-page-state Counter)

(instance (Scene Counter)
  (define (scene-initialize seed width height) (initial seed width height))
  (define (scene-update state input) (step state input))
  (define (scene-view state) (draw state))
  (define (scene-hud state) (panels state))
  (define (scene-save state) (serialize (save-counter state)))
  (define (scene-restore bytes) (restore-counter (deserialize bytes))))

(struct TestApplication
  ())

(instance (Application (! mut screen events storage tasks) TestApplication)
  (define (start entry)
    (handle Marker
        ((marker (lambda () 17)))
      (dispatch-local (once (lambda ()
                              (yield)
                              (unless (= (marker) 17) (panic "a child lost its inherited handler"))
                              (sleep 100000))))
      (start (ann (Entry) (Entry (SceneApplication Counter)))))))

(define-page-entry TestApplication)

(import
 (snail core base)
 (snail shell task)
 (snail shell app))

;; Each task retains the private handler across its waits on storage and
;; events. Its host default lets the runner detect a leaked handler between
;; turns.
(effect Marker
  ((marker (-> I32)))
  (host "snail.test"
        ((marker "marker"))))

(: reset-test (All (T e) (-> (-> (-> T ! Marker mut tasks e) T ! mut tasks e))))
(define (reset-test)
  (lambda (run)
    (handle Marker
        ((marker (lambda () 17)))
      (dispatch-local (once (lambda ()
                              (yield)
                              (unless (= (marker) 17) (panic "a child lost its inherited handler"))
                              (sleep 100000))))
      (run))))

;; The runtime drains children after a normal root return. Explicit reload
;; closes that scope after the root has handed over, including this case.
;; Each root is a task, as the loop of `define-application` is.
(extern background-boot "snail.runtime.browser.events" "boot" (-> I32 Unit ! events))
(extern background-poll "snail.runtime.browser.events" "poll" (-> I32 ! events))
(: background-main (-> (Option Any) I64 ! mut events))
(define (background-main handover)
  (app-start (once (lambda ()
                     (background-boot 2)
                     (background-poll) ; Resize.
                     (background-poll) ; Frame.
                     (background-poll) ; Acknowledge presentation.
                     (dispatch-local (once (lambda () (sleep 100000))))
                     handover))))
(expose background-main "background_main")

(: unpresented-main (-> (Option Any) I64 ! mut events))
(define (unpresented-main handover)
  (app-start (once (lambda ()
                     (background-boot 2)
                     (dispatch-local (once (lambda () (sleep 100000))))
                     handover))))
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

(: spawn-child (-> I32 Unit ! mut storage events))
(define (spawn-child which)
  (dispatch-local (once (lambda ()
                          (match which
                            (0 (child-load))
                            (1 (child-store))
                            (2 (child-event))
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
  (Counter-count (type-convert state Counter)))

(: inspect-resizes (-> Any I32))
(define (inspect-resizes state)
  (Counter-resizes (type-convert state Counter)))

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

(define-application Counter
  (reset: reset-test)
  (init: initial)
  (update: step)
  (view: draw)
  (hud: panels)
  (save: save-counter)
  (restore: restore-counter))

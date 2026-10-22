(import
 (lofi base)
 (lofi app))

;; The private handler stays installed across storage and event suspension.
;; Its host default lets the runner detect a leaked handler after a trap.
(effect Marker
  ((marker (-> I32)))
  (host "snail.test"
        ((marker "marker"))))

(: reset-test (All (T e) (-> (-> (-> T ! Marker e) T ! e))))
(define (reset-test)
  (lambda (run)
    (handle Marker
        ((marker (lambda () 17)))
      (run))))

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

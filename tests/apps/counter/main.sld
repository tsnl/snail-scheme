;; The smallest application: a counter that a button adds to, with a
;; greeting. The development server's test (tests/develop.mjs) edits the
;; greeting while the counter runs and checks that the count survives.
(import
 (lofi base)
 (lofi app))

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

(: start (-> I32 I32 I32 Counter))
(define (start seed width height)
  (Counter 0 width height))

(: step (-> Counter Input Counter))
(define (step counter input)
  (match input
    ((Press 1 _) (Counter-count-set counter (+ (Counter-count counter) 1)))
    ((Resize width height) (Counter (Counter-count counter) width height))
    (_ counter)))

;; One box, its batch versioned by the count, under a fixed camera.
(: draw (-> Counter Frame))
(define (draw counter)
  (Frame (Camera (Vec3 4.0 4.0 4.0) (Vec3 0.0 0.0 0.0) (Perspective 0.8))
         (Light (Vec3 0.3 1.0 0.5) 0.8 0.3)
         (rgb 16 20 28)
         1.0
         (list (Batch 1 (i64->i32 (Counter-count counter)) (Solid)
                      (lambda () (list (item (Box) (Vec3 0.0 0.0 0.0) (Vec3 1.0 1.0 1.0) 0.0 (rgb 143 209 143))))))))

(: panels (-> Counter (List Panel)))
(define (panels counter)
  (list (Panel "counter" (At (TopLeft) 0)
               (list (Label (look "greeting") greeting)
                     (Label (look "count") (i64->string (Counter-count counter)))
                     (Button (look "add") "Add" "" add-action 0 (Enabled) -1.0)))))

(: save (-> Counter Save))
(define (save counter)
  (Save (Counter-count counter)))

(: restore (-> Save Counter))
(define (restore saved)
  (Counter (Save-count saved) 0 0))

(define-application Counter start step draw panels save restore)

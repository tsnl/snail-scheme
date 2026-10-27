(import
 (snail-core base)
 (snail-core app))

(: initial (-> I32 I32 I32 I64))
(define (initial seed width height)
  0)

;; Updating a mutable cell could corrupt the checkpoint before an event traps.
(: step (-> I64 Input I64 ! mut))
(define (step state input)
  (ref-get (ref state)))

(: draw (-> I64 Frame))
(define (draw state)
  (panic "unused"))

(: panels (-> I64 (List Panel)))
(define (panels state)
  (Nil))

(: saved (-> I64 I64))
(define (saved state)
  state)

(define-application I64
  (reset: default-reset)
  (init: initial)
  (update: step)
  (view: draw)
  (hud: panels)
  (save: saved)
  (restore: saved))

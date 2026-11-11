(import
 (snail core base)
 (snail shell app)
 (snail shell wire))

(: initial (impl (Fn I32 I32 I32 -> I64)))
(define (initial seed width height)
  0)

;; Updating a mutable cell could corrupt the checkpoint before an event traps.
(: step (impl (Fn I64 Input -> I64 ! mut)))
(define (step state input)
  (ref-get (ref state)))

(: draw (impl (Fn I64 -> Frame)))
(define (draw state)
  (panic "unused"))

(: panels (impl (Fn I64 -> (List Panel))))
(define (panels state)
  (Nil))

(: saved (impl (Fn I64 -> I64)))
(define (saved state)
  state)

(instance (Scene I64)
  (define (scene-initialize seed width height) (initial seed width height))
  (define (scene-update state input) (step state input))
  (define (scene-view state) (draw state))
  (define (scene-hud state) (panels state))
  (define (scene-save state) (serialize (saved state)))
  (define (scene-restore bytes) (saved (deserialize bytes))))

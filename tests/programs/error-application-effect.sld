(import
 (snail core base)
 (snail shell app)
 (snail shell wire))

(define (initial (seed I32) (width I32) (height I32)) (→ I64)
  0)

;; Updating a mutable cell could corrupt the checkpoint before an event traps.
(define (step (state I64) (input Input)) (→ I64) (! mut)
  (ref-get (ref state)))

(define (draw (state I64)) (→ Frame)
  (panic "unused"))

(define (panels (state I64)) (→ (List Panel))
  (Nil))

(define (saved (state I64)) (→ I64)
  state)

(instance (Scene I64)
  (define scene-initialize (lambda (seed width height) (initial seed width height)))
  (define scene-update (lambda (state input) (step state input)))
  (define scene-view (lambda (state) (draw state)))
  (define scene-hud (lambda (state) (panels state)))
  (define scene-save (lambda (state) (serialize (saved state))))
  (define scene-restore (lambda (bytes) (saved (deserialize bytes)))))

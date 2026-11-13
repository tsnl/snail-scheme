(define-library (hearsay application)
  (export Hearsay)
  (import
   (snail core base)
   (snail shell app)
   (snail shell wire)
   (hearsay shell)
   (hearsay art))
  (begin
    (define (view (shell Shell)) (→ Frame)
      (view-shell shell art))

    (type Hearsay (SceneApplication Shell))

    (define-page-state Shell)

    (instance (Scene Shell)
      (define (scene-initialize (seed I32) (width I32) (height I32)) (→ Shell)
        (new-shell seed width height))
      (define (scene-update (state Shell) (input Input)) (→ Shell)
        (update-shell state input))
      (define (scene-view (state Shell)) (→ Frame)
        (view state))
      (define (scene-hud (state Shell)) (→ (List Panel))
        (shell-hud state))
      (define (scene-save (state Shell)) (→ Bytes)
        (serialize (shell-save state)))
      (define (scene-restore (bytes Bytes)) (→ Shell)
        (shell-restore (deserialize bytes))))))

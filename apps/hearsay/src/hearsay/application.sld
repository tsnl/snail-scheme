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
      (define scene-initialize (lambda (seed width height) (new-shell seed width height)))
      (define scene-update (lambda (state input) (update-shell state input)))
      (define scene-view (lambda (state) (view state)))
      (define scene-hud (lambda (state) (shell-hud state)))
      (define scene-save (lambda (state) (serialize (shell-save state))))
      (define scene-restore (lambda (bytes) (shell-restore (deserialize bytes)))))))

(define-library (hearsay application)
  (export Hearsay)
  (import
   (snail core base)
   (snail shell app)
   (snail shell wire)
   (hearsay shell)
   (hearsay art))
  (begin
    (: view (impl (Fn Shell -> Frame)))
    (define (view shell)
      (view-shell shell art))

    (type Hearsay (SceneApplication Shell))

    (define-page-state Shell)

    (instance (Scene Shell)
      (define (scene-initialize seed width height) (new-shell seed width height))
      (define (scene-update state input) (update-shell state input))
      (define (scene-view state) (view state))
      (define (scene-hud state) (shell-hud state))
      (define (scene-save state) (serialize (shell-save state)))
      (define (scene-restore bytes) (shell-restore (deserialize bytes))))))

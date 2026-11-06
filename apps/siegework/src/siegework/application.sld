(define-library (siegework application)
  (export Siegework)
  (import
   (snail core base)
   (snail shell app)
   (snail shell wire)
   (siegework game)
   (siegework view)
   (siegework hud))
  (begin

    (type Siegework (SceneApplication Game))

    (define-page-state Game)

    (instance (Scene Game)
      (define (scene-initialize seed width height) (new-game seed width height))
      (define (scene-update state input) (update-game state input))
      (define (scene-view state) (view-game state))
      (define (scene-hud state) (game-hud state))
      (define (scene-save state) (serialize (game-save state)))
      (define (scene-restore bytes) (game-restore (deserialize bytes))))))

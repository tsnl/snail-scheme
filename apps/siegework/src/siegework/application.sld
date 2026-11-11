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
      (define scene-initialize (lambda (seed width height) (new-game seed width height)))
      (define scene-update (lambda (state input) (update-game state input)))
      (define scene-view (lambda (state) (view-game state)))
      (define scene-hud (lambda (state) (game-hud state)))
      (define scene-save (lambda (state) (serialize (game-save state))))
      (define scene-restore (lambda (bytes) (game-restore (deserialize bytes)))))))

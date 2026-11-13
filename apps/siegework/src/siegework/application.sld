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
      (define (scene-initialize (seed I32) (width I32) (height I32)) (→ Game)
        (new-game seed width height))
      (define (scene-update (state Game) (input Input)) (→ Game)
        (update-game state input))
      (define (scene-view (state Game)) (→ Frame)
        (view-game state))
      (define (scene-hud (state Game)) (→ (List Panel))
        (game-hud state))
      (define (scene-save (state Game)) (→ Bytes)
        (serialize (game-save state)))
      (define (scene-restore (bytes Bytes)) (→ Game)
        (game-restore (deserialize bytes))))))

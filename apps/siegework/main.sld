;; Siegework: explore a seeded map, wire an energy network across it, and
;; destroy three nests before their attacks destroy your hub.
(import
 (snail core base)
 (snail shell app)
 (siegework game)
 (siegework view)
 (siegework hud))

(define-application Game
  (reset: default-reset)
  (init: new-game)
  (update: update-game)
  (view: view-game)
  (hud: game-hud)
  (save: game-save)
  (restore: game-restore))

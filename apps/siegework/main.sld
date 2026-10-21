;; Siegework: explore a seeded map, wire an energy network across it, and
;; destroy three nests before their attacks destroy your hub.
(import
 (lofi base)
 (lofi app)
 (siegework game)
 (siegework view)
 (siegework hud))

(define-application Game new-game update-game view-game game-hud game-save game-restore)

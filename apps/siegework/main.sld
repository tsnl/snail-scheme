;; Siegework: explore a seeded map, mine ore, and destroy three nests before
;; their waves destroy your hub.
(import
 (lofi base)
 (lofi app)
 (siegework game)
 (siegework view))

(define-application Game new-game update-game view-game game-hud game-save game-restore)

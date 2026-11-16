;; Siegework: the page's scene, from its game, view and HUD.
(import
 (snail core base)
 (snail shell app)
 (snail shell wire)
 (apps siegework game)
 (apps siegework view)
 (apps siegework hud))

(run-scene (new SceneHandler
             (initialize new-game)
             (update update-game)
             (start (lambda () (unit)))
             (draw (lambda (game drawing) (render (view-game game)) drawing))
             (hud game-hud)
             (image-url (lambda (drawing image) ""))
             (save (lambda (game) (serialize (game-save game))))
             (restore (lambda (bytes) (game-restore (deserialize bytes))))))

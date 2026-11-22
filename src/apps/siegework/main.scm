;; Siegework: the page's scene, from its game, view and HUD.
(import
 (snail core base)
 (snail shell app)
 (snail shell wire)
 (apps siegework game)
 (apps siegework view)
 (apps siegework hud)
 (only (snail shell gpu) Gpu)
 (only (snail shell dom) Dom)
 (only (snail shell page) Events)
 (only (snail shell page) PageStorage)
 (only (snail core io) Clock))

(define (main (gpu Gpu) (dom Dom) (events Events) (storage PageStorage) (clock Clock)) (→ Unit)
  (run-scene gpu dom events storage clock (new SceneHandler
                                            (initialize new-game)
                                            (update update-game)
                                            (start start-frames)
                                            (draw (lambda (game frames)
                                                    (draw-frame gpu (view-game game) frames)))
                                            (hud game-hud)
                                            (image-url (lambda (drawing image) ""))
                                            (save (lambda (game) (serialize (game-save game))))
                                            (restore
                                             (lambda (bytes) (game-restore (deserialize bytes))))))
  (unit))

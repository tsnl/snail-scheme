;; Hearsay: the page's scene, the prototypes' shell drawn with the cast's
;; art.
(import
 (snail core base)
 (snail shell app)
 (snail shell wire)
 (apps hearsay shell)
 (apps hearsay drawing)
 (apps hearsay art))

(run-scene (new SceneHandler
             (initialize new-shell)
             (update update-shell)
             (start start-drawing)
             (draw (lambda (shell drawing) (draw-shell shell drawing art)))
             (hud shell-hud)
             (image-url drawing-url)
             (save (lambda (shell) (serialize (shell-save shell))))
             (restore (lambda (bytes) (shell-restore (deserialize bytes))))))

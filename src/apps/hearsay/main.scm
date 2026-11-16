;; Hearsay: the page's scene, the prototypes' shell drawn with the cast's
;; art.
(import
 (snail core base)
 (snail shell app)
 (snail shell wire)
 (apps hearsay shell)
 (apps hearsay art))

(run-scene (new SceneHandler
             (initialize new-shell)
             (update update-shell)
             (view (lambda (shell) (view-shell shell art)))
             (hud shell-hud)
             (save (lambda (shell) (serialize (shell-save shell))))
             (restore (lambda (bytes) (shell-restore (deserialize bytes))))))

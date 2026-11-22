;; Hearsay: the page's scene, the prototypes' shell drawn with the cast's
;; art.
(import
 (snail core base)
 (snail shell app)
 (snail shell wire)
 (apps hearsay shell)
 (apps hearsay drawing)
 (apps hearsay art)
 (only (snail shell gpu) Gpu)
 (only (snail shell page) Events)
 (only (snail shell page) PageStorage)
 (only (snail core io) Clock))

(define (main (gpu Gpu) (events Events) (storage PageStorage) (clock Clock)) (→ Unit) (! mut)
  (run-scene gpu events storage clock (new SceneHandler
                                        (initialize new-shell)
                                        (update update-shell)
                                        (start start-drawing)
                                        (draw (lambda (shell drawing)
                                                (draw-shell gpu clock shell drawing art)))
                                        (hud shell-hud)
                                        (image-url drawing-url)
                                        (save (lambda (shell) (serialize (shell-save shell))))
                                        (restore
                                         (lambda (bytes) (shell-restore (deserialize bytes))))))
  (unit))

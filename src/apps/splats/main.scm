;; Splats: gaussian splatting through (snail shell graphics splat). Its
;; view is not saved; a reload starts it again.
(import
 (snail core base)
 (snail shell app)
 (apps splats viewer))

(run-scene (new SceneHandler
             (initialize new-view)
             (update update-view)
             (start start-drawing)
             (draw draw-view)
             (hud (lambda (view) (Nil)))
             (image-url (lambda (drawing key) ""))
             (save (lambda (view) (make-array 0 (i32->u8 0))))
             (restore (lambda (bytes) (new-view 0 0 0)))))

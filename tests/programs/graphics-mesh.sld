;; The geometry table's shapes and a batch's indirect draws, through the
;; recording handler: each shape's triangles, and one draw per shape that
;; has instances, from its own first instance.
(import
 (snail core base)
 (snail core io)
 (snail shell gpu)
 (snail shell gpu record)
 (snail shell graphics pod)
 (snail shell graphics mesh))

(define (instance (x F32)) (→ Instance)
  (let ((one (new Vec4f (x 1.0) (y 1.0) (z 1.0) (w 1.0))))
    (new Instance
      (place (new Vec4f (x x) (y 0.0) (z 0.0) (w 0.0)))
      (scale one)
      (color one)
      (from (new Vec4f (x x) (y 0.0) (z 0.0) (w 0.0)))
      (material (new Vec4f (x 0.0) (y 1.0) (z 0.0) (w 0.0))))))

(define batch
  (→ Meshes)
  (meshes (list (new Pair (first (Prism)) (second (instance 0.0)))
                (new Pair (first (Box)) (second (instance 1.0)))
                (new Pair (first (Prism)) (second (instance 2.0))))))

(define (heads (lines (List String))) (→ (List String))
  (map (lambda (line)
         (match (string-index line #\{)
           ((Some at) (substring line 0 at))
           ((None) line)))
       lines))

(write-line (string-append "instance bytes: " (show (array-length (● batch instances)))))
(for-each (lambda (draw)
            (write-line (string-append "draw: " (show (● draw index-count))
                                       " indices from " (show (● draw first-index))
                                       ", vertices from " (show (● draw base-vertex))
                                       ", " (show (● draw instance-count))
                                       " instances from " (show (● draw first-instance)))))
          (● batch draws))
(for-each write-line
          (heads (● (with-recorded-gpu 100000000
                                       (lambda ()
                                         (request-device 100000000)
                                         (let* ((encoder (create-command-encoder))
                                                (pass (begin-render-pass encoder
                                                                         (new RenderPassDescriptor
                                                                           (colors
                                                                            (list
                                                                             (new ColorAttachment
                                                                               (view
                                                                                (view-of
                                                                                 (●
                                                                                  (current-texture)
                                                                                  texture)
                                                                                 1))
                                                                               (load (Keep))
                                                                               (store #t))))
                                                                           (depth (None))))))
                                           (draw-meshes pass "test" batch #t)
                                           (end-pass pass)
                                           (submit (list (finish encoder))))))
                    second)))

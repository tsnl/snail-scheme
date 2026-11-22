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
      (material (new Vec2f (x 0.0) (y 1.0)))
      (id 0))))

(define batch
  (→ Meshes)
  (meshes (list (new Pair (first (Prism)) (second (instance 0.0)))
                (new Pair (first (Box)) (second (instance 1.0)))
                (new Pair (first (Prism)) (second (instance 2.0))))))

;; A created object's kind, id and label, and a pass's id and encoder,
;; without their descriptors.
(define (heads (lines (List String))) (→ (List String))
  (map (lambda (line)
         (let ((words (words-of line)))
           (cond ((string=? (list-ref words 0) "create") (string-join (take words 4) " "))
                 ((string=? (list-ref words 0) "pass") (string-join (take words 3) " "))
                 (else line))))
       lines))

(define (words-of (text String)) (→ (List String))
  (match (string-index text #\space)
    ((Some at)
     (Cons (substring text 0 at) (words-of (substring text (+ at 1) (string-length text)))))
    ((None) (list text))))

(define (main (out OutputPort)) (→ Unit) (! mut)
  (write-line out (string-append "instance bytes: " (show (array-length (● batch instances)))))
  (for-each (lambda (draw)
              (write-line out (string-append "draw: " (show (● draw index-count))
                                             " indices from " (show (● draw first-index))
                                             ", vertices from " (show (● draw base-vertex))
                                             ", " (show (● draw instance-count))
                                             " instances from " (show (● draw first-instance)))))
            (● batch draws))
  (for-each (lambda (text) (write-line out text))
            (heads (● (with-recorded-gpu (lambda (gpu) (frame gpu))) second)))
  (unit))
(define (frame (gpu Gpu)) (→ Unit) (! mut)
  (request-device gpu)
  (let* ((geometry (make-geometry gpu))
         (uploaded (upload-batch gpu "mesh/test" batch))
         (encoder (create-command-encoder gpu))
         (pass (begin-render-pass gpu encoder
                                  (new RenderPassDescriptor
                                    (colors (list (Some (new ColorAttachment
                                                          (view
                                                           (view-of gpu
                                                                    (● (current-texture gpu)
                                                                       texture)
                                                                    1))
                                                          (load (Keep))
                                                          (store #t)))))
                                    (depth (None))))))
    (draw-meshes gpu pass geometry uploaded)
    (end-pass gpu pass)
    (submit gpu (list (finish gpu encoder)))
    (release-batch gpu uploaded)))


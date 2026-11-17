;; Records deriving Pod: their WGSL declarations, layouts by WGSL's rules,
;; vertex attributes, and the bytes they pack to.
(import
 (snail core base)
 (snail core io)
 (snail shell gpu)
 (snail shell graphics pod))

;; An F32 after a vec3f shares its 16 bytes; the next vec4f aligns to 16.
(record Light
  ((direction Vec3f)
   (intensity F32)
   (color Vec4f))
  (deriving Pod))

;; A struct field aligns to its largest field, and the size rounds up to it.
;; A hyphen in a field's name is an underscore in WGSL.
(record Scene
  ((count I32)
   (sun Light)
   (exposure-bias F32))
  (deriving Pod))

(record Vertex
  ((position Vec3f)
   (uv Vec2f)
   (material I32))
  (deriving Pod))

(define scene-shape (→ (Shape Scene)) (shape))

(define vertex-shape (→ (Shape Vertex)) (shape))

(define (bytes-text (bytes Bytes)) (→ String)
  (string-join (map (lambda (byte) (show (u8->i32 byte))) (array->list bytes)) " "))

(define (layout-text (layout Layout)) (→ String)
  (string-join (map (lambda (field)
                      (string-append (● field name) "@" (show (● field offset))))
                    (● layout fields))
               " "))

(write-string (declarations scene-shape))
(write-line (string-append "scene: size "
                           (show (● scene-shape layout size))
                           ", align "
                           (show (● scene-shape layout align))
                           ", "
                           (layout-text (● scene-shape layout))))
(write-line (string-append "vertex: stride "
                           (show (stride vertex-shape))
                           ", "
                           (layout-text (● vertex-shape layout))))
(for-each (lambda (attribute)
            (write-line (string-append "  location "
                                       (show (● attribute location))
                                       " at "
                                       (show (● attribute offset)))))
          (● (vertex-layout vertex-shape (PerVertex) 0) attributes))
(write-line (bytes-text (pack vertex-shape (list (new Vertex
                                                   (position (new Vec3f (x 1.0) (y 2.0) (z -1.0)))
                                                   (uv (new Vec2f (x 0.5) (y 0.25)))
                                                   (material 258))))))
(write-line (show (array-length (pod-bytes scene-shape (new Scene
                                                         (count 1)
                                                         (sun (new Light
                                                                (direction (new Vec3f
                                                                             (x 0.0)
                                                                             (y 1.0)
                                                                             (z 0.0)))
                                                                (intensity 2.0)
                                                                (color
                                                                 (new Vec4f
                                                                   (x 1.0)
                                                                   (y 1.0)
                                                                   (z 1.0)
                                                                   (w 1.0)))))
                                                         (exposure-bias 1.0))))))

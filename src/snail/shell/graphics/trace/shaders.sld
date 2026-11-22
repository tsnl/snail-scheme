;; The path tracer's shaders, printed to WGSL when this library is built,
;; each from the file of its name: `unpack-shader` from unpack.wgsl.scm,
;; and so `layers-shader`, `surface-shader`, `scene-shader` and
;; `path-shader`.
(generate-library (snail shell graphics trace shaders)
                  (import
                   (snail core base)
                   (snail shell resource)
                   (snail shell graphics wgsl))
                  (lambda ((resources Resources))
(shader-library resources (list "snail" "shell" "graphics" "trace" "shaders")
                                  (list (new Pair
                                          (first "unpack-shader")
                                          (second (link-file "unpack.wgsl.scm")))
                                        (new Pair
                                          (first "layers-shader")
                                          (second (link-file "layers.wgsl.scm")))
                                        (new Pair
                                          (first "surface-shader")
                                          (second (link-file "surface.wgsl.scm")))
                                        (new Pair
                                          (first "scene-shader")
                                          (second (link-file "scene.wgsl.scm")))
                                        (new Pair
                                          (first "path-shader")
                                          (second (link-file "path.wgsl.scm")))))))

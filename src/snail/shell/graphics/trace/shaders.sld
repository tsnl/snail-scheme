;; The path tracer's shaders, printed to WGSL when this library is built,
;; each from the file of its name: `unpack-shader` from unpack.wgsl.scm,
;; and so `layers-shader`, `surface-shader`, `bvh-shader`, `path-shader`
;; and `svgf-shader`.
(generate-library (snail shell graphics trace shaders)
                  (import
                   (snail core base)
                   (snail shell resource)
                   (snail shell graphics wgsl))
                  (shader-library (list "snail" "shell" "graphics" "trace" "shaders")
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
                                          (first "bvh-shader")
                                          (second (link-file "bvh.wgsl.scm")))
                                        (new Pair
                                          (first "path-shader")
                                          (second (link-file "path.wgsl.scm")))
                                        (new Pair
                                          (first "svgf-shader")
                                          (second (link-file "svgf.wgsl.scm"))))))

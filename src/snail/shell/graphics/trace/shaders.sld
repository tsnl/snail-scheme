;; The path tracer's shaders, printed to WGSL when this library is built,
;; each from the file of its name: `unpack-shader` from unpack.wgsl.scm,
;; and so `layers-shader`.
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
                                          (second (link-file "layers.wgsl.scm"))))))

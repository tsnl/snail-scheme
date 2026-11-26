;; The path tracer's shaders, printed to WGSL when this library is built,
;; each from the file of its name: `unpack-shader` from unpack.wgsl.scm,
;; the emitter, path, reservoir and reference kernels follow the same convention.
(generate-library (snail shell graphics trace shaders)
                  (import
                   (snail core base)
                   (snail shell resource)
                   (snail shell graphics wgsl))
                  (lambda ((resources Resources))
                    (shader-library resources (list "snail" "shell" "graphics" "trace" "shaders")
                                    (list (new Pair
                                            (first "fog-shader")
                                            (second (link-file "fog.wgsl.scm")))
                                          (new Pair
                                            (first "focus-shader")
                                            (second (link-file "focus.wgsl.scm")))
                                          (new Pair (first "water-shader")
                                               (second (link-file "water.wgsl.scm")))
                                          (new Pair
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
                                            (first "emitter-build-shader")
                                            (second (link-file "emitter-build.wgsl.scm")))
                                          (new Pair
                                            (first "emitter-light-shader")
                                            (second (link-file "emitter-light.wgsl.scm")))
                                          (new Pair
                                            (first "reference-shader")
                                            (second (link-file "reference.wgsl.scm")))
                                          (new Pair
                                            (first "path-shader")
                                            (second (link-file "path.wgsl.scm")))
                                          (new Pair
                                            (first "restir-shader")
                                            (second (link-file "restir.wgsl.scm")))
                                          (new Pair
                                            (first "compose-shader")
                                            (second (link-file "compose.wgsl.scm")))))))

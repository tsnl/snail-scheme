(generate-library (snail shell graphics forward shaders)
                  (import
                   (snail core base)
                   (snail shell resource)
                   (snail shell graphics wgsl))
                  (lambda ((resources Resources))
                    (shader-library resources (list "snail" "shell" "graphics" "forward" "shaders")
                                    (list (new Pair
                                            (first "forward-shader")
                                            (second (link-file "material.wgsl.scm")))
                                          (new Pair
                                            (first "unpack-shader")
                                            (second (link-file "unpack.wgsl.scm")))
                                          (new Pair
                                            (first "ground-layer-shader")
                                            (second (link-file "ground-layer.wgsl.scm")))
                                          (new Pair
                                            (first "water-shader")
                                            (second (link-file "water.wgsl.scm")))))))

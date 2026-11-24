;; The test's shaders, printed to WGSL when this library is built: `paint`
;; fills a target with a uniform's color, and `square` squares numbers in
;; a storage buffer.
(generate-library (gpu-test shaders)
                  (import
                   (snail core base)
                   (snail shell resource)
                   (snail shell graphics wgsl))
                  (lambda ((resources Resources))
                    (shader-library resources (list "gpu-test" "shaders")
                                    (list (new Pair
                                            (first "paint")
                                            (second (link-file "paint.wgsl.scm")))
                                          (new Pair
                                            (first "inspect-reservoir")
                                            (second (link-file "reservoir.wgsl.scm")))
                                          (new Pair
                                            (first "sky-probe")
                                            (second (link-file "sky.wgsl.scm")))
                                          (new Pair
                                            (first "water-probe")
                                            (second (link-file "water.wgsl.scm")))
                                          (new Pair
                                            (first "square")
                                            (second (link-file "square.wgsl.scm")))))))

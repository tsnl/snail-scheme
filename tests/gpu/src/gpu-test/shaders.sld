;; The test's shaders, printed to WGSL when this library is built: `paint`
;; fills a target with a uniform's color, and `square` squares numbers in
;; a storage buffer.
(generate-library (gpu-test shaders)
                  (import
                   (snail core base)
                   (snail shell resource)
                   (snail shell graphics wgsl))
                  (shader-library (list "gpu-test" "shaders")
                                  (list (new Pair
                                          (first "paint")
                                          (second (link-file "paint.wgsl.scm")))
                                        (new Pair
                                          (first "square")
                                          (second (link-file "square.wgsl.scm"))))))

;; The test's shaders, printed to WGSL when this library is built.
(generate-library (gpu-test shaders)
                  (import
                   (snail core base)
                   (snail shell resource)
                   (snail shell graphics wgsl))
                  (shader-library (list "gpu-test" "shaders")
                                  (list (new Pair
                                          (first "paint")
                                          (second (link-file "paint.wgsl.scm"))))))

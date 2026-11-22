;; The training app's shader, printed to WGSL when this library is built:
;; `present-shader` from present.wgsl.scm.
(generate-library (apps train shaders)
                  (import
                   (snail core base)
                   (snail shell resource)
                   (snail shell graphics wgsl))
                  (lambda ((resources Resources))
(shader-library resources (list "apps" "train" "shaders")
                                  (list (new Pair
                                          (first "present-shader")
                                          (second (link-file "present.wgsl.scm")))))))

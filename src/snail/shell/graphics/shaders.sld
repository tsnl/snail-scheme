;; The graphics libraries' shaders, printed to WGSL when this library is
;; built: `quad-shader` from quad.wgsl.scm and `atlas-shader` from
;; atlas.wgsl.scm.
(generate-library (snail shell graphics shaders)
                  (import
                   (snail core base)
                   (snail shell resource)
                   (snail shell graphics wgsl))
                  (shader-library (list "snail" "shell" "graphics" "shaders")
                                  (list (new Pair
                                          (first "quad-shader")
                                          (second (link-file "quad.wgsl.scm")))
                                        (new Pair
                                          (first "atlas-shader")
                                          (second (link-file "atlas.wgsl.scm"))))))

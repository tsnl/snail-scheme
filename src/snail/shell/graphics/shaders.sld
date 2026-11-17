;; The graphics libraries' shaders, printed to WGSL when this library is
;; built, each from the file of its name: `quad-shader` from
;; quad.wgsl.scm, and so `atlas-shader`, `lighting-shader`, `raster-shader`,
;; `sun-shader`, `post-shader`, `bvh-shader`, `rays-shader`,
;; `svgf-shader`, `environment-shader` and `environment-light-shader`.
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
                                          (second (link-file "atlas.wgsl.scm")))
                                        (new Pair
                                          (first "lighting-shader")
                                          (second (link-file "lighting.wgsl.scm")))
                                        (new Pair
                                          (first "raster-shader")
                                          (second (link-file "raster.wgsl.scm")))
                                        (new Pair
                                          (first "sun-shader")
                                          (second (link-file "sun.wgsl.scm")))
                                        (new Pair
                                          (first "post-shader")
                                          (second (link-file "post.wgsl.scm")))
                                        (new Pair
                                          (first "bvh-shader")
                                          (second (link-file "bvh.wgsl.scm")))
                                        (new Pair
                                          (first "rays-shader")
                                          (second (link-file "rays.wgsl.scm")))
                                        (new Pair
                                          (first "svgf-shader")
                                          (second (link-file "svgf.wgsl.scm")))
                                        (new Pair
                                          (first "environment-shader")
                                          (second (link-file "environment.wgsl.scm")))
                                        (new Pair
                                          (first "environment-light-shader")
                                          (second (link-file "environment-light.wgsl.scm"))))))

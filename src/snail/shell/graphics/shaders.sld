;; The graphics libraries' shaders, printed to WGSL when this library is
;; built, each from the file of its name: `quad-shader` from
;; quad.wgsl.scm, and so `atlas-shader`, `lighting-shader`, `raster-shader`,
;; `sun-shader`, `post-shader`, `scan-shader`, `radix-sort-shader`,
;; `splat-project-shader` and `splat-draw-shader`.
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
                                          (first "scan-shader")
                                          (second (link-file "scan.wgsl.scm")))
                                        (new Pair
                                          (first "radix-sort-shader")
                                          (second (link-file "radix-sort.wgsl.scm")))
                                        (new Pair
                                          (first "splat-project-shader")
                                          (second (link-file "splat-project.wgsl.scm")))
                                        (new Pair
                                          (first "splat-draw-shader")
                                          (second (link-file "splat-draw.wgsl.scm"))))))

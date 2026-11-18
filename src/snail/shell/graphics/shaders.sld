;; The graphics libraries' shaders, printed to WGSL when this library is
;; built, each from the file of its name: `quad-shader` from
;; quad.wgsl.scm, and so `atlas-shader`, `lighting-shader`, `raster-shader`,
;; `sun-shader`, `post-shader`, `scan-shader`, `radix-sort-shader`,
;; `splat-project-shader` and `splat-draw-shader`, and training's
;; `splat-tiles-shader`, `splat-count-shader`, `splat-keys-shader`,
;; `splat-ranges-shader`, `splat-forward-shader`, `splat-backward-shader`
;; and `splat-blur-shader`, and the path tracer's `bvh-shader`,
;; `rays-shader`, `svgf-shader`, `environment-shader` and
;; `environment-light-shader`.
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
                                          (second (link-file "splat-draw.wgsl.scm")))
                                        (new Pair
                                          (first "splat-tiles-shader")
                                          (second (link-file "splat-tiles.wgsl.scm")))
                                        (new Pair
                                          (first "splat-count-shader")
                                          (second (link-file "splat-count.wgsl.scm")))
                                        (new Pair
                                          (first "splat-keys-shader")
                                          (second (link-file "splat-keys.wgsl.scm")))
                                        (new Pair
                                          (first "splat-ranges-shader")
                                          (second (link-file "splat-ranges.wgsl.scm")))
                                        (new Pair
                                          (first "splat-forward-shader")
                                          (second (link-file "splat-forward.wgsl.scm")))
                                        (new Pair
                                          (first "splat-backward-shader")
                                          (second (link-file "splat-backward.wgsl.scm")))
                                        (new Pair
                                          (first "splat-blur-shader")
                                          (second (link-file "splat-blur.wgsl.scm")))
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

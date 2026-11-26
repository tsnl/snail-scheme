;; The graphics libraries' shaders, printed to WGSL when this library is
;; built, each from the file of its name: `quad-shader` from
;; quad.wgsl.scm, and so `atlas-shader`, `lighting-shader`, `raster-shader`,
;; `sun-shader`, `tone-shader`, `post-shader`, `scan-shader`, `radix-sort-shader`,
;; `splat-project-shader`, `splat-draw-shader` and `splat-present-shader`,
;; and training's
;; `splat-tiles-shader`, `splat-count-shader`, `splat-keys-shader`,
;; `splat-ranges-shader`, `splat-forward-shader`,
;; `splat-forward-state-shader`, `splat-backward-shader`,
;; `splat-ssim-shader`, `splat-ssim-forward-shader`,
;; `splat-ssim-backward-shader`, `splat-place-shader`, `splat-normals-shader`
;; and `splat-knn-shader`, and the path tracer's `bvh-shader`,
;; `rays-shader`, `reservoir-operations`, `svgf-shader`, `environment-shader` and
;; `environment-light-shader`.
(generate-library (snail shell graphics shaders)
                  (import
                   (snail core base)
                   (snail shell resource)
                   (snail shell graphics wgsl))
                  (lambda ((resources Resources))
                    (shader-library resources (list "snail" "shell" "graphics" "shaders")
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
                                            (first "upscale-shader")
                                            (second (link-file "upscale.wgsl.scm")))
                                          (new Pair
                                            (first "tone-shader")
                                            (second (link-file "tone.wgsl.scm")))
                                          (new Pair (first "post-shader")
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
                                            (first "splat-present-shader")
                                            (second (link-file "splat-present.wgsl.scm")))
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
                                            (first "splat-forward-state-shader")
                                            (second (link-file "splat-forward-state.wgsl.scm")))
                                          (new Pair
                                            (first "splat-backward-shader")
                                            (second (link-file "splat-backward.wgsl.scm")))
                                          (new Pair
                                            (first "splat-ssim-shader")
                                            (second (link-file "splat-ssim.wgsl.scm")))
                                          (new Pair
                                            (first "splat-ssim-forward-shader")
                                            (second (link-file "splat-ssim-forward.wgsl.scm")))
                                          (new Pair
                                            (first "splat-ssim-backward-shader")
                                            (second (link-file "splat-ssim-backward.wgsl.scm")))
                                          (new Pair
                                            (first "splat-place-shader")
                                            (second (link-file "splat-place.wgsl.scm")))
                                          (new Pair
                                            (first "splat-normals-shader")
                                            (second (link-file "splat-normals.wgsl.scm")))
                                          (new Pair
                                            (first "splat-knn-shader")
                                            (second (link-file "splat-knn.wgsl.scm")))
                                          (new Pair
                                            (first "bvh-shader")
                                            (second (link-file "bvh.wgsl.scm")))
                                          (new Pair
                                            (first "rays-shader")
                                            (second (link-file "rays.wgsl.scm")))
                                          (new Pair
                                            (first "reservoir-operations")
                                            (second (link-file "reservoir.wgsl.scm")))
                                          (new Pair
                                            (first "svgf-shader")
                                            (second (link-file "svgf.wgsl.scm")))
                                          (new Pair
                                            (first "atmosphere-shader")
                                            (second (link-file "atmosphere.wgsl.scm")))
                                          (new Pair
                                            (first "environment-shader")
                                            (second (link-file "environment.wgsl.scm")))
                                          (new Pair
                                            (first "environment-light-shader")
                                            (second (link-file "environment-light.wgsl.scm")))))))

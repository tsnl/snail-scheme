;; WGSL programs shared by the raster, tensor and splat libraries.
(generate-library (snail shell graphics shaders)
                  (import
                   (snail core base)
                   (snail shell resource)
                   (snail shell graphics wgsl))
                  (lambda ((resources Resources))
                    (shader-library resources (list "snail" "shell" "graphics" "shaders")
                                    (list (new Pair
                                            (first "blit-shader")
                                            (second (link-file "blit.wgsl.scm")))
                                          (new Pair
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
                                            (second (link-file "splat-knn.wgsl.scm")))))))

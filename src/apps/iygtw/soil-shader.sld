(generate-library (apps iygtw soil-shader)
                  (import
                   (snail core base)
                   (snail shell resource)
                   (snail shell graphics wgsl))
                  (lambda ((resources Resources))
                    (shader-library resources (list "apps" "iygtw" "soil-shader")
                                    (list (new Pair
                                            (first "mud-shader")
                                            (second (link-file "soil.wgsl.scm")))))))

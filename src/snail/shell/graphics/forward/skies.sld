(generate-library (snail shell graphics forward skies)
                  (import
                   (snail core base)
                   (snail shell syntax)
                   (snail shell graphics forward bake))
                  (let* ((names (list "morning"
                                      "high-sun"
                                      "golden-hour"
                                      "moonrise"
                                      "white-sky"
                                      "brdf-lut"))
                         (skies
                          (map (lambda (id) (bake-environment (lambda (dir) (sky-radiance id dir))))
                               (iota 4)))
                         (white (bake-environment (lambda (d) (white-radiance d))))
                         (values (append skies (list white (bake-brdf)))))
                    (library-syntax (list "snail" "shell" "graphics" "forward" "skies") names
                                    (list (list "snail" "core" "base"))
                                    (map
                                     (lambda (kv) (form "define" (list (SymbolSyntax (● kv first))
                                                                       (form "→"
                                                                             (list (SymbolSyntax
                                                                                    "Bytes")))
                                                                       (BytesSyntax
                                                                        (● kv second)))))
                                     (zip names values)))))

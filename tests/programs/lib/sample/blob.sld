;; A generated library embedding a file's bytes: the recipe reads them and
;; returns them in a byte vector literal, which reaches the compiler as the
;; bytes themselves rather than as text.
(generate-library (sample blob)
                  (import
                   (snail-core base)
                   (snail-core io)
                   (snail-core syntax))
                  (library-syntax (list "sample" "blob")
                                  (list "pixel")
                                  (list (list "snail-core" "base"))
                                  (list (form "define"
                                              (list (SymbolSyntax "pixel")
                                                    (BytesSyntax
                                                     (read-bytes
                                                      "tests/programs/data/pixel.png")))))))

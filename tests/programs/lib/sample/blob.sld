;; A generated library made from files its recipe names, relative to the
;; recipe wherever the build runs it: a PNG's bytes, read by the producer
;; and returned in a byte vector literal, which reaches the compiler as the
;; bytes themselves rather than as text, and the length of a file the
;; producer links and reads when it runs.
(generate-library (sample blob)
                  (import
                   (snail core base)
                   (snail shell resource)
                   (snail shell syntax))
                  (library-syntax
                   (list "sample" "blob")
                   (list "pixel" "greeting-length")
                   (list (list "snail" "core" "base"))
                   (list (form "define"
                               (list (SymbolSyntax "pixel")
                                     (BytesSyntax (read-resource (link-file "data/pixel.png")))))
                         (form "define"
                               (list (SymbolSyntax "greeting-length")
                                     (IntegerSyntax
                                      (vector-length
                                       (read-resource (link-file "data/greeting.txt")))))))))

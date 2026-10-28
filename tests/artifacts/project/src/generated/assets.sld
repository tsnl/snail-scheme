;; Compiling this producer requests client. The syntax it produces requests
;; admin. Both use the same project traversal as the importing program.
(generate-library (generated assets)
                  (import
                   (snail-core base)
                   (snail-core artifact)
                   (snail-core syntax))
                  (let ((client (artifact-bundle "client")))
                    (library-syntax
                     (list "generated" "assets")
                     (list "producer-bytes" "admin-bundle")
                     (list (list "snail-core" "base")
                           (list "snail-core" "artifact"))
                     (list (form "define" (list (SymbolSyntax "producer-bytes")
                                                (BytesSyntax
                                                 (match (artifact-ref client
                                                                      "nested/data.bin")
                                                   ((Some bytes) bytes)
                                                   ((None)
                                                    (panic
                                                     "missing client data"))))))
                           (form ":"
                                 (list (SymbolSyntax "admin-bundle")
                                       (SymbolSyntax "ArtifactBundle")))
                           (form "define"
                                 (list (SymbolSyntax "admin-bundle")
                                       (form "artifact-bundle"
                                             (list
                                              (StringSyntax "admin")))))))))

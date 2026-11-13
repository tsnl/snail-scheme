;; Compiling this producer requests client. The syntax it produces requests
;; admin. Both use the same project traversal as the importing program.
(generate-library (generated assets)
                  (import
                   (snail core base)
                   (snail shell artifact)
                   (snail shell syntax))
                  (let ((client (artifact-bundle "client")))
                    (library-syntax
                     (list "generated" "assets")
                     (list "producer-bytes" "admin-bundle")
                     (list (list "snail" "core" "base") (list "snail" "shell" "artifact"))
                     (list (form "define" (list (form "producer-bytes" (Nil))
                                                (form "→" (list (SymbolSyntax "Bytes")))
                                                (BytesSyntax
                                                 (match (artifact-ref client "nested/data.bin")
                                                   ((Some bytes) bytes)
                                                   ((None) (panic "missing client data"))))))
                           (form "define"
                                 (list (form "admin-bundle" (Nil))
                                       (form "→" (list (SymbolSyntax "ArtifactBundle")))
                                       (form "artifact-bundle" (list (StringSyntax "admin")))))))))

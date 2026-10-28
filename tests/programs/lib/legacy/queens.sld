;; A Scheme program translated to Snail-Core when the library is built.
(generate-library (legacy queens)
                  (import
                   (snail-core base)
                   (snail-core io)
                   (scheme compiler))
                  (scheme->snail-core-library (list "legacy" "queens")
                                              (read-file
                                               "tests/programs/scheme/queens.scm")))

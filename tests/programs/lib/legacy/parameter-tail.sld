(generate-library (legacy parameter-tail)
                  (import
                   (snail-core base)
                   (scheme compiler))
                  (scheme->snail-core-library (list "legacy" "parameter-tail")
                                              "(lambda (x . 7) x)"))

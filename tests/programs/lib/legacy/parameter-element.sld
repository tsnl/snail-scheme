(generate-library (legacy parameter-element)
                  (import
                   (snail-core base)
                   (scheme compiler))
                  (scheme->snail-core-library (list "legacy" "parameter-element")
                                              "(lambda (x 7) x)"))

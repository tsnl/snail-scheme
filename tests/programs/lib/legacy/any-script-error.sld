(generate-library (legacy any-script-error)
                  (import
                   (snail core base)
                   (scheme compiler))
                  (scheme->snail-core-library (list "legacy" "any-script-error")
                                              "(car #t) (display \"unreachable\")"))

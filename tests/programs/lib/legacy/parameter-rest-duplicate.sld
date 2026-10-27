(generate-library (legacy parameter-rest-duplicate)
                  (import
                   (snail-core base)
                   (scheme compiler))
                  (scheme->snail-core-library (list "legacy" "parameter-rest-duplicate") "(lambda (a r . r) r)"))

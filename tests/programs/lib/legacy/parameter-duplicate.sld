(generate-library (legacy parameter-duplicate)
                  (import
                   (snail-core base)
                   (scheme compiler))
                  (scheme->snail-core-library (list "legacy" "parameter-duplicate") "(lambda (x x) x)"))

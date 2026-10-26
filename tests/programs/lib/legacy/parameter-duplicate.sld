(generate-library (legacy parameter-duplicate)
                  (import
                   (lofi base)
                   (scheme compiler))
                  (scheme->lofi-library (list "legacy" "parameter-duplicate") "(lambda (x x) x)"))

(generate-library (legacy parameter-rest-duplicate)
                  (import
                   (lofi base)
                   (scheme compiler))
                  (scheme->lofi-library (list "legacy" "parameter-rest-duplicate") "(lambda (a r . r) r)"))

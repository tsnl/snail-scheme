(generate-library (legacy parameter-element)
                  (import
                   (lofi base)
                   (scheme compiler))
                  (scheme->lofi-library (list "legacy" "parameter-element") "(lambda (x 7) x)"))

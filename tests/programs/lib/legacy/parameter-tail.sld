(generate-library (legacy parameter-tail)
                  (import
                   (lofi base)
                   (scheme compiler))
                  (scheme->lofi-library (list "legacy" "parameter-tail") "(lambda (x . 7) x)"))

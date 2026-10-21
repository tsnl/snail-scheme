;; A Scheme program translated to Lofi when the library is built.
(generate-library (legacy queens)
                  (import
                   (lofi io)
                   (scheme compiler))
                  (scheme->lofi-library "(legacy queens)" (read-file "tests/programs/scheme/queens.scm")))

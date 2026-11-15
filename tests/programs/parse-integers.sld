(import
 (snail core base)
 (snail core io))

(define (main) (→ Unit) (! output-port)
  (for-each (lambda (text) (write (string->i64 text)) (newline))
            (list "0"
                  "-0"
                  "+7"
                  "00042"
                  "9223372036854775807"
                  "-9223372036854775808"
                  "9223372036854775808"
                  "-9223372036854775809"
                  "99999999999999999999999999999999"
                  ""
                  "+"
                  "-"
                  " 1"
                  "1 "
                  "1/1"
                  "#x10"
                  "#e1"
                  "1.0"
                  "1e2"
                  "12x"
                  "١"))
  (unit))

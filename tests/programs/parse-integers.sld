(import
 (snail-core base)
 (snail-core io))

(for-each (lambda (text) (display (string->i64 text)) (newline))
          (list "0" "-42" "+7" "9223372036854775807" "-9223372036854775808" "9223372036854775808" "12x" "" "-"))

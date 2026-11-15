;; Unicode properties and case mapping from (snail shell text)'s tables:
;; simple mappings, flags, digits in other scripts, and full folds that
;; expand one scalar into several.
(import
 (snail core base)
 (snail core io)
 (snail shell text))

(define (yes (flag Bool)) (→ String)
  (if flag "#t" "#f"))

(define (digit (char Char)) (→ String)
  (match (char-digit-value char)
    ((Some value) (show value))
    ((None) "none")))

(define (main) (→ Unit) (! output-port)
  (write-line (list->string (map char-upcase (string->list "λßᾳa"))))
  (write-line (list->string (map char-downcase (string->list "İΛA"))))
  ;; U+017F, the long s, is written by number: the editors' grammar does not
  ;; yet read it in a string (#781).
  (write-line (list->string (map char-foldcase (list #\ς (integer->char 383) #\İ #\ᾼ))))
  (write-line (string-join (map yes (list (char-lower-case? #\λ)
                                          (char-lower-case? #\Λ)
                                          (char-lower-case? #\😀)
                                          (char-upper-case? #\Λ)
                                          (char-unicode-alphabetic? #\λ)
                                          (char-unicode-alphabetic? #\3)
                                          (char-unicode-whitespace? (integer->char 12288))
                                          (char-unicode-whitespace? #\x)
                                          (char-unicode-numeric? #\٣)))
                           " "))
  (write-line (string-join (map digit (string->list "٣9Ⅷ²x")) " "))
  (write-line (string-foldcase "StraßeΣςİ"))
  (write-line
   (string-join (map (lambda (char) (show (string-length (string-foldcase (make-string 1 char)))))
                     (string->list "ßΐİﬃᎠ"))
                " "))
  (write-line (show (string-length (string-foldcase (make-string 1 (integer->char 0)))))))

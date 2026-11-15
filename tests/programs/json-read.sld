;; JSON text read back. What the writer writes reads back as it was, so
;; each value is written again unchanged; whitespace and every escape read
;; as JavaScript's JSON.parse reads them, and the expected output of the
;; valid texts was checked against JSON.stringify(JSON.parse(text)). Text
;; that is not one JSON value of integers reads as nothing.
(import
 (snail core base)
 (snail core io)
 (snail shell json)
 (snail shell json read))

(define (read-back (text String)) (→ String)
  (match (string->json text)
    ((Some value) (json->string value))
    ((None) "nothing")))

(define (written) (→ (List Json))
  (list (Json-null)
        (Json-integer -9223372036854775808)
        (Json-string "quote \" backslash \\ tab\tend λ 😀")
        (Json-string (list->string (list (integer->char 55296) (integer->char 31))))
        (Json-array (list (Json-integer 1) (Json-array (Nil)) (Json-object (Nil))))
        (Json-object (list (new Pair (first "a") (second (Json-bool #t)))
                           (new Pair (first "a") (second (Json-bool #f)))))))

(define (main) (→ Unit) (! Output-port)
  (for-each (lambda (value) (write-line (read-back (json->string value)))) (written))
  (for-each (lambda (text) (write-line (read-back text)))
            (list
             " { \"runtime\" : \"runtime.wasm\" ,\n \"modules\" : [ {\"name\": \"main\", \"file\": \"main.wasm\"} ] } "
             "\"\\u00e9\\ud83d\\ude00 \\ud800 \\/\\b\\f\\n\\r\\t\""
             "-0"
             "[1,]"
             "{\"a\" 1}"
             "{\"a\":1,}"
             "1.5"
             "2e3"
             "tru"
             "\"\\x\""
             "[1] 2"
             "\"\n\""
             "99999999999999999999"
             ""
             "{1:2}"))
  (match (string->json "{\"a\": 1, \"b\": 2, \"a\": 3}")
    ((Some value)
     (for-each (lambda (name)
                 (write-line (match (json-member value name)
                               ((Some member) (json->string member))
                               ((None) "no member"))))
               (list "a" "b" "c")))
    ((None) (write-line "nothing")))
  (unit))

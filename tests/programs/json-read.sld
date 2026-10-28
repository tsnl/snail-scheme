;; JSON text read back. What the writer writes reads back as it was, so
;; each value is written again unchanged; whitespace and every escape read
;; as JavaScript's JSON.parse reads them, and the expected output of the
;; valid texts was checked against JSON.stringify(JSON.parse(text)). Text
;; that is not one JSON value of integers reads as nothing.
(import
 (snail-core base)
 (snail-core io)
 (snail-core json)
 (snail-core json read))

(: read-back (-> String String))
(define (read-back text)
  (match (string->json text)
    ((Some value) (json->string value))
    ((None) "nothing")))

(: written (List Json))
(define written
  (list (JsonNull)
        (JsonInteger -9223372036854775808)
        (JsonString "quote \" backslash \\ tab\tend λ 😀")
        (JsonString (list->string (list (integer->char 55296) (integer->char 31))))
        (JsonArray (list (JsonInteger 1) (JsonArray (Nil)) (JsonObject (Nil))))
        (JsonObject (list (Pair "a" (JsonBool #t)) (Pair "a" (JsonBool #f))))))

(for-each (lambda (value) (write-line (read-back (json->string value)))) written)

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

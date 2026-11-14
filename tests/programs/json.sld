;; JSON text for each kind of value. The expected output was produced once
;; by Node's JSON.stringify for the same values, except the last three
;; lines, which JavaScript cannot express: a name given twice, which no
;; JavaScript object has, and the I64 extremes, which are beyond its exact
;; integers and were written by BigInt's toString.
(import
 (snail core base)
 (snail core io)
 (snail shell json))

(define (chars (codes (List I64))) (→ String)
  (list->string (map integer->char codes)))

(define (controls) (→ String) (chars (append (iota 32) (list 127))))

;; A mebibyte of text in lines, as a file's contents would be sent.
(define (long-text) (→ String)
  (string-concatenate (map (lambda (line)
                             (string-append (make-string 63 (integer->char (+ 97 (modulo line 26))))
                                            "\n"))
                           (iota 16384))))

(define (main) (→ Unit) (! output-port)
  (for-each (lambda (value) (write-line (json->string value)))
            (list (JsonNull)
                  (JsonBool #t)
                  (JsonBool #f)
                  (JsonInteger 0)
                  (JsonInteger -1)
                  (JsonInteger 42)
                  (JsonInteger 9007199254740991)
                  (JsonInteger -9007199254740991)
                  (JsonString "")
                  (JsonString "plain")
                  (JsonString "quote \" backslash \\ slash / tab\tend")
                  (JsonString (controls))
                  (JsonString "λ € 😀 \x2028; \x2029; \xfeff;")
                  (JsonString (string-append "a" (chars (list 55296)) "b"))
                  (JsonString (chars (list 57343)))
                  (JsonString (chars (list 56832 55357)))
                  (JsonArray (Nil))
                  (JsonObject (Nil))
                  (JsonArray (list (JsonInteger 1)
                                   (JsonArray (list (JsonInteger 2) (JsonArray (Nil))))
                                   (JsonObject (Nil))))
                  (JsonObject (list (new Pair (first "b") (second (JsonInteger 1)))
                                    (new Pair
                                      (first "a")
                                      (second (JsonArray (list (JsonBool #t) (JsonNull)))))))
                  (JsonObject
                   (list (new Pair (first "k\"\n") (second (JsonString "v")))
                         (new Pair (first "") (second (JsonString "empty name")))))
                  (JsonObject (list (new Pair (first "phase") (second (JsonString "failed")))
                                    (new Pair (first "id") (second (JsonInteger 3)))
                                    (new Pair (first "diagnostics")
                                         (second (JsonArray (list (JsonObject
                                                                   (list (new Pair (first "message")
                                                                              (second (JsonString
                                                                                       "unbound name: x")))
                                                                         (new Pair (first "line")
                                                                              (second (JsonInteger
                                                                                       12)))))))))
                                    (new Pair (first "published") (second (JsonNull)))
                                    (new Pair (first "runs") (second (JsonArray (Nil))))))))
  (let ((text (json->string (JsonString (long-text)))))
    (write-line (show (string-length text)))
    (write-line (substring text 0 70)))
  (write-line
   (json->string (JsonObject (list (new Pair (first "a") (second (JsonInteger 1)))
                                   (new Pair (first "a") (second (JsonInteger 2)))))))
  (write-line (json->string (JsonInteger 9223372036854775807)))
  (write-line (json->string (JsonInteger -9223372036854775808)))
  (unit))

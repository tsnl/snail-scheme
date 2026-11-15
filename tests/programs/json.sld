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

(define (main) (→ Unit) (! Output-port)
  (for-each (lambda (value) (write-line (json->string value)))
            (list (Json-null)
                  (Json-bool #t)
                  (Json-bool #f)
                  (Json-integer 0)
                  (Json-integer -1)
                  (Json-integer 42)
                  (Json-integer 9007199254740991)
                  (Json-integer -9007199254740991)
                  (Json-string "")
                  (Json-string "plain")
                  (Json-string "quote \" backslash \\ slash / tab\tend")
                  (Json-string (controls))
                  (Json-string "λ € 😀 \x2028; \x2029; \xfeff;")
                  (Json-string (string-append "a" (chars (list 55296)) "b"))
                  (Json-string (chars (list 57343)))
                  (Json-string (chars (list 56832 55357)))
                  (Json-array (Nil))
                  (Json-object (Nil))
                  (Json-array (list (Json-integer 1)
                                    (Json-array (list (Json-integer 2) (Json-array (Nil))))
                                    (Json-object (Nil))))
                  (Json-object (list (new Pair (first "b") (second (Json-integer 1)))
                                     (new Pair
                                       (first "a")
                                       (second (Json-array (list (Json-bool #t) (Json-null)))))))
                  (Json-object
                   (list (new Pair (first "k\"\n") (second (Json-string "v")))
                         (new Pair (first "") (second (Json-string "empty name")))))
                  (Json-object (list (new Pair (first "phase") (second (Json-string "failed")))
                                     (new Pair (first "id") (second (Json-integer 3)))
                                     (new Pair (first "diagnostics")
                                          (second (Json-array (list (Json-object
                                                                     (list
                                                                      (new Pair (first "message")
                                                                           (second (Json-string
                                                                                    "unbound name: x")))
                                                                      (new Pair (first "line")
                                                                           (second (Json-integer
                                                                                    12)))))))))
                                     (new Pair (first "published") (second (Json-null)))
                                     (new Pair (first "runs") (second (Json-array (Nil))))))))
  (let ((text (json->string (Json-string (long-text)))))
    (write-line (show (string-length text)))
    (write-line (substring text 0 70)))
  (write-line
   (json->string (Json-object (list (new Pair (first "a") (second (Json-integer 1)))
                                    (new Pair (first "a") (second (Json-integer 2)))))))
  (write-line (json->string (Json-integer 9223372036854775807)))
  (write-line (json->string (Json-integer -9223372036854775808)))
  (unit))

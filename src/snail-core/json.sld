;; JSON values and their compact text, written as JavaScript's
;; `JSON.stringify` writes the same value. This is a writer only: a program
;; that emits JSON builds a `Json` and writes it.
(define-library (snail-core json)
  (export
   Json
   JsonNull
   JsonBool
   JsonInteger
   JsonString
   JsonArray
   JsonObject
   json->string)
  (import
   (snail-core base))
  (begin

    ;; ---- Values ----

    ;; Numbers are integers, which is all a program here needs to say: ids,
    ;; sizes, counts and exit codes. An object is its members in order, so
    ;; its text is the same on every run; a name given twice is written
    ;; twice. JavaScript reads an integer beyond 2^53 to the nearest double,
    ;; so one that must survive exactly goes as a string. A JavaScript
    ;; object puts names such as "0" and "42" first, in numeric order, so
    ;; an object keyed by numbers is written as an array of records.
    (enum Json
      (JsonNull)
      (JsonBool ((value Bool)))
      (JsonInteger ((value I64)))
      (JsonString ((value String)))
      (JsonArray ((items (List Json))))
      (JsonObject ((members (List (Pair String Json))))))

    ;; ---- Strings ----

    (: hex4 (-> I32 String))
    (define (hex4 code)
      (string-generate 4
                       (lambda (index)
                         (string-ref "0123456789abcdef"
                                     (i32->i64 (i32-and (i32-shift-right/logical code
                                                                                 (i64->i32 (* 4
                                                                                              (- 3
                                                                                                 index))))
                                                        15))))))

    ;; `JSON.stringify`'s escapes: the quote and the backslash, the five
    ;; controls with short forms, and every other control as \u and four
    ;; lowercase hex digits. A surrogate escapes the same way: a Snail
    ;; String holds scalars, so a surrogate Char, which only `i32->char`
    ;; makes, is always alone, and JavaScript escapes a lone surrogate.
    ;; Everything else, DEL, U+2028 and U+2029 among it, is written as it is.
    (: escape (-> Char (Option String)))
    (define (escape char)
      (let ((code (char->i32 char)))
        (cond ((= code 34) (Some "\\\""))
              ((= code 92) (Some "\\\\"))
              ((= code 8) (Some "\\b"))
              ((= code 9) (Some "\\t"))
              ((= code 10) (Some "\\n"))
              ((= code 12) (Some "\\f"))
              ((= code 13) (Some "\\r"))
              ((or (< code 32) (and (>= code 55296) (<= code 57343)))
               (Some (string-append "\\u" (hex4 code))))
              (else (None)))))

    ;; Each run of characters between escapes is copied as one substring,
    ;; so a long text with few escapes, a file's contents, is a few pieces.
    (: string-pieces (-> String (List String) (List String)))
    (define (string-pieces text pieces)
      (let loop ((start 0) (index 0) (pieces (Cons "\"" pieces)))
        (if (= index (string-length text))
            (Cons "\"" (Cons (substring text start index) pieces))
            (match (escape (string-ref text index))
              ((None) (loop start (+ index 1) pieces))
              ((Some escaped)
               (loop (+ index 1)
                     (+ index 1)
                     (Cons escaped (Cons (substring text start index) pieces))))))))

    ;; ---- Writing ----

    ;; The pieces of a value's text, prepended in reverse to `pieces`, so
    ;; that writing is one pass and one final concatenation.
    (: value-pieces (-> Json (List String) (List String)))
    (define (value-pieces value pieces)
      (match value
        ((JsonNull) (Cons "null" pieces))
        ((JsonBool flag) (Cons (if flag "true" "false") pieces))
        ((JsonInteger number) (Cons (i64->string number) pieces))
        ((JsonString text) (string-pieces text pieces))
        ((JsonArray items) (Cons "]" (separated value-pieces items (Cons "[" pieces))))
        ((JsonObject members) (Cons "}" (separated member-pieces members (Cons "{" pieces))))))

    (: member-pieces (-> (Pair String Json) (List String) (List String)))
    (define (member-pieces member pieces)
      (value-pieces (Pair-second member) (Cons ":" (string-pieces (Pair-first member) pieces))))

    ;; Items with a comma between each two, and no spaces anywhere.
    (: separated
       (All (T) (-> (-> T (List String) (List String)) (List T) (List String) (List String))))
    (define (separated write items pieces)
      (match items
        ((Nil) pieces)
        ((Cons first rest)
         (fold-left (lambda (pieces item) (write item (Cons "," pieces)))
                    (write first pieces)
                    rest))))

    (: json->string (-> Json String))
    (define (json->string value)
      (string-concatenate (reverse (value-pieces value (Nil)))))

    ))

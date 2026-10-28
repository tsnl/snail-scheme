;; JSON text read back into the values (snail-core json) writes: any JSON
;; text whose numbers are integers, such as a modules.json. A library of
;; its own, so that a program that only writes JSON does not carry it.
(define-library (snail-core json read)
  (export
   string->json
   json-member)
  (import
   (snail-core base)
   (snail-core json))
  (begin

    ;; ---- Reading ----

    ;; A text's value, or None unless the text is one value with only
    ;; whitespace around it. A number must be an integer that fits an I64,
    ;; as the writer's are. An escape gives the scalar it names, a surrogate
    ;; pair one scalar and a lone surrogate the Char that `i32->char` makes,
    ;; so what the writer wrote reads back as it was. Each reader takes the
    ;; text and the index where its value starts, and gives the value with
    ;; the index after it.
    (: string->json (-> String (Option Json)))
    (define (string->json text)
      (let ((chars (string->vector text)))
        (match (read-value chars (skip-space chars 0))
          ((Some (Pair value end)) (if (= (skip-space chars end) (vector-length chars)) (Some value) (None)))
          ((None) (None)))))

    ;; The value of an object's first member named `name`.
    (: json-member (-> Json String (Option Json)))
    (define (json-member value name)
      (match value
        ((JsonObject members) (assoc-ref members name))
        (_ (None))))

    ;; ---- Values ----

    (: skip-space (-> (Vector Char) I64 I64))
    (define (skip-space chars index)
      (if (and (< index (vector-length chars)) (member? (vector-ref chars index) (list #\space #\tab #\newline (integer->char 13))))
          (skip-space chars (+ index 1))
          index))

    (: at? (-> (Vector Char) I64 Char Bool))
    (define (at? chars index char)
      (and (< index (vector-length chars)) (char=? (vector-ref chars index) char)))

    (: read-value (-> (Vector Char) I64 (Option (Pair Json I64))))
    (define (read-value chars index)
      (cond ((at? chars index #\{) (read-members chars (skip-space chars (+ index 1)) (Nil)))
            ((at? chars index #\[) (read-items chars (skip-space chars (+ index 1)) (Nil)))
            ((at? chars index #\") (read-string-value chars (+ index 1)))
            ((at? chars index #\t) (read-word chars index "true" (JsonBool #t)))
            ((at? chars index #\f) (read-word chars index "false" (JsonBool #f)))
            ((at? chars index #\n) (read-word chars index "null" (JsonNull)))
            (else (read-integer chars index))))

    (: read-word (-> (Vector Char) I64 String Json (Option (Pair Json I64))))
    (define (read-word chars index word value)
      (let ((end (+ index (string-length word))))
        (if (and (<= end (vector-length chars)) (string=? (vector->string (subvector chars index end)) word))
            (Some (Pair value end))
            (None))))

    ;; An optional minus and digits, which a fraction or an exponent must
    ;; not follow.
    (: read-integer (-> (Vector Char) I64 (Option (Pair Json I64))))
    (define (read-integer chars index)
      (let ((end (digits-end chars (if (at? chars index #\-) (+ index 1) index))))
        (match (if (any? (lambda (char) (at? chars end char)) (list #\. #\e #\E)) (None) (string->i64 (vector->string (subvector chars index end))))
          ((Some number) (Some (Pair (JsonInteger number) end)))
          ((None) (None)))))

    (: digits-end (-> (Vector Char) I64 I64))
    (define (digits-end chars index)
      (if (and (< index (vector-length chars)) (char-numeric? (vector-ref chars index))) (digits-end chars (+ index 1)) index))

    ;; An array's items after its `[`; `items` holds those read so far,
    ;; newest first.
    (: read-items (-> (Vector Char) I64 (List Json) (Option (Pair Json I64))))
    (define (read-items chars index items)
      (if (and (null? items) (at? chars index #\]))
          (Some (Pair (JsonArray (Nil)) (+ index 1)))
          (match (read-value chars index)
            ((Some (Pair item end))
             (let ((next (skip-space chars end)) (items (Cons item items)))
               (cond ((at? chars next #\,) (read-items chars (skip-space chars (+ next 1)) items))
                     ((at? chars next #\]) (Some (Pair (JsonArray (reverse items)) (+ next 1))))
                     (else (None)))))
            ((None) (None)))))

    ;; An object's members after its `{`, as an array's items.
    (: read-members (-> (Vector Char) I64 (List (Pair String Json)) (Option (Pair Json I64))))
    (define (read-members chars index members)
      (if (and (null? members) (at? chars index #\}))
          (Some (Pair (JsonObject (Nil)) (+ index 1)))
          (match (read-member chars index)
            ((Some (Pair member end))
             (let ((next (skip-space chars end)) (members (Cons member members)))
               (cond ((at? chars next #\,) (read-members chars (skip-space chars (+ next 1)) members))
                     ((at? chars next #\}) (Some (Pair (JsonObject (reverse members)) (+ next 1))))
                     (else (None)))))
            ((None) (None)))))

    ;; A member's name, a colon and its value.
    (: read-member (-> (Vector Char) I64 (Option (Pair (Pair String Json) I64))))
    (define (read-member chars index)
      (match (if (at? chars index #\") (read-string chars (+ index 1) (Nil)) (None))
        ((Some (Pair name end))
         (let ((colon (skip-space chars end)))
           (match (if (at? chars colon #\:) (read-value chars (skip-space chars (+ colon 1))) (None))
             ((Some (Pair value after)) (Some (Pair (Pair name value) after)))
             ((None) (None)))))
        ((None) (None))))

    ;; ---- Strings ----

    (: read-string-value (-> (Vector Char) I64 (Option (Pair Json I64))))
    (define (read-string-value chars index)
      (match (read-string chars index (Nil))
        ((Some (Pair text end)) (Some (Pair (JsonString text) end)))
        ((None) (None))))

    ;; A string's text after its opening quote, and the index after its
    ;; closing one; `text` holds the characters read so far, newest first.
    ;; A control character must be escaped.
    (: read-string (-> (Vector Char) I64 (List Char) (Option (Pair String I64))))
    (define (read-string chars index text)
      (cond ((at? chars index #\") (Some (Pair (list->string (reverse text)) (+ index 1))))
            ((at? chars index #\\)
             (match (read-escape chars (+ index 1))
               ((Some (Pair char next)) (read-string chars next (Cons char text)))
               ((None) (None))))
            ((and (< index (vector-length chars)) (>= (char->i32 (vector-ref chars index)) 32))
             (read-string chars (+ index 1) (Cons (vector-ref chars index) text)))
            (else (None))))

    (: short-escapes (List (Pair Char Char)))
    (define short-escapes
      (list (Pair #\" #\") (Pair #\\ #\\) (Pair #\/ #\/) (Pair #\b (integer->char 8)) (Pair #\f (integer->char 12))
            (Pair #\n #\newline) (Pair #\r (integer->char 13)) (Pair #\t #\tab)))

    ;; The character an escape names, after its backslash.
    (: read-escape (-> (Vector Char) I64 (Option (Pair Char I64))))
    (define (read-escape chars index)
      (if (at? chars index #\u)
          (read-unicode chars (+ index 1))
          (match (if (< index (vector-length chars)) (assoc-ref short-escapes (vector-ref chars index)) (None))
            ((Some char) (Some (Pair char (+ index 1))))
            ((None) (None)))))

    ;; Four hex digits after `\u`; a high surrogate that an escaped low one
    ;; follows makes one scalar with it.
    (: read-unicode (-> (Vector Char) I64 (Option (Pair Char I64))))
    (define (read-unicode chars index)
      (match (hex-value chars index)
        ((Some code)
         (match (low-surrogate chars (+ index 4) code)
           ((Some low) (Some (Pair (i32->char (+ (+ 65536 (* (- code 55296) 1024)) (- low 56320))) (+ index 10))))
           ((None) (Some (Pair (i32->char code) (+ index 4))))))
        ((None) (None))))

    ;; The low surrogate escaped at `index`, when `high` is a high one.
    (: low-surrogate (-> (Vector Char) I64 I32 (Option I32)))
    (define (low-surrogate chars index high)
      (match (if (and (>= high 55296) (<= high 56319) (at? chars index #\\) (at? chars (+ index 1) #\u)) (hex-value chars (+ index 2)) (None))
        ((Some low) (if (and (>= low 56320) (<= low 57343)) (Some low) (None)))
        ((None) (None))))

    (: hex-value (-> (Vector Char) I64 (Option I32)))
    (define (hex-value chars index)
      (fold-left (lambda (value offset)
                   (match (Pair value (if (< (+ index offset) (vector-length chars)) (hex-digit (vector-ref chars (+ index offset))) (None)))
                     ((Pair (Some total) (Some digit)) (Some (+ (* total 16) digit)))
                     (_ (None))))
                 (ann (Some 0) (Option I32)) (iota 4)))

    ;; Lowercase digits come first, uppercase sixteen places later.
    (: hex-digit (-> Char (Option I32)))
    (define (hex-digit char)
      (match (string-index "0123456789abcdef0123456789ABCDEF" char)
        ((Some position) (Some (i64->i32 (remainder position 16))))
        ((None) (None))))))

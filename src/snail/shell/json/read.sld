;; JSON text read back into the values (snail shell json) writes: any JSON
;; text whose numbers are integers, such as a modules.json. A library of
;; its own, so that a program that only writes JSON does not carry it.
(define-library (snail shell json read)
  (export
   string->json
   json-member)
  (import
   (snail core base)
   (snail shell json))
  (begin

    ;; ---- Reading ----

    ;; A text's value, or None unless the text is one value with only
    ;; whitespace around it. A number must be an integer that fits an I64,
    ;; as the writer's are. An escape gives the scalar it names, a surrogate
    ;; pair one scalar and a lone surrogate the Char that `i32->char` makes,
    ;; so what the writer wrote reads back as it was. Each reader takes the
    ;; text and the index where its value starts, and gives the value with
    ;; the index after it.

    (define (string->json (text String)) (→ (Option Json))
      (let ((chars (string->vector text)))
        (match (read-value chars (skip-space chars 0))
          ((Some (Pair value end))
           (if (= (skip-space chars end) (vector-length chars)) (Some value) (None)))
          ((None) (None)))))

    ;; The value of an object's first member named `name`.

    (define (json-member (value Json) (name String)) (→ (Option Json))
      (match value
        ((JsonObject members) (assoc-ref members name))
        (_ (None))))

    ;; ---- Values ----

    (define (skip-space (chars (Vector Char)) (index I64)) (→ I64)
      (if (and (< index (vector-length chars))
               (member? (vector-ref chars index) (list #\space #\tab #\newline (integer->char 13))))
          (skip-space chars (+ index 1))
          index))

    (define (at? (chars (Vector Char)) (index I64) (char Char)) (→ Bool)
      (and (< index (vector-length chars)) (char=? (vector-ref chars index) char)))

    (define (read-value (chars (Vector Char)) (index I64)) (→ (Option (Pair Json I64)))
      (cond ((at? chars index #\{) (read-members chars (skip-space chars (+ index 1)) (Nil)))
            ((at? chars index #\[) (read-items chars (skip-space chars (+ index 1)) (Nil)))
            ((at? chars index #\") (read-string-value chars (+ index 1)))
            ((at? chars index #\t) (read-word chars index "true" (JsonBool #t)))
            ((at? chars index #\f) (read-word chars index "false" (JsonBool #f)))
            ((at? chars index #\n) (read-word chars index "null" (JsonNull)))
            (else (read-integer chars index))))

    (define (read-word (chars (Vector Char)) (index I64) (word String) (value Json))
      (→ (Option (Pair Json I64)))
      (let ((end (+ index (string-length word))))
        (if (and (<= end (vector-length chars))
                 (string=? (vector->string (subvector chars index end)) word))
            (Some (new Pair (first value) (second end)))
            (None))))

    ;; An optional minus and digits, which a fraction or an exponent must
    ;; not follow.

    (define (read-integer (chars (Vector Char)) (index I64)) (→ (Option (Pair Json I64)))
      (let ((end (digits-end chars (if (at? chars index #\-) (+ index 1) index))))
        (match (if (any? (lambda (char) (at? chars end char)) (list #\. #\e #\E))
                   (None)
                   (string->i64 (vector->string (subvector chars index end))))
          ((Some number) (Some (new Pair (first (JsonInteger number)) (second end))))
          ((None) (None)))))

    (define (digits-end (chars (Vector Char)) (index I64)) (→ I64)
      (if (and (< index (vector-length chars)) (char-numeric? (vector-ref chars index)))
          (digits-end chars (+ index 1))
          index))

    ;; An array's items after its `[`; `items` holds those read so far,
    ;; newest first.

    (define (read-items (chars (Vector Char)) (index I64) (items (List Json)))
      (→ (Option (Pair Json I64)))
      (if (and (null? items) (at? chars index #\]))
          (Some (new Pair (first (JsonArray (Nil))) (second (+ index 1))))
          (match (read-value chars index)
            ((Some (Pair item end))
             (let ((next (skip-space chars end)) (items (Cons item items)))
               (cond ((at? chars next #\,) (read-items chars (skip-space chars (+ next 1)) items))
                     ((at? chars next #\])
                      (Some (new Pair (first (JsonArray (reverse items))) (second (+ next 1)))))
                     (else (None)))))
            ((None) (None)))))

    ;; An object's members after its `{`, as an array's items.

    (define (read-members (chars (Vector Char)) (index I64) (members (List (Pair String Json))))
      (→ (Option (Pair Json I64)))
      (if (and (null? members) (at? chars index #\}))
          (Some (new Pair (first (JsonObject (Nil))) (second (+ index 1))))
          (match (read-member chars index)
            ((Some (Pair member end))
             (let ((next (skip-space chars end)) (members (Cons member members)))
               (cond
                ((at? chars next #\,) (read-members chars (skip-space chars (+ next 1)) members))
                ((at? chars next #\})
                 (Some (new Pair (first (JsonObject (reverse members))) (second (+ next 1)))))
                (else (None)))))
            ((None) (None)))))

    ;; A member's name, a colon and its value.

    (define (read-member (chars (Vector Char)) (index I64))
      (→ (Option (Pair (Pair String Json) I64)))
      (match (if (at? chars index #\") (read-string chars (+ index 1) (Nil)) (None))
        ((Some (Pair name end))
         (let ((colon (skip-space chars end)))
           (match (if (at? chars colon #\:)
                      (read-value chars (skip-space chars (+ colon 1)))
                      (None))
             ((Some (Pair value after))
              (Some (new Pair (first (new Pair (first name) (second value))) (second after))))
             ((None) (None)))))
        ((None) (None))))

    ;; ---- Strings ----

    (define (read-string-value (chars (Vector Char)) (index I64)) (→ (Option (Pair Json I64)))
      (match (read-string chars index (Nil))
        ((Some (Pair text end)) (Some (new Pair (first (JsonString text)) (second end))))
        ((None) (None))))

    ;; A string's text after its opening quote, and the index after its
    ;; closing one; `text` holds the characters read so far, newest first.
    ;; A control character must be escaped.

    (define (read-string (chars (Vector Char)) (index I64) (text (List Char)))
      (→ (Option (Pair String I64)))
      (cond ((at? chars index #\")
             (Some (new Pair (first (list->string (reverse text))) (second (+ index 1)))))
            ((at? chars index #\\)
             (match (read-escape chars (+ index 1))
               ((Some (Pair char next)) (read-string chars next (Cons char text)))
               ((None) (None))))
            ((and (< index (vector-length chars)) (>= (char->i32 (vector-ref chars index)) 32))
             (read-string chars (+ index 1) (Cons (vector-ref chars index) text)))
            (else (None))))

    (define (short-escapes) (→ (List (Pair Char Char)))
      (list (new Pair (first #\") (second #\"))
            (new Pair (first #\\) (second #\\))
            (new Pair (first #\/) (second #\/))
            (new Pair (first #\b) (second (integer->char 8)))
            (new Pair (first #\f) (second (integer->char 12)))
            (new Pair (first #\n) (second #\newline))
            (new Pair (first #\r) (second (integer->char 13)))
            (new Pair (first #\t) (second #\tab))))

    ;; The character an escape names, after its backslash.

    (define (read-escape (chars (Vector Char)) (index I64)) (→ (Option (Pair Char I64)))
      (if (at? chars index #\u)
          (read-unicode chars (+ index 1))
          (match (if (< index (vector-length chars))
                     (assoc-ref (short-escapes) (vector-ref chars index))
                     (None))
            ((Some char) (Some (new Pair (first char) (second (+ index 1)))))
            ((None) (None)))))

    ;; Four hex digits after `\u`; a high surrogate that an escaped low one
    ;; follows makes one scalar with it.

    (define (read-unicode (chars (Vector Char)) (index I64)) (→ (Option (Pair Char I64)))
      (match (hex-value chars index)
        ((Some code)
         (match (low-surrogate chars (+ index 4) code)
           ((Some low)
            (Some
             (new Pair
               (first (i32->char (+ (+ 65536 (* (- code 55296) 1024)) (- low 56320))))
               (second (+ index 10)))))
           ((None) (Some (new Pair (first (i32->char code)) (second (+ index 4)))))))
        ((None) (None))))

    ;; The low surrogate escaped at `index`, when `high` is a high one.

    (define (low-surrogate (chars (Vector Char)) (index I64) (high I32)) (→ (Option I32))
      (match (if (and (>= high 55296)
                      (<= high 56319)
                      (at? chars index #\\)
                      (at? chars (+ index 1) #\u))
                 (hex-value chars (+ index 2))
                 (None))
        ((Some low) (if (and (>= low 56320) (<= low 57343)) (Some low) (None)))
        ((None) (None))))

    (define (hex-value (chars (Vector Char)) (index I64)) (→ (Option I32))
      (fold-left (lambda (value offset)
                   (match (new Pair (first value)
                               (second (if (< (+ index offset) (vector-length chars))
                                           (hex-digit (vector-ref chars (+ index offset)))
                                           (None))))
                     ((Pair (Some total) (Some digit)) (Some (+ (* total 16) digit)))
                     (_ (None))))
                 (ann (Some 0) (Option I32)) (iota 4)))

    ;; Lowercase digits come first, uppercase sixteen places later.

    (define (hex-digit (char Char)) (→ (Option I32))
      (match (string-index "0123456789abcdef0123456789ABCDEF" char)
        ((Some position) (Some (i64->i32 (remainder position 16))))
        ((None) (None))))))

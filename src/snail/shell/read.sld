;; Scheme's external representation to data. The reader is a recursive
;; descent over a string; every step returns the datum it read and the index
;; after it, or a message saying what is wrong.
(define-library (snail shell read)
  (export
   read-datum
   read-datums)
  (import
   (snail core base)
   (snail shell integer)
   (snail shell number)
   (snail shell datum))
  (begin

    ;; ---- Results ----

    (enum Step
      (Parsed ((value Any) (next I64)))
      (Failed ((message String))))

    ;; Binds the value and next index of a successful step, or passes a
    ;; failure through.
    (define-syntax after
      (syntax-rules ()
        ((_ ((value next) step) body ...)
         (match step
           ((Parsed value next) body ...)
           ((Failed message) (Failed message))))))

    ;; ---- Characters and atmosphere ----

    (define (char-at (text String) (index I64)) (→ (Option Char))
      (if (< index (string-length text)) (Some (string-ref text index)) (None)))

    (define (next-is? (text String) (index I64) (char Char)) (→ Bool)
      (match (char-at text index)
        ((Some c) (= c char))
        ((None) #f)))

    (define (delimiter? (text String) (index I64)) (→ Bool)
      (match (char-at text index)
        ((Some c) (or (char-whitespace? c) (member? c (list #\( #\) #\" #\;))))
        ((None) #t)))

    ;; Skips whitespace, line comments and nested block comments.

    (define (skip (text String) (index I64)) (→ I64)
      (match (char-at text index)
        ((Some c)
         (cond ((char-whitespace? c) (skip text (+ index 1)))
               ((= c #\;) (skip text (line-end text index)))
               ((and (= c #\#) (next-is? text (+ index 1) #\|))
                (skip text (block-end text (+ index 2) 1)))
               (else index)))
        ((None) index)))

    (define (line-end (text String) (index I64)) (→ I64)
      (if (or (>= index (string-length text)) (= (string-ref text index) #\newline))
          index
          (line-end text (+ index 1))))

    (define (block-end (text String) (index I64) (depth I64)) (→ I64)
      (cond ((or (= depth 0) (>= index (string-length text))) index)
            ((and (next-is? text index #\|) (next-is? text (+ index 1) #\#))
             (block-end text (+ index 2) (- depth 1)))
            ((and (next-is? text index #\#) (next-is? text (+ index 1) #\|))
             (block-end text (+ index 2) (+ depth 1)))
            (else (block-end text (+ index 1) depth))))

    ;; ---- Data ----

    (define (read-at (text String) (start I64)) (→ Step)
      (let ((index (skip text start)))
        (match (char-at text index)
          ((None) (Failed "expected a datum before the end of the text"))
          ((Some c)
           (cond ((= c #\() (read-list text (+ index 1) (Nil)))
                 ((= c #\)) (Failed "unexpected closing parenthesis"))
                 ((= c #\") (read-string-literal text (+ index 1) (Nil)))
                 ((= c #\') (read-abbreviation text (+ index 1) "quote"))
                 ((= c #\`) (read-abbreviation text (+ index 1) "quasiquote"))
                 ((= c #\,) (if (next-is? text (+ index 1) #\@)
                                (read-abbreviation text (+ index 2) "unquote-splicing")
                                (read-abbreviation text (+ index 1) "unquote")))
                 ((= c #\#) (read-hash text index))
                 (else (read-atom text index)))))))

    (define (read-abbreviation (text String) (index I64) (name String)) (→ Step)
      (after ((datum next) (read-at text index))
             (Parsed (datum-list (list (ann (Symbol name) Any) datum)) next)))

    ;; A list, with an optional dotted tail before its closing parenthesis.

    (define (read-list (text String) (start I64) (items (List Any))) (→ Step)
      (let ((index (skip text start)))
        (cond ((next-is? text index #\))
               (Parsed (fold-left (lambda (tail item) (ann (SchemePair item tail) Any))
                                  (ann (Null) Any)
                                  items)
                       (+ index 1)))
              ((and (next-is? text index #\.) (delimiter? text (+ index 1)) (not (null? items)))
               (after ((tail next) (read-at text (+ index 1)))
                      (let ((close (skip text next)))
                        (if (next-is? text close #\))
                            (Parsed
                             (fold-left (lambda (rest item) (ann (SchemePair item rest) Any))
                                        tail
                                        items)
                             (+ close 1))
                            (Failed "expected ) after a dotted tail")))))
              ((>= index (string-length text)) (Failed "unclosed list"))
              (else (after ((item next) (read-at text index))
                           (read-list text next (Cons item items)))))))

    (define (read-string-literal (text String) (index I64) (chars (List Char))) (→ Step)
      (match (char-at text index)
        ((None) (Failed "unterminated string"))
        ((Some #\") (Parsed (list->string (reverse chars)) (+ index 1)))
        ((Some #\\)
         (match (char-at text (+ index 1))
           ((Some #\n) (read-string-literal text (+ index 2) (Cons #\newline chars)))
           ((Some #\r) (read-string-literal text (+ index 2) (Cons #\return chars)))
           ((Some #\t) (read-string-literal text (+ index 2) (Cons #\tab chars)))
           ((Some c) (read-string-literal text (+ index 2) (Cons c chars)))
           ((None) (Failed "unterminated string"))))
        ((Some c) (read-string-literal text (+ index 1) (Cons c chars)))))

    ;; `#t`, `#f`, `#\char`, `#(vector)` and `#u8(bytes)`; numbers with
    ;; prefixes such as `#x` are atoms.

    (define (read-hash (text String) (index I64)) (→ Step)
      (cond
       ((next-is? text (+ index 1) #\() (after ((items next) (read-list text (+ index 2) (Nil)))
                                               (match (datum->list items)
                                                 ((Some items)
                                                  (Parsed (list->vector items) next))
                                                 ((None)
                                                  (Failed "a vector cannot have a dotted tail")))))
       ((next-is? text (+ index 1) #\\) (read-character text (+ index 2)))
       ((and (next-is? text (+ index 1) #\u)
             (next-is? text (+ index 2) #\8)
             (next-is? text (+ index 3) #\())
        (after ((items next) (read-list text (+ index 4) (Nil))) (bytes-datum items next)))
       (else (read-atom text index))))

    ;; Parse each byte once, preserving the exact-integer requirement.

    (define (bytes-datum (items Any) (next I64)) (→ Step)
      (match (datum->list items)
        ((Some items)
         (let loop ((items items) (bytes (ann (Nil) (List U8))))
           (match items
             ((Nil) (Parsed (list->vector (reverse bytes)) next))
             ((Cons item rest)
              (match (byte-value item)
                ((Some byte) (loop rest (Cons byte bytes)))
                ((None) (Failed "a bytevector holds exact integers from 0 to 255")))))))
        ((None) (Failed "a bytevector cannot have a dotted tail"))))

    ;; The reader already stores integral exact literals as Integer. Check
    ;; their bounds before narrowing, so large values cannot wrap into bytes.

    (define (byte-value (datum Any)) (→ (Option U8))
      (match-any datum
                 ((Integer n)
                  (if (and (<= (integer-from-i64 0) n) (<= n (integer-from-i64 255)))
                      (Some (i32->u8 (i64->i32 (integer->i64 n))))
                      (None)))
                 (else (None))))

    (define (read-character (text String) (index I64)) (→ Step)
      (let* ((end (token-end text (+ index 1))) (name (substring text index end)))
        (cond ((= (string-length name) 1) (Parsed (string-ref name 0) end))
              ((string=? name "space") (Parsed #\space end))
              ((string=? name "newline") (Parsed #\newline end))
              ((string=? name "tab") (Parsed #\tab end))
              (else (Failed (string-append "unknown character name " name))))))

    (define (token-end (text String) (index I64)) (→ I64)
      (if (delimiter? text index) index (token-end text (+ index 1))))

    (define (read-atom (text String) (index I64)) (→ Step)
      (let* ((end (token-end text index)) (token (substring text index end)))
        (cond ((or (string=? token "#t") (string=? token "#true")) (Parsed #t end))
              ((or (string=? token "#f") (string=? token "#false")) (Parsed #f end))
              (else (match (string->number token)
                      ((Some n) (Parsed (number->datum n) end))
                      ((None) (if (= (string-ref token 0) #\#)
                                  (Failed (string-append "unknown syntax " token))
                                  (Parsed (Symbol token) end))))))))

    ;; ---- Entry points ----

    (define (read-datum (text String)) (→ (Result Any String))
      (match (read-at text 0)
        ((Parsed datum next)
         (if (= (skip text next) (string-length text)) (Ok datum) (Err "more than one datum")))
        ((Failed message) (Err message))))

    ;; Every datum in the text, in order.

    (define (read-datums (text String)) (→ (Result (List Any) String))
      (let loop ((index (skip text 0)) (items (Nil)))
        (if (= index (string-length text))
            (Ok (reverse items))
            (match (read-at text index)
              ((Parsed datum next) (loop (skip text next) (Cons datum items)))
              ((Failed message) (Err message))))))

    ))

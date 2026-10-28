;; Scheme's external representation to data. The reader is a recursive
;; descent over a string; every step returns the datum it read and the index
;; after it, or a message saying what is wrong.
(define-library (snail shell read)
  (export
   read-datum
   read-datums)
  (import
   (snail core base)
   (snail shell number)
   (snail shell datum))
  (begin

    ;; ---- Results ----

    (enum Step
      (Parsed ((value Datum) (next I64)))
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

    (: char-at (-> String I64 (Option Char)))
    (define (char-at text index)
      (if (< index (string-length text)) (Some (string-ref text index)) (None)))

    (: next-is? (-> String I64 Char Bool))
    (define (next-is? text index char)
      (match (char-at text index)
        ((Some c) (= c char))
        ((None) #f)))

    (: delimiter? (-> String I64 Bool))
    (define (delimiter? text index)
      (match (char-at text index)
        ((Some c) (or (char-whitespace? c) (member? c (list #\( #\) #\" #\;))))
        ((None) #t)))

    ;; Skips whitespace, line comments and nested block comments.
    (: skip (-> String I64 I64))
    (define (skip text index)
      (match (char-at text index)
        ((Some c)
         (cond ((char-whitespace? c) (skip text (+ index 1)))
               ((= c #\;) (skip text (line-end text index)))
               ((and (= c #\#) (next-is? text (+ index 1) #\|))
                (skip text (block-end text (+ index 2) 1)))
               (else index)))
        ((None) index)))

    (: line-end (-> String I64 I64))
    (define (line-end text index)
      (if (or (>= index (string-length text)) (= (string-ref text index) #\newline))
          index
          (line-end text (+ index 1))))

    (: block-end (-> String I64 I64 I64))
    (define (block-end text index depth)
      (cond ((or (= depth 0) (>= index (string-length text))) index)
            ((and (next-is? text index #\|) (next-is? text (+ index 1) #\#))
             (block-end text (+ index 2) (- depth 1)))
            ((and (next-is? text index #\#) (next-is? text (+ index 1) #\|))
             (block-end text (+ index 2) (+ depth 1)))
            (else (block-end text (+ index 1) depth))))

    ;; ---- Data ----

    (: read-at (-> String I64 Step))
    (define (read-at text start)
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

    (: read-abbreviation (-> String I64 String Step))
    (define (read-abbreviation text index name)
      (after ((datum next) (read-at text index))
             (Parsed (datum-list (list (SymbolDatum name) datum)) next)))

    ;; A list, with an optional dotted tail before its closing parenthesis.
    (: read-list (-> String I64 (List Datum) Step))
    (define (read-list text start items)
      (let ((index (skip text start)))
        (cond ((next-is? text index #\))
               (Parsed (fold-left (lambda (tail item) (PairDatum item tail)) (NullDatum) items)
                       (+ index 1)))
              ((and (next-is? text index #\.) (delimiter? text (+ index 1)) (not (null? items)))
               (after ((tail next) (read-at text (+ index 1)))
                      (let ((close (skip text next)))
                        (if (next-is? text close #\))
                            (Parsed
                             (fold-left (lambda (rest item) (PairDatum item rest)) tail items)
                             (+ close 1))
                            (Failed "expected ) after a dotted tail")))))
              ((>= index (string-length text)) (Failed "unclosed list"))
              (else (after ((item next) (read-at text index))
                           (read-list text next (Cons item items)))))))

    (: read-string-literal (-> String I64 (List Char) Step))
    (define (read-string-literal text index chars)
      (match (char-at text index)
        ((None) (Failed "unterminated string"))
        ((Some #\") (Parsed (StringDatum (list->string (reverse chars))) (+ index 1)))
        ((Some #\\)
         (match (char-at text (+ index 1))
           ((Some #\n) (read-string-literal text (+ index 2) (Cons #\newline chars)))
           ((Some #\t) (read-string-literal text (+ index 2) (Cons #\tab chars)))
           ((Some c) (read-string-literal text (+ index 2) (Cons c chars)))
           ((None) (Failed "unterminated string"))))
        ((Some c) (read-string-literal text (+ index 1) (Cons c chars)))))

    ;; `#t`, `#f`, `#\char`, `#(vector)` and `#u8(bytes)`; numbers with
    ;; prefixes such as `#x` are atoms.
    (: read-hash (-> String I64 Step))
    (define (read-hash text index)
      (cond
       ((next-is? text (+ index 1) #\() (after ((items next) (read-list text (+ index 2) (Nil)))
                                               (match (datum->list items)
                                                 ((Some items)
                                                  (Parsed (VectorDatum (list->vector items)) next))
                                                 ((None)
                                                  (Failed "a vector cannot have a dotted tail")))))
       ((next-is? text (+ index 1) #\\) (read-character text (+ index 2)))
       ((and (next-is? text (+ index 1) #\u)
             (next-is? text (+ index 2) #\8)
             (next-is? text (+ index 3) #\())
        (after ((items next) (read-list text (+ index 4) (Nil))) (bytes-datum items next)))
       (else (read-atom text index))))

    (: bytes-datum (-> Datum I64 Step))
    (define (bytes-datum items next)
      (match (datum->list items)
        ((Some items)
         (if (every? byte-datum? items)
             (Parsed (BytesDatum (list->vector (map (lambda (item)
                                                      (match item
                                                        ((NumberDatum n)
                                                         (i32->u8
                                                          (i64->i32 (f64->i64 (number->f64 n)))))
                                                        (_ (i32->u8 0))))
                                                    items)))
                     next)
             (Failed "a bytevector holds exact integers from 0 to 255")))
        ((None) (Failed "a bytevector cannot have a dotted tail"))))

    (: byte-datum? (-> Datum Bool))
    (define (byte-datum? datum)
      (match datum
        ((NumberDatum n)
         (and (number-exact? n)
              (number-integer? n)
              (<= 0.0 (number->f64 n))
              (<= (number->f64 n) 255.0)))
        (_ #f)))

    (: read-character (-> String I64 Step))
    (define (read-character text index)
      (let* ((end (token-end text (+ index 1))) (name (substring text index end)))
        (cond ((= (string-length name) 1) (Parsed (CharDatum (string-ref name 0)) end))
              ((string=? name "space") (Parsed (CharDatum #\space) end))
              ((string=? name "newline") (Parsed (CharDatum #\newline) end))
              ((string=? name "tab") (Parsed (CharDatum #\tab) end))
              (else (Failed (string-append "unknown character name " name))))))

    (: token-end (-> String I64 I64))
    (define (token-end text index)
      (if (delimiter? text index) index (token-end text (+ index 1))))

    (: read-atom (-> String I64 Step))
    (define (read-atom text index)
      (let* ((end (token-end text index)) (token (substring text index end)))
        (cond ((or (string=? token "#t") (string=? token "#true")) (Parsed (BooleanDatum #t) end))
              ((or (string=? token "#f") (string=? token "#false")) (Parsed (BooleanDatum #f) end))
              (else (match (string->number token)
                      ((Some n) (Parsed (NumberDatum n) end))
                      ((None) (if (= (string-ref token 0) #\#)
                                  (Failed (string-append "unknown syntax " token))
                                  (Parsed (SymbolDatum token) end))))))))

    ;; ---- Entry points ----

    (: read-datum (-> String (Result Datum String)))
    (define (read-datum text)
      (match (read-at text 0)
        ((Parsed datum next)
         (if (= (skip text next) (string-length text)) (Ok datum) (Err "more than one datum")))
        ((Failed message) (Err message))))

    ;; Every datum in the text, in order.
    (: read-datums (-> String (Result (List Datum) String)))
    (define (read-datums text)
      (let loop ((index (skip text 0)) (items (Nil)))
        (if (= index (string-length text))
            (Ok (reverse items))
            (match (read-at text index)
              ((Parsed datum next) (loop (skip text next) (Cons datum items)))
              ((Failed message) (Err message))))))

    ))

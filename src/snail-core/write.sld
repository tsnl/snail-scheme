;; Data to Scheme's external representation. `write` notation reads back as
;; the same datum; `display` notation shows strings and characters as text.
(define-library (snail-core write)
  (export
   datum->string
   datum->display-string)
  (import
   (snail-core base)
   (snail-core number)
   (snail-core datum))
  (begin

    (: datum->string (-> Datum String))
    (define (datum->string datum)
      (string-concatenate (datum-text datum #t)))

    (: datum->display-string (-> Datum String))
    (define (datum->display-string datum)
      (string-concatenate (datum-text datum #f)))

    ;; The pieces of a datum's text, concatenated once at the end.
    (: datum-text (-> Datum Bool (List String)))
    (define (datum-text datum write?)
      (match datum
        ((NullDatum) (list "()"))
        ((BooleanDatum value) (list (if value "#t" "#f")))
        ((CharDatum char)
         (if write? (list (character-name char)) (list (make-string 1 char))))
        ((StringDatum text) (if write? (list (quoted text)) (list text)))
        ((SymbolDatum name) (list name))
        ((NumberDatum n) (list (number->string n)))
        ((PairDatum head tail)
         (Cons "("
               (append (datum-text head write?) (list-tail-text tail write?))))
        ((VectorDatum items)
         (sequence-text "#("
                        (map (lambda (item) (datum-text item write?))
                             (vector->list items))))
        ((BytesDatum bytes)
         (sequence-text "#u8("
                        (map (lambda (byte) (list (show byte)))
                             (vector->list bytes))))
        ((ProcedureDatum _) (list "#<procedure>"))))

    (: list-tail-text (-> Datum Bool (List String)))
    (define (list-tail-text tail write?)
      (match tail
        ((NullDatum) (list ")"))
        ((PairDatum head rest)
         (Cons " "
               (append (datum-text head write?) (list-tail-text rest write?))))
        (_ (Cons " . " (append (datum-text tail write?) (list ")"))))))

    (: sequence-text (-> String (List (List String)) (List String)))
    (define (sequence-text open items)
      (Cons open
            (append (concatenate (map-indexed (lambda (index item)
                                                (if (= index 0)
                                                    item
                                                    (Cons " " item)))
                                              items))
                    (list ")"))))

    (: character-name (-> Char String))
    (define (character-name char)
      (cond ((= char #\space) "#\\space")
            ((= char #\newline) "#\\newline")
            ((= char #\tab) "#\\tab")
            (else (string-append "#\\" (make-string 1 char)))))

    (: quoted (-> String String))
    (define (quoted text)
      (string-append "\""
                     (string-concatenate (map escaped (string->list text)))
                     "\""))

    (: escaped (-> Char String))
    (define (escaped char)
      (cond ((= char #\") "\\\"")
            ((= char #\\) "\\\\")
            ((= char #\newline) "\\n")
            ((= char #\tab) "\\t")
            (else (make-string 1 char))))

    ))

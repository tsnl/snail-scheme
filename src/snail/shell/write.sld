;; Data to Scheme's external representation. `write` notation reads back as
;; the same datum; `display` notation shows strings and characters as text.
(define-library (snail shell write)
  (export
   datum->string
   datum->display-string)
  (import
   (snail core base)
   (snail shell number)
   (snail shell datum))
  (begin

    (: datum->string (-> Any String))
    (define (datum->string datum)
      (string-concatenate (datum-text datum #t)))

    (: datum->display-string (-> Any String))
    (define (datum->display-string datum)
      (string-concatenate (datum-text datum #f)))

    ;; The pieces of a datum's text, concatenated once at the end.
    (: datum-text (-> Any Bool (List String)))
    (define (datum-text datum write?)
      (match-any datum
                 ((Null _) (list "()"))
                 ((Bool value) (list (if value "#t" "#f")))
                 ((Char char) (if write? (list (character-name char)) (list (make-string 1 char))))
                 ((String text) (if write? (list (quoted text)) (list text)))
                 ((Symbol (Symbol name)) (list name))
                 ((SchemePair (SchemePair head tail))
                  (Cons "(" (append (datum-text head write?) (list-tail-text tail write?))))
                 (((Vector Any) items)
                  (sequence-text "#("
                                 (map (lambda (item) (datum-text item write?))
                                      (vector->list items))))
                 ((Bytes bytes)
                  (sequence-text "#u8("
                                 (map (lambda (byte) (list (show byte))) (vector->list bytes))))
                 ((Procedure _) (list "#<procedure>"))
                 (else (match (datum-number datum)
                         ((Some n) (list (number->string n)))
                         ((None) (list "#<opaque>"))))))

    (: list-tail-text (-> Any Bool (List String)))
    (define (list-tail-text tail write?)
      (match-any tail
                 ((Null _) (list ")"))
                 ((SchemePair (SchemePair head rest))
                  (Cons " " (append (datum-text head write?) (list-tail-text rest write?))))
                 (else (Cons " . " (append (datum-text tail write?) (list ")"))))))

    (: sequence-text (-> String (List (List String)) (List String)))
    (define (sequence-text open items)
      (Cons open
            (append
             (concatenate (map-indexed (lambda (index item) (if (= index 0) item (Cons " " item)))
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
      (string-append "\"" (string-concatenate (map escaped (string->list text))) "\""))

    (: escaped (-> Char String))
    (define (escaped char)
      (cond ((= char #\") "\\\"")
            ((= char #\\) "\\\\")
            ((= char #\newline) "\\n")
            ((= char #\tab) "\\t")
            (else (make-string 1 char))))

    ))

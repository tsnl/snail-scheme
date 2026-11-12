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

    (instance (Repr Any)
      (define repr datum->string))

    (define (datum->string (datum Any)) (→ String)
      (string-concatenate (datum-text datum #t)))

    (define (datum->display-string (datum Any)) (→ String)
      (string-concatenate (datum-text datum #f)))

    ;; The pieces of a datum's text, concatenated once at the end.

    (define (datum-text (datum Any) (write? Bool)) (→ (List String))
      (match-any datum
                 ((Null _) (list "()"))
                 ((Bool value) (list (if value "#t" "#f")))
                 ((Char char) (list (if write? (repr char) (show char))))
                 ((String text) (list (if write? (repr text) text)))
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

    (define (list-tail-text (tail Any) (write? Bool)) (→ (List String))
      (match-any tail
                 ((Null _) (list ")"))
                 ((SchemePair (SchemePair head rest))
                  (Cons " " (append (datum-text head write?) (list-tail-text rest write?))))
                 (else (Cons " . " (append (datum-text tail write?) (list ")"))))))

    (define (sequence-text (open String) (items (List (List String)))) (→ (List String))
      (Cons open
            (append
             (concatenate (map-indexed (lambda (index item) (if (= index 0) item (Cons " " item)))
                                       items))
             (list ")"))))

    ))

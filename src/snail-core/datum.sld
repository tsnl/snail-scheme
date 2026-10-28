;; Scheme data as one Snail-Core type. Pairs are immutable, so data are trees
;; and never cyclic; symbols compare by name. A procedure takes its
;; arguments as a list and may print and mutate storage, as Scheme
;; procedures do.
(define-library (snail-core datum)
  (export
   Datum
   NullDatum
   BooleanDatum
   CharDatum
   StringDatum
   SymbolDatum
   NumberDatum
   PairDatum
   VectorDatum
   BytesDatum
   ProcedureDatum
   datum=?
   datum-list
   datum->list
   datum-truthy?
   datum->syntax)
  (import
   (snail-core base)
   (snail-core io)
   (snail-core number)
   (snail-core syntax))
  (begin

    (enum Datum
      (NullDatum)
      (BooleanDatum ((value Bool)))
      (CharDatum ((value Char)))
      (StringDatum ((value String)))
      (SymbolDatum ((name String)))
      (NumberDatum ((value Number)))
      (PairDatum ((car Datum) (cdr Datum)))
      (VectorDatum ((items (Vector Datum))))
      (BytesDatum ((bytes Bytes)))
      (ProcedureDatum ((call (-> (List Datum) Datum ! console mut)))))

    ;; Structural equality, as Scheme's `equal?`; procedures are never equal.
    (: datum=? (-> Datum Datum Bool))
    (define (datum=? a b)
      (match (Pair a b)
        ((Pair (NullDatum) (NullDatum)) #t)
        ((Pair (BooleanDatum x) (BooleanDatum y)) (= x y))
        ((Pair (CharDatum x) (CharDatum y)) (= x y))
        ((Pair (StringDatum x) (StringDatum y)) (string=? x y))
        ((Pair (SymbolDatum x) (SymbolDatum y)) (string=? x y))
        ((Pair (NumberDatum x) (NumberDatum y))
         (and (= (number-exact? x) (number-exact? y)) (= x y)))
        ((Pair (PairDatum x1 x2) (PairDatum y1 y2)) (and (datum=? x1 y1) (datum=? x2 y2)))
        ((Pair (VectorDatum x) (VectorDatum y))
         (datum=? (datum-list (vector->list x)) (datum-list (vector->list y))))
        ((Pair (BytesDatum x) (BytesDatum y)) (bytes=? x y))
        (_ #f)))

    (: datum-list (-> (List Datum) Datum))
    (define (datum-list items)
      (fold-right PairDatum (NullDatum) items))

    ;; The elements of a proper list.
    (: datum->list (-> Datum (Option (List Datum))))
    (define (datum->list datum)
      (let loop ((datum datum) (items (Nil)))
        (match datum
          ((NullDatum) (Some (reverse items)))
          ((PairDatum head tail) (loop tail (Cons head items)))
          (_ (None)))))

    ;; Everything but #f is true in Scheme.
    (: datum-truthy? (-> Datum Bool))
    (define (datum-truthy? datum)
      (match datum
        ((BooleanDatum value) value)
        (_ #t)))

    ;; ---- Syntax ----

    ;; The syntax that reads as a datum, for a `generate-library` recipe: a
    ;; proper list is a form, and a symbol, an exact integer that fits I64,
    ;; a float, a string, a character, a boolean or a byte vector is itself.
    ;; Nothing else has Snail-Core syntax.
    (: datum->syntax (-> Datum Syntax))
    (define (datum->syntax datum)
      (match datum
        ((NullDatum) (ListSyntax (Nil)))
        ((PairDatum _ _) (match (datum->list datum)
                           ((Some items) (ListSyntax (map datum->syntax items)))
                           ((None)
                            (panic "datum->syntax: an improper list has no Snail-Core syntax"))))
        ((SymbolDatum name) (SymbolSyntax name))
        ((NumberDatum n) (number-syntax n))
        ((StringDatum text) (StringSyntax text))
        ((CharDatum c) (CharSyntax c))
        ((BooleanDatum value) (BooleanSyntax value))
        ((BytesDatum bytes) (BytesSyntax bytes))
        ((VectorDatum _) (panic "datum->syntax: a vector has no Snail-Core syntax"))
        ((ProcedureDatum _) (panic "datum->syntax: a procedure has no syntax"))))

    ;; A float written without a point gains one, so it reads as a float.
    (: number-syntax (-> Number Syntax))
    (define (number-syntax n)
      (let ((text (number->string n)))
        (match (string->i64 text)
          ((Some value)
           (if (number-exact? n) (IntegerSyntax value) (FloatSyntax (string-append text ".0"))))
          ((None)
           (if (number-exact? n)
               (panic (string-append "datum->syntax: no Snail-Core literal for " text))
               (FloatSyntax text))))))

    (: bytes=? (-> Bytes Bytes Bool))
    (define (bytes=? a b)
      (and (= (vector-length a) (vector-length b))
           (let loop ((index 0))
             (or (= index (vector-length a))
                 (and (= (vector-ref a index) (vector-ref b index)) (loop (+ index 1)))))))

    ))

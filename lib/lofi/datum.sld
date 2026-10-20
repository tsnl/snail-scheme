;; Scheme data as one Lofi type. Pairs are immutable, so data are trees
;; and never cyclic; symbols compare by name.
(define-library (lofi datum)
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
   datum=?
   datum-list
   datum->list
   datum-truthy?)
  (import
   (lofi base)
   (lofi number))
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
      (BytesDatum ((bytes Bytes))))

    ;; Structural equality, as Scheme's `equal?`.
    (: datum=? (-> Datum Datum Bool))
    (define (datum=? a b)
      (match (Pair a b)
        ((Pair (NullDatum) (NullDatum)) #t)
        ((Pair (BooleanDatum x) (BooleanDatum y)) (= x y))
        ((Pair (CharDatum x) (CharDatum y)) (= x y))
        ((Pair (StringDatum x) (StringDatum y)) (string=? x y))
        ((Pair (SymbolDatum x) (SymbolDatum y)) (string=? x y))
        ((Pair (NumberDatum x) (NumberDatum y)) (and (= (number-exact? x) (number-exact? y)) (= x y)))
        ((Pair (PairDatum x1 x2) (PairDatum y1 y2)) (and (datum=? x1 y1) (datum=? x2 y2)))
        ((Pair (VectorDatum x) (VectorDatum y)) (datum=? (datum-list (vector->list x)) (datum-list (vector->list y))))
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

    (: bytes=? (-> Bytes Bytes Bool))
    (define (bytes=? a b)
      (and (= (vector-length a) (vector-length b))
           (let loop ((index 0))
             (or (= index (vector-length a))
                 (and (= (vector-ref a index) (vector-ref b index)) (loop (+ index 1)))))))

    ))

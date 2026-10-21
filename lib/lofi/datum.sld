;; Scheme data as one Lofi type, and typed Lofi values as Scheme data. Pairs
;; are immutable, so data are trees and never cyclic; symbols compare by
;; name. A procedure takes its arguments as a list and may print and mutate
;; storage, as Scheme procedures do. `Dynamic` converts typed values to data
;; and back, checking each datum that returns to typed code.
(define-library (lofi datum)
  (export
   Datum
   NullDatum
   UnspecifiedDatum
   BooleanDatum
   CharDatum
   StringDatum
   SymbolDatum
   NumberDatum
   PairDatum
   VectorDatum
   BytesDatum
   ProcedureDatum
   OpaqueDatum
   datum=?
   datum-list
   datum->list
   datum-truthy?
   datum-kind
   Dynamic
   to-datum
   from-datum
   define-opaque)
  (import
   (lofi base)
   (lofi io)
   (lofi integer)
   (lofi rational)
   (lofi number))
  (begin

    ;; ---- Data ----

    ;; `UnspecifiedDatum` is the value of expressions whose value Scheme
    ;; leaves unspecified, and of typed functions returning Unit. An opaque
    ;; datum holds a typed value that Scheme may pass around but not take
    ;; apart, with the name it prints as.
    (enum Datum
      (NullDatum)
      (UnspecifiedDatum)
      (BooleanDatum ((value Bool)))
      (CharDatum ((value Char)))
      (StringDatum ((value String)))
      (SymbolDatum ((name String)))
      (NumberDatum ((value Number)))
      (PairDatum ((car Datum) (cdr Datum)))
      (VectorDatum ((items (Vector Datum))))
      (BytesDatum ((bytes Bytes)))
      (ProcedureDatum ((call (-> (List Datum) Datum ! console mut))))
      (OpaqueDatum ((type String) (value Any))))

    ;; Structural equality, as Scheme's `equal?`; procedures and opaque
    ;; values are never equal.
    (: datum=? (-> Datum Datum Bool))
    (define (datum=? a b)
      (match (Pair a b)
        ((Pair (NullDatum) (NullDatum)) #t)
        ((Pair (UnspecifiedDatum) (UnspecifiedDatum)) #t)
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

    ;; What sort of datum this is, for messages that cannot print it.
    (: datum-kind (-> Datum String))
    (define (datum-kind datum)
      (match datum
        ((NullDatum) "the empty list")
        ((UnspecifiedDatum) "an unspecified value")
        ((BooleanDatum _) "a boolean")
        ((CharDatum _) "a character")
        ((StringDatum _) "a string")
        ((SymbolDatum _) "a symbol")
        ((NumberDatum _) "a number")
        ((PairDatum _ _) "a pair")
        ((VectorDatum _) "a vector")
        ((BytesDatum _) "a bytevector")
        ((ProcedureDatum _) "a procedure")
        ((OpaqueDatum type _) (string-append "a " type))))

    (: bytes=? (-> Bytes Bytes Bool))
    (define (bytes=? a b)
      (and (= (vector-length a) (vector-length b))
           (let loop ((index 0))
             (or (= index (vector-length a))
                 (and (= (vector-ref a index) (vector-ref b index)) (loop (+ index 1)))))))

    ;; ---- Typed values ----

    ;; A typed value as Scheme data, and back. `from-datum` parses: it
    ;; panics when the datum is not a value of the type, so typed code never
    ;; receives one that is not.
    (typeclass (Dynamic T)
      (: to-datum (-> T Datum))
      (: from-datum (-> Datum T)))

    (: expected (All (A) (-> String Datum A)))
    (define (expected what datum)
      (panic (string-append "expected " what ", got " (datum-kind datum))))

    (instance (Dynamic Datum)
      (define (to-datum datum) datum)
      (define (from-datum datum) datum))

    ;; A procedure returning to a function typed to return Unit may return
    ;; anything; the value is dropped.
    (instance (Dynamic Unit)
      (define (to-datum value) (UnspecifiedDatum))
      (define (from-datum datum) (unit)))

    (instance (Dynamic Bool)
      (define (to-datum value) (BooleanDatum value))
      (define (from-datum datum)
        (match datum
          ((BooleanDatum value) value)
          (_ (expected "a boolean" datum)))))

    (instance (Dynamic Char)
      (define (to-datum value) (CharDatum value))
      (define (from-datum datum)
        (match datum
          ((CharDatum value) value)
          (_ (expected "a character" datum)))))

    (instance (Dynamic String)
      (define (to-datum value) (StringDatum value))
      (define (from-datum datum)
        (match datum
          ((StringDatum value) value)
          (_ (expected "a string" datum)))))

    ;; ---- Numbers ----

    ;; An integer type takes the exact integers in its range; a float type
    ;; takes any real number.
    (: exact-integer (-> Datum String Integer))
    (define (exact-integer datum what)
      (match datum
        ((NumberDatum (Exact r)) (if (rational-integer? r) (Rational-numerator r) (expected what datum)))
        (_ (expected what datum))))

    (: integer-between (-> Datum String I64 I64 I64))
    (define (integer-between datum what low high)
      (let ((n (exact-integer datum what)))
        (if (integer-fits-i64? n)
            (let ((value (integer->i64 n)))
              (if (and (<= low value) (<= value high)) value (expected what datum)))
            (expected what datum))))

    (: real (-> Datum String F64))
    (define (real datum what)
      (match datum
        ((NumberDatum n) (number->f64 n))
        (_ (expected what datum))))

    (instance (Dynamic I64)
      (define (to-datum value) (NumberDatum (number-from-i64 value)))
      (define (from-datum datum) (integer-between datum "an I64" -9223372036854775808 9223372036854775807)))

    (instance (Dynamic I32)
      (define (to-datum value) (NumberDatum (number-from-i64 (i32->i64 value))))
      (define (from-datum datum) (i64->i32 (integer-between datum "an I32" -2147483648 2147483647))))

    (instance (Dynamic U8)
      (define (to-datum value) (NumberDatum (number-from-i64 (i32->i64 (u8->i32 value)))))
      (define (from-datum datum) (i32->u8 (i64->i32 (integer-between datum "a U8" 0 255)))))

    (instance (Dynamic F64)
      (define (to-datum value) (NumberDatum (number-from-f64 value)))
      (define (from-datum datum) (real datum "an F64")))

    (instance (Dynamic F32)
      (define (to-datum value) (NumberDatum (number-from-f64 (f32->f64 value))))
      (define (from-datum datum) (f64->f32 (real datum "an F32"))))

    (instance (Dynamic Integer)
      (define (to-datum value) (NumberDatum (number-from-integer value)))
      (define (from-datum datum) (exact-integer datum "an exact integer")))

    (instance (Dynamic Number)
      (define (to-datum value) (NumberDatum value))
      (define (from-datum datum)
        (match datum
          ((NumberDatum value) value)
          (_ (expected "a number" datum)))))

    ;; ---- Collections ----

    ;; A list is a proper list and a pair a pair. A vector is a vector, or a
    ;; bytevector whose bytes convert as numbers. `None` is #f and
    ;; `(Some x)` is x, so #f returning as an `(Option Bool)` is `None`.
    (instance (Dynamic (List T))
      (requires (Dynamic T))
      (define (to-datum items) (datum-list (map to-datum items)))
      (define (from-datum datum)
        (match (datum->list datum)
          ((Some items) (map from-datum items))
          ((None) (expected "a list" datum)))))

    (instance (Dynamic (Vector T))
      (requires (Dynamic T))
      (define (to-datum items) (VectorDatum (vector-map to-datum items)))
      (define (from-datum datum)
        (match datum
          ((VectorDatum items) (vector-map from-datum items))
          ((BytesDatum bytes) (vector-map (lambda (byte) (from-datum (to-datum byte))) bytes))
          (_ (expected "a vector" datum)))))

    (instance (Dynamic (Pair A B))
      (requires (Dynamic A) (Dynamic B))
      (define (to-datum pair) (PairDatum (to-datum (Pair-first pair)) (to-datum (Pair-second pair))))
      (define (from-datum datum)
        (match datum
          ((PairDatum head tail) (Pair (from-datum head) (from-datum tail)))
          (_ (expected "a pair" datum)))))

    (instance (Dynamic (Option T))
      (requires (Dynamic T))
      (define (to-datum value)
        (match value
          ((Some x) (to-datum x))
          ((None) (BooleanDatum #f))))
      (define (from-datum datum)
        (match datum
          ((BooleanDatum #f) (None))
          (_ (Some (from-datum datum))))))

    ;; ---- Functions ----

    ;; A typed function becomes a procedure that converts its arguments and
    ;; result. A procedure returning to typed code becomes a function that
    ;; claims to be total, although Scheme code may print or mutate: that
    ;; claim is this boundary's unsafe assumption.
    (: arity-error (All (A) (-> I64 (List Datum) A)))
    (define (arity-error count arguments)
      (panic (string-append "expected " (i64->string count) " arguments, got " (i64->string (length arguments)))))

    (: procedure-of (-> Datum (-> (List Datum) Datum ! console mut)))
    (define (procedure-of datum)
      (match datum
        ((ProcedureDatum call) call)
        (_ (expected "a procedure" datum))))

    (instance (Dynamic (-> R))
      (requires (Dynamic R))
      (define (to-datum f)
        (ProcedureDatum (lambda (arguments)
                          (match arguments
                            ((Nil) (to-datum (f)))
                            (_ (arity-error 0 arguments))))))
      (define (from-datum datum)
        (let ((call (procedure-of datum)))
          (lambda () (from-datum (unsafe-total (lambda () (call (Nil)))))))))

    (instance (Dynamic (-> A R))
      (requires (Dynamic A) (Dynamic R))
      (define (to-datum f)
        (ProcedureDatum (lambda (arguments)
                          (match arguments
                            ((Cons a (Nil)) (to-datum (f (from-datum a))))
                            (_ (arity-error 1 arguments))))))
      (define (from-datum datum)
        (let ((call (procedure-of datum)))
          (lambda (a) (from-datum (unsafe-total (lambda () (call (list (to-datum a))))))))))

    (instance (Dynamic (-> A B R))
      (requires (Dynamic A) (Dynamic B) (Dynamic R))
      (define (to-datum f)
        (ProcedureDatum (lambda (arguments)
                          (match arguments
                            ((Cons a (Cons b (Nil))) (to-datum (f (from-datum a) (from-datum b))))
                            (_ (arity-error 2 arguments))))))
      (define (from-datum datum)
        (let ((call (procedure-of datum)))
          (lambda (a b) (from-datum (unsafe-total (lambda () (call (list (to-datum a) (to-datum b))))))))))

    (instance (Dynamic (-> A B C R))
      (requires (Dynamic A) (Dynamic B) (Dynamic C) (Dynamic R))
      (define (to-datum f)
        (ProcedureDatum (lambda (arguments)
                          (match arguments
                            ((Cons a (Cons b (Cons c (Nil)))) (to-datum (f (from-datum a) (from-datum b) (from-datum c))))
                            (_ (arity-error 3 arguments))))))
      (define (from-datum datum)
        (let ((call (procedure-of datum)))
          (lambda (a b c) (from-datum (unsafe-total (lambda () (call (list (to-datum a) (to-datum b) (to-datum c))))))))))

    (instance (Dynamic (-> A B C D R))
      (requires (Dynamic A) (Dynamic B) (Dynamic C) (Dynamic D) (Dynamic R))
      (define (to-datum f)
        (ProcedureDatum (lambda (arguments)
                          (match arguments
                            ((Cons a (Cons b (Cons c (Cons d (Nil)))))
                             (to-datum (f (from-datum a) (from-datum b) (from-datum c) (from-datum d))))
                            (_ (arity-error 4 arguments))))))
      (define (from-datum datum)
        (let ((call (procedure-of datum)))
          (lambda (a b c d)
            (from-datum (unsafe-total (lambda () (call (list (to-datum a) (to-datum b) (to-datum c) (to-datum d))))))))))

    ;; ---- Opaque values ----

    ;; `(define-opaque Type "name")` lets values of Type cross into Scheme
    ;; whole, printing as #<name>. Scheme can hold one and pass it back but
    ;; not take it apart; one returning to typed code is checked to be a
    ;; Type through its `Any`.
    (define-syntax define-opaque
      (syntax-rules ()
        ((_ Type name)
         (instance (Dynamic Type)
           (define (to-datum value) (OpaqueDatum name (type-convert value Any)))
           (define (from-datum datum) (type-convert (opaque-value datum name) Type))))))

    (: opaque-value (-> Datum String Any))
    (define (opaque-value datum name)
      (match datum
        ((OpaqueDatum _ value) value)
        (_ (expected (string-append "a " name) datum))))

    ))

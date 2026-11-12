;; Scheme values use Core Any. Only distinctions absent from Core need
;; nominal types: the empty list, symbols, pairs and effectful procedures.
;; A procedure's nominal type preserves its fixed calling effects in Any.
(define-library (snail shell datum)
  (export
   Null
   Symbol
   SchemePair
   Procedure
   match-any
   number->datum
   datum-number
   datum=?
   datum-list
   datum->list
   datum-truthy?
   datum->syntax)
  (import
   (snail core base)
   (snail core io)
   (snail shell integer)
   (snail shell rational)
   (snail shell number)
   (snail shell syntax))
  (begin

    (struct Null
      ())
    (struct Symbol
      ((name String)))
    (struct SchemePair
      ((car Any)
       (cdr Any)))
    (struct Procedure
      ((call (Fn (List Any) → Any ! output-port mut dyn-cast))))

    ;; Each branch names a concrete type and an ordinary pattern for it.
    ;; Probing is pure; a failed type or pattern proceeds to the next branch.
    ;; Hold the input once, including when no branch accepts it.
    (define-syntax match-any
      (syntax-rules (else)
        ((_ value (else body ...)) (begin value body ...))
        ((_ value ((type pattern) body ...) rest ...)
         (let ((held (ann value Any)))
           (match (try-convert held type)
             ((Ok pattern) (begin body ...))
             (_ (match-any held rest ...)))))))

    ;; The typed parser still serves Number clients; Scheme stores only its
    ;; native payload. Integral exact literals start as arbitrary integers.

    (define (number->datum (n Number)) (→ Any)
      (match n
        ((Exact r) (if (rational-integer? r) (ann (● r numerator) Any) (ann r Any)))
        ((Inexact x) (ann x Any))))

    ;; A view for equality, comparison and formatting, never stored in Scheme
    ;; cells. Arithmetic instead selects instances on the original payloads.

    (define (datum-number (value Any)) (→ (Option Number))
      (match-any value
                 ((Integer n) (Some (number-from-integer n)))
                 ((Rational r) (Some (Exact r)))
                 ((F64 x) (Some (Inexact x)))
                 (else (None))))

    ;; Structural equality for Scheme's immutable data. Foreign Core values
    ;; and procedures have no Scheme equality contract and compare false.

    (define (datum=? (a Any) (b Any)) (→ Bool)
      (match-any a
                 ((Null _) (type-test b Null))
                 ((Bool x) (match-any b ((Bool y) (= x y)) (else #f)))
                 ((Char x) (match-any b ((Char y) (= x y)) (else #f)))
                 ((String x) (match-any b ((String y) (string=? x y)) (else #f)))
                 ((Symbol (Symbol x))
                  (match-any b ((Symbol (Symbol y)) (string=? x y)) (else #f)))
                 ((SchemePair (SchemePair x1 x2))
                  (match-any b
                             ((SchemePair (SchemePair y1 y2)) (and (datum=? x1 y1) (datum=? x2 y2)))
                             (else #f)))
                 (((Vector Any) x)
                  (match-any b
                             (((Vector Any) y) (vectors=? x y))
                             (else #f)))
                 ((Bytes x) (match-any b ((Bytes y) (bytes=? x y)) (else #f)))
                 (else (match (Pair (datum-number a) (datum-number b))
                         ((Pair (Some x) (Some y))
                          (and (= (number-exact? x) (number-exact? y)) (= x y)))
                         (_ #f)))))

    (define (vectors=? (a (Vector Any)) (b (Vector Any))) (→ Bool)
      (and (= (vector-length a) (vector-length b))
           (let loop ((index 0))
             (or (= index (vector-length a))
                 (and (datum=? (vector-ref a index) (vector-ref b index))
                      (loop (+ index 1)))))))

    (define (bytes=? (a Bytes) (b Bytes)) (→ Bool)
      (and (= (vector-length a) (vector-length b))
           (let loop ((index 0))
             (or (= index (vector-length a))
                 (and (= (vector-ref a index) (vector-ref b index)) (loop (+ index 1)))))))

    (define (datum-list (items (List Any))) (→ Any)
      (fold-right (lambda (head tail) (ann (SchemePair head tail) Any)) (ann (Null) Any) items))

    (define (datum->list (datum Any)) (→ (Option (List Any)))
      (let loop ((datum datum) (items (ann (Nil) (List Any))))
        (match-any datum
                   ((Null _) (Some (reverse items)))
                   ((SchemePair (SchemePair head tail)) (loop tail (Cons head items)))
                   (else (None)))))

    (define (datum-truthy? (datum Any)) (→ Bool)
      (match-any datum ((Bool value) value) (else #t)))

    ;; ---- Syntax ----

    ;; A proper list is a form; only values with a Core literal can appear
    ;; in generated syntax. An arbitrary Core value can still pass through
    ;; Scheme, without acquiring an external representation or syntax.

    (define (datum->syntax (datum Any)) (→ Syntax)
      (match-any datum
                 ((Null _) (ListSyntax (Nil)))
                 ((SchemePair _)
                  (match (datum->list datum)
                    ((Some items) (ListSyntax (map datum->syntax items)))
                    ((None) (panic "datum->syntax: an improper list has no Snail-Core syntax"))))
                 ((Symbol (Symbol name)) (SymbolSyntax name))
                 ((String text) (StringSyntax text))
                 ((Char c) (CharSyntax c))
                 ((Bool value) (BooleanSyntax value))
                 ((Bytes bytes) (BytesSyntax bytes))
                 (else (match (datum-number datum)
                         ((Some n) (number-syntax n))
                         ((None) (panic "datum->syntax: this value has no Snail-Core syntax"))))))

    ;; A float written without a point gains one, so it reads as a float.

    (define (number-syntax (n Number)) (→ Syntax)
      (let ((text (number->string n)))
        (match (string->i64 text)
          ((Some value)
           (if (number-exact? n) (IntegerSyntax value) (FloatSyntax (string-append text ".0"))))
          ((None)
           (if (number-exact? n)
               (panic (string-append "datum->syntax: no Snail-Core literal for " text))
               (FloatSyntax text))))))

    ))

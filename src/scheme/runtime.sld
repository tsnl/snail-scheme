;; The run-time support of Scheme programs that (scheme compiler) translated.
;; Every value is a Datum and every variable a cell holding one. The standard
;; procedures are cells holding procedures, named like translated variables
;; with a leading `%`, so a program may rebind them. Pairs are immutable, so
;; `eq?` and `eqv?` compare structurally, like `equal?`.
(define-library (scheme runtime)
  (export
   call
   arity!
   rest-arguments
   scheme-number
   unspecified
   member-datum?
   %+
   %-
   %*
   %/
   %=
   %<
   %>
   %<=
   %>=
   %quotient
   %remainder
   %modulo
   %abs
   %max
   %min
   %number?
   %integer?
   %zero?
   %positive?
   %negative?
   %even?
   %odd?
   %number->string
   %cons
   %car
   %cdr
   %list
   %length
   %append
   %reverse
   %list-ref
   %null?
   %pair?
   %list?
   %eq?
   %eqv?
   %equal?
   %not
   %boolean?
   %symbol?
   %string?
   %char?
   %procedure?
   %string-append
   %string-length
   %substring
   %string=?
   %char-upcase
   %char-downcase
   %char-foldcase
   %char-alphabetic?
   %char-numeric?
   %char-whitespace?
   %char-upper-case?
   %char-lower-case?
   %char-ci=?
   %digit-value
   %string-upcase
   %string-downcase
   %string-foldcase
   %string-ci=?
   %symbol->string
   %string->symbol
   %display
   %write
   %newline
   %apply
   %map
   %for-each
   %vector
   %vector-ref
   %vector-length
   %error)
  (import
   (lofi base)
   (lofi io)
   (lofi number)
   (lofi integer)
   (lofi rational)
   (lofi datum)
   (lofi text)
   (lofi write))
  (begin

    ;; ---- Calls ----

    (: call (-> Datum (List Datum) Datum ! console mut))
    (define (call procedure arguments)
      (match procedure
        ((ProcedureDatum f) (f arguments))
        (_ (panic (string-append "not a procedure: " (datum->string procedure))))))

    ;; Exactly `count` arguments, or at least `count` with a rest list.
    (: arity! (-> (List Datum) I64 Bool Unit))
    (define (arity! arguments count rest?)
      (let ((given (length arguments)))
        (unless (if rest? (>= given count) (= given count))
          (panic (string-append "expected " (i64->string count) (if rest? " or more" "") " arguments, got " (i64->string given))))))

    (: rest-arguments (-> (List Datum) I64 Datum))
    (define (rest-arguments arguments count)
      (datum-list (list-tail arguments count)))

    (: scheme-number (-> String Datum))
    (define (scheme-number text)
      (match (string->number text)
        ((Some n) (NumberDatum n))
        ((None) (panic (string-append "not a number: " text)))))

    ;; The value of expressions whose value Scheme leaves unspecified.
    (: unspecified Datum)
    (define unspecified (BooleanDatum #f))

    (: member-datum? (-> Datum Datum Bool))
    (define (member-datum? item items)
      (match items
        ((PairDatum head tail) (or (datum=? head item) (member-datum? item tail)))
        (_ #f)))

    ;; Procedures of fixed arity, from Lofi functions.
    (: procedure1 (-> (-> Datum Datum ! console mut) (Ref Datum) ! mut))
    (define (procedure1 f)
      (ref (ProcedureDatum (lambda (arguments) (arity! arguments 1 #f) (f (list-ref arguments 0))))))

    (: procedure2 (-> (-> Datum Datum Datum ! console mut) (Ref Datum) ! mut))
    (define (procedure2 f)
      (ref (ProcedureDatum (lambda (arguments) (arity! arguments 2 #f) (f (list-ref arguments 0) (list-ref arguments 1))))))

    (: variadic (-> (-> (List Datum) Datum ! console mut) (Ref Datum) ! mut))
    (define (variadic f)
      (ref (ProcedureDatum f)))

    (: boolean (-> Bool Datum))
    (define (boolean value)
      (BooleanDatum value))

    (: type-error (All (A) (-> String Datum A)))
    (define (type-error expected datum)
      (panic (string-append "expected " expected ", got " (datum->string datum))))

    ;; ---- Numbers ----

    (: number-of (-> Datum Number))
    (define (number-of datum)
      (match datum
        ((NumberDatum n) n)
        (_ (type-error "a number" datum))))

    (: integer-of (-> Datum Integer))
    (define (integer-of datum)
      (match (number-of datum)
        ((Exact r) (if (rational-integer? r) (Rational-numerator r) (type-error "an integer" datum)))
        ((Inexact _) (type-error "an exact integer" datum))))

    (: number (-> Number Datum))
    (define (number n)
      (NumberDatum n))

    ;; `(- x)` negates and `(- x y ...)` subtracts the rest from x; `/` alike.
    (: inverse-fold (-> (-> Number Number Number) Number (List Datum) Datum))
    (define (inverse-fold op identity arguments)
      (match arguments
        ((Cons first (Nil)) (number (op identity (number-of first))))
        ((Cons first rest) (number (fold-left (lambda (total item) (op total (number-of item))) (number-of first) rest)))
        ((Nil) (panic "expected at least one argument"))))

    ;; True when each adjacent pair compares as `test` accepts.
    (: chain (-> (-> I64 Bool) (List Datum) Datum))
    (define (chain test arguments)
      (boolean (let loop ((items arguments))
                 (match items
                   ((Cons a (Cons b rest)) (and (test (number-compare (number-of a) (number-of b))) (loop (Cons b rest))))
                   (_ #t)))))

    (: %+ (Ref Datum))
    (define %+ (variadic (lambda (arguments) (number (fold-left (lambda (total item) (number-add total (number-of item))) (number-from-i64 0) arguments)))))

    (: %* (Ref Datum))
    (define %* (variadic (lambda (arguments) (number (fold-left (lambda (total item) (number-multiply total (number-of item))) (number-from-i64 1) arguments)))))

    (: %- (Ref Datum))
    (define %- (variadic (lambda (arguments) (inverse-fold number-subtract (number-from-i64 0) arguments))))

    (: %/ (Ref Datum))
    (define %/ (variadic (lambda (arguments) (inverse-fold number-divide (number-from-i64 1) arguments))))

    (: %= (Ref Datum))
    (define %= (variadic (lambda (arguments) (chain (lambda (order) (= order 0)) arguments))))

    (: %< (Ref Datum))
    (define %< (variadic (lambda (arguments) (chain (lambda (order) (< order 0)) arguments))))

    (: %> (Ref Datum))
    (define %> (variadic (lambda (arguments) (chain (lambda (order) (> order 0)) arguments))))

    (: %<= (Ref Datum))
    (define %<= (variadic (lambda (arguments) (chain (lambda (order) (<= order 0)) arguments))))

    (: %>= (Ref Datum))
    (define %>= (variadic (lambda (arguments) (chain (lambda (order) (>= order 0)) arguments))))

    (: %quotient (Ref Datum))
    (define %quotient (procedure2 (lambda (a b) (number (number-from-integer (integer-quotient (integer-of a) (integer-of b)))))))

    (: %remainder (Ref Datum))
    (define %remainder (procedure2 (lambda (a b) (number (number-from-integer (integer-remainder (integer-of a) (integer-of b)))))))

    (: %modulo (Ref Datum))
    (define %modulo (procedure2 (lambda (a b) (number (number-from-integer (integer-modulo (integer-of a) (integer-of b)))))))

    (: %abs (Ref Datum))
    (define %abs (procedure1 (lambda (a) (if (< (number-compare (number-of a) (number-from-i64 0)) 0)
                                             (number (number-subtract (number-from-i64 0) (number-of a)))
                                             a))))

    (: %max (Ref Datum))
    (define %max (variadic (lambda (arguments) (extreme (lambda (order) (> order 0)) arguments))))

    (: %min (Ref Datum))
    (define %min (variadic (lambda (arguments) (extreme (lambda (order) (< order 0)) arguments))))

    (: extreme (-> (-> I64 Bool) (List Datum) Datum))
    (define (extreme better? arguments)
      (match arguments
        ((Cons first rest)
         (fold-left (lambda (best item) (if (better? (number-compare (number-of item) (number-of best))) item best)) first rest))
        ((Nil) (panic "expected at least one argument"))))

    (: %number? (Ref Datum))
    (define %number? (procedure1 (lambda (a) (boolean (match a ((NumberDatum _) #t) (_ #f))))))

    (: %integer? (Ref Datum))
    (define %integer? (procedure1 (lambda (a) (boolean (match a ((NumberDatum n) (number-integer? n)) (_ #f))))))

    (: sign (-> Datum I64))
    (define (sign a)
      (number-compare (number-of a) (number-from-i64 0)))

    (: %zero? (Ref Datum))
    (define %zero? (procedure1 (lambda (a) (boolean (= (sign a) 0)))))

    (: %positive? (Ref Datum))
    (define %positive? (procedure1 (lambda (a) (boolean (> (sign a) 0)))))

    (: %negative? (Ref Datum))
    (define %negative? (procedure1 (lambda (a) (boolean (< (sign a) 0)))))

    (: %even? (Ref Datum))
    (define %even? (procedure1 (lambda (a) (boolean (integer-zero? (integer-remainder (integer-of a) (integer-from-i64 2)))))))

    (: %odd? (Ref Datum))
    (define %odd? (procedure1 (lambda (a) (boolean (not (integer-zero? (integer-remainder (integer-of a) (integer-from-i64 2))))))))

    (: %number->string (Ref Datum))
    (define %number->string (procedure1 (lambda (a) (StringDatum (number->string (number-of a))))))

    ;; ---- Pairs and lists ----

    (: %cons (Ref Datum))
    (define %cons (procedure2 (lambda (a b) (PairDatum a b))))

    (: %car (Ref Datum))
    (define %car (procedure1 (lambda (a) (match a ((PairDatum head _) head) (_ (type-error "a pair" a))))))

    (: %cdr (Ref Datum))
    (define %cdr (procedure1 (lambda (a) (match a ((PairDatum _ tail) tail) (_ (type-error "a pair" a))))))

    (: %list (Ref Datum))
    (define %list (variadic (lambda (arguments) (datum-list arguments))))

    (: items-of (-> Datum (List Datum)))
    (define (items-of datum)
      (match (datum->list datum)
        ((Some items) items)
        ((None) (type-error "a list" datum))))

    (: %length (Ref Datum))
    (define %length (procedure1 (lambda (a) (number (number-from-i64 (length (items-of a)))))))

    (: %append (Ref Datum))
    ;; The last argument becomes the tail as it is, so it need not be a list.
    (define %append (variadic (lambda (arguments)
                                (match (reverse arguments)
                                  ((Cons last front) (fold-left (lambda (tail items) (fold-right PairDatum tail (items-of items))) last front))
                                  ((Nil) (NullDatum))))))

    (: %reverse (Ref Datum))
    (define %reverse (procedure1 (lambda (a) (datum-list (reverse (items-of a))))))

    (: %list-ref (Ref Datum))
    (define %list-ref (procedure2 (lambda (a k) (list-ref (items-of a) (integer->i64 (integer-of k))))))

    (: %null? (Ref Datum))
    (define %null? (procedure1 (lambda (a) (boolean (match a ((NullDatum) #t) (_ #f))))))

    (: %pair? (Ref Datum))
    (define %pair? (procedure1 (lambda (a) (boolean (match a ((PairDatum _ _) #t) (_ #f))))))

    (: %list? (Ref Datum))
    (define %list? (procedure1 (lambda (a) (boolean (match (datum->list a) ((Some _) #t) ((None) #f))))))

    ;; ---- Equivalence and types ----

    (: %eq? (Ref Datum))
    (define %eq? (procedure2 (lambda (a b) (boolean (datum=? a b)))))

    (: %eqv? (Ref Datum))
    (define %eqv? (procedure2 (lambda (a b) (boolean (datum=? a b)))))

    (: %equal? (Ref Datum))
    (define %equal? (procedure2 (lambda (a b) (boolean (datum=? a b)))))

    (: %not (Ref Datum))
    (define %not (procedure1 (lambda (a) (boolean (not (datum-truthy? a))))))

    (: %boolean? (Ref Datum))
    (define %boolean? (procedure1 (lambda (a) (boolean (match a ((BooleanDatum _) #t) (_ #f))))))

    (: %symbol? (Ref Datum))
    (define %symbol? (procedure1 (lambda (a) (boolean (match a ((SymbolDatum _) #t) (_ #f))))))

    (: %string? (Ref Datum))
    (define %string? (procedure1 (lambda (a) (boolean (match a ((StringDatum _) #t) (_ #f))))))

    (: %char? (Ref Datum))
    (define %char? (procedure1 (lambda (a) (boolean (match a ((CharDatum _) #t) (_ #f))))))

    (: %procedure? (Ref Datum))
    (define %procedure? (procedure1 (lambda (a) (boolean (match a ((ProcedureDatum _) #t) (_ #f))))))

    ;; ---- Strings and symbols ----

    (: text-of (-> Datum String))
    (define (text-of datum)
      (match datum
        ((StringDatum text) text)
        (_ (type-error "a string" datum))))

    (: %string-append (Ref Datum))
    (define %string-append (variadic (lambda (arguments) (StringDatum (string-concatenate (map text-of arguments))))))

    (: %string-length (Ref Datum))
    (define %string-length (procedure1 (lambda (a) (number (number-from-i64 (string-length (text-of a)))))))

    (: %substring (Ref Datum))
    (define %substring
      (variadic (lambda (arguments)
                  (arity! arguments 3 #f)
                  (StringDatum (substring (text-of (list-ref arguments 0)) (integer->i64 (integer-of (list-ref arguments 1)))
                                          (integer->i64 (integer-of (list-ref arguments 2))))))))

    (: %string=? (Ref Datum))
    (define %string=? (procedure2 (lambda (a b) (boolean (string=? (text-of a) (text-of b))))))

    (: text (-> (-> String String) (Ref Datum) ! mut))
    (define (text f)
      (procedure1 (lambda (a) (StringDatum (f (text-of a))))))

    (: %string-upcase (Ref Datum))
    (define %string-upcase (text string-upcase))

    (: %string-downcase (Ref Datum))
    (define %string-downcase (text string-downcase))

    (: %string-foldcase (Ref Datum))
    (define %string-foldcase (text string-foldcase))

    (: %string-ci=? (Ref Datum))
    (define %string-ci=?
      (procedure2 (lambda (a b) (boolean (string=? (string-foldcase (text-of a)) (string-foldcase (text-of b)))))))

    ;; ---- Characters ----

    ;; Scheme's character procedures are Unicode's, from the runtime's
    ;; tables through (lofi text): `char-upcase` maps the full repertoire,
    ;; `char-numeric?` holds for any script's decimal digits, and
    ;; `string-foldcase` may expand a scalar, as "ß" into "ss", so
    ;; `string-ci=?` compares folded text rather than scalar by scalar.
    (: char-of (-> Datum Char))
    (define (char-of datum)
      (match datum
        ((CharDatum char) char)
        (_ (type-error "a character" datum))))

    (: character (-> (-> Char Char) (Ref Datum) ! mut))
    (define (character f)
      (procedure1 (lambda (a) (CharDatum (f (char-of a))))))

    (: character-property (-> (-> Char Bool) (Ref Datum) ! mut))
    (define (character-property holds?)
      (procedure1 (lambda (a) (boolean (holds? (char-of a))))))

    (: %char-upcase (Ref Datum))
    (define %char-upcase (character char-upcase))

    (: %char-downcase (Ref Datum))
    (define %char-downcase (character char-downcase))

    (: %char-foldcase (Ref Datum))
    (define %char-foldcase (character char-foldcase))

    (: %char-alphabetic? (Ref Datum))
    (define %char-alphabetic? (character-property char-unicode-alphabetic?))

    (: %char-numeric? (Ref Datum))
    (define %char-numeric? (character-property char-unicode-numeric?))

    (: %char-whitespace? (Ref Datum))
    (define %char-whitespace? (character-property char-unicode-whitespace?))

    (: %char-upper-case? (Ref Datum))
    (define %char-upper-case? (character-property char-upper-case?))

    (: %char-lower-case? (Ref Datum))
    (define %char-lower-case? (character-property char-lower-case?))

    (: %char-ci=? (Ref Datum))
    (define %char-ci=? (procedure2 (lambda (a b) (boolean (char=? (char-foldcase (char-of a)) (char-foldcase (char-of b)))))))

    ;; R7RS answers #f for anything that is not a decimal digit.
    (: %digit-value (Ref Datum))
    (define %digit-value
      (procedure1 (lambda (a)
                    (match (char-digit-value (char-of a))
                      ((Some value) (number (number-from-i64 value)))
                      ((None) (boolean #f))))))

    (: %symbol->string (Ref Datum))
    (define %symbol->string (procedure1 (lambda (a) (match a ((SymbolDatum name) (StringDatum name)) (_ (type-error "a symbol" a))))))

    (: %string->symbol (Ref Datum))
    (define %string->symbol (procedure1 (lambda (a) (SymbolDatum (text-of a)))))

    ;; ---- Output and errors ----

    (: %display (Ref Datum))
    (define %display (procedure1 (lambda (a) (write-string (datum->display-string a)) unspecified)))

    (: %write (Ref Datum))
    (define %write (procedure1 (lambda (a) (write-string (datum->string a)) unspecified)))

    (: %newline (Ref Datum))
    (define %newline (variadic (lambda (arguments) (arity! arguments 0 #f) (newline) unspecified)))

    (: %error (Ref Datum))
    (define %error
      (variadic (lambda (arguments)
                  (match arguments
                    ((Cons message irritants)
                     (panic (string-concatenate (Cons (datum->display-string message)
                                                      (map (lambda (irritant) (string-append " " (datum->string irritant))) irritants)))))
                    ((Nil) (panic "error"))))))

    ;; ---- Higher-order procedures ----

    ;; `(apply f a ... list)` calls f with the a's followed by the list.
    (: %apply (Ref Datum))
    (define %apply
      (variadic (lambda (arguments)
                  (match arguments
                    ((Cons f rest)
                     (match (reverse rest)
                       ((Cons items front) (call f (append (reverse front) (items-of items))))
                       ((Nil) (call f (Nil)))))
                    ((Nil) (panic "apply: expected a procedure"))))))

    (: %map (Ref Datum))
    (define %map (procedure2 (lambda (f items) (datum-list (map (lambda (item) (call f (list item))) (items-of items))))))

    (: %for-each (Ref Datum))
    (define %for-each (procedure2 (lambda (f items) (for-each (lambda (item) (call f (list item)) (unit)) (items-of items)) unspecified)))

    ;; ---- Vectors ----

    (: %vector (Ref Datum))
    (define %vector (variadic (lambda (arguments) (VectorDatum (list->vector arguments)))))

    (: items-of-vector (-> Datum (Vector Datum)))
    (define (items-of-vector datum)
      (match datum
        ((VectorDatum items) items)
        (_ (type-error "a vector" datum))))

    (: %vector-ref (Ref Datum))
    (define %vector-ref (procedure2 (lambda (v k) (vector-ref (items-of-vector v) (integer->i64 (integer-of k))))))

    (: %vector-length (Ref Datum))
    (define %vector-length (procedure1 (lambda (v) (number (number-from-i64 (vector-length (items-of-vector v)))))))

    ))

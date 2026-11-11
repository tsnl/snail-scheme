;; The run-time support of Scheme programs that (scheme compiler) translated.
;; Every value is an Any and every variable a cell holding one. The standard
;; procedures are cells holding procedures, named like translated variables
;; with a leading `%`, so a program may rebind them. Pairs are immutable, so
;; `eq?` and `eqv?` compare structurally, like `equal?`.
(define-library (scheme runtime)
  (export
   call
   scheme-evaluate
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
   (snail core base)
   (snail core io)
   (snail core dynamic)
   (only (snail core primitive) any-type-id)
   (snail shell arithmetic)
   (snail shell arithmetic dynamic)
   (snail shell number)
   (snail shell integer)
   (snail shell rational)
   (snail shell datum)
   (snail shell text)
   (snail shell write))
  (begin

    ;; ---- Calls ----

    (: call (impl (Fn Any (List Any) -> Any ! console mut dyn-cast)))
    (define (call procedure arguments)
      ((::call (type-convert procedure Procedure)) arguments))

    ;; Generated scripts fail at the current evaluation. A caller using call
    ;; directly can instead recover with its own dyn-cast handler.
    (: scheme-evaluate (impl (Fn (dyn (Fn -> Any ! console mut dyn-cast)) -> Any ! console mut)))
    (define (scheme-evaluate work)
      (handle dyn-cast
          ((conversion-failed (lambda (error) (panic (cast-error->string error)))))
        (work)))

    (: arity! (impl (Fn (List Any) I64 Bool -> Unit)))
    (define (arity! arguments count rest?)
      (let ((given (length arguments)))
        (unless (if rest? (>= given count) (= given count))
          (panic (string-append "expected "
                                (i64->string count)
                                (if rest? " or more" "")
                                " arguments, got "
                                (i64->string given))))))

    (: rest-arguments (impl (Fn (List Any) I64 -> Any)))
    (define (rest-arguments arguments count)
      (datum-list (list-tail arguments count)))

    (: scheme-number (impl (Fn String -> Any)))
    (define (scheme-number text)
      (match (string->number text)
        ((Some n) (number->datum n))
        ((None) (panic (string-append "not a number: " text)))))

    ;; The value of expressions whose value Scheme leaves unspecified.
    (: unspecified Any)
    (define unspecified (ann #f Any))

    (: member-datum? (impl (Fn Any Any -> Bool)))
    (define (member-datum? item items)
      (match-any items
                 ((SchemePair (SchemePair head tail))
                  (or (datum=? head item) (member-datum? item tail)))
                 (else #f)))

    ;; Bind arguments from an explicitly typed list before inferring the
    ;; body. This avoids inferring a concrete closure and trying to cast it.
    (define-syntax procedure1
      (syntax-rules (lambda)
        ((_ (lambda (value) body ...))
         (variadic (lambda (arguments)
                     (arity! arguments 1 #f)
                     (let ((value (list-ref arguments 0))) body ...))))))

    (define-syntax procedure2
      (syntax-rules (lambda)
        ((_ (lambda (left right) body ...))
         (variadic (lambda (arguments)
                     (arity! arguments 2 #f)
                     (let ((left (list-ref arguments 0)) (right (list-ref arguments 1)))
                       body ...))))))

    (define-syntax variadic
      (syntax-rules (lambda)
        ((_ (lambda (arguments) body ...))
         (ref (ann (Procedure (lambda (arguments)
                                (ann arguments (List Any))
                                (ann (begin body ...) Any))) Any)))))

    ;; A domain check shares the failure path of concrete type conversions.
    (: type-error (All (A) (impl (Fn String Any -> A ! dyn-cast))))
    (define (type-error expected datum)
      (absurd (conversion-failed
               (CastError (TypeMismatch) (list expected) (any-type-id datum)
                          "scheme runtime" "" -1))))

    ;; ---- Numbers ----

    (: number-of (impl (Fn Any -> Number ! dyn-cast)))
    (define (number-of datum)
      (match (datum-number datum)
        ((Some n) n)
        ((None) (type-error "Integer, Rational or F64" datum))))

    (: integer-of (impl (Fn Any -> Integer ! dyn-cast)))
    (define (integer-of datum)
      (match (number-of datum)
        ((Exact r)
         (if (rational-integer? r) (::numerator r) (type-error "an integer" datum)))
        ((Inexact _) (type-error "an exact integer" datum))))

    (: inverse-fold
       (impl (Fn (dyn (Fn Any Any -> Any ! dyn-cast)) Any (List Any) -> Any ! dyn-cast)))
    (define (inverse-fold op identity arguments)
      (match arguments
        ((Cons first (Nil)) (op identity first))
        ((Cons first rest) (fold-left op first rest))
        ((Nil) (panic "expected at least one argument"))))

    (: chain (impl (Fn (dyn (Fn I64 -> Bool)) (List Any) -> Any ! dyn-cast)))
    (define (chain test arguments)
      (let loop ((items arguments))
        (match items
          ((Cons a (Cons b rest))
           (and (test (number-compare (number-of a) (number-of b))) (loop (Cons b rest))))
          (_ #t))))

    ;; Only these definitions select the Scheme numeric tower policy.
    ;; Importing the runtime cannot enable promotion in its typed clients.
    (with-instances (dynamic-arithmetic)
                    (: %+ (Ref Any))
                    (define %+ (variadic (lambda (arguments)
                                           (fold-left add
                                                      (ann (integer-from-i64 0) Any)
                                                      arguments))))
                    (: %* (Ref Any))
                    (define %* (variadic (lambda (arguments)
                                           (fold-left multiply
                                                      (ann (integer-from-i64 1) Any)
                                                      arguments))))
                    (: %- (Ref Any))
                    (define %- (variadic (lambda (arguments)
                                           (inverse-fold subtract (integer-from-i64 0) arguments))))
                    (: %/ (Ref Any))
                    (define %/ (variadic (lambda (arguments)
                                           (inverse-fold divide (integer-from-i64 1) arguments)))))

    (: %= (Ref Any))
    (define %= (variadic (lambda (arguments) (chain (lambda (order) (= order 0)) arguments))))

    (: %< (Ref Any))
    (define %< (variadic (lambda (arguments) (chain (lambda (order) (< order 0)) arguments))))

    (: %> (Ref Any))
    (define %> (variadic (lambda (arguments) (chain (lambda (order) (> order 0)) arguments))))

    (: %<= (Ref Any))
    (define %<= (variadic (lambda (arguments) (chain (lambda (order) (<= order 0)) arguments))))

    (: %>= (Ref Any))
    (define %>= (variadic (lambda (arguments) (chain (lambda (order) (>= order 0)) arguments))))

    (: %quotient (Ref Any))
    (define %quotient
      (procedure2 (lambda (a b)
                    (ann (integer-quotient (integer-of a) (integer-of b)) Any))))

    (: %remainder (Ref Any))
    (define %remainder
      (procedure2 (lambda (a b)
                    (ann (integer-remainder (integer-of a) (integer-of b)) Any))))

    (: %modulo (Ref Any))
    (define %modulo
      (procedure2 (lambda (a b)
                    (ann (integer-modulo (integer-of a) (integer-of b)) Any))))

    (: %abs (Ref Any))
    (define %abs
      (procedure1 (lambda (a)
                    (if (< (sign a) 0)
                        (with-instances (dynamic-arithmetic)
                                        (subtract (ann (integer-from-i64 0) Any) a))
                        a))))

    (: %max (Ref Any))
    (define %max (variadic (lambda (arguments) (extreme (lambda (order) (> order 0)) arguments))))

    (: %min (Ref Any))
    (define %min (variadic (lambda (arguments) (extreme (lambda (order) (< order 0)) arguments))))

    (: extreme (impl (Fn (dyn (Fn I64 -> Bool)) (List Any) -> Any ! dyn-cast)))
    (define (extreme better? arguments)
      (match arguments
        ((Cons first rest)
         (fold-left (lambda (best item)
                      (if (better? (number-compare (number-of item) (number-of best))) item best))
                    first
                    rest))
        ((Nil) (panic "expected at least one argument"))))

    (: %number? (Ref Any))
    (define %number?
      (procedure1 (lambda (a) (match (datum-number a) ((Some _) #t) ((None) #f)))))

    (: %integer? (Ref Any))
    (define %integer?
      (procedure1
       (lambda (a) (match (datum-number a) ((Some n) (number-integer? n)) ((None) #f)))))

    (: sign (impl (Fn Any -> I64 ! dyn-cast)))
    (define (sign a)
      (number-compare (number-of a) (number-from-i64 0)))

    (: %zero? (Ref Any))
    (define %zero? (procedure1 (lambda (a) (= (sign a) 0))))

    (: %positive? (Ref Any))
    (define %positive? (procedure1 (lambda (a) (> (sign a) 0))))

    (: %negative? (Ref Any))
    (define %negative? (procedure1 (lambda (a) (< (sign a) 0))))

    (: %even? (Ref Any))
    (define %even?
      (procedure1 (lambda (a)
                    (integer-zero? (integer-remainder (integer-of a) (integer-from-i64 2))))))

    (: %odd? (Ref Any))
    (define %odd?
      (procedure1 (lambda (a)
                    (not (integer-zero?
                          (integer-remainder (integer-of a) (integer-from-i64 2)))))))

    (: %number->string (Ref Any))
    (define %number->string (procedure1 (lambda (a) (number->string (number-of a)))))

    ;; ---- Pairs and lists ----

    (: %cons (Ref Any))
    (define %cons (procedure2 (lambda (a b) (SchemePair a b))))

    (: %car (Ref Any))
    (define %car (procedure1 (lambda (a) (::car (type-convert a SchemePair)))))

    (: %cdr (Ref Any))
    (define %cdr (procedure1 (lambda (a) (::cdr (type-convert a SchemePair)))))

    (: %list (Ref Any))
    (define %list (variadic (lambda (arguments) (datum-list arguments))))

    (: items-of (impl (Fn Any -> (List Any) ! dyn-cast)))
    (define (items-of datum)
      (match (datum->list datum)
        ((Some items) items)
        ((None) (type-error "a list" datum))))

    (: %length (Ref Any))
    (define %length (procedure1 (lambda (a) (integer-from-i64 (length (items-of a))))))

    (: %append (Ref Any))
    ;; The last argument becomes the tail as it is, so it need not be a list.
    (define %append (variadic (lambda (arguments)
                                (match (reverse arguments)
                                  ((Cons last front)
                                   (fold-left (lambda (tail items)
                                                (fold-right (lambda (head tail)
                                                              (ann (SchemePair head tail) Any))
                                                            tail
                                                            (items-of items)))
                                              last
                                              front))
                                  ((Nil) (ann (Null) Any))))))

    (: %reverse (Ref Any))
    (define %reverse (procedure1 (lambda (a) (datum-list (reverse (items-of a))))))

    (: %list-ref (Ref Any))
    (define %list-ref
      (procedure2 (lambda (a k) (list-ref (items-of a) (integer->i64 (integer-of k))))))

    (: %null? (Ref Any))
    (define %null? (procedure1 (lambda (a) (type-test a Null))))

    (: %pair? (Ref Any))
    (define %pair? (procedure1 (lambda (a) (type-test a SchemePair))))

    (: %list? (Ref Any))
    (define %list?
      (procedure1 (lambda (a) (match (datum->list a) ((Some _) #t) ((None) #f)))))

    ;; ---- Equivalence and types ----

    (: %eq? (Ref Any))
    (define %eq? (procedure2 (lambda (a b) (datum=? a b))))

    (: %eqv? (Ref Any))
    (define %eqv? (procedure2 (lambda (a b) (datum=? a b))))

    (: %equal? (Ref Any))
    (define %equal? (procedure2 (lambda (a b) (datum=? a b))))

    (: %not (Ref Any))
    (define %not (procedure1 (lambda (a) (not (datum-truthy? a)))))

    (: %boolean? (Ref Any))
    (define %boolean? (procedure1 (lambda (a) (type-test a Bool))))

    (: %symbol? (Ref Any))
    (define %symbol? (procedure1 (lambda (a) (type-test a Symbol))))

    (: %string? (Ref Any))
    (define %string? (procedure1 (lambda (a) (type-test a String))))

    (: %char? (Ref Any))
    (define %char? (procedure1 (lambda (a) (type-test a Char))))

    (: %procedure? (Ref Any))
    (define %procedure?
      (procedure1 (lambda (a) (type-test a Procedure))))

    ;; ---- Strings and symbols ----

    (: text-of (impl (Fn Any -> String ! dyn-cast)))
    (define (text-of value) value)

    (: %string-append (Ref Any))
    (define %string-append
      (variadic (lambda (arguments) (string-concatenate (map text-of arguments)))))

    (: %string-length (Ref Any))
    (define %string-length
      (procedure1 (lambda (a) (integer-from-i64 (string-length a)))))

    (: %substring (Ref Any))
    (define %substring
      (variadic (lambda (arguments)
                  (arity! arguments 3 #f)
                  (substring (list-ref arguments 0)
                             (integer->i64 (integer-of (list-ref arguments 1)))
                             (integer->i64 (integer-of (list-ref arguments 2)))))))

    (: %string=? (Ref Any))
    (define %string=? (procedure2 (lambda (a b) (string=? a b))))

    (: text (impl (Fn (dyn (Fn String -> String)) -> (Ref Any))))
    (define (text f)
      (procedure1 (lambda (a) (f a))))

    (: %string-upcase (Ref Any))
    (define %string-upcase (text string-upcase))

    (: %string-downcase (Ref Any))
    (define %string-downcase (text string-downcase))

    (: %string-foldcase (Ref Any))
    (define %string-foldcase (text string-foldcase))

    (: %string-ci=? (Ref Any))
    (define %string-ci=?
      (procedure2 (lambda (a b)
                    (string=? (string-foldcase a) (string-foldcase b)))))

    ;; ---- Characters ----

    ;; Scheme's character procedures are Unicode's, from the runtime's
    ;; tables through (snail shell text): `char-upcase` maps the full repertoire,
    ;; `char-numeric?` holds for any script's decimal digits, and
    ;; `string-foldcase` may expand a scalar, as "ß" into "ss", so
    ;; `string-ci=?` compares folded text rather than scalar by scalar.

    (: character (impl (Fn (dyn (Fn Char -> Char)) -> (Ref Any))))
    (define (character f)
      (procedure1 (lambda (a) (f a))))

    (: character-property (impl (Fn (dyn (Fn Char -> Bool)) -> (Ref Any))))
    (define (character-property holds?)
      (procedure1 (lambda (a) (holds? a))))

    (: %char-upcase (Ref Any))
    (define %char-upcase (character char-upcase))

    (: %char-downcase (Ref Any))
    (define %char-downcase (character char-downcase))

    (: %char-foldcase (Ref Any))
    (define %char-foldcase (character char-foldcase))

    (: %char-alphabetic? (Ref Any))
    (define %char-alphabetic? (character-property char-unicode-alphabetic?))

    (: %char-numeric? (Ref Any))
    (define %char-numeric? (character-property char-unicode-numeric?))

    (: %char-whitespace? (Ref Any))
    (define %char-whitespace? (character-property char-unicode-whitespace?))

    (: %char-upper-case? (Ref Any))
    (define %char-upper-case? (character-property char-upper-case?))

    (: %char-lower-case? (Ref Any))
    (define %char-lower-case? (character-property char-lower-case?))

    (: %char-ci=? (Ref Any))
    (define %char-ci=?
      (procedure2
       (lambda (a b) (char=? (char-foldcase a) (char-foldcase b)))))

    ;; R7RS answers #f for anything that is not a decimal digit.
    (: %digit-value (Ref Any))
    (define %digit-value
      (procedure1 (lambda (a)
                    (match (char-digit-value a)
                      ((Some value) (ann (integer-from-i64 value) Any))
                      ((None) (ann #f Any))))))

    (: %symbol->string (Ref Any))
    (define %symbol->string (procedure1 (lambda (a) (::name (type-convert a Symbol)))))

    (: %string->symbol (Ref Any))
    (define %string->symbol (procedure1 (lambda (a) (Symbol a))))

    ;; ---- Output and errors ----

    (: %display (Ref Any))
    (define %display (procedure1 (lambda (a) (write-string (datum->display-string a)) unspecified)))

    (: %write (Ref Any))
    (define %write (procedure1 (lambda (a) (write-string (datum->string a)) unspecified)))

    (: %newline (Ref Any))
    (define %newline (variadic (lambda (arguments) (arity! arguments 0 #f) (newline) unspecified)))

    (: %error (Ref Any))
    (define %error
      (variadic (lambda (arguments)
                  (match arguments
                    ((Cons message irritants)
                     (panic (string-concatenate (Cons (datum->display-string message)
                                                      (map (lambda (irritant)
                                                             (string-append " "
                                                                            (datum->string
                                                                             irritant)))
                                                           irritants)))))
                    ((Nil) (panic "error"))))))

    ;; ---- Higher-order procedures ----

    ;; `(apply f a ... list)` calls f with the a's followed by the list.
    (: %apply (Ref Any))
    (define %apply
      (variadic (lambda (arguments)
                  (match arguments
                    ((Cons f rest)
                     (match (reverse rest)
                       ((Cons items front) (call f (append (reverse front) (items-of items))))
                       ((Nil) (call f (Nil)))))
                    ((Nil) (panic "apply: expected a procedure"))))))

    (: %map (Ref Any))
    (define %map
      (procedure2
       (lambda (f items) (datum-list (map (lambda (item) (call f (list item))) (items-of items))))))

    (: %for-each (Ref Any))
    (define %for-each
      (procedure2 (lambda (f items)
                    (for-each (lambda (item) (call f (list item)) (unit)) (items-of items))
                    unspecified)))

    ;; ---- Vectors ----

    (: %vector (Ref Any))
    (define %vector (variadic (lambda (arguments) (list->vector arguments))))

    (: %vector-ref (Ref Any))
    (define %vector-ref
      (procedure2 (lambda (v k) (vector-ref (ann v (Vector Any)) (integer->i64 (integer-of k))))))

    (: %vector-length (Ref Any))
    (define %vector-length
      (procedure1 (lambda (v) (integer-from-i64 (vector-length (ann v (Vector Any)))))))

    ))

;; The run-time support of Scheme programs that (scheme compiler) translated.
;; Every value is an Any and every variable a cell holding one. The standard
;; procedures are cells holding procedures, named like translated variables
;; with a leading `%`, so a program may rebind them. Pairs are immutable, so
;; `eq?` and `eqv?` compare structurally, like `equal?`.
(define-library (scheme runtime)
  (export
   call
   Variable Variable-value Variable-value-set!
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
    ;; Scheme bindings have shared mutable identity, independently of their
    ;; dynamically typed value. The typed core needs no special reference type.
    (struct Variable
      ((value Any)))


    ;; ---- Calls ----

    (define (call (procedure Any) (arguments (List Any))) (→ Any) (! output-port mut dyn-cast)
      ((● (type-convert procedure Procedure) call) arguments))

    ;; Generated scripts fail at the current evaluation. A caller using call
    ;; directly can instead recover with its own dyn-cast handler.
    (define (scheme-evaluate (work (Fn → Any ! output-port mut dyn-cast))) (→ Any) (! output-port mut)
      (handle dyn-cast
          ((conversion-failed (lambda (error) (panic (cast-error->string error)))))
        (work)))

    (define (arity! (arguments (List Any)) (count I64) (rest? Bool)) (→ Unit)
      (let ((given (length arguments)))
        (unless (if rest? (>= given count) (= given count))
          (panic (string-append "expected "
                                (i64->string count)
                                (if rest? " or more" "")
                                " arguments, got "
                                (i64->string given))))))

    (define (rest-arguments (arguments (List Any)) (count I64)) (→ Any)
      (datum-list (list-tail arguments count)))

    (define (scheme-number (text String)) (→ Any)
      (match (string->number text)
        ((Some n) (number->datum n))
        ((None) (panic (string-append "not a number: " text)))))

    ;; The value of expressions whose value Scheme leaves unspecified.
    (define unspecified (→ Any) (ann #f Any))

    (define (member-datum? (item Any) (items Any)) (→ Bool)
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
         (Variable (ann (Procedure (lambda (arguments)
                                (ann arguments (List Any))
                                (ann (begin body ...) Any))) Any)))))

    ;; A domain check shares the failure path of concrete type conversions.
    (define (type-error (expected String) (datum Any)) (→ A) (! dyn-cast) (∀ A)
      (absurd (conversion-failed
               (CastError (TypeMismatch) (list expected) (any-type-id datum)
                          "scheme runtime" "" -1))))

    ;; ---- Numbers ----

    (define (number-of (datum Any)) (→ Number) (! dyn-cast)
      (match (datum-number datum)
        ((Some n) n)
        ((None) (type-error "Integer, Rational or F64" datum))))

    (define (integer-of (datum Any)) (→ Integer) (! dyn-cast)
      (match (number-of datum)
        ((Exact r)
         (if (rational-integer? r) (● r numerator) (type-error "an integer" datum)))
        ((Inexact _) (type-error "an exact integer" datum))))

    (define (inverse-fold (op (Fn Any Any → Any ! dyn-cast))
                          (identity Any)
                          (arguments (List Any)))
      (→ Any)
      (! dyn-cast)
      (match arguments
        ((Cons first (Nil)) (op identity first))
        ((Cons first rest) (fold-left op first rest))
        ((Nil) (panic "expected at least one argument"))))

    (define (chain (test (Fn I64 → Bool)) (arguments (List Any))) (→ Any) (! dyn-cast)
      (let loop ((items arguments))
        (match items
          ((Cons a (Cons b rest))
           (and (test (number-compare (number-of a) (number-of b))) (loop (Cons b rest))))
          (_ #t))))

    ;; Only these definitions select the Scheme numeric tower policy.
    ;; Importing the runtime cannot enable promotion in its typed clients.
    (with-instances (dynamic-arithmetic)
                    (define %+ (→ Variable) (variadic (lambda (arguments)
                                                         (fold-left add
                                                                    (ann (integer-from-i64 0) Any)
                                                                    arguments))))
                    (define %* (→ Variable) (variadic (lambda (arguments)
                                                         (fold-left multiply
                                                                    (ann (integer-from-i64 1) Any)
                                                                    arguments))))
                    (define %- (→ Variable) (variadic (lambda (arguments)
                                                         (inverse-fold subtract
                                                                       (integer-from-i64 0)
                                                                       arguments))))
                    (define %/ (→ Variable) (variadic (lambda (arguments)
                                                         (inverse-fold divide
                                                                       (integer-from-i64 1)
                                                                       arguments)))))

    (define %=
      (→ Variable)
      (variadic (lambda (arguments) (chain (lambda (order) (= order 0)) arguments))))

    (define %<
      (→ Variable)
      (variadic (lambda (arguments) (chain (lambda (order) (< order 0)) arguments))))

    (define %>
      (→ Variable)
      (variadic (lambda (arguments) (chain (lambda (order) (> order 0)) arguments))))

    (define %<=
      (→ Variable)
      (variadic (lambda (arguments) (chain (lambda (order) (<= order 0)) arguments))))

    (define %>=
      (→ Variable)
      (variadic (lambda (arguments) (chain (lambda (order) (>= order 0)) arguments))))

    (define %quotient (→ Variable)
      (procedure2 (lambda (a b)
                    (ann (integer-quotient (integer-of a) (integer-of b)) Any))))

    (define %remainder (→ Variable)
      (procedure2 (lambda (a b)
                    (ann (integer-remainder (integer-of a) (integer-of b)) Any))))

    (define %modulo (→ Variable)
      (procedure2 (lambda (a b)
                    (ann (integer-modulo (integer-of a) (integer-of b)) Any))))

    (define %abs (→ Variable)
      (procedure1 (lambda (a)
                    (if (< (sign a) 0)
                        (with-instances (dynamic-arithmetic)
                                        (subtract (ann (integer-from-i64 0) Any) a))
                        a))))

    (define %max
      (→ Variable)
      (variadic (lambda (arguments) (extreme (lambda (order) (> order 0)) arguments))))

    (define %min
      (→ Variable)
      (variadic (lambda (arguments) (extreme (lambda (order) (< order 0)) arguments))))

    (define (extreme (better? (Fn I64 → Bool)) (arguments (List Any))) (→ Any) (! dyn-cast)
      (match arguments
        ((Cons first rest)
         (fold-left (lambda (best item)
                      (if (better? (number-compare (number-of item) (number-of best))) item best))
                    first
                    rest))
        ((Nil) (panic "expected at least one argument"))))

    (define %number? (→ Variable)
      (procedure1 (lambda (a) (match (datum-number a) ((Some _) #t) ((None) #f)))))

    (define %integer? (→ Variable)
      (procedure1
       (lambda (a) (match (datum-number a) ((Some n) (number-integer? n)) ((None) #f)))))

    (define (sign (a Any)) (→ I64) (! dyn-cast)
      (number-compare (number-of a) (number-from-i64 0)))

    (define %zero? (→ Variable) (procedure1 (lambda (a) (= (sign a) 0))))

    (define %positive? (→ Variable) (procedure1 (lambda (a) (> (sign a) 0))))

    (define %negative? (→ Variable) (procedure1 (lambda (a) (< (sign a) 0))))

    (define %even? (→ Variable)
      (procedure1 (lambda (a)
                    (integer-zero? (integer-remainder (integer-of a) (integer-from-i64 2))))))

    (define %odd? (→ Variable)
      (procedure1 (lambda (a)
                    (not (integer-zero?
                          (integer-remainder (integer-of a) (integer-from-i64 2)))))))

    (define %number->string (→ Variable) (procedure1 (lambda (a) (number->string (number-of a)))))

    ;; ---- Pairs and lists ----

    (define %cons (→ Variable) (procedure2 (lambda (a b) (SchemePair a b))))

    (define %car (→ Variable) (procedure1 (lambda (a) (● (type-convert a SchemePair) car))))

    (define %cdr (→ Variable) (procedure1 (lambda (a) (● (type-convert a SchemePair) cdr))))

    (define %list (→ Variable) (variadic (lambda (arguments) (datum-list arguments))))

    (define (items-of (datum Any)) (→ (List Any)) (! dyn-cast)
      (match (datum->list datum)
        ((Some items) items)
        ((None) (type-error "a list" datum))))

    (define %length
      (→ Variable)
      (procedure1 (lambda (a) (integer-from-i64 (length (items-of a))))))

    ;; The last argument becomes the tail as it is, so it need not be a list.
    (define %append (→ Variable) (variadic (lambda (arguments)
                                              (match (reverse arguments)
                                                ((Cons last front)
                                                 (fold-left (lambda (tail items)
                                                              (fold-right (lambda (head tail)
                                                                            (ann
                                                                             (SchemePair head tail)
                                                                             Any))
                                                                          tail
                                                                          (items-of items)))
                                                            last
                                                            front))
                                                ((Nil) (ann (Null) Any))))))

    (define %reverse (→ Variable) (procedure1 (lambda (a) (datum-list (reverse (items-of a))))))

    (define %list-ref (→ Variable)
      (procedure2 (lambda (a k) (list-ref (items-of a) (integer->i64 (integer-of k))))))

    (define %null? (→ Variable) (procedure1 (lambda (a) (type-test a Null))))

    (define %pair? (→ Variable) (procedure1 (lambda (a) (type-test a SchemePair))))

    (define %list? (→ Variable)
      (procedure1 (lambda (a) (match (datum->list a) ((Some _) #t) ((None) #f)))))

    ;; ---- Equivalence and types ----

    (define %eq? (→ Variable) (procedure2 (lambda (a b) (datum=? a b))))

    (define %eqv? (→ Variable) (procedure2 (lambda (a b) (datum=? a b))))

    (define %equal? (→ Variable) (procedure2 (lambda (a b) (datum=? a b))))

    (define %not (→ Variable) (procedure1 (lambda (a) (not (datum-truthy? a)))))

    (define %boolean? (→ Variable) (procedure1 (lambda (a) (type-test a Bool))))

    (define %symbol? (→ Variable) (procedure1 (lambda (a) (type-test a Symbol))))

    (define %string? (→ Variable) (procedure1 (lambda (a) (type-test a String))))

    (define %char? (→ Variable) (procedure1 (lambda (a) (type-test a Char))))

    (define %procedure? (→ Variable)
      (procedure1 (lambda (a) (type-test a Procedure))))

    ;; ---- Strings and symbols ----

    (define (text-of (value Any)) (→ String) (! dyn-cast) value)

    (define %string-append (→ Variable)
      (variadic (lambda (arguments) (string-concatenate (map text-of arguments)))))

    (define %string-length (→ Variable)
      (procedure1 (lambda (a) (integer-from-i64 (string-length a)))))

    (define %substring (→ Variable)
      (variadic (lambda (arguments)
                  (arity! arguments 3 #f)
                  (substring (list-ref arguments 0)
                             (integer->i64 (integer-of (list-ref arguments 1)))
                             (integer->i64 (integer-of (list-ref arguments 2)))))))

    (define %string=? (→ Variable) (procedure2 (lambda (a b) (string=? a b))))

    (define (text (f (Fn String → String))) (→ Variable)
      (procedure1 (lambda (a) (f a))))

    (define %string-upcase (→ Variable) (text string-upcase))

    (define %string-downcase (→ Variable) (text string-downcase))

    (define %string-foldcase (→ Variable) (text string-foldcase))

    (define %string-ci=? (→ Variable)
      (procedure2 (lambda (a b)
                    (string=? (string-foldcase a) (string-foldcase b)))))

    ;; ---- Characters ----

    ;; Scheme's character procedures are Unicode's, from the runtime's
    ;; tables through (snail shell text): `char-upcase` maps the full repertoire,
    ;; `char-numeric?` holds for any script's decimal digits, and
    ;; `string-foldcase` may expand a scalar, as "ß" into "ss", so
    ;; `string-ci=?` compares folded text rather than scalar by scalar.

    (define (character (f (Fn Char → Char))) (→ Variable)
      (procedure1 (lambda (a) (f a))))

    (define (character-property (holds? (Fn Char → Bool))) (→ Variable)
      (procedure1 (lambda (a) (holds? a))))

    (define %char-upcase (→ Variable) (character char-upcase))

    (define %char-downcase (→ Variable) (character char-downcase))

    (define %char-foldcase (→ Variable) (character char-foldcase))

    (define %char-alphabetic? (→ Variable) (character-property char-unicode-alphabetic?))

    (define %char-numeric? (→ Variable) (character-property char-unicode-numeric?))

    (define %char-whitespace? (→ Variable) (character-property char-unicode-whitespace?))

    (define %char-upper-case? (→ Variable) (character-property char-upper-case?))

    (define %char-lower-case? (→ Variable) (character-property char-lower-case?))

    (define %char-ci=? (→ Variable)
      (procedure2
       (lambda (a b) (char=? (char-foldcase a) (char-foldcase b)))))

    ;; R7RS answers #f for anything that is not a decimal digit.
    (define %digit-value (→ Variable)
      (procedure1 (lambda (a)
                    (match (char-digit-value a)
                      ((Some value) (ann (integer-from-i64 value) Any))
                      ((None) (ann #f Any))))))

    (define %symbol->string
      (→ Variable)
      (procedure1 (lambda (a) (● (type-convert a Symbol) name))))

    (define %string->symbol (→ Variable) (procedure1 (lambda (a) (Symbol a))))

    ;; ---- Output and errors ----

    (define %display
      (→ Variable)
      (procedure1 (lambda (a) (write-string (datum->display-string a)) unspecified)))

    (define %write (→ Variable) (procedure1 (lambda (a) (write a) unspecified)))

    (define %newline
      (→ Variable)
      (variadic (lambda (arguments) (arity! arguments 0 #f) (newline) unspecified)))

    (define %error (→ Variable)
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
    (define %apply (→ Variable)
      (variadic (lambda (arguments)
                  (match arguments
                    ((Cons f rest)
                     (match (reverse rest)
                       ((Cons items front) (call f (append (reverse front) (items-of items))))
                       ((Nil) (call f (Nil)))))
                    ((Nil) (panic "apply: expected a procedure"))))))

    (define %map (→ Variable)
      (procedure2
       (lambda (f items) (datum-list (map (lambda (item) (call f (list item))) (items-of items))))))

    (define %for-each (→ Variable)
      (procedure2 (lambda (f items)
                    (for-each (lambda (item) (call f (list item)) (unit)) (items-of items))
                    unspecified)))

    ;; ---- Vectors ----

    (define %vector (→ Variable) (variadic (lambda (arguments) (list->vector arguments))))

    (define %vector-ref (→ Variable)
      (procedure2 (lambda (v k) (vector-ref (ann v (Vector Any)) (integer->i64 (integer-of k))))))

    (define %vector-length (→ Variable)
      (procedure1 (lambda (v) (integer-from-i64 (vector-length (ann v (Vector Any)))))))

    ))

;; Small, decidable type algebra. These types describe normal Scheme values;
;; initialization and the number of returned values are separate properties.
(define-library (snail-scheme types)
  (export scalar-type-names arrow-type? union-type? type-arguments type-result
          type-equal? type-subtype? type-union type-intersect type-subtract literal-type
          runtime-type? dynamic-type? type-compatible? nominal-type?
          make-type-variable type-variable? type-variable-name all-type? all-variables all-body
          function-type? shallow-type? type-substitute type-erasure type-error-at)
  (import (scheme base) (scheme cxr) (snail-scheme source)
          (prefix (snail-scheme ir) ir:))
  (begin
    ;; ---- Types and subtyping ----

    (define scalar-type-names
      '(? Any Never Boolean False True Null ExactInteger InexactReal Complex Number
          String Symbol Char Pair Vector Bytevector Procedure Record Unspecified i32))

    (define (arrow-type? type) (and (pair? type) (eq? (car type) '->)))
    (define (union-type? type) (and (pair? type) (eq? (car type) 'U)))
    (define (nominal-type? type) (and (pair? type) (eq? (car type) 'record)))
    (define (intersection-type? type) (and (pair? type) (eq? (car type) 'I)))
    (define (all-type? type) (and (pair? type) (eq? (car type) 'All)))
    (define (all-variables type) (cadr type))
    (define (all-body type) (if (all-type? type) (caddr type) type))
    (define (function-type? type) (or (arrow-type? type) (all-type? type)))
    (define (type-arguments type) (reverse (cdr (reverse (cdr type)))))
    (define (type-result type) (car (reverse type)))
    (define (dynamic-type? type) (eq? type '?))

    ;; Variables are opaque identities. Their names exist only for diagnostics.
    (define-record-type <type-variable>
      (make-type-variable name) type-variable? (name type-variable-name))

    (define (all? predicate items)
      (or (null? items) (and (predicate (car items)) (all? predicate (cdr items)))))
    (define (some? predicate items)
      (and (pair? items) (or (predicate (car items)) (some? predicate (cdr items)))))

    ;; Chibi equal? compares record fields. Binding identities must instead stay
    ;; opaque, including two hygienic binders with identical names and locations.
    (define (type-equal? left right)
      (or (eq? left right)
          (and (all-type? left) (all-type? right)
               (= (length (all-variables left)) (length (all-variables right)))
               (type-equal? (all-body left)
                            (type-substitute (all-body right) (map cons (all-variables right) (all-variables left)))))
          (and (or (and (union-type? left) (union-type? right))
                   (and (intersection-type? left) (intersection-type? right)))
               (all? (lambda (arm) (some? (lambda (other) (type-equal? arm other)) (cdr right))) (cdr left))
               (all? (lambda (arm) (some? (lambda (other) (type-equal? arm other)) (cdr left))) (cdr right)))
          (and (pair? left) (pair? right)
               (type-equal? (car left) (car right)) (type-equal? (cdr left) (cdr right)))))

    (define (type-subtype? source target)
      (or (type-equal? source target) (eq? source 'Never) (eq? target 'Any)
          (and (intersection-type? target)
               (all? (lambda (part) (type-subtype? source part)) (cdr target)))
          (and (intersection-type? source)
               (some? (lambda (part) (type-subtype? part target)) (cdr source)))
          (and (eq? source 'Boolean) (type-subtype? '(U False True) target))
          (and (eq? source 'Number) (type-subtype? '(U ExactInteger InexactReal Complex) target))
          (and (union-type? source) (all? (lambda (arm) (type-subtype? arm target)) (cdr source)))
          (and (union-type? target) (some? (lambda (arm) (type-subtype? source arm)) (cdr target)))
          (and (memq source '(False True)) (eq? target 'Boolean))
          (and (memq source '(i32 ExactInteger InexactReal Complex)) (eq? target 'Number))
          (and (eq? source 'i32) (eq? target 'ExactInteger))
          (and (nominal-type? source) (eq? target 'Record))
          (and (function-type? source) (eq? target 'Procedure))))

    (define (type-compatible? source target)
      (or (type-subtype? source target) (dynamic-type? source) (dynamic-type? target)
          (and (eq? target 'i32) (type-subtype? source 'ExactInteger))))

    (define (type-members type)
      (cond ((union-type? type) (apply append (map type-members (cdr type)))) ((eq? type 'Never) '())
            ((eq? type 'Boolean) '(False True))
            ((eq? type 'Number) '(ExactInteger InexactReal Complex)) (else (list type))))

    (define (insert-type type types)
      (cond ((null? types) (list type))
            ((type-subtype? type (car types)) types)
            ((type-subtype? (car types) type) (insert-type type (cdr types)))
            (else (cons (car types) (insert-type type (cdr types))))))

    (define (type-union . types)
      (let loop ((arms (apply append (map type-members types))) (result '()))
        (cond ((memq '? arms) '?) ((null? arms)
                                   (cond ((null? result) 'Never) ((null? (cdr result)) (car result))
                                         (else (cons 'U result))))
              (else (loop (cdr arms) (insert-type (car arms) result))))))

    (define (type-intersect left right)
      (cond ((memq left '(Any ?)) right) ((memq right '(Any ?)) left)
            ((type-subtype? left right) left) ((type-subtype? right left) right)
            ((union-type? left)
             (apply type-union (map (lambda (arm) (type-intersect arm right)) (cdr left))))
            ((union-type? right) (type-intersect right left))
            ((memq left '(Boolean Number))
             (apply type-union (map (lambda (arm) (type-intersect arm right)) (type-members left))))
            ((memq right '(Boolean Number)) (type-intersect right left))
            ((or (type-variable? left) (type-variable? right)
                 (intersection-type? left) (intersection-type? right))
             (type-intersection left right))
            (else 'Never)))

    ;; Internal conjunctions retain A membership when a predicate establishes a
    ;; concrete category. They are never surface types or runtime predicates.
    (define (intersection-parts type) (if (intersection-type? type) (cdr type) (list type)))
    (define (type-intersection left right)
      (let loop ((parts (append (intersection-parts left) (intersection-parts right))) (result '()))
        (cond ((null? parts) (if (null? (cdr result)) (car result) (cons 'I result)))
              ((some? (lambda (part)
                        (and (not (type-variable? (car parts))) (not (type-variable? part))
                             (eq? (type-intersect (car parts) part) 'Never))) result) 'Never)
              (else (loop (cdr parts) (insert-intersection (car parts) result))))))
    (define (insert-intersection type types)
      (cond ((null? types) (list type))
            ((type-subtype? (car types) type) types)
            ((type-subtype? type (car types)) (insert-intersection type (cdr types)))
            (else (cons (car types) (insert-intersection type (cdr types))))))

    ;; A difference must overapproximate. In particular Integer minus i32 cannot
    ;; be represented by this algebra, and remains Integer rather than Never.
    (define (type-subtract source excluded)
      (cond ((type-subtype? source excluded) 'Never)
            ((or (union-type? source) (memq source '(Boolean Number)))
             (apply type-union (map (lambda (arm) (type-subtract arm excluded)) (type-members source))))
            (else source)))

    (define (runtime-type? type)
      (or (memq type scalar-type-names) (nominal-type? type)
          (and (union-type? type) (all? runtime-type? (cdr type)))))

    (define (shallow-type? type)
      (or (runtime-type? type) (type-variable? type)
          (and (or (union-type? type) (intersection-type? type)) (all? shallow-type? (cdr type)))))

    ;; Substitution also normalizes unions: replacing A with Any or a union must
    ;; not leave an unsimplified alternative that changes equality or inference.
    (define (type-substitute type substitutions)
      (cond ((assq type substitutions) => cdr)
            ((union-type? type)
             (apply type-union (map (lambda (part) (type-substitute part substitutions)) (cdr type))))
            ((arrow-type? type)
             (cons '-> (map (lambda (part) (type-substitute part substitutions)) (cdr type))))
            (else type)))

    (define (type-erasure type)
      (cond ((type-variable? type) 'Any)
            ((all-type? type) (type-erasure (all-body type)))
            ((union-type? type) (apply type-union (map type-erasure (cdr type))))
            ((arrow-type? type) (cons '-> (map type-erasure (cdr type))))
            (else type)))

    ;; ---- Located diagnostics ----

    (define (type-datum type)
      (cond ((type-variable? type) (type-variable-name type))
            ((nominal-type? type) (ir:value-definition-name (cadr type)))
            ((pair? type) (map type-datum type))
            (else type)))

    (define (type-error-at loc message . details)
      (apply error (string-append
                    (if (loc? loc)
                        (string-append (loc-filename loc) ":" (number->string (loc-line loc))
                                       ":" (number->string (loc-column loc)) ": ") "")
                    message) (map type-datum details)))

    (define (literal-type value)
      (cond ((eq? value #f) 'False) ((eq? value #t) 'True) ((null? value) 'Null)
            ((exact-integer? value)
             (if (<= -2147483648 value 2147483647) 'i32 'ExactInteger))
            ((and (number? value) (not (real? value))) 'Complex) ((number? value) 'InexactReal)
            ((string? value) 'String) ((symbol? value) 'Symbol) ((char? value) 'Char)
            ((pair? value) 'Pair) ((vector? value) 'Vector) ((bytevector? value) 'Bytevector)
            (else 'Any))))

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-types)
    (import (snail-scheme test-utils))
    (begin
      ;; An independent finite membership model: each row is one inhabited
      ;; region and the static categories containing it, including both sides
      ;; of the i32 boundary and distinct, equal-shaped nominal records.
      (define test-regions
        '((False Boolean) (True Boolean) (Null) (i32 ExactInteger Number)
          (ExactInteger Number) (InexactReal Number) (Complex Number) (String) (Symbol) (Char)
          (Pair) (Vector) (Bytevector) (Procedure) (Unspecified)
          (Record (record first)) (Record (record second)) (Record)))
      (define test-algebra-types
        (append scalar-type-names
                '((U False True) (U ExactInteger InexactReal) (U i32 String)
                  (U String ExactInteger) (U False String) (U Record String)
                  (record first) (record second) (U (record first) String))))
      (define (test-member? region type)
        (cond ((memq type '(Any ?)) #t) ((eq? type 'Never) #f)
              ((union-type? type) (some? (lambda (arm) (test-member? region arm)) (cdr type)))
              (else (and (member type region) #t))))
      (define (test-algebra-pair left right)
        (let ((union (type-union left right)) (intersection (type-intersect left right))
              (difference (type-subtract left right)))
          (for-each
           (lambda (region)
             (let ((l (test-member? region left)) (r (test-member? region right)))
               (expect (test-member? region union) (or l r))
               (expect (test-member? region intersection) (and l r))
               (if (and l (not r)) (expect (test-member? region difference) #t))
               (if (and l (type-subtype? left right)) (expect r #t)))) test-regions)))

      ;; Quantified variables range over independent subsets of these witnesses.
      ;; This membership oracle does not use the compiler's type operations.
      (define (test-subsets items)
        (if (null? items) '(())
            (let ((tail (test-subsets (cdr items))))
              (append tail (map (lambda (subset) (cons (car items) subset)) tail)))))
      (define (test-abstract-member? region type variables)
        (cond ((assq type variables) => (lambda (entry) (and (memq region (cdr entry)) #t)))
              ((union-type? type)
               (some? (lambda (arm) (test-abstract-member? region arm variables)) (cdr type)))
              ((intersection-type? type)
               (all? (lambda (part) (test-abstract-member? region part variables)) (cdr type)))
              (else (test-member? region type))))
      (define (test-abstract-pair left right regions variables)
        (for-each
         (lambda (region)
           (let ((l (test-abstract-member? region left variables))
                 (r (test-abstract-member? region right variables)))
             (expect (test-abstract-member? region (type-union left right) variables) (or l r))
             (expect (test-abstract-member? region (type-intersect left right) variables) (and l r))
             (if (and l (not r))
                 (expect (test-abstract-member? region (type-subtract left right) variables) #t))
             (if (and l (type-subtype? left right)) (expect r #t)))) regions))
      (define (test-abstract-algebra a b)
        (let* ((regions '((False Boolean) (String) (ExactInteger Number)))
               (subsets (test-subsets regions))
               (types (list a b 'Any 'Never 'String 'False (type-intersect a 'String)
                            (type-union a 'False) (type-intersect a b)
                            (type-intersect (type-union a 'String) (type-union b 'False)))))
          (for-each (lambda (as)
                      (for-each (lambda (bs)
                                  (for-each (lambda (left)
                                              (for-each (lambda (right)
                                                          (test-abstract-pair left right regions (list (cons a as) (cons b bs))))
                                                        types)) types)) subsets)) subsets)))
      (define (test-types)
        (let ((a (make-type-variable 'A)) (b (make-type-variable 'A)))
          (expect (type-equal? a b) #f)
          (expect (type-subtype? (type-intersect a 'String) a) #t)
          (expect (type-subtype? (type-intersect a 'String) 'String) #t)
          (expect (type-intersect (type-intersect a 'String) 'ExactInteger) 'Never)
          (expect (type-equal? (list 'All (list a) (list '-> a a))
                               (list 'All (list b) (list '-> b b))) #t)
          (test-abstract-algebra a b))
        (let ((first (list 'record (ir:make-value-definition 'same-name #f)))
              (second (list 'record (ir:make-value-definition 'same-name #f))))
          (expect (type-equal? first second) #f)
          (expect (type-subtype? first second) #f)
          (expect (type-intersect first second) 'Never))
        (expect (type-equal? '(-> (U String i32) i32) '(-> (U i32 String) i32)) #t)
        (expect (type-subtype? '? 'String) #f)
        (expect (type-subtype? 'String '?) #f)
        (expect (type-union 'String '(U String ExactInteger)) '(U String ExactInteger))
        (expect (type-union '(U String (U String ExactInteger))) '(U String ExactInteger))
        (expect (type-intersect '(U String ExactInteger) 'String) 'String)
        (expect (type-subtract '(U String ExactInteger) 'String) 'ExactInteger)
        (expect (type-subtract 'ExactInteger 'i32) 'ExactInteger)
        (expect (type-intersect 'Number 'ExactInteger) 'ExactInteger)
        (expect (type-subtype? '(-> String String) 'Procedure) #t)
        (for-each (lambda (left)
                    (for-each (lambda (right) (test-algebra-pair left right)) test-algebra-types))
                  test-algebra-types))))))

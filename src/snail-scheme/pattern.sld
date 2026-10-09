;; Parse syntax-rules-style raw patterns into structured pattern objects, then
;; dispatch datum scrutinees against them. Matching constructs structured match
;; results; flattening turns successful results into capture alists for callbacks.
;; Dispatch returns the first callback value other than #f, or #f if none accepts.
;;
;; R7RS 4.3.2 raw pattern forms (P, Pi, and Pe denote nested patterns):
;;   _                         wildcard, unless declared a literal
;;   name                      pattern variable, unless literal or ellipsis
;;   literal                   symbol matched with eqv? through lookup
;;   (P1 … Pn)               proper list, including ()
;;   (P1 … Pn . Ptail)       dotted list; Ptail matches the remaining datum
;;   (P1 … Pk Pe <ellipsis> Pm+1 … Pn)
;;                             proper list with a repeated segment
;;   (P1 … Pk Pe <ellipsis> Pm+1 … Pn . Ptail)
;;                             repetition plus fixed suffix and dotted tail
;;   #(P1 … Pn)              vector
;;   #(P1 … Pk Pe <ellipsis> Pm+1 … Pn)
;;                             vector with a repeated segment
;;   constant                  datum matched with equal?
;; Repetitions may be empty or nested; one repeated segment per sequence.
;; The active ellipsis is a marker, not a standalone pattern unless literal.
;; Here … abbreviates a sequence; only <ellipsis> denotes the actual marker.
;; R7RS syntax-rules skips the leading macro keyword; this dispatcher matches
;; the whole input. The public API currently uses symbol identity for literals.
;; https://standards.scheme.org/corrected-r7rs/r7rs-Z-H-6.html#TAG:__tex2page_sec_4.3.2

(define-library (snail-scheme pattern)
  (export
   pattern-dispatch)

  (import
   (scheme base)
   (snail-scheme common))

  (begin

    ;; ---- Public API ----

    ;; Dispatch by symbol spelling. Match the head normally: use a literal head
    ;; for forms, or _ to ignore it. Callbacks receive a capture alist; #f declines
    ;; a branch. Return the first accepted callback value, or #f if none accepts.
    ;; Captures retain original datums; external records are opaque to matching.
    (define (pattern-dispatch ellipsis literals pattern-callback-pairs)
      (build-pattern-dispatcher
       ellipsis literals (lambda (x) x) pattern-callback-pairs))

    ;; ---- Dispatch ----

    (define (build-pattern-dispatcher ellipsis literals lookup pattern-callback-pairs)
      (assert (symbol? ellipsis))
      (assert (and (list? literals) (every? symbol? literals)))
      (assert (procedure? lookup))
      (let*-values (((raw-patterns callbacks) (unzip-pattern-callback-pairs pattern-callback-pairs))
                    ((patterns)
                     (map (lambda (raw-pattern) (parse-pattern ellipsis literals raw-pattern))
                          raw-patterns)))
        (for-each (lambda (pattern) (assert (distinct-pattern-variables? pattern))) patterns)
        (lambda (scrutinee)
          (dispatch-against-pattern-list lookup patterns callbacks scrutinee))))

    ;; The lists are aligned at construction. A callback returning #f declines
    ;; its branch; every other value, including (), stops the search.
    (define (dispatch-against-pattern-list lookup patterns callbacks scrutinee)
      (let loop ((patterns patterns)
		 (callbacks callbacks))
        (if (null? patterns)
            #f
            (let ((matched (match-pattern lookup (car patterns) scrutinee)))
              (or (and matched ((car callbacks) (flatten-match matched)))
                  (loop (cdr patterns) (cdr callbacks)))))))

    ;; Separate external pairs before parsing patterns or invoking callbacks.
    (define (unzip-pattern-callback-pairs pairs)
      (assert (list? pairs))
      (let loop ((pairs pairs)
		 (raw-patterns '())
		 (callbacks '()))
        (if (null? pairs)
            (values (reverse raw-patterns) (reverse callbacks))
            (let ((pair (car pairs)))
              (assert (pair? pair))
              (assert (procedure? (cdr pair)))
              (loop (cdr pairs) (cons (car pair) raw-patterns) (cons (cdr pair) callbacks))))))

    ;; ---- Pattern ----

    (define-record-type <discard-pattern>
      (make-discard-pattern)
      discard-pattern?)

    (define-record-type <singleton-pattern>
      (make-singleton-pattern name)
      singleton-pattern?
      (name singleton-pattern-name))

    (define-record-type <repeated-pattern>
      (make-repeated-pattern item variables)
      repeated-pattern?
      (item repeated-pattern-item)
      (variables repeated-pattern-variables))

    (define-record-type <literal-pattern>
      (make-literal-pattern name)
      literal-pattern?
      (name literal-pattern-name))

    (define-record-type <constant-pattern>
      (make-constant-pattern datum)
      constant-pattern?
      (datum constant-pattern-datum))

    (define-record-type <sequence-pattern>
      (make-sequence-pattern
       prefix-patterns
       opt-repeated-item-pattern ; #f if not provided
       suffix-patterns
       opt-improper-tail-pattern) ; #f if not provided
      sequence-pattern?
      (prefix-patterns sequence-pattern-prefix-patterns)
      (opt-repeated-item-pattern sequence-pattern-opt-repeated-item-pattern)
      (suffix-patterns sequence-pattern-suffix-patterns)
      (opt-improper-tail-pattern sequence-pattern-opt-improper-tail-pattern))

    (define-record-type <vector-pattern>
      (make-vector-pattern
       prefix-patterns
       opt-repeated-item-pattern ; #f if not provided
       suffix-patterns)
      vector-pattern?
      (prefix-patterns vector-pattern-prefix-patterns)
      (opt-repeated-item-pattern vector-pattern-opt-repeated-item-pattern)
      (suffix-patterns vector-pattern-suffix-patterns))

    (define-record-type <list-pattern>
      (make-list-pattern
       prefix-patterns
       opt-repeated-item-pattern ; #f if not provided
       suffix-patterns
       improper-tail)
      list-pattern?
      (prefix-patterns list-pattern-prefix-patterns)
      (opt-repeated-item-pattern list-pattern-opt-repeated-item-pattern)
      (suffix-patterns list-pattern-suffix-patterns)
      (improper-tail list-pattern-improper-tail))

    ;; Raw patterns are host datums. Every parsed pattern is a record, so #f
    ;; can represent absent repetition or tail without excluding the constant #f.
    (define (parse-pattern ellipsis literals raw-pattern)
      (cond
       ((symbol? raw-pattern)
        (cond
         ((raw-literal-pattern? literals raw-pattern) (make-literal-pattern raw-pattern))
         ((raw-ellipsis-pattern? ellipsis literals raw-pattern) (error "unexpected pattern ellipsis" raw-pattern))
         ((eq? raw-pattern '_) (make-discard-pattern))
         (else (make-singleton-pattern raw-pattern))))
       ((vector? raw-pattern) (parse-vector-pattern ellipsis literals raw-pattern))
       ((or (null? raw-pattern) (pair? raw-pattern)) (parse-list-pattern ellipsis literals raw-pattern))
       ((or (boolean? raw-pattern) (number? raw-pattern) (char? raw-pattern)
            (string? raw-pattern) (bytevector? raw-pattern)) (make-constant-pattern raw-pattern))
       (else (error "invalid raw pattern" raw-pattern))))

    (define (parse-vector-pattern ellipsis literals raw-pattern)
      (let ((sequence (parse-sequence-pattern ellipsis literals (vector->list raw-pattern))))
        (make-vector-pattern
         (sequence-pattern-prefix-patterns sequence)
         (sequence-pattern-opt-repeated-item-pattern sequence)
         (sequence-pattern-suffix-patterns sequence))))

    (define (parse-list-pattern ellipsis literals raw-pattern)
      (let ((sequence (parse-sequence-pattern ellipsis literals raw-pattern)))
        (make-list-pattern
         (sequence-pattern-prefix-patterns sequence)
         (sequence-pattern-opt-repeated-item-pattern sequence)
         (sequence-pattern-suffix-patterns sequence)
         (sequence-pattern-opt-improper-tail-pattern sequence))))

    ;; Parse first to last. Before ellipsis, elements belong to the prefix; its
    ;; preceding element becomes the repeated item, and all later elements form
    ;; the suffix. Nested sequences start their own state machine.
    (define (parse-sequence-pattern ellipsis literals raw-pattern)
      (let loop ((remaining-raw-pattern raw-pattern)
                 (state 'prefix)
                 (prefix-patterns '())
                 (opt-repeated-item-pattern #f)
                 (suffix-patterns '()))
        (assert (member state '(prefix repeated-item suffix)))
        (cond
         ((not (pair? remaining-raw-pattern))
          (make-sequence-pattern
           (reverse prefix-patterns)
           opt-repeated-item-pattern
           (reverse suffix-patterns)
           (and (not (null? remaining-raw-pattern))
                (parse-pattern ellipsis literals remaining-raw-pattern))))
         ((eq? state 'repeated-item)
          (let ((item (car prefix-patterns)))
            (loop (cdr remaining-raw-pattern) 'suffix (cdr prefix-patterns)
                  (make-repeated-pattern item (collect-pattern-variables item)) suffix-patterns)))
         ((eq? state 'prefix)
          (let ((item (parse-pattern ellipsis literals (car remaining-raw-pattern)))
                (rest-raw-pattern (cdr remaining-raw-pattern)))
            (loop rest-raw-pattern
                  (if (and (pair? rest-raw-pattern)
                           (raw-ellipsis-pattern? ellipsis literals (car rest-raw-pattern)))
                      'repeated-item 'prefix)
                  (cons item prefix-patterns) opt-repeated-item-pattern suffix-patterns)))
         (else
          ;; Parsing a standalone ellipsis also rejects a second repeated segment.
          (loop (cdr remaining-raw-pattern) 'suffix prefix-patterns opt-repeated-item-pattern
                (cons (parse-pattern ellipsis literals (car remaining-raw-pattern)) suffix-patterns))))))

    ;; Traverse the parsed capture structure, including names from empty repeats.
    (define (collect-pattern-variables pattern)
      (cond
       ((singleton-pattern? pattern) (list (singleton-pattern-name pattern)))
       ((repeated-pattern? pattern) (repeated-pattern-variables pattern))
       ((vector-pattern? pattern)
        (append (collect-pattern-element-variables (vector-pattern-prefix-patterns pattern))
                (collect-pattern-variables (vector-pattern-opt-repeated-item-pattern pattern))
                (collect-pattern-element-variables (vector-pattern-suffix-patterns pattern))))
       ((list-pattern? pattern)
        (append (collect-pattern-element-variables (list-pattern-prefix-patterns pattern))
                (collect-pattern-variables (list-pattern-opt-repeated-item-pattern pattern))
                (collect-pattern-element-variables (list-pattern-suffix-patterns pattern))
                (collect-pattern-variables (list-pattern-improper-tail pattern))))
       (else '())))

    (define (collect-pattern-element-variables patterns)
      (apply append (map collect-pattern-variables patterns)))

    (define (distinct-pattern-variables? pattern)
      (let loop ((names (collect-pattern-variables pattern)))
        (or (null? names)
            (and (not (memq (car names) (cdr names)))
                 (loop (cdr names))))))

    ;; The active ellipsis token is a marker, not a complete pattern by itself.
    (define (raw-ellipsis-pattern? ellipsis literals raw-pattern)
      (and (eq? raw-pattern ellipsis)
           (not (raw-literal-pattern? literals raw-pattern))))

    (define (raw-literal-pattern? literals raw-pattern)
      (and (memq raw-pattern literals) #t))

    ;; ---- Match ----

    ;; Successful matches retain structure; #f is reserved for failure.
    ;; Discard results also represent successful literals and constants, and
    ;; absent repetitions or tails. Singleton results retain original input datums.
    (define-record-type <discard-match>
      (make-discard-match)
      discard-match?)

    (define-record-type <singleton-match>
      (make-singleton-match name datum)
      singleton-match?
      (name singleton-match-name)
      (datum singleton-match-datum))

    (define-record-type <repeated-match>
      (make-repeated-match variables iterations)
      repeated-match?
      (variables repeated-match-variables)
      (iterations repeated-match-iterations))

    ;; Prefix and suffix are ordered lists of child match results. The repeated
    ;; item and improper tail are individual match results, including discard.
    (define-record-type <vector-match>
      (make-vector-match prefix repeated-item suffix)
      vector-match?
      (prefix vector-match-prefix)
      (repeated-item vector-match-repeated-item)
      (suffix vector-match-suffix))

    (define-record-type <list-match>
      (make-list-match prefix repeated-item suffix improper-tail)
      list-match?
      (prefix list-match-prefix)
      (repeated-item list-match-repeated-item)
      (suffix list-match-suffix)
      (improper-tail list-match-improper-tail))

    ;; Return #f on failure, or a structured match result on success.
    ;; Matching records input datums and repetition structure, never an alist.
    ;; Literals and constants constrain matching without producing captures.
    (define (match-pattern lookup pattern input)
      (cond
       ((discard-pattern? pattern) (make-discard-match))
       ((singleton-pattern? pattern) (make-singleton-match (singleton-pattern-name pattern) input))
       ((literal-pattern? pattern) (match-literal-pattern lookup pattern input))
       ((constant-pattern? pattern)
        (and (equal? (constant-pattern-datum pattern) input) (make-discard-match)))
       ((vector-pattern? pattern) (match-vector-pattern lookup pattern input))
       ((list-pattern? pattern) (match-list-pattern lookup pattern input))
       (else (error "unknown parsed pattern" pattern))))

    ;; Match the prefix, reserve and match the suffix, then repeat over the residue.
    ;; Record the parts without flattening their results into captures.
    (define (match-vector-pattern lookup pattern input)
      (and (vector? input)
           (let*-values (((item) (vector-pattern-opt-repeated-item-pattern pattern))
                         ((prefix-matches remaining)
                          (match-pattern-prefix lookup (vector-pattern-prefix-patterns pattern)
                                                (vector->list input)))
                         ((residue suffix-elements)
                          (if prefix-matches
                              (split-pattern-suffix (vector-pattern-suffix-patterns pattern) remaining)
                              (values #f #f)))
                         ((suffix-matches)
                          (and residue
                               (match-pattern-elements lookup (vector-pattern-suffix-patterns pattern) suffix-elements)))
                         ((repeated-match)
                          (and suffix-matches
                               (if item
                                   (match-repeated-pattern lookup item residue)
                                   (and (null? residue) (make-discard-match))))))
             (and repeated-match
                  (make-vector-match prefix-matches repeated-match suffix-matches)))))

    (define (match-list-pattern lookup pattern input)
      (and (or (pair? input) (null? input))
           (let*-values (((item) (list-pattern-opt-repeated-item-pattern pattern))
                         ((prefix-matches remaining)
                          (match-list-pattern-prefix lookup (list-pattern-prefix-patterns pattern) input))
                         ((elements tail)
                          (cond
                           ((not prefix-matches) (values #f #f))
                           (item (split-list-tail remaining))
                           ;; Without repetition, the tail matches the whole remainder.
                           (else (values '() remaining))))
                         ((residue suffix-elements)
                          (if elements
                              (split-pattern-suffix (list-pattern-suffix-patterns pattern) elements)
                              (values #f #f)))
                         ((suffix-matches)
                          (and residue
                               (match-pattern-elements lookup (list-pattern-suffix-patterns pattern) suffix-elements)))
                         ((tail-match)
                          (and suffix-matches
                               (match-list-pattern-tail lookup (list-pattern-improper-tail pattern) tail)))
                         ((repeated-match)
                          (and tail-match
                               (if item
                                   (match-repeated-pattern lookup item residue)
                                   (and (null? residue) (make-discard-match))))))
             (and repeated-match
                  (make-list-match prefix-matches repeated-match suffix-matches tail-match)))))

    ;; Consume a vector prefix from its list of elements.
    ;; Return child matches and remaining elements; #f matches indicate failure.
    (define (match-pattern-prefix lookup patterns elements)
      (let loop ((patterns patterns) (elements elements) (matches '()))
        (cond
         ((null? patterns) (values (reverse matches) elements))
         ((null? elements) (values #f #f))
         (else
          (let ((matched (match-pattern lookup (car patterns) (car elements))))
            (if matched
                (loop (cdr patterns) (cdr elements) (cons matched matches))
                (values #f #f)))))))

    ;; Consume a list prefix, retaining the original cdr as the remainder.
    (define (match-list-pattern-prefix lookup patterns input)
      (let loop ((patterns patterns) (input input) (matches '()))
        (cond
         ((null? patterns) (values (reverse matches) input))
         ((not (pair? input)) (values #f #f))
         (else
          (let ((matched (match-pattern lookup (car patterns) (car input))))
            (if matched
                (loop (cdr patterns) (cdr input) (cons matched matches))
                (values #f #f)))))))

    (define (match-pattern-elements lookup patterns elements)
      (let-values (((matches remaining) (match-pattern-prefix lookup patterns elements)))
        (and matches (null? remaining) matches)))

    ;; With repetition, a dotted tail matches only the final cdr, never spare pairs.
    (define (match-list-pattern-tail lookup pattern input)
      (if pattern
          (match-pattern lookup pattern input)
          (and (null? input) (make-discard-match))))

    ;; The residue is already isolated; repetition has no suffix or tail handling.
    (define (match-repeated-pattern lookup pattern elements)
      (let loop ((elements elements) (iterations '()))
        (if (null? elements)
            (make-repeated-match (repeated-pattern-variables pattern) (reverse iterations))
            (let ((matched (match-pattern lookup (repeated-pattern-item pattern) (car elements))))
              (and matched (loop (cdr elements) (cons matched iterations)))))))

    (define (match-literal-pattern lookup pattern input)
      (and (eqv? (lookup (literal-pattern-name pattern))
                 (lookup input))
           (make-discard-match)))

    ;; Peel off one input element per suffix pattern, working from the end.
    ;; Return residue and suffix elements, or two #f values if too short.
    (define (split-pattern-suffix suffix elements)
      (let loop ((suffix suffix) (remaining (reverse elements)) (reserved '()))
        (cond
         ((null? suffix) (values (reverse remaining) reserved))
         ((null? remaining) (values #f #f))
         (else (loop (cdr suffix) (cdr remaining) (cons (car remaining) reserved))))))

    ;; Separate remaining list elements from the final cdr without inspecting it.
    (define (split-list-tail input)
      (let loop ((input input) (reversed-elements '()))
        (if (pair? input)
            (loop (cdr input) (cons (car input) reversed-elements))
            (values (reverse reversed-elements) input))))

    ;; ---- Flatten ----

    ;; Build the callback alist only after the whole pattern has matched successfully.
    ;; Sequence children stay in pattern order, regardless of matching order.
    (define (flatten-match matched)
      (cond
       ((discard-match? matched) '())
       ((singleton-match? matched)
        (list (cons (singleton-match-name matched) (singleton-match-datum matched))))
       ((repeated-match? matched) (flatten-repeated-match matched))
       ((vector-match? matched)
        (append (flatten-match-list (vector-match-prefix matched))
                (flatten-match (vector-match-repeated-item matched))
                (flatten-match-list (vector-match-suffix matched))))
       ((list-match? matched)
        (append (flatten-match-list (list-match-prefix matched))
                (flatten-match (list-match-repeated-item matched))
                (flatten-match-list (list-match-suffix matched))
                (flatten-match (list-match-improper-tail matched))))
       (else (error "unknown match result" matched))))

    (define (flatten-match-list matches)
      (apply append (map flatten-match matches)))

    ;; Add one list layer per repetition. Names survive even with no iterations,
    ;; and recursively flattened iterations retain empty and ragged inner repeats.
    (define (flatten-repeated-match matched)
      (let ((iterations (map flatten-match (repeated-match-iterations matched))))
        (map (lambda (name)
               (cons name (map (lambda (captures) (cdr (assq name captures))) iterations)))
             (repeated-match-variables matched))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-pattern)
    (import (snail-scheme test-utils) (scheme read))
    (begin
      (define (read-datum text)
        (read (open-input-string text)))

      ;; Exercise matching only through the public dispatcher.
      (define (dispatch-captures ellipsis literals pattern input)
        (let ((dispatch (pattern-dispatch ellipsis literals
                                          (list (cons pattern (lambda (captures) captures))))))
          (dispatch input)))

      (define (accepts-pattern? ellipsis literals pattern)
        (not (raises? (lambda ()
                        (pattern-dispatch ellipsis literals
                                          (list (cons pattern (lambda (captures) captures))))))))

      (define (check-match pattern text captures)
        (expect (dispatch-captures '... '() pattern (read-datum text))
                captures))

      (define (check-no-match pattern text)
        (expect (dispatch-captures '... '() pattern (read-datum text)) #f))

      (define (raises? thunk)
        (guard (ex ((error-object? ex) #t)) (thunk) #f))

      (define (test-pattern-parsing)
        (for-each
         (lambda (pattern) (expect (accepts-pattern? '... '() pattern) #t))
         (list '_ 'x #t #f 42 #\a "hello" #u8(0 255) '()
               '(x . y) '(head middle ... last . tail) '((x ...) ...)
               '#(x ... last) '(_ _)))
        (for-each
         (lambda (pattern) (expect (accepts-pattern? '... '() pattern) #f))
         (list '... '(... x) '(x ... ...) '(x ... y ...) '(x x)
               '(x . x) '(x (x ...)) '#(x x) '(x . ...) (lambda () #t)))
        (expect (accepts-pattern? '::: '() '(x :::)) #t)
        (expect (accepts-pattern? '::: '() '(... x)) #t)
        (expect (accepts-pattern? '... '(lit _) '(lit lit _ _)) #t)
        (expect (accepts-pattern? '... '(...) '(... ...)) #t)
        (expect (accepts-pattern? '_ '() '_) #f)
        (expect (accepts-pattern? '_ '() '(x _)) #t)
        (expect (raises? (lambda () (dispatch-captures '... '() '(x x) (read-datum "(1 2)")))) #t))

      (define (test-dispatch-arguments)
        (expect (raises? (lambda () (pattern-dispatch 1 '() '()))) #t)
        (expect (raises? (lambda () (pattern-dispatch '... '(1) '()))) #t)
        (expect (raises? (lambda () (pattern-dispatch '... 'not-a-list '()))) #t)
        (expect (raises? (lambda () (pattern-dispatch '... '() '() #f))) #t)
        (expect (raises? (lambda () (pattern-dispatch '... '() '() eq? eq?))) #t)
        (let ((dispatch (pattern-dispatch '::: '(keyword)
                                          (list (cons '(keyword x :::) (lambda (captures) captures))))))
          (expect (dispatch (read-datum "(keyword 1 2)"))
                  '((x . (1 2))))
          (expect (dispatch (read-datum "(alias 1 2)")) #f)
          (expect (dispatch (read-datum "(42 1 2)")) #f)))

      (define (test-dispatch-construction)
        (for-each
         (lambda (arms)
           (expect (raises? (lambda () (pattern-dispatch '... '() arms))) #t))
         (list 42 (cons (cons '_ (lambda (_) #t)) 'improper)
               (list 42) (list '()) (list '(x))
               (list (list 'x (lambda (_) #t)))
               (list (cons '_ 42))
               (list (cons '(x x) (lambda (_) #t)))
               (list (cons '_ (lambda (_) #t))
                     (cons '(x x) (lambda (_) #t)))))
        ;; Dispatch keeps parsed patterns and callbacks independently of external pairs.
        (let* ((pair (cons 'x (lambda (captures) captures)))
               (dispatch (pattern-dispatch '... '() (list pair))))
          (set-car! pair '(x x))
          (set-cdr! pair 42)
          (expect (dispatch (read-datum "1"))
                  '((x . 1)))))

      (define (test-capture-variables)
        (for-each
         (lambda (example)
           (expect (dispatch-captures '... '(literal) (car example) (read-datum (cdr example))) '()))
         (list (cons '() "()") (cons #f "#f") (cons 42 "42")
               (cons 'literal "literal") (cons '(literal literal) "(literal literal)")
               (cons '(_ ...) "(1 2)") (cons '#(literal ...) "#(literal literal)")
               (cons '(1 ...) "(1 1)")))
        (expect (map car (dispatch-captures '... '(literal) '(literal (x ...) #(y z) . rest)
                                            (read-datum "(literal (1 2) #(3 4) . 5)")))
                '(x y z rest))
        (expect (map car (dispatch-captures '... '() '((x ...) ...) (read-datum "()"))) '(x))
        (expect (accepts-pattern? '... '(literal) '(x x)) #f)
        (expect (accepts-pattern? '... '(literal) '(x #(x))) #f)
        (expect (accepts-pattern? '... '(literal) '(#(x ...) . x)) #f))

      (define (test-atomic-matches)
        (check-match '_ "(anything . here)" '())
        (check-match 'x "(a . b)" '((x . (a . b))))
        (check-match #f "#f" '())
        (check-match #t "#t" '())
        (check-match 42 "42" '())
        (check-match #\a "#\\a" '())
        (check-match "hello" "\"hello\"" '())
        (check-match #u8() "#u8()" '())
        (check-match #u8(0 255) "#u8(0 #xff)" '())
        (check-match 'x "#u8(1 2)" '((x . #u8(1 2))))
        (check-no-match #f "#t")
        (check-no-match 42 "43")
        (check-no-match "hello" "hello")
        (check-no-match #u8(1) "#u8(2)")
        (check-no-match #u8() "()")
        (expect (dispatch-captures '... '(define) '(define name value)
                                   (read-datum "(define answer 42)"))
                '((name . answer) (value . 42)))
        (expect (dispatch-captures '... '(define) '(define name value)
                                   (read-datum "(other answer 42)")) #f)
        (expect (dispatch-captures '... '(_) '_ (read-datum "x")) #f)
        (expect (dispatch-captures '... '(_) '_ (read-datum "_")) '()))

      (define (test-list-matches)
        (check-match '() "()" '())
        (check-match '(x y) "(1 2)" '((x . 1) (y . 2)))
        (check-match '(x (y z)) "(1 (2 3))" '((x . 1) (y . 2) (z . 3)))
        (check-match '(x . rest) "(1 2 3)" '((x . 1) (rest . (2 3))))
        (check-match '(x . rest) "(1 . 2)" '((x . 1) (rest . 2)))
        (check-match '(x . rest) "(1)" '((x . 1) (rest . ())))
        (check-match '(x y) "(1 . (2))" '((x . 1) (y . 2)))
        (check-match '(x y . rest) "(1 . (2 . 3))" '((x . 1) (y . 2) (rest . 3)))
        (check-match '(x . rest) "(1 . #(2))" '((x . 1) (rest . #(2))))
        (check-no-match '(x) "()")
        (check-no-match '(x) "(1 2)")
        (check-no-match '(x y) "(1 . 2)")
        (check-no-match '(x) "1")
        (check-no-match '() "#()"))

      (define (test-repeated-matches)
        (check-match '(x ...) "()" '((x . ())))
        (check-match '(x ...) "(1 2 3)" '((x . (1 2 3))))
        (check-match '(head middle ... last) "(1 2)" '((head . 1) (middle . ()) (last . 2)))
        (check-match '(head middle ... last) "(1 2 3 4)" '((head . 1) (middle . (2 3)) (last . 4)))
        (check-match '(x ... first last) "(1 2)" '((x . ()) (first . 1) (last . 2)))
        (check-match '(x ... first last) "(1 2 3 4)" '((x . (1 2)) (first . 3) (last . 4)))
        (check-match '(x ... first last . tail) "(1 . (2 . 3))"
                     '((x . ()) (first . 1) (last . 2) (tail . 3)))
        (check-match '((name value) ...) "((a 1) (b 2))" '((name . (a b)) (value . (1 2))))
        (check-match '((name value) ...) "()" '((name . ()) (value . ())))
        (check-match '((x ...) ...) "(() (a b) ())" '((x . (() (a b) ()))))
        (check-match '((x ...) ...) "()" '((x . ())))
        (check-match '(((x ...) ...) ...) "((() (a)) () ((b c)))" '((x . ((() (a)) () ((b c))))))
        (check-match '((name value ...) ...) "((a) (b 1 2))" '((name . (a b)) (value . (() (1 2)))))
        (check-match '(_ ...) "(1 2 3)" '())
        (check-match '(1 ... last) "(1 1 2)" '((last . 2)))
        (check-match '(x ... . tail) "(1 2)" '((x . (1 2)) (tail . ())))
        (check-match '(x ... . tail) "(1 . (2 . 3))" '((x . (1 2)) (tail . 3)))
        (check-match '(x ... . tail) "()" '((x . ()) (tail . ())))
        (check-match '(head x ... . tail) "(1 . 2)" '((head . 1) (x . ()) (tail . 2)))
        (check-match '(head x ... last . tail) "(1 2 3 . 4)"
                     '((head . 1) (x . (2)) (last . 3) (tail . 4)))
        (check-match '(head x ... first last . tail) "(1 . (2 3 . (4 5 . 6)))"
                     '((head . 1) (x . (2 3)) (first . 4) (last . 5) (tail . 6)))
        ;; The constant #f is distinct from an absent repeated item or tail pattern.
        (check-match '(#f ...) "()" '())
        (check-match '(#f ... last . #f) "(#f #f 3 . #f)" '((last . 3)))
        (check-no-match '(#f ... last . #f) "(#f 3)")
        (check-no-match '(head x ... last) "(1)")
        (check-no-match '(x ... first last) "(1)")
        (check-no-match '(x ...) "(1 . 2)")
        (check-no-match '((x y) ...) "((1 2) (3))")
        (check-no-match '(1 ... last) "(1 2 3)")
        (check-no-match '(x ... . _) "42")
        (check-no-match '(x ... . _) "#()")
        ;; A dotted tail cannot take an arbitrary proper suffix after repetition.
        (check-no-match '(x ... . 2) "(1 2)")
        (check-no-match '(1 ... . tail) "(1 2)")
        (expect (dispatch-captures '::: '() '(x ::: last) (read-datum "(1 2 3)"))
                '((x . (1 2)) (last . 3)))
        (expect (dispatch-captures '... '(...) '(x ... y) (read-datum "(1 ... 2)"))
                '((x . 1) (y . 2)))
        (expect (dispatch-captures '::: '() '(... x :::) (read-datum "(1 2 3)"))
                '((... . 1) (x . (2 3)))))

      (define (test-vector-matches)
        (check-match '#() "#()" '())
        (check-match '#(x y) "#(1 2)" '((x . 1) (y . 2)))
        (check-match '#(x ... last) "#(1 2 3)" '((x . (1 2)) (last . 3)))
        (check-match '#(head x ... first last) "#(1 2 3)"
                     '((head . 1) (x . ()) (first . 2) (last . 3)))
        (check-match '#(head #(x ...) ... first last) "#(1 #(2 3) #() 4 5)"
                     '((head . 1) (x . ((2 3) ())) (first . 4) (last . 5)))
        (check-match '#(x ...) "#()" '((x . ())))
        (check-match '#(#f ...) "#()" '())
        (check-match '#(#f ...) "#(#f #f)" '())
        (check-match '(#(x ...) ...) "(#() #(1 2))" '((x . (() (1 2)))))
        (check-no-match '#(x) "(1)")
        (check-no-match '#(head x ... first last) "#(1 2)")
        (check-no-match '#(x y) "#(1 2 3)")
        (check-no-match '#(1 ... last) "#(1 2 3)")
        (check-no-match '#(#f ...) "#(#f #t)")
        (check-no-match '(x) "#(1)")
        (check-no-match '#(x) "#u8(1)")
        (check-no-match #u8(1) "#(1)"))

      (define (test-flattened-captures)
        ;; Keep outer captures in pattern order while grouping multiple variables
        ;; across repeated vectors and retaining nested empty repetition layers.
        (check-match '(head #(tag (x ...) y) ... last . tail)
                     "(0 #(1 () 2) #(3 (4 5) 6) 7 . 8)"
                     '((head . 0) (tag . (1 3)) (x . (() (4 5)))
                       (y . (2 6)) (last . 7) (tail . 8)))
        (check-match '(head #(tag (x ...) y) ... last . tail)
                     "(0 7 . 8)"
                     '((head . 0) (tag . ()) (x . ()) (y . ()) (last . 7) (tail . 8)))
        (check-match '#((name x ... last) ...) "#((a 1) (b 2 3 4))"
                     '((name . (a b)) (x . (() (2 3))) (last . (1 4)))))

      ;; This test-owned record has no meaning to the pattern library.
      (define-record-type <opaque-value>
        (make-opaque-value payload)
        opaque-value?
        (payload opaque-value-payload))

      (define (test-capture-identity)
        (let* ((first (make-opaque-value 'first))
               (second (make-opaque-value 'second))
               (input (vector first second))
               (whole (dispatch-captures '... '() 'whole input))
               (captures (dispatch-captures '... '() '#(x ...) input)))
          (expect (eq? (cdr (assq 'whole whole)) input) #t)
          (expect (eq? (car (cdr (assq 'x captures))) first) #t)
          (expect (eq? (cadr (cdr (assq 'x captures))) second) #t)
          (expect (dispatch-captures '... '(first) 'first first) #f)
          (expect (dispatch-captures '... '() '_ first) '()))
        (let* ((input (list (list 'a) (vector 'b)))
               (captures (dispatch-captures '... '() '(x y) input))
               (repeated (dispatch-captures '... '() '(x ...) input))
               (tail (dispatch-captures '... '() '(x . tail) input)))
          (expect (map car captures) '(x y))
          (expect (eq? (cdr (assq 'x captures)) (car input)) #t)
          (expect (eq? (cdr (assq 'y captures)) (cadr input)) #t)
          (expect (eq? (car (cdr (assq 'x repeated))) (car input)) #t)
          (expect (eq? (cadr (cdr (assq 'x repeated))) (cadr input)) #t)
          (expect (eq? (cdr (assq 'tail tail)) (cdr input)) #t))
        (let* ((tail (make-opaque-value 'tail))
               (input (cons 'a tail))
               (captures (dispatch-captures '... '() '(x . tail) input))
               (repeated (dispatch-captures '... '() '(x ... . tail) input)))
          (expect (eq? (cdr (assq 'tail captures)) tail) #t)
          (expect (eq? (cdr (assq 'tail repeated)) tail) #t))
        (let* ((tail (vector 'c))
               (input (cons 'a (cons 'b tail)))
               (captures (dispatch-captures '... '() '(head x ... . tail) input)))
          (expect (map car captures) '(head x tail))
          (expect (cdr (assq 'x captures)) '(b))
          (expect (eq? (cdr (assq 'tail captures)) tail) #t))
        (expect (dispatch-captures '... '() 'x #f) '((x . #f)))
        (expect (dispatch-captures '... '() 'x '()) '((x . ())))
        (expect (dispatch-captures '... '() '(x ...) '()) '((x . ()))))

      (define (test-pattern-dispatch)
        (let* ((called '())
               (dispatch
                (pattern-dispatch '... '(define import)
                                  (list (cons '(import name) (lambda (_) (error "unmatched callback invoked")))
                                        (cons '(define name value)
                                              (lambda (captures)
                                                (expect captures '((name . x) (value . 1)))
                                                (set! called (cons 'declined called))
                                                #f))
                                        (cons '(define name value)
                                              (lambda (captures)
                                                (expect captures '((name . x) (value . 1)))
                                                (set! called (cons 'accepted called))
                                                'accepted))
                                        (cons '_ (lambda (_) (error "unexpected fallback"))))))
               (result (dispatch (read-datum "(define x 1)"))))
          (expect result 'accepted)
          (expect (reverse called) '(declined accepted)))
        (let* ((called '())
               (dispatch
                (pattern-dispatch '... '()
                                  (list (cons '_ (lambda (_)
                                                   (set! called (cons 'first called))
                                                   #f))
                                        (cons '(x) (lambda (_)
                                                     (set! called (cons 'second called))
                                                     #f))
                                        (cons '(2) (lambda (_) (error "unmatched callback invoked")))))))
          (expect (dispatch (read-datum "(1)")) #f)
          (expect (reverse called) '(first second)))
        ;; Scheme's other values are truthy, including the empty capture alist.
        (for-each
         (lambda (value)
           (let ((dispatch (pattern-dispatch '... '()
                                             (list (cons '_ (lambda (_) value))
                                                   (cons '_ (lambda (_) (error "unexpected fallback")))))))
             (expect (dispatch (read-datum "1")) value)))
         (list #t '() 0 ""))
        (let ((dispatch (pattern-dispatch '... '()
                                          (list (cons '(1 x) (lambda (_) 'wrong))
                                                (cons '(x y) (lambda (captures) captures))))))
          (expect (dispatch (read-datum "(2 3)"))
                  '((x . 2) (y . 3))))
        (let ((dispatch (pattern-dispatch '... '()
                                          (list (cons #f (lambda (captures)
                                                           (expect captures '())
                                                           '()))))))
          (expect (dispatch (read-datum "#f")) '())
          (expect (dispatch (read-datum "#t")) #f))
        (expect ((pattern-dispatch '... '() '()) (read-datum "x")) #f)
        (expect (raises? (lambda ()
                           ((pattern-dispatch '... '() (list (cons '_ (lambda (_) (error "callback failed")))
                                                             (cons '_ (lambda (_) #t))))
                            (read-datum "x")))) #t))

      (define (test-pattern)
        (run-test test-pattern-parsing)
        (run-test test-dispatch-arguments)
        (run-test test-dispatch-construction)
        (run-test test-capture-variables)
        (run-test test-atomic-matches)
        (run-test test-list-matches)
        (run-test test-repeated-matches)
        (run-test test-vector-matches)
        (run-test test-flattened-captures)
        (run-test test-capture-identity)
        (run-test test-pattern-dispatch))
      ))))

;; Parse syntax-rules-style raw patterns into structured pattern objects, then
;; dispatch syntax scrutinees against them. Matching constructs structured match
;; results; flattening turns successful results into capture alists for callbacks.
;; Dispatch returns the first callback value other than #f, or #f if none accepts.
;;
;; R7RS 4.3.2 raw pattern forms (P, Pi, and Pe denote nested patterns):
;;   _                         wildcard, unless declared a literal
;;   name                      pattern variable, unless literal or ellipsis
;;   literal                   identifier matched by binding identity
;;   (P1 … Pn)               proper list, including ()
;;   (P1 … Pn . Ptail)       dotted list; Ptail matches the remaining syntax
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

(define-library (snail-scheme syntax-pattern)
  (export
   syntax-dispatch)

  (import
   (scheme base)
   (snail-scheme common)
   (snail-scheme syntax))

  (begin
    ;;
    ;; Public API
    ;;

    ;; Dispatch by symbol spelling. Match the head normally: use a literal head
    ;; for forms, or _ to ignore it. Callbacks receive a capture alist; #f declines
    ;; a branch. Return the first accepted callback value, or #f if none accepts.
    (define (syntax-dispatch ellipsis literals pattern-callback-pairs)
      (build-syntax-dispatcher
       ellipsis literals (lambda (x) x) pattern-callback-pairs))

    ;;
    ;; Dispatch
    ;;

    ;; Check arguments once. Parsing needs ellipsis and literals; matching needs
    ;; lookup, which maps symbols to identities compared with eqv?.
    (define (build-syntax-dispatcher ellipsis literals lookup pattern-callback-pairs)
      (assert (symbol? ellipsis))
      (assert (and (list? literals) (every? symbol? literals)))
      (assert (procedure? lookup))
      (let*-values (((raw-patterns callbacks) (unzip-pattern-callback-pairs pattern-callback-pairs))
                    ((patterns)
                     (map (lambda (raw-pattern) (parse-pattern ellipsis literals raw-pattern))
                          raw-patterns)))
        (for-each (lambda (pattern) (assert (distinct-pattern-variables? pattern))) patterns)
        (lambda (scrutinee)
          (assert (syntax? scrutinee))
          (dispatch-syntax-against-pattern-list lookup patterns callbacks scrutinee))))

    ;; The lists are aligned at construction. A callback returning #f declines
    ;; its branch; every other value, including (), stops the search.
    (define (dispatch-syntax-against-pattern-list lookup patterns callbacks scrutinee)
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

    ;;
    ;; Pattern
    ;;

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

    ;;
    ;; Match
    ;;

    ;; Successful matches retain structure; #f is reserved for failure.
    ;; Discard results also represent successful literals and constants, and
    ;; absent repetitions or tails. Singleton results retain original input syntax.
    (define-record-type <discard-match>
      (make-discard-match)
      discard-match?)

    (define-record-type <singleton-match>
      (make-singleton-match name syntax)
      singleton-match?
      (name singleton-match-name)
      (syntax singleton-match-syntax))

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
    ;; Matching records syntax objects and repetition structure, never an alist.
    ;; Literals and constants constrain matching without producing captures.
    (define (match-pattern lookup pattern input)
      (cond
       ((discard-pattern? pattern) (make-discard-match))
       ((singleton-pattern? pattern) (make-singleton-match (singleton-pattern-name pattern) input))
       ((literal-pattern? pattern) (match-literal-pattern lookup pattern input))
       ((constant-pattern? pattern)
        (and (atom-syntax? input)
             (equal? (constant-pattern-datum pattern) (atom-syntax-value input)) (make-discard-match)))
       ((vector-pattern? pattern) (match-vector-pattern lookup pattern input))
       ((list-pattern? pattern) (match-list-pattern lookup pattern input))
       (else (error "unknown parsed pattern" pattern))))

    ;; Match the prefix, reserve and match the suffix, then repeat over the residue.
    ;; Record the parts without flattening their results into captures.
    (define (match-vector-pattern lookup pattern input)
      (and (vector-syntax? input)
           (let*-values (((item) (vector-pattern-opt-repeated-item-pattern pattern))
                         ((prefix-matches remaining)
                          (match-pattern-prefix lookup (vector-pattern-prefix-patterns pattern)
                                                (vector-syntax-elements input)))
                         ((residue suffix-elements)
                          (if prefix-matches
                              (split-syntax-suffix (vector-pattern-suffix-patterns pattern) remaining)
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
      (and (list-syntax? input)
           (let*-values (((item) (list-pattern-opt-repeated-item-pattern pattern))
                         ((prefix-matches remaining)
                          (match-list-pattern-prefix lookup (list-pattern-prefix-patterns pattern) input))
                         ((elements tail)
                          (cond
                           ((not prefix-matches) (values #f #f))
                           (item (split-list-syntax remaining))
                           ;; Without repetition, the tail matches the whole remainder.
                           (else (values '() remaining))))
                         ((residue suffix-elements)
                          (if elements
                              (split-syntax-suffix (list-pattern-suffix-patterns pattern) elements)
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

    ;; Consume a vector prefix directly from its list of child syntax objects.
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

    ;; Consume a list prefix, following explicit list tails such as (a . (b c)).
    ;; Construct a remaining list only when needed, retaining children and location.
    (define (match-list-pattern-prefix lookup patterns input)
      (let loop ((patterns patterns) (input input)
                 (elements (list-syntax-elements input)) (matches '()))
        (let ((tail (list-syntax-improper-tail input)))
          (cond
           ((null? patterns)
            (values (reverse matches)
                    (cond
                     ((eq? elements (list-syntax-elements input)) input)
                     ((and (null? elements) (syntax? tail)) tail)
                     (else (make-list-syntax elements tail (syntax-loc input))))))
           ((pair? elements)
            (let ((matched (match-pattern lookup (car patterns) (car elements))))
              (if matched
                  (loop (cdr patterns) input (cdr elements) (cons matched matches))
                  (values #f #f))))
           ((list-syntax? tail)
            (loop patterns tail (list-syntax-elements tail) matches))
           (else (values #f #f))))))

    (define (match-pattern-elements lookup patterns elements)
      (let-values (((matches remaining) (match-pattern-prefix lookup patterns elements)))
        (and matches (null? remaining) matches)))

    ;; With repetition, a dotted tail matches only the final cdr, never spare pairs.
    (define (match-list-pattern-tail lookup pattern input)
      (if pattern
          (match-pattern lookup pattern input)
          (and (list-syntax? input)
               (null? (list-syntax-elements input))
               (null? (list-syntax-improper-tail input)) (make-discard-match))))

    ;; The residue is already isolated; repetition has no suffix or tail handling.
    (define (match-repeated-pattern lookup pattern elements)
      (let loop ((elements elements) (iterations '()))
        (if (null? elements)
            (make-repeated-match (repeated-pattern-variables pattern) (reverse iterations))
            (let ((matched (match-pattern lookup (repeated-pattern-item pattern) (car elements))))
              (and matched (loop (cdr elements) (cons matched iterations)))))))

    (define (match-literal-pattern lookup pattern input)
      (and (syntax-identifier? input)
           (eqv? (lookup (literal-pattern-name pattern))
                 (lookup (atom-syntax-value input)))
           (make-discard-match)))

    ;; Peel off one input element per suffix pattern, working from the end.
    ;; Return residue and suffix elements, or two #f values if too short.
    (define (split-syntax-suffix suffix elements)
      (let loop ((suffix suffix) (remaining (reverse elements)) (reserved '()))
        (cond
         ((null? suffix) (values (reverse remaining) reserved))
         ((null? remaining) (values #f #f))
         (else (loop (cdr suffix) (cdr remaining) (cons (car remaining) reserved))))))

    ;; Separate all remaining list elements from the final cdr. Explicit list
    ;; tails extend the elements; atom and vector tails remain syntax objects.
    (define (split-list-syntax input)
      (let loop ((input input) (reversed-elements '()))
        (if (list-syntax? input)
            (let* ((elements (list-syntax-elements input))
                   (tail (list-syntax-improper-tail input))
                   (collected (append (reverse elements) reversed-elements)))
              (if (syntax? tail)
                  (loop tail collected)
                  (values (reverse collected)
                          (if (null? elements) input
                              (make-list-syntax '() '() (syntax-loc input))))))
            (values (reverse reversed-elements) input))))

    ;;
    ;; Flatten
    ;;

    ;; Build the callback alist only after the whole pattern has matched successfully.
    ;; Sequence children stay in pattern order, regardless of matching order.
    (define (flatten-match matched)
      (cond
       ((discard-match? matched) '())
       ((singleton-match? matched)
        (list (cons (singleton-match-name matched) (singleton-match-syntax matched))))
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

    ))

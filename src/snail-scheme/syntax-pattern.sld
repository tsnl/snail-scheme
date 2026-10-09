(define-library (snail-scheme syntax-pattern)
  (export
   <syntax-pattern-context>
   make-syntax-pattern-context
   syntax-pattern-context?
   syntax-pattern-context-ellipsis
   syntax-pattern-context-literals
   syntax-pattern-context-literal=?
   pattern?
   pattern-variables
   syntax-pattern
   match-syntax-pattern-arm
   <match-result>
   make-match-result
   match-result?
   match-result-success?
   match-result-groups
   <match-group>
   make-match-group
   match-group?
   match-group-singleton?
   match-group-name
   match-group-data
   <syntax-pattern-dispatch-result>
   make-syntax-pattern-dispatch-result
   syntax-pattern-dispatch-result?
   syntax-pattern-dispatch-result-success?
   syntax-pattern-dispatch-result-returned)

  (import
   (scheme base)
   (snail-scheme common)
   (snail-scheme syntax))

  (begin
    (define-record-type <syntax-pattern-context>
      (new-syntax-pattern-context ellipsis literals literal=?)
      syntax-pattern-context?
      (ellipsis syntax-pattern-context-ellipsis)
      (literals syntax-pattern-context-literals)
      (literal=? syntax-pattern-context-literal=?))

    ;; Configuration and optional-argument handling stay outside the validator.
    (define (make-syntax-pattern-context ellipsis literals . comparison)
      (assert (symbol? ellipsis))
      (assert (and (list? literals) (every? symbol? literals)))
      (new-syntax-pattern-context ellipsis literals (pattern-literal-comparison comparison)))

    (define (pattern-literal-comparison comparison)
      (assert (<= (length comparison) 1))
      (let ((literal=? (if (null? comparison) literal-symbol=? (car comparison))))
        (assert (procedure? literal=?))
        literal=?))

    (define-record-type <match-result>
      (make-match-result
       success?     ; boolean indicating whether the match succeeded
       groups)      ; list of match group objects, always `null` if not `success?`.
      match-result?
      (success? match-result-success?)
      (groups match-result-groups))

    (define-record-type <match-group>
      (make-match-group
       singleton?   ; boolean indicating whether the match is a singleton or an ellipsis match.
       name         ; the name of the pattern variable used to match this group
       data)        ; syntax if singleton; otherwise lists nested once per ellipsis
      match-group?
      (singleton? match-group-singleton?)
      (name match-group-name)
      (data match-group-data))

    (define-record-type <syntax-pattern-dispatch-result>
      (make-syntax-pattern-dispatch-result
       success?     ; boolean indicating whether the dispatch was successful on any of the patterns provided
       returned)    ; the callback return value if success?, otherwise null
      syntax-pattern-dispatch-result?
      (success? syntax-pattern-dispatch-result-success?)
      (returned syntax-pattern-dispatch-result-returned))

    ;; Patterns are host datums; inputs and captures are located syntax objects.
    ;; Validity is independent of whether a pattern captures any variables.
    (define (pattern? context pattern)
      (assert (syntax-pattern-context? context))
      (and (pattern-shape? context pattern)
           (distinct-pattern-variables? (pattern-variables context pattern))))

    (define (pattern-shape? context pattern)
      (or (literal-pattern? context pattern)
          (wildcard-pattern? context pattern)
          (pattern-variable? context pattern)
          (constant-pattern? pattern)
          (list-pattern? context pattern)
          (vector-pattern? context pattern)))

    (define (literal-pattern? context pattern)
      (and (symbol? pattern)
           (memq pattern (syntax-pattern-context-literals context)) #t))

    (define (wildcard-pattern? context pattern)
      (and (eq? pattern '_) (not (literal-pattern? context pattern))
           (not (ellipsis-pattern? context pattern))))

    ;; The active ellipsis token is a marker, not a complete pattern by itself.
    (define (ellipsis-pattern? context pattern)
      (and (eq? pattern (syntax-pattern-context-ellipsis context))
           (not (literal-pattern? context pattern))))

    (define (pattern-variable? context pattern)
      (and (symbol? pattern)
           (not (literal-pattern? context pattern))
           (not (wildcard-pattern? context pattern))
           (not (ellipsis-pattern? context pattern))))

    (define (constant-pattern? pattern)
      (or (boolean? pattern) (number? pattern) (char? pattern)
          (string? pattern) (bytevector? pattern)))

    (define (repeated-pattern? context pattern)
      (and (pair? pattern) (pair? (cdr pattern))
           (ellipsis-pattern? context (cadr pattern))))

    (define (list-pattern? context pattern)
      (and (or (null? pattern) (pair? pattern))
           (pattern-sequence? context pattern #f)))

    (define (vector-pattern? context pattern)
      (and (vector? pattern) (list-pattern? context (vector->list pattern))))

    ;; At most one repetition per sequence; nested sequences start afresh.
    (define (pattern-sequence? context pattern repeated?)
      (cond
       ((null? pattern) #t)
       ((not (pair? pattern)) (pattern-shape? context pattern))
       ((repeated-pattern? context pattern)
        (and (not repeated?)
             (pattern-shape? context (car pattern))
             (pattern-sequence? context (cddr pattern) #t)))
       (else
        (and (pattern-shape? context (car pattern))
             (pattern-sequence? context (cdr pattern) repeated?)))))

    ;; Always a list of variable occurrences in traversal order, including
    ;; duplicates. No captures means '(); this function does not validate.
    (define (pattern-variables context pattern)
      (cond
       ((pattern-variable? context pattern) (list pattern))
       ((pair? pattern)
        (append (pattern-variables context (car pattern))
                (pattern-variables context (cdr pattern))))
       ((vector? pattern) (pattern-variables context (vector->list pattern)))
       (else '())))

    (define (distinct-pattern-variables? names)
      (or (null? names)
          (and (not (memq (car names) (cdr names)))
               (distinct-pattern-variables? (cdr names)))))

    ;; Validate arms when constructing the dispatcher. The first matching arm
    ;; receives one match-result; even a callback returning #f is successful.
    ;; Match the head normally: use a literal head for forms, or _ to ignore it.
    (define (syntax-pattern context pattern-callback-pairs)
      (assert (syntax-pattern-context? context))
      (assert (list? pattern-callback-pairs))
      (for-each
       (lambda (arm)
         (assert (and (pair? arm) (procedure? (cdr arm))))
         (assert (pattern? context (car arm))))
       pattern-callback-pairs)
      (lambda (scrutinee)
        (assert (syntax? scrutinee))
        (dispatch-syntax-pattern context pattern-callback-pairs scrutinee)))

    (define (dispatch-syntax-pattern context arms scrutinee)
      (if (null? arms)
          (make-syntax-pattern-dispatch-result #f '())
          (let ((result (try-dispatch-syntax-pattern-arm
                         context (caar arms) (cdar arms) scrutinee)))
            (if (syntax-pattern-dispatch-result-success? result)
                result
                (dispatch-syntax-pattern context (cdr arms) scrutinee)))))

    (define (try-dispatch-syntax-pattern-arm context pattern callback scrutinee)
      (let ((result (match-syntax-pattern context pattern scrutinee)))
        (if (match-result-success? result)
            (make-syntax-pattern-dispatch-result #t (callback result))
            (make-syntax-pattern-dispatch-result #f '()))))

    (define (match-syntax-pattern-arm context pattern scrutinee)
      (assert (syntax-pattern-context? context))
      (assert (pattern? context pattern))
      (assert (syntax? scrutinee))
      (match-syntax-pattern context pattern scrutinee))

    (define (literal-symbol=? name input)
      (eq? name (atom-syntax-value input)))

    ;; View unprefixed syntax lists as pairs, including explicit dotted lists
    ;; such as (a . (b c)). Synthesized cdrs retain the containing list's location.
    (define (syntax-pair? stx)
      (and (list-syntax? stx) (null? (list-syntax-prefix stx))
           (pair? (list-syntax-elements stx))))

    (define (syntax-null? stx)
      (and (list-syntax? stx) (null? (list-syntax-prefix stx))
           (null? (list-syntax-elements stx)) (null? (list-syntax-improper-tail stx))))

    (define (syntax-car stx)
      (car (list-syntax-elements stx)))

    (define (syntax-cdr stx)
      (let ((rest (cdr (list-syntax-elements stx)))
            (tail (list-syntax-improper-tail stx)))
        (if (and (null? rest) (syntax? tail))
            tail
            (make-list-syntax rest tail (syntax-loc stx) '()))))

    (define (syntax-pair-count stx)
      (let loop ((stx stx) (count 0))
        (if (syntax-pair? stx)
            (loop (syntax-cdr stx) (+ count 1))
            count)))

    (define (pattern-pair-count pattern)
      (if (pair? pattern) (+ 1 (pattern-pair-count (cdr pattern))) 0))

    (define (match-syntax-pattern context pattern scrutinee)
      (let ((groups (match-pattern-groups context pattern scrutinee)))
        (make-match-result (if groups #t #f) (or groups '()))))

    ;; Internal matches return groups on success (possibly empty), or #f.
    (define (match-pattern-groups context pattern input)
      (cond
       ((symbol? pattern) (match-symbol-pattern context pattern input))
       ((null? pattern) (and (syntax-null? input) '()))
       ((pair? pattern)
        (and (or (syntax-pair? input) (syntax-null? input))
             (match-sequence-pattern context pattern input)))
       ((vector? pattern) (match-vector-pattern context pattern input))
       (else (and (atom-syntax? input) (equal? pattern (atom-syntax-value input)) '()))))

    (define (match-symbol-pattern context pattern input)
      (cond
       ((literal-pattern? context pattern)
        (and (syntax-identifier? input)
             ((syntax-pattern-context-literal=? context) pattern input) '()))
       ((eq? pattern '_) '())
       (else (list (make-match-group #t pattern input)))))

    (define (match-sequence-pattern context pattern input)
      (cond
       ((not (pair? pattern)) (match-pattern-groups context pattern input))
       ((repeated-pattern? context pattern)
        (match-repeated-pattern context (car pattern) (cddr pattern) input))
       (else
        (and (syntax-pair? input)
             (combine-match-groups
              (match-pattern-groups context (car pattern) (syntax-car input))
              (match-sequence-pattern context (cdr pattern) (syntax-cdr input)))))))

    (define (match-repeated-pattern context item suffix input)
      (let ((count (- (syntax-pair-count input) (pattern-pair-count suffix)))
            (names (pattern-variables context item)))
        (and (>= count 0)
             (let loop ((remaining count) (input input) (iterations '()))
               (if (= remaining 0)
                   (combine-match-groups
                    (collect-repeated-match-groups names (reverse iterations))
                    (match-pattern-groups context suffix input))
                   (let ((groups (match-pattern-groups context item (syntax-car input))))
                     (and groups
                          (loop (- remaining 1) (syntax-cdr input) (cons groups iterations)))))))))

    (define (match-vector-pattern context pattern input)
      (and (list-syntax? input) (equal? (list-syntax-prefix input) "#")
           (null? (list-syntax-improper-tail input))
           (match-pattern-groups
            context (vector->list pattern)
            (make-list-syntax (list-syntax-elements input) '() (syntax-loc input) '()))))

    (define (combine-match-groups left right)
      (and left right (append left right)))

    ;; Each repetition adds a list layer, preserving empty and ragged groups.
    (define (collect-repeated-match-groups names iterations)
      (if (null? names)
          '()
          (cons
           (make-match-group #f (car names)
                             (map (lambda (groups) (match-group-data (car groups))) iterations))
           (collect-repeated-match-groups (cdr names) (map cdr iterations)))))
    ))

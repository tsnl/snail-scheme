;; Optional representation specialization for closed monomorphic i32 functions.
;; Public Scheme values and closure adapters remain eqref. This bounded emitter
;; accepts only pure integer expressions and self recursion; everything else
;; stays on the ordinary backend. i32 is a checked range, never wrapping Scheme
;; arithmetic. Intermediate arithmetic is widened to i64 and proved not to
;; overflow; results and call arguments retain any unproved i32 range checks.
(define-library (snail-scheme wasm-i32)
  (export i32-specialization-enabled specialize-i32)
  (import (scheme base) (scheme cxr) (snail-scheme types) (snail-scheme type-analysis)
          (prefix (snail-scheme ir) ir:))
  (begin
    ;; ---- Candidate and emitted value ----

    (define i32-specialization-enabled (make-parameter #t))
    (define i32-range (cons -2147483648 2147483647))
    (define i64-range (cons -9223372036854775808 9223372036854775807))
    (define-record-type <context>
      (make-context binding label primitives parameters locals)
      context?
      (binding context-binding) (label context-label) (primitives context-primitives)
      (parameters context-parameters) (locals context-locals set-context-locals!))
    (define-record-type <value>
      (make-value code range)
      value?
      (code value-code) (range value-range))

    (define (fresh-local! context)
      (let ((name (string->symbol (string-append "$wide" (number->string (length (context-locals context)))))))
        (set-context-locals! context (cons name (context-locals context))) name))
    (define (in-range? actual required)
      (and (<= (car required) (car actual)) (<= (cdr actual) (cdr required))))
    (define (all? predicate items)
      (or (null? items) (and (predicate (car items)) (all? predicate (cdr items)))))

    (define (specialize-i32 procedure index binding primitives signature)
      (and (type-optimizations-enabled) (i32-specialization-enabled) (arrow-type? signature) binding
           (all? (lambda (type) (eq? type 'i32)) (cdr signature))
           (let* ((parameters (parameter-names (ir:lambda-parameters procedure)))
                  (context (make-context binding (string->symbol (string-append "$i32_" (number->string index)))
                                         primitives parameters '()))
                  (ranges (map (lambda (entry) (cons (car entry) i32-range)) parameters))
                  (body (lower-return (ir:lambda-body procedure) ranges context)))
             (and body (function-definition context body)))))

    (define (parameter-names parameters)
      (let loop ((parameters parameters) (index 0))
        (if (null? parameters) '()
            (cons (cons (car parameters) (string->symbol (string-append "$n" (number->string index))))
                  (loop (cdr parameters) (+ index 1))))))
    (define (function-definition context body)
      `(func ,(context-label context)
             ,@(map (lambda (entry) `(param ,(cdr entry) i32)) (context-parameters context))
             (result i32)
             ,@(map (lambda (name) `(local ,name i64)) (reverse (context-locals context)))
             (loop $self (result i32) ,body)))

    ;; ---- Ranges and checked narrowing ----

    (define (checked-narrow value context)
      (if (in-range? (value-range value) i32-range) `(i32.wrap_i64 ,(value-code value))
          (let ((name (fresh-local! context)))
            `(block (result i32) (local.set ,name ,(value-code value))
                    (if (i64.gt_u (i64.add (local.get ,name) (i64.const 2147483648))
                                  (i64.const 4294967295)) (then (call $fail (i32.const 8))))
                    (i32.wrap_i64 (local.get ,name))))))

    ;; The native compiler host also has checked i64 arithmetic. Prove each
    ;; endpoint safe before computing it; #f declines the whole specialization.
    ;; Sign tests keep the thresholds in range and avoid MIN / -1 entirely.
    (define (add-bound left right)
      (and (not (or (and (> right 0) (> left (- (cdr i64-range) right)))
                    (and (< right 0) (< left (- (car i64-range) right)))))
           (+ left right)))

    (define (subtract-bound left right)
      (and (not (or (and (> right 0) (< left (+ (car i64-range) right)))
                    (and (< right 0) (> left (+ (cdr i64-range) right)))))
           (- left right)))

    (define (multiply-bound left right)
      (cond ((or (= left 0) (= right 0)) 0)
            ((and (> left 0) (> right 0) (> left (quotient (cdr i64-range) right))) #f)
            ((and (> left 0) (< right 0) (< right (quotient (car i64-range) left))) #f)
            ((and (< left 0) (> right 0) (< left (quotient (car i64-range) right))) #f)
            ((and (< left 0) (< right 0) (< left (quotient (cdr i64-range) right))) #f)
            (else (* left right))))

    (define (lesser-bound left right) (if (< left right) left right))
    (define (greater-bound left right) (if (> left right) left right))

    ;; A nonempty list contains exact i64 endpoints or failed scalar proofs.
    ;; Initialize from its first endpoint so zero and negative ranges stay exact.
    (define (integer-bounds endpoints)
      (and (all? exact-integer? endpoints)
           (let loop ((rest (cdr endpoints)) (low (car endpoints)) (high (car endpoints)))
             (if (null? rest) (cons low high)
                 (loop (cdr rest) (lesser-bound low (car rest)) (greater-bound high (car rest)))))))

    (define (arithmetic-range operation left right)
      (case operation
        ((+) (integer-bounds (list (add-bound (car left) (car right))
                                   (add-bound (cdr left) (cdr right)))))
        ((-) (integer-bounds (list (subtract-bound (car left) (cdr right))
                                   (subtract-bound (cdr left) (car right)))))
        ((*) (integer-bounds (list (multiply-bound (car left) (car right))
                                   (multiply-bound (car left) (cdr right))
                                   (multiply-bound (cdr left) (car right))
                                   (multiply-bound (cdr left) (cdr right)))))))

    (define (branch-ranges test ranges truth? context)
      (let* ((arguments (ir:application-operands test)) (left (car arguments)) (right (cadr arguments))
             (entry (and (ir:name? left) (assq (ir:name-definition left) ranges))))
        (if (and entry (ir:literal? right) (exact-integer? (ir:literal-value right)))
            (let ((refined (refine-range (cdr entry) (operator test context)
                                         (ir:literal-value right) truth?)))
              ;; Keep ordinary, ordered intervals even on unreachable paths.
              ;; Losing that dead-path precision may cause a safe fallback.
              (if (<= (car refined) (cdr refined))
                  (cons (cons (car entry) refined) ranges) ranges))
            ranges)))

    (define (refine-range range operation constant truth?)
      (let ((low (car range)) (high (cdr range)))
        (case operation
          ((<) (if truth? (cons low (lesser-bound high (- constant 1))) (cons (greater-bound low constant) high)))
          ((<=) (if truth? (cons low (lesser-bound high constant)) (cons (greater-bound low (+ constant 1)) high)))
          ((>) (refine-range range '<= constant (not truth?)))
          ((>=) (refine-range range '< constant (not truth?)))
          ((=) (if truth? (cons (greater-bound low constant) (lesser-bound high constant)) range))
          (else range))))

    ;; ---- Pure expression subset ----

    (define (operator node context)
      (let ((name (and (ir:application? node) (ir:application-operator node))))
        (and (ir:name? name)
             (let ((definition (ir:name-definition name)))
               (cond ((eq? definition (context-binding context)) 'self)
                     ((memq definition (context-primitives context)) (ir:value-definition-name definition))
                     (else #f))))))

    (define (only-expression block)
      (let ((items (ir:block-items block))) (and (= (length items) 1) (car items))))

    (define (lower-number node ranges context)
      (cond ((and (ir:literal? node) (exact-integer? (ir:literal-value node)))
             (let ((number (ir:literal-value node)))
               (and (<= -2147483648 number 2147483647)
                    (make-value `(i64.const ,number) (cons number number)))))
            ((ir:name? node)
             (let ((parameter (assq (ir:name-definition node) (context-parameters context))))
               (and parameter (make-value `(i64.extend_i32_s (local.get ,(cdr parameter)))
                                          (cdr (assq (car parameter) ranges))))))
            ((ir:block? node) (and (only-expression node) (lower-number (only-expression node) ranges context)))
            ((eq? (operator node context) 'self)
             (let ((call (lower-self-call node ranges context #f)))
               (and call (make-value `(i64.extend_i32_s ,call) i32-range))))
            ((memq (operator node context) '(+ - *)) (lower-arithmetic node ranges context))
            (else #f)))

    (define (lower-arithmetic node ranges context)
      (let ((arguments (ir:application-operands node)))
        (and (= (length arguments) 2)
             (let ((left (lower-number (car arguments) ranges context))
                   (right (lower-number (cadr arguments) ranges context)))
               (and left right (bounded-arithmetic (operator node context) left right))))))

    (define (bounded-arithmetic operation left right)
      (let ((range (arithmetic-range operation (value-range left) (value-range right))))
        (and range
             (make-value `(,(case operation ((+) 'i64.add) ((-) 'i64.sub) ((*) 'i64.mul))
                           ,(value-code left) ,(value-code right)) range))))

    (define (lower-test node ranges context)
      (and (memq (operator node context) '(= < <= > >=))
           (= (length (ir:application-operands node)) 2)
           (let ((left (lower-number (car (ir:application-operands node)) ranges context))
                 (right (lower-number (cadr (ir:application-operands node)) ranges context)))
             (and left right
                  (comparison-code (operator node context) left right)))))

    ;; Compare at i32 width only when both computed values fit. Their arithmetic
    ;; still evaluates at its original width before either lossless narrowing.
    (define (comparison-code operation left right)
      (let ((narrow? (and (in-range? (value-range left) i32-range)
                          (in-range? (value-range right) i32-range)))
            (suffix (case operation ((=) "eq") ((<) "lt_s") ((<=) "le_s") ((>) "gt_s") ((>=) "ge_s"))))
        `(,(string->symbol (string-append (if narrow? "i32." "i64.") suffix))
          ,(if narrow? `(i32.wrap_i64 ,(value-code left)) (value-code left))
          ,(if narrow? `(i32.wrap_i64 ,(value-code right)) (value-code right)))))

    ;; ---- Returns and recursive calls ----

    (define (lower-return node ranges context)
      (cond ((ir:block? node) (and (only-expression node) (lower-return (only-expression node) ranges context)))
            ((ir:conditional? node) (lower-conditional node ranges context))
            ((eq? (operator node context) 'self) (lower-self-call node ranges context #t))
            (else (let ((value (lower-number node ranges context)))
                    (and value (checked-narrow value context))))))

    (define (lower-conditional node ranges context)
      (let* ((test (ir:conditional-test node)) (condition (lower-test test ranges context)))
        (and condition (ir:conditional-opt-alternate node)
             (let ((yes (lower-return (ir:conditional-consequent node) (branch-ranges test ranges #t context) context))
                   (no (lower-return (ir:conditional-opt-alternate node) (branch-ranges test ranges #f context) context)))
               (and yes no `(if (result i32) ,condition (then ,yes) (else ,no)))))))

    (define (lower-self-call node ranges context tail?)
      (let ((arguments (map (lambda (node) (lower-number node ranges context)) (ir:application-operands node))))
        (and (= (length arguments) (length (context-parameters context))) (all? value? arguments)
             (cond (tail? (tail-self-call arguments context))
                   ((all? (lambda (value) (in-range? (value-range value) i32-range)) arguments)
                    `(call ,(context-label context)
                           ,@(map (lambda (value) (checked-narrow value context)) arguments)))
                   (else (guarded-self-call arguments context))))))

    ;; Evaluate every operand before performing any callee-entry range check.
    ;; The only operator here is this function's immutable top-level identity:
    ;; reaching its body proves its bare-lambda initializer has completed.
    (define (guarded-self-call arguments context)
      (let ((locals (map (lambda (value) (fresh-local! context)) arguments)))
        `(block (result i32)
                ,@(map (lambda (name value) `(local.set ,name ,(value-code value))) locals arguments)
                (call ,(context-label context)
                      ,@(map (lambda (name value)
                               (checked-narrow (make-value `(local.get ,name) (value-range value)) context))
                             locals arguments)))))

    ;; Save all operands before replacing any parameter: (f b a) must swap.
    ;; Entry checks follow operand evaluation and precede the next iteration.
    ;; Partial local updates before a failing check cannot escape this pure
    ;; worker. Each backedge reestablishes i32 domains, not earlier branch facts.
    (define (tail-self-call arguments context)
      (let ((locals (map (lambda (value) (fresh-local! context)) arguments)))
        `(block (result i32)
                ,@(map (lambda (name value) `(local.set ,name ,(value-code value))) locals arguments)
                ,@(map (lambda (parameter name value)
                         `(local.set ,(cdr parameter)
                                     ,(checked-narrow (make-value `(local.get ,name) (value-range value)) context)))
                       (context-parameters context) locals arguments)
                (br $self)))))

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-wasm-i32)
    (import (snail-scheme test-utils))
    (begin
      ;; Chibi's arbitrary precision supplies an independent arithmetic oracle.
      ;; Decode large expectations only when host tests run, not while the
      ;; bootstrap parser reads this inactive section during self-compilation.
      (define (test-bound-arithmetic)
        (let ((edges (map string->number
                          '("-9223372036854775808" "-9223372036854775807" "-3074457345618258603"
                            "-3074457345618258602" "-3037000500" "-2147483648" "-3" "-1" "0" "1" "3"
                            "2147483647" "3037000499" "3037000500" "3074457345618258602"
                            "3074457345618258603" "9223372036854775806" "9223372036854775807"))))
          (for-each
           (lambda (left)
             (for-each
              (lambda (right)
                (for-each
                 (lambda (entry)
                   (let ((answer ((car entry) left right)))
                     (expect ((cdr entry) left right)
                             (and (<= (car i64-range) answer (cdr i64-range)) answer))))
                 (list (cons + add-bound) (cons - subtract-bound) (cons * multiply-bound)))) edges)) edges)))

      (define (test-wasm-i32)
        (test-bound-arithmetic)
        (expect (refine-range i32-range '< 2 #f) '(2 . 2147483647))
        (expect (arithmetic-range '- '(2 . 2147483647) '(1 . 1)) '(1 . 2147483646))
        (expect (in-range? (arithmetic-range '+ i32-range i32-range) i32-range) #f)
        (expect (arithmetic-range '* i64-range '(0 . 0)) '(0 . 0))
        (expect (arithmetic-range '* i64-range '(1 . 1)) i64-range)
        (expect (arithmetic-range '* i64-range '(-1 . -1)) #f)
        (expect (arithmetic-range '+ i64-range '(1 . 1)) #f)
        (expect (arithmetic-range '- i64-range '(1 . 1)) #f))))))

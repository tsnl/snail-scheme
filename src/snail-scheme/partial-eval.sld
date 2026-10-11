;; A bounded interpreter proves complete computations before emission replaces
;; them with scalars. The visitor consumes each result directly after checking
;; the source children; this evaluator never stores expression results.
(define-library (snail-scheme partial-eval)
  (export make-partial-state partial-primitives reserve-bindings remember!
          partial-evaluate scalar? unknown partial-evaluation-enabled)
  (import (scheme base) (scheme cxr)
          (prefix (snail-scheme ir) ir:))
  (begin

    ;; ---- Known values and work limits ----

    (define partial-evaluation-enabled (make-parameter #t))
    (define unknown (vector 'unknown))
    (define-record-type <closure>
      (make-closure procedure environment) closure?
      (procedure closure-procedure) (environment closure-environment))
    (define-record-type <primitive>
      (make-primitive name) primitive? (name primitive-name))
    (define-record-type <object>
      (make-object kind fields) object? (kind object-kind) (fields object-fields))
    (define-record-type <quoted>
      (make-quoted datum) quoted? (datum quoted-datum))
    (define-record-type <state>
      (make-state assigned declared primitives remaining) state?
      (assigned state-assigned) (declared state-declared)
      (primitives partial-primitives)
      (remaining state-remaining set-state-remaining!))
    (define-record-type <attempt>
      (make-attempt state remaining) attempt?
      (state attempt-state) (remaining attempt-remaining set-attempt-remaining!))

    ;; Failure is ordinary data: this pass also runs on hosts without call/cc.
    ;; Every consumer checks unknown before using a speculative result.
    (define (spend! attempt)
      (let ((state (attempt-state attempt)))
        (and (> (state-remaining state) 0) (> (attempt-remaining attempt) 0)
             (begin (set-state-remaining! state (- (state-remaining state) 1))
                    (set-attempt-remaining! attempt (- (attempt-remaining attempt) 1)) #t))))

    (define (scalar? value)
      (or (boolean? value) (null? value) (symbol? value) (char? value)
          (and (exact-integer? value) (<= -9223372036854775808 value 9223372036854775807))))
    (define (literal-value value) (if (scalar? value) value (make-quoted value)))

    ;; ---- Ordered bindings and source traversal ----

    (define (children node)
      (cond ((ir:lambda? node) (list (ir:lambda-body node)))
            ((ir:block? node) (ir:block-items node))
            ((ir:value-binding? node) (list (ir:value-binding-initializer node)))
            ((ir:application? node) (append (ir:application-operands node) (list (ir:application-operator node))))
            ((ir:conditional? node)
             (append (list (ir:conditional-test node) (ir:conditional-consequent node))
                     (if (ir:conditional-opt-alternate node) (list (ir:conditional-opt-alternate node)) '())))
            ((ir:assignment? node) (list (ir:assignment-value node)))
            ((ir:annotation? node) (list (ir:annotation-expression node)))
            ((ir:instantiation? node) (list (ir:instantiation-expression node)))
            (else '())))

    (define (collect-bindings items predicate definition)
      (apply append (map (lambda (node)
                           (append (if (predicate node) (list (definition node)) '())
                                   (collect-bindings (children node) predicate definition))) items)))

    (define (reserve-bindings items environment)
      (append (map (lambda (node) (cons (ir:value-binding-definition node) unknown))
                   (let select ((items items))
                     (cond ((null? items) '())
                           ((ir:value-binding? (car items)) (cons (car items) (select (cdr items))))
                           (else (select (cdr items)))))) environment))

    (define (binding-known? definition state)
      (not (or (memq definition (state-assigned state)) (memq definition (state-declared state)))))

    ;; An evaluated closure could hide private mutable data that later escapes.
    ;; Only syntactic lambdas capture this traversal's scalar-only slot graph.
    (define (remember! definition initializer value environment state)
      (when (and (binding-known? definition state)
                 (or (scalar? value) (and (ir:lambda? initializer) (closure? value))))
        (set-cdr! (assq definition environment) value)))

    (define (primitive-environment primitives)
      (map (lambda (definition) (cons definition (make-primitive (ir:value-definition-name definition)))) primitives))

    (define (make-partial-state items declared primitives)
      (make-state (collect-bindings items ir:assignment?
                                    (lambda (node) (ir:name-definition (ir:assignment-target node))))
                  declared (primitive-environment primitives) 300000))

    ;; Typed bindings are unavailable here, and annotation/instantiation syntax
    ;; is opaque to evaluate. Thus a fold cannot erase a dynamic type boundary.
    ;; The visitor also retains the expression's own inferred result guard.
    (define (partial-evaluate node environment state)
      (if (partial-evaluation-enabled) (try-evaluate node environment state) unknown))

    ;; ---- Complete speculative evaluation ----

    (define (try-evaluate node environment state)
      (evaluate node environment (make-attempt state 16384) 0))

    (define (read-binding definition environment attempt)
      (let ((entry (assq definition environment)))
        (if (and entry (binding-known? definition (attempt-state attempt))) (cdr entry) unknown)))

    (define (evaluate node environment attempt depth)
      (cond ((or (not (spend! attempt)) (> depth 256)) unknown)
            ((ir:literal? node) (literal-value (ir:literal-value node)))
            ((ir:name? node) (read-binding (ir:name-definition node) environment attempt))
            ((ir:lambda? node) (make-closure node environment))
            ((ir:block? node) (evaluate-sequence (ir:block-items node) environment attempt (+ depth 1)))
            ((ir:conditional? node) (evaluate-conditional node environment attempt (+ depth 1)))
            ((ir:application? node) (evaluate-call node environment attempt (+ depth 1)))
            (else unknown)))

    (define (evaluate-conditional node environment attempt depth)
      (let ((test (evaluate (ir:conditional-test node) environment attempt depth)))
        (if (eq? test unknown) unknown
            (let ((branch (if (eq? test #f) (ir:conditional-opt-alternate node) (ir:conditional-consequent node))))
              (if branch (evaluate branch environment attempt depth) unknown)))))

    ;; Fresh slots belong to this activation. Unknown preceding work prevents
    ;; folding the whole block, even if a later expression is independently known.
    (define (evaluate-sequence items environment attempt depth)
      (let ((environment (reserve-bindings items environment)))
        (let loop ((items items) (result unknown))
          (cond ((null? items) result)
                ((ir:value-binding? (car items))
                 (if (initialize-binding (car items) environment attempt depth)
                     (loop (cdr items) unknown) unknown))
                (else (let ((value (evaluate (car items) environment attempt depth)))
                        (if (eq? value unknown) unknown (loop (cdr items) value))))))))

    (define (initialize-binding node environment attempt depth)
      (let ((definition (ir:value-binding-definition node)))
        (and (binding-known? definition (attempt-state attempt))
             (let ((value (evaluate (ir:value-binding-initializer node) environment attempt depth)))
               (and (not (eq? value unknown))
                    (begin (set-cdr! (assq definition environment) value) #t))))))

    (define (evaluate-operands nodes environment attempt depth)
      (let loop ((nodes nodes) (values '()))
        (if (null? nodes) (reverse values)
            (let ((value (evaluate (car nodes) environment attempt depth)))
              (if (eq? value unknown) unknown (loop (cdr nodes) (cons value values)))))))

    (define (evaluate-call node environment attempt depth)
      (let ((arguments (evaluate-operands (ir:application-operands node) environment attempt depth)))
        (if (eq? arguments unknown) unknown
            (let ((operator (evaluate (ir:application-operator node) environment attempt depth)))
              (cond ((primitive? operator) (invoke-primitive (primitive-name operator) arguments attempt))
                    ((closure? operator) (invoke-closure operator arguments attempt depth))
                    (else unknown))))))

    (define (invoke-closure closure arguments attempt depth)
      (let* ((procedure (closure-procedure closure)) (parameters (ir:lambda-parameters procedure)))
        (if (or (ir:lambda-opt-rest-parameter procedure) (not (= (length parameters) (length arguments)))) unknown
            (evaluate (ir:lambda-body procedure)
                      (append (map cons parameters arguments) (closure-environment closure)) attempt depth))))

    ;; ---- Target integer arithmetic ----

    ;; Check before host arithmetic: the compiler can itself run with i64s.
    (define (checked-add a b)
      (if (or (and (> b 0) (> a (- 9223372036854775807 b)))
              (and (< b 0) (< a (- -9223372036854775808 b)))) unknown (+ a b)))
    (define (checked-subtract a b)
      (if (or (and (> b 0) (< a (+ -9223372036854775808 b)))
              (and (< b 0) (> a (+ 9223372036854775807 b)))) unknown (- a b)))
    (define (checked-multiply a b)
      (if (cond ((> a 0) (if (> b 0) (> a (quotient 9223372036854775807 b))
                             (and (< b 0) (< b (quotient -9223372036854775808 a)))))
                ((< a 0) (if (> b 0) (< a (quotient -9223372036854775808 b))
                             (and (< b 0) (< a (quotient 9223372036854775807 b)))))
                (else #f)) unknown (* a b)))

    (define (integer-arguments? arguments)
      (or (null? arguments) (and (exact-integer? (car arguments)) (scalar? (car arguments))
                                 (integer-arguments? (cdr arguments)))))
    (define (fold-integers operation result rest attempt)
      (cond ((eq? result unknown) unknown) ((null? rest) result) ((not (spend! attempt)) unknown)
            (else (fold-integers operation (operation result (car rest)) (cdr rest) attempt))))

    (define (integer-operation name arguments attempt)
      (if (not (integer-arguments? arguments)) unknown
          (case name
            ((+) (fold-integers checked-add 0 arguments attempt))
            ((*) (fold-integers checked-multiply 1 arguments attempt))
            ((-) (cond ((null? arguments) unknown)
                       ((null? (cdr arguments)) (checked-subtract 0 (car arguments)))
                       (else (fold-integers checked-subtract (car arguments) (cdr arguments) attempt))))
            ((quotient remainder modulo) (integer-division name arguments))
            (else unknown))))

    (define (integer-division name arguments)
      (if (not (= (length arguments) 2)) unknown
          (let ((a (car arguments)) (b (cadr arguments)))
            (if (or (zero? b) (and (= a -9223372036854775808) (= b -1))) unknown
                ((case name ((quotient) quotient) ((remainder) remainder) (else modulo)) a b)))))

    (define (compare-integers predicate arguments attempt)
      (if (or (not (integer-arguments? arguments)) (< (length arguments) 2)) unknown
          (let loop ((rest arguments))
            (cond ((not (spend! attempt)) unknown) ((null? (cdr rest)) #t)
                  ((predicate (car rest) (cadr rest)) (loop (cdr rest))) (else #f)))))

    ;; ---- Pure operations and private allocations ----

    ;; Quoted compound data may have been mutated by an earlier invocation. Its
    ;; category is known, but its contents and identity are never inspected here.
    (define (value-kind value)
      (cond ((object? value) (object-kind value))
            ((quoted? value)
             (let ((datum (quoted-datum value)))
               (cond ((pair? datum) 'pair) ((vector? datum) 'vector) ((string? datum) 'string)
                     ((bytevector? datum) 'bytevector) ((number? datum) 'number) (else 'unknown))))
            ((null? value) 'null) ((boolean? value) 'boolean) ((char? value) 'char)
            ((symbol? value) 'symbol) ((number? value) 'number)
            ((or (closure? value) (primitive? value)) 'procedure) (else 'unknown)))

    (define (private-object? value kind) (and (object? value) (eq? (object-kind value) kind)))
    (define (private-list arguments attempt)
      (let loop ((rest (reverse arguments)) (result '()))
        (cond ((null? rest) result) ((not (spend! attempt)) unknown)
              (else (loop (cdr rest) (make-object 'pair (cons (car rest) result)))))))
    (define (private-length value attempt)
      (let loop ((value value) (count 0))
        (cond ((not (spend! attempt)) unknown) ((null? value) count)
              ((private-object? value 'pair) (loop (cdr (object-fields value)) (+ count 1)))
              (else unknown))))
    (define (private-vector-ref value index)
      (if (and (private-object? value 'vector) (exact-integer? index)
               (<= 0 index) (< index (vector-length (object-fields value))))
          (vector-ref (object-fields value) index) unknown))

    (define (fixed-primitive-arity name)
      (case name
        ((not zero? positive? negative? null? boolean? pair? vector? string? symbol?
              char? number? bytevector? procedure? car cdr length vector-length) 1)
        ((cons vector-ref) 2) (else #f)))

    (define (invoke-primitive name arguments attempt)
      (let ((arity (fixed-primitive-arity name)))
        (if (and arity (not (= arity (length arguments)))) unknown
            (pure-primitive name arguments attempt))))

    ;; This exhaustive dispatch keeps each admitted operation's checks beside it.
    (define (pure-primitive name arguments attempt)
      (case name
        ((+ - * quotient remainder modulo) (integer-operation name arguments attempt))
        ((= < <= > >=)
         (compare-integers (case name ((=) =) ((<) <) ((<=) <=) ((>) >) (else >=)) arguments attempt))
        ((not) (eq? (car arguments) #f))
        ((zero? positive? negative?)
         (if (integer-arguments? arguments)
             ((case name ((zero?) zero?) ((positive?) positive?) (else negative?)) (car arguments)) unknown))
        ((null? boolean? pair? vector? string? symbol? char? number? bytevector? procedure?)
         (eq? (value-kind (car arguments))
              (case name ((null?) 'null) ((boolean?) 'boolean) ((pair?) 'pair) ((vector?) 'vector)
                    ((string?) 'string) ((symbol?) 'symbol) ((char?) 'char) ((number?) 'number)
                    ((bytevector?) 'bytevector) (else 'procedure))))
        ((cons) (make-object 'pair (cons (car arguments) (cadr arguments))))
        ((list) (private-list arguments attempt))
        ((car cdr)
         (if (private-object? (car arguments) 'pair)
             ((if (eq? name 'car) car cdr) (object-fields (car arguments))) unknown))
        ((vector) (make-object 'vector (list->vector arguments)))
        ((vector-ref) (private-vector-ref (car arguments) (cadr arguments)))
        ((vector-length) (if (private-object? (car arguments) 'vector) (vector-length (object-fields (car arguments))) unknown))
        ((length) (private-length (car arguments) attempt))
        (else unknown))))

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-partial-eval)
    (import (snail-scheme test-utils) (snail-scheme reader) (snail-scheme syntax-parser)
            (snail-scheme expand) (snail-scheme library))
    (begin
      (define (fold-last source)
        (let* ((core (make-core-library '(scheme base) '(+ - * = < cons car cdr set-car! vector vector-ref error)))
               (primitives (let loop ((exports (library-exports core)))
                             (if (null? exports) '()
                                 (let ((definition (named-binding-definition (car exports))))
                                   (if (ir:value-definition? definition) (cons definition (loop (cdr exports)))
                                       (loop (cdr exports)))))))
               (program (syntax-list->ir-library (reader->syntax-list (string->reader "partial-eval-test.scm" source))
                                                 (lambda (name) #f) (list core)))
               (items (library-body program))
               (declared (collect-bindings items ir:type-declaration? ir:type-declaration-definition))
               (state (make-partial-state items declared primitives))
               (value (evaluate-sequence items (partial-primitives state) (make-attempt state 16384) 0)))
          (if (scalar? value) value 'unfolded)))

      (define (test-partial-recursion)
        (expect (fold-last "(import (scheme base))
          (define (sum n) (if (= n 0) 0 (+ n (sum (- n 1))))) (sum 20)") 210)
        (expect (fold-last "(import (scheme base))
          (define (forever n) (forever n)) (forever 1)") 'unfolded)
        (expect (fold-last "(import (scheme base)) (car (cons (+ 20 22) 0))") 42)
        (expect (fold-last "(import (scheme base)) (vector-ref (vector 1 42 3) 1)") 42))

      (define (test-partial-boundaries)
        (for-each (lambda (source) (expect (fold-last (string-append "(import (scheme base)) " source)) 'unfolded))
                  '("(+ 9223372036854775807 1)" "(* -9223372036854775808 -1)"
                    "(define (f ignored) 7) (f (car 1))"
                    "(if (car 1) 42 0)"
                    "(begin (car 1) 42)"
                    "((lambda (x) 42))"
                    "(vector-ref (vector 42) -1)"
                    "(define (f) x) (define y (f)) (define x 42) y"
                    "(define x 1) (set! x 2) (+ x 1)"
                    "(car '(1 2))"
                    "(define getter ((lambda (x) (lambda () x)) (cons 1 2)))
                     (set-car! (getter) 9) (car (getter))"
                    "(: f (-> i32 i32)) (define (f n) n) (f 42)"))
        (expect (fold-last "(import (scheme base)) ((lambda (+) (+ 7 2)) (lambda (a b) (- a b)))") 5))

      (define (test-partial-eval)
        (run-test test-partial-recursion)
        (run-test test-partial-boundaries))))))

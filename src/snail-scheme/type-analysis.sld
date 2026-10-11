;; Bidirectional checking and finite occurrence facts over resolved identities.
;; The result is evidence for the emitter, not a rewritten IR. A type fact holds
;; only after its recorded guard succeeds. Initialization is never inferred here.
(define-library (snail-scheme type-analysis)
  (export analyze-types type-optimizations-enabled analysis-fact analysis-guard analysis-guards
          analysis-signature analysis-call-guards fact-type fact-single? fact-callee predicate-type
          analysis-statistics)
  (import (scheme base) (scheme cxr) (snail-scheme identity-map)
          (snail-scheme types) (snail-scheme type-inference)
          (prefix (snail-scheme ir) ir:))
  (begin
    ;; ---- Evidence and analysis state ----

    (define type-optimizations-enabled (make-parameter #t))
    (define current-procedure (make-parameter #f))

    ;; Instantiation preserves the Scheme value and the implementation origins.
    ;; A join can have several origins; recursive-use validation needs them all.
    (define-record-type <instance>
      (make-instance callee types) instance?
      (callee instance-callee) (types instance-types))
    (define-record-type <callees>
      (make-callees members) callees? (members callees-members))

    (define-record-type <fact>
      (make-fact type single? object yes no callee)
      fact?
      (type fact-type) (single? fact-single?) (object fact-object)
      (yes fact-yes) (no fact-no) (callee fact-callee))

    (define (value-fact type) (make-fact type #t #f '() '() #f))
    (define (unknown-fact) (make-fact '? #f #f '() '() #f))
    (define (normalized-fact fact)
      (make-fact (fact-type fact) #t (fact-object fact)
                 (fact-yes fact) (fact-no fact) (fact-callee fact)))
    (define (entry-value key entries default)
      (let ((entry (assq key entries))) (if entry (cdr entry) default)))

    (define-record-type <analysis>
      (make-analysis facts fact-count guards signatures declarations primitives assigned bindings summaries records call-guards calls)
      analysis?
      (facts analysis-facts set-analysis-facts!) (fact-count analysis-fact-count set-analysis-fact-count!)
      (guards analysis-guards set-analysis-guards!)
      (signatures analysis-signatures set-analysis-signatures!)
      (declarations analysis-declarations set-analysis-declarations!)
      (primitives analysis-primitives) (assigned analysis-assigned)
      (bindings analysis-bindings) (summaries analysis-summaries set-analysis-summaries!)
      (records analysis-records set-analysis-records!)
      (call-guards analysis-call-guard-plans set-analysis-call-guards!)
      (calls analysis-calls set-analysis-calls!))

    (define (analysis-fact analysis node)
      (identity-map-ref (analysis-facts analysis) node (unknown-fact)))

    ;; Node identity selects the latest evidence. The count retains the number
    ;; of analysis records, including repeated visits, for existing statistics.
    (define (record-fact! analysis node fact)
      (set-analysis-facts! analysis (identity-map-set (analysis-facts analysis) node fact))
      (set-analysis-fact-count! analysis (+ 1 (analysis-fact-count analysis))))

    (define (analysis-guard analysis node) (entry-value node (analysis-guards analysis) #f))
    (define (analysis-signature analysis node)
      (entry-value node (analysis-signatures analysis) #f))
    (define (analysis-call-guards analysis node)
      (entry-value node (analysis-call-guard-plans analysis) '()))
    (define (analysis-statistics analysis)
      (list (cons 'expressions (analysis-fact-count analysis))
            (cons 'guards (length (analysis-guards analysis)))
            (cons 'signatures (length (analysis-signatures analysis)))
            (cons 'function-summaries (length (analysis-summaries analysis)))))

    ;; ---- Whole-program declarations and mutation ----

    (define (children node)
      (cond ((ir:lambda? node) (list (ir:lambda-body node)))
            ((ir:block? node) (ir:block-items node))
            ((ir:application? node) (append (ir:application-operands node)
                                            (list (ir:application-operator node))))
            ((ir:conditional? node)
             (append (list (ir:conditional-test node) (ir:conditional-consequent node))
                     (if (ir:conditional-opt-alternate node)
                         (list (ir:conditional-opt-alternate node)) '())))
            ((ir:value-binding? node) (list (ir:value-binding-initializer node)))
            ((ir:assignment? node) (list (ir:assignment-value node)))
            ((ir:annotation? node) (list (ir:annotation-expression node)))
            ((ir:instantiation? node) (list (ir:instantiation-expression node)))
            (else '())))

    (define (all-nodes items)
      (apply append (map (lambda (node) (cons node (all-nodes (children node)))) items)))
    (define (select predicate items)
      (cond ((null? items) '())
            ((predicate (car items)) (cons (car items) (select predicate (cdr items))))
            (else (select predicate (cdr items)))))

    (define (analyze-types items primitives)
      (let* ((nodes (all-nodes items))
             (assigned (map (lambda (node) (ir:name-definition (ir:assignment-target node)))
                            (select ir:assignment? nodes)))
             (bindings (map (lambda (node) (cons (ir:value-binding-definition node)
                                                 (ir:value-binding-initializer node)))
                            (select ir:value-binding? nodes)))
             (analysis (make-analysis empty-identity-map 0 '() '() '() primitives assigned bindings '() '() '() '())))
        (for-each (lambda (node) (register-record! node items analysis)) (select ir:record-schema? nodes))
        (for-each (lambda (node) (declare-record! node analysis)) (select ir:record-schema? nodes))
        (for-each (lambda (node) (declare-type! node analysis)) (select ir:type-declaration? nodes))
        (analyze-sequence items '() '() #f #f analysis)
        (check-recursive-instances analysis)
        analysis))

    (define (declare-type! node analysis)
      (let* ((definition (ir:type-declaration-definition node)) (type (ir:type-declaration-type node))
             (initializer (entry-value definition (analysis-bindings analysis) #f)))
        (validate-type type analysis (ir:type-declaration-loc node))
        (if (or (not initializer) (assq definition (analysis-declarations analysis)))
            (type-error-at (ir:type-declaration-loc node) "type declaration requires one local definition"))
        (set-analysis-declarations! analysis (cons (cons definition type) (analysis-declarations analysis)))
        (if (function-type? type)
            (begin
              (if (memq definition (analysis-assigned analysis))
                  (type-error-at (ir:type-declaration-loc node) "cannot assign a function signature"))
              (if (ir:lambda? initializer) (declare-lambda! initializer type analysis))))))

    (define (declare-lambda! node type analysis)
      (if (not (and (ir:lambda? node) (not (ir:lambda-opt-rest-parameter node))
                    (= (length (ir:lambda-parameters node)) (length (type-arguments (all-body type))))))
          (type-error-at (node-location node) "function annotation requires a fixed-arity lambda of matching arity" type))
      (validate-type type analysis (node-location node))
      (let ((previous (analysis-signature analysis node)))
        (cond ((not previous)
               (set-analysis-signatures! analysis (cons (cons node type) (analysis-signatures analysis))))
              ((not (type-equal? previous type)) (type-error-at (node-location node) "conflicting function annotations" type previous)))))

    (define (every? predicate items)
      (or (null? items) (and (predicate (car items)) (every? predicate (cdr items)))))

    ;; ---- Nominal record schemas ----

    (define (typed-record? node)
      (not (every? (lambda (field) (eq? (cadr field) '?)) (ir:record-schema-fields node))))

    (define (register-record! node items analysis)
      (let ((definition (ir:record-schema-definition node)))
        (if (and (memq node items) (not (memq definition (analysis-assigned analysis)))
                 (fresh-record-descriptor? definition analysis))
            (set-analysis-records! analysis (cons (cons definition node) (analysis-records analysis)))
            (if (typed-record? node)
                (type-error-at (ir:record-schema-loc node) "typed records require a stable top-level descriptor")))))

    ;; Metadata alone cannot certify fresh nominal identity: even a manually
    ;; supplied core schema must name an actual, immutable descriptor allocation.
    (define (fresh-record-descriptor? definition analysis)
      (let* ((initializer (entry-value definition (analysis-bindings analysis) #f))
             (operator (and (ir:application? initializer) (ir:application-operator initializer))))
        (and (ir:name? operator)
             (memq (ir:name-definition operator) (analysis-primitives analysis))
             (eq? (ir:value-definition-name (ir:name-definition operator)) '%make-record-type))))

    (define (validate-type type analysis loc)
      (if (not (or (shallow-type? type) (function-type? type)))
          (type-error-at loc "annotations require a shallow type or a checked function signature" type))
      (cond ((nominal-type? type)
             (if (not (assq (cadr type) (analysis-records analysis)))
                 (type-error-at loc "nominal type requires a stable top-level record declaration" type)))
            ((function-type? type)
             (if (not (every? shallow-type? (cdr (all-body type))))
                 (type-error-at loc "function domains and results must be shallow types; nested All and arrows are unsupported" type))
             (for-each (lambda (part) (validate-type part analysis loc)) (cdr (all-body type))))
            ((union-type? type) (for-each (lambda (part) (validate-type part analysis loc)) (cdr type)))))

    (define (declare-generated! definition type analysis)
      (declare-type! (ir:make-type-declaration definition type (ir:value-definition-loc definition)) analysis))

    (define (record-argument-type name node)
      (let ((field (assq name (ir:record-schema-fields node))))
        (if field (cadr field) (error "record constructor argument is not a field" name))))

    (define (declare-record! node analysis)
      (if (typed-record? node)
          (let ((type (list 'record (ir:record-schema-definition node))))
            (declare-generated! (ir:record-schema-constructor node)
                                (append '(->) (map (lambda (name) (record-argument-type name node))
                                                   (ir:record-schema-arguments node)) (list type)) analysis)
            (declare-generated! (ir:record-schema-predicate node) '(-> Any Boolean) analysis)
            (for-each (lambda (field) (declare-record-field! field node type analysis))
                      (ir:record-schema-fields node)))))

    (define (declare-record-field! field node type analysis)
      (if (and (not (eq? (cadr field) '?)) (not (memq (car field) (ir:record-schema-arguments node))))
          (error "typed record field must be initialized by its constructor" (car field)))
      (declare-generated! (caddr field) (list '-> type (cadr field)) analysis)
      (if (cadddr field) (declare-generated! (cadddr field) (list '-> type (cadr field) 'Unspecified) analysis)))

    ;; ---- Stable references and occurrence filters ----

    ;; A filter is (binding-identity include? shallow-type). No heap paths occur.
    ;; At most 32 facts are retained: dropping facts loses precision, not safety.
    (define (combine-filters first second)
      (let ((facts (append first second))) (if (> (length facts) 32) '() facts)))
    (define (common-filters first second)
      (select (lambda (fact)
                (let contains? ((others second))
                  (and (pair? others)
                       (or (same-filter? fact (car others)) (contains? (cdr others)))))) first))
    (define (same-filter? first second)
      (and (eq? (car first) (car second)) (eq? (cadr first) (cadr second))
           (type-equal? (caddr first) (caddr second))))

    (define (narrow type object path)
      (if (or (not object) (null? path)) type
          (let ((filter (car path)))
            (narrow (if (eq? object (car filter))
                        ((if (cadr filter) type-intersect type-subtract) type (caddr filter)) type)
                    object (cdr path)))))

    (define (name-fact node environment path analysis)
      (let* ((definition (ir:name-definition node))
             (base (binding-fact definition environment analysis))
             (stable? (not (memq definition (analysis-assigned analysis))))
             (object (and stable? (or (fact-object base) definition)))
             (type (narrow (fact-type base) object path)))
        (make-fact type (fact-single? base) object
                   (if stable? (fact-yes base) '()) (if stable? (fact-no base) '())
                   (and stable? (fact-callee base)))))

    (define (binding-fact definition environment analysis)
      (let ((declared (entry-value definition (analysis-declarations analysis) #f))
            (stored (entry-value definition environment (value-fact '?))))
        (cond ((memq definition (analysis-assigned analysis))
               (make-fact (or declared '?) (fact-single? stored) #f '() '() #f))
              ((assq definition environment) => cdr)
              ((memq definition (analysis-primitives analysis))
               (make-fact 'Procedure #t #f '() '() (ir:value-definition-name definition)))
              (else (make-fact (or declared '?) #t #f '() '()
                               (binding-callee definition '() analysis))))))

    ;; Forward aliases can name a checked implementation without evaluating it.
    ;; Reads still carry their ordinary initialization check in the emitter.
    (define (binding-callee definition visited analysis)
      (and (not (memq definition visited)) (not (memq definition (analysis-assigned analysis)))
           (callee-view (initializer-callee (entry-value definition (analysis-bindings analysis) #f)
                                            (cons definition visited) analysis)
                        (entry-value definition (analysis-declarations analysis) #f)
                        (ir:value-definition-loc definition) analysis)))
    (define (initializer-callee node visited analysis)
      (cond ((ir:lambda? node) node)
            ((ir:name? node) (binding-callee (ir:name-definition node) visited analysis))
            ((ir:instantiation? node)
             (let ((callee (initializer-callee (ir:instantiation-expression node) visited analysis)))
               (and callee (make-instance callee (ir:instantiation-types node)))))
            ((ir:annotation? node)
             (callee-view (initializer-callee (ir:annotation-expression node) visited analysis)
                          (ir:annotation-type node) (ir:annotation-loc node) analysis))
            ((ir:block? node)
             (let ((items (ir:block-items node)))
               (and (pair? items) (initializer-callee (car (reverse items)) visited analysis))))
            ((ir:conditional? node)
             (let ((yes (initializer-callee (ir:conditional-consequent node) visited analysis))
                   (no (initializer-callee (ir:conditional-opt-alternate node) visited analysis)))
               (and yes no (make-callees (list yes no)))))
            (else #f)))

    (define (callee-view callee type loc analysis)
      (cond ((callees? callee)
             (make-callees (map (lambda (member) (callee-view member type loc analysis)) (callees-members callee))))
            ((and (arrow-type? type) (ir:lambda? callee) (all-type? (analysis-signature analysis callee)))
             (make-instance callee (infer-type-arguments (analysis-signature analysis callee)
                                                         (type-arguments type) (type-result type) loc)))
            (else callee)))

    (define (truth-filters fact truth?)
      (let ((filters ((if truth? fact-yes fact-no) fact)) (object (fact-object fact)))
        (if object (combine-filters filters (list (list object (not truth?) 'False))) filters)))

    (define (predicate-type name)
      (case name
        ((exact-integer?) 'ExactInteger) ((number? real?) 'Number) ((inexact?) 'InexactReal)
        ((boolean?) 'Boolean) ((string?) 'String) ((symbol?) 'Symbol) ((char?) 'Char)
        ((pair?) 'Pair) ((null?) 'Null) ((vector?) 'Vector) ((bytevector?) 'Bytevector)
        ((procedure?) 'Procedure) (else #f)))

    (define (predicate-fact type argument)
      (let ((object (fact-object argument)))
        (make-fact 'Boolean #t #f (if object (list (list object #t type)) '())
                   (if object (list (list object #f type)) '()) #f)))

    ;; ---- Checking and synthesis ----

    (define (analyze node environment path strict? expected analysis)
      ;; Record a guard from incoming evidence before publishing its postcondition.
      ;; The emitter executes this plan even when a surrounding consumer uses the
      ;; postcondition to omit its own redundant check.
      (let* ((fact (infer node environment path strict? expected analysis))
             (checked (if expected (check-result node fact expected analysis) fact)))
        (record-fact! analysis node checked)
        checked))

    (define (infer node environment path strict? expected analysis)
      (cond ((ir:literal? node) (value-fact (literal-type (ir:literal-value node))))
            ((ir:name? node) (name-fact node environment path analysis))
            ((ir:lambda? node) (analyze-lambda node environment path expected analysis))
            ((ir:annotation? node)
             (validate-type (ir:annotation-type node) analysis (node-location node))
             (if (function-type? (ir:annotation-type node))
                 (analyze (ir:annotation-expression node) environment path #t (ir:annotation-type node) analysis)
                 (check-result node (analyze (ir:annotation-expression node) environment path #t #f analysis)
                               (ir:annotation-type node) analysis)))
            ((ir:instantiation? node) (analyze-instantiation node environment path analysis))
            ((ir:block? node) (analyze-sequence (ir:block-items node) environment path strict? expected analysis))
            ((ir:conditional? node) (analyze-conditional node environment path strict? expected analysis))
            ((ir:application? node) (analyze-call node environment path strict? expected analysis))
            ((ir:assignment? node) (analyze-assignment node environment path strict? analysis))
            ((ir:type-declaration? node) (value-fact 'Unspecified))
            ((ir:record-schema? node) (value-fact 'Unspecified))
            (else (error "unexpected typing expression" node))))

    (define (check-result node fact expected analysis)
      (let ((actual (fact-type fact)))
        (cond ((and (arrow-type? expected) (all-type? actual))
               (check-result node (instantiate-fact fact
                                                    (infer-type-arguments actual (type-arguments expected) (type-result expected)
                                                                          (node-location node)) node) expected analysis))
              ((function-type? expected)
               (if (not (type-equal? actual expected))
                   (type-error-at (node-location node) "unsupported opaque function annotation" expected)) fact)
              ((not (or (type-compatible? actual expected)
                        (and (ir:annotation? node) (eq? actual 'Any))))
               (type-error node actual expected))
              (else
               (if (or (not (fact-single? fact))
                       (and (not (memq expected '(Any ?))) (not (type-subtype? actual expected))))
                   (let ((guard (if (type-subtype? actual expected) 'Any expected)))
                     (require-runtime-type guard node)
                     (set-analysis-guards! analysis (cons (cons node guard) (analysis-guards analysis)))))
               (make-fact (if (eq? expected '?) actual expected) #t (fact-object fact)
                          (fact-yes fact) (fact-no fact) (fact-callee fact))))))

    (define (type-error node actual expected)
      (type-error-at (node-location node) "type mismatch" actual 'expected expected))
    (define (require-runtime-type type node)
      (if (not (runtime-type? type))
          (type-error-at (node-location node) "cannot check an erased type variable at a dynamic boundary" type)))
    (define (node-location node)
      (cond ((ir:name? node) (ir:name-loc node)) ((ir:literal? node) (ir:literal-loc node))
            ((ir:application? node) (ir:application-loc node))
            ((ir:lambda? node) (ir:lambda-loc node)) ((ir:block? node) (ir:block-loc node))
            ((ir:conditional? node) (ir:conditional-loc node))
            ((ir:annotation? node) (ir:annotation-loc node))
            ((ir:instantiation? node) (ir:instantiation-loc node)) (else #f)))

    (define (analyze-sequence items environment path strict? expected analysis)
      (cond ((null? items) (value-fact 'Unspecified))
            ((ir:value-binding? (car items))
             (let* ((node (car items)) (definition (ir:value-binding-definition node))
                    (declared (entry-value definition (analysis-declarations analysis) #f))
                    (fact (analyze (ir:value-binding-initializer node) environment path
                                   (or strict? declared) declared analysis)))
               ;; Every ordinary binding store executes single-value normalization.
               (analyze-sequence (cdr items) (cons (cons definition (normalized-fact fact)) environment)
                                 path strict? expected analysis)))
            ((null? (cdr items)) (analyze (car items) environment path strict? expected analysis))
            (else (analyze (car items) environment path strict? #f analysis)
                  (analyze-sequence (cdr items) environment path strict? expected analysis))))

    (define (analyze-assignment node environment path strict? analysis)
      (let* ((definition (ir:name-definition (ir:assignment-target node)))
             (declared (entry-value definition (analysis-declarations analysis) #f)))
        (analyze (ir:assignment-value node) environment path (or strict? declared) declared analysis)
        (value-fact 'Unspecified)))

    (define (analyze-conditional node environment path strict? expected analysis)
      (let* ((test (analyze (ir:conditional-test node) environment path strict? #f analysis))
             (yes-path (truth-filters test #t)) (no-path (truth-filters test #f))
             (yes (analyze (ir:conditional-consequent node) environment
                           (combine-filters path yes-path) strict? expected analysis))
             (no (if (ir:conditional-opt-alternate node)
                     (analyze (ir:conditional-opt-alternate node) environment
                              (combine-filters path no-path) strict? expected analysis)
                     (value-fact 'Unspecified))))
        (make-fact (joined-type yes no)
                   (and (fact-single? yes) (fact-single? no)) #f
                   (join-branch-filters yes-path yes no-path no #t)
                   (join-branch-filters yes-path yes no-path no #f)
                   (joined-callees yes no))))

    (define (joined-callees yes no)
      (cond ((eq? (fact-type yes) 'Never) (fact-callee no))
            ((eq? (fact-type no) 'Never) (fact-callee yes))
            ((and (fact-callee yes) (fact-callee no))
             (make-callees (list (fact-callee yes) (fact-callee no))))
            (else #f)))
    (define (joined-type yes no)
      (let ((type (type-union (fact-type yes) (fact-type no))))
        (if (and (function-type? type) (not (joined-callees yes no))) 'Procedure type)))

    (define (join-branch-filters yes-path yes no-path no truth?)
      (let ((yes-facts (combine-filters yes-path (truth-filters yes truth?)))
            (no-facts (combine-filters no-path (truth-filters no truth?))))
        (cond ((impossible-truth? (fact-type yes) truth?) no-facts)
              ((impossible-truth? (fact-type no) truth?) yes-facts)
              (else (common-filters yes-facts no-facts)))))
    (define (impossible-truth? type truth?)
      (if truth? (type-subtype? type 'False)
          (and (not (memq type '(? Any))) (eq? (type-intersect type 'False) 'Never))))

    ;; ---- Procedures and verified predicate summaries ----

    (define (analyze-lambda node environment path expected analysis)
      (let ((signature (or (and (function-type? expected) expected) (analysis-signature analysis node))))
        (if signature (declare-lambda! node signature analysis))
        (parameterize ((current-procedure node))
          (analyze-lambda-body node environment path (and signature (all-body signature)) #f analysis))
        (make-fact (or signature 'Procedure) #t #f '() '() node)))

    (define (parameter-facts node signature arguments analysis)
      (map (lambda (definition type argument)
             (if signature
                 (set-analysis-declarations! analysis
                                             (cons (cons definition type) (analysis-declarations analysis))))
             (cons definition (cond (argument (normalized-fact argument))
                                    (signature (value-fact type))
                                    (else (unknown-fact)))))
           (ir:lambda-parameters node)
           (if signature (type-arguments signature) (map (lambda (parameter) '?) (ir:lambda-parameters node)))
           (or arguments (map (lambda (parameter) #f) (ir:lambda-parameters node)))))

    (define (analyze-lambda-body node environment path signature arguments analysis)
      (let* ((parameters (parameter-facts node signature arguments analysis))
             (body (analyze (ir:lambda-body node) (append parameters environment) path
                            (and signature #t) (and signature (type-result signature)) analysis)))
        ;; Summaries are published only after checking the body, never assumed
        ;; during recursion. Substitution later exports only formal-parameter facts.
        (set-analysis-summaries! analysis (cons (cons node body) (analysis-summaries analysis)))
        body))

    (define (substitute-filters filters parameters arguments)
      (apply append
             (map (lambda (filter)
                    (let loop ((parameters parameters) (arguments arguments))
                      (cond ((null? parameters) '())
                            ((eq? (car filter) (car parameters))
                             (let ((object (fact-object (car arguments))))
                               (if object (list (cons object (cdr filter))) '())))
                            (else (loop (cdr parameters) (cdr arguments)))))) filters)))

    (define (procedure-result procedure signature arguments analysis)
      (let* ((body (entry-value procedure (analysis-summaries analysis) (unknown-fact)))
             (parameters (ir:lambda-parameters procedure)))
        (if (not (= (length parameters) (length arguments))) (unknown-fact)
            (make-fact (if signature (type-result signature)
                           (if (function-type? (fact-type body)) 'Procedure (fact-type body)))
                       (or signature (fact-single? body)) #f
                       (substitute-filters (fact-yes body) parameters arguments)
                       (substitute-filters (fact-no body) parameters arguments) #f))))

    ;; ---- Instantiated callable views ----

    (define (analyze-instantiation node environment path analysis)
      (for-each (lambda (type)
                  (if (not (runtime-type? type))
                      (type-error-at (node-location node) "type arguments must be shallow types" type))
                  (validate-type type analysis (node-location node))) (ir:instantiation-types node))
      (instantiate-fact (analyze (ir:instantiation-expression node) environment path #t #f analysis)
                        (ir:instantiation-types node) node))

    (define (instantiate-fact fact types node)
      (if (not (every? shallow-type? types))
          (type-error-at (node-location node) "type arguments must be shallow types"))
      (let ((signature (instantiate-type (fact-type fact) types (node-location node))))
        (if (not (fact-callee fact))
            (type-error-at (node-location node) "inst requires a checked implementation"))
        (make-fact signature #t (fact-object fact) '() '() (make-instance (fact-callee fact) types))))

    ;; Operands and then the operator are evaluated before these entry checks.
    ;; An abstract obligation can only be discharged by proof, never erasure.
    (define (plan-call-guards! node arguments signature analysis)
      (if (= (length arguments) (length (type-arguments signature)))
          (let ((guards (map (lambda (argument type)
                               (cond ((memq type '(? Any)) #f)
                                     ((runtime-type? type) type)
                                     ((type-subtype? (fact-type argument) type) #f)
                                     (else (require-runtime-type type node))))
                             arguments (type-arguments signature))))
            (set-analysis-call-guards! analysis (cons (cons node guards) (analysis-call-guard-plans analysis))))))

    ;; ---- Recursive instantiation ----

    ;; Edges include ordinary helpers and all alternatives of checked callable
    ;; joins. An opaque dynamic call carries no instantiated relationship.
    ;; Each edge is (caller callee type-arguments-or-#f source-node).
    (define (record-call! node callee viewed? analysis)
      (define (record callee types)
        (cond ((instance? callee) (record (instance-callee callee) (and viewed? (instance-types callee))))
              ((callees? callee) (for-each (lambda (callee) (record callee types)) (callees-members callee)))
              ((and (ir:lambda? callee) (current-procedure)
                    (or types (not (all-type? (analysis-signature analysis callee)))))
               (set-analysis-calls! analysis
                                    (cons (list (current-procedure) callee types node) (analysis-calls analysis))))))
      (record callee #f))

    (define (calls-reach? from target edges visited)
      (and (not (memq from visited))
           (or (eq? from target)
               (let loop ((edges-left edges))
                 (and (pair? edges-left)
                      (or (and (eq? from (caar edges-left))
                               (calls-reach? (cadar edges-left) target edges (cons from visited)))
                          (loop (cdr edges-left))))))))

    (define (check-recursive-instances analysis)
      (for-each
       (lambda (edge)
         (let ((signature (analysis-signature analysis (car edge))))
           (if (and (caddr edge) (calls-reach? (cadr edge) (car edge) (analysis-calls analysis) '())
                    (not (and (all-type? signature) (type-equal? (caddr edge) (all-variables signature)))))
               (type-error-at (node-location (cadddr edge))
                              "polymorphic recursion requires the same type parameters in declaration order"))))
       (analysis-calls analysis)))

    ;; ---- Applications and primitive contracts ----

    (define (analyze-call node environment path strict? expected analysis)
      (let* ((operands (ir:application-operands node))
             (arguments (map (lambda (operand) (analyze operand environment path strict? #f analysis)) operands))
             (operator (ir:application-operator node)))
        (if (and (ir:lambda? operator) (not (analysis-signature analysis operator))
                 (not (ir:lambda-opt-rest-parameter operator))
                 (= (length arguments) (length (ir:lambda-parameters operator))))
            (analyze-immediate-call operator arguments environment path strict? expected analysis)
            (call-result node (analyze operator environment path strict? #f analysis)
                         arguments strict? expected analysis))))

    (define (analyze-immediate-call procedure arguments environment path strict? expected analysis)
      (let* ((parameters (parameter-facts procedure #f arguments analysis))
             (body (analyze (ir:lambda-body procedure) (append parameters environment) path strict? expected analysis)))
        (record-fact! analysis procedure (value-fact 'Procedure))
        body))

    (define (call-result node operator arguments strict? expected analysis)
      (let ((type (fact-type operator)) (callee (fact-callee operator)))
        (if (and strict? (not (or (function-type? type) (memq type '(? Procedure Never)))))
            (type-error node type 'Procedure))
        (cond ((all-type? type)
               (call-result node (instantiate-fact operator
                                                   (call-type-arguments node operator arguments expected analysis) node)
                            arguments strict? expected analysis))
              ((symbol? callee) (primitive-result node callee arguments strict? analysis))
              ((or (arrow-type? type) (ir:lambda? callee) (instance? callee) (callees? callee))
               (checked-call-result node operator arguments strict? analysis))
              (else (unknown-fact)))))

    (define (call-type-arguments node operator arguments expected analysis)
      (if (eq? (fact-callee operator) (current-procedure))
          (all-variables (analysis-signature analysis (current-procedure)))
          (infer-type-arguments (fact-type operator) (map fact-type arguments) expected (node-location node))))

    (define (checked-call-result node operator arguments strict? analysis)
      (let* ((callee (fact-callee operator))
             (procedure (callee-procedure callee))
             (declared (and procedure (analysis-signature analysis procedure)))
             (signature (if (arrow-type? (fact-type operator)) (fact-type operator)
                            (and declared (type-erasure declared)))))
        (if (and (arrow-type? (fact-type operator)) (not callee))
            (type-error-at (node-location node) "function view requires a checked implementation before use"))
        (if (and strict? signature) (check-arguments node arguments (type-arguments signature)))
        (record-call! node callee (and (arrow-type? (fact-type operator)) #t) analysis)
        (if (and signature (not (and declared (arrow-type? declared))))
            (plan-call-guards! node arguments signature analysis))
        (if procedure (procedure-result procedure signature arguments analysis)
            (if signature (value-fact (type-result signature)) (unknown-fact)))))

    (define (callee-procedure callee)
      (cond ((ir:lambda? callee) callee)
            ((instance? callee) (callee-procedure (instance-callee callee)))
            (else #f)))

    (define (check-arguments node arguments expected)
      (if (not (= (length arguments) (length expected)))
          (type-error-at (node-location node) "typed call has wrong arity"))
      (for-each (lambda (argument type)
                  (if (not (type-compatible? (fact-type argument) type))
                      (type-error node (fact-type argument) type))) arguments expected))

    (define (primitive-result node name arguments strict? analysis)
      (let ((predicate (predicate-type name)) (count (length arguments)))
        (cond ((and predicate (= count 1)) (predicate-fact predicate (car arguments)))
              ((memq name '(%make-record %record?)) (record-result name arguments analysis))
              ((memq name '(+ - * / = < <= > >= quotient remainder modulo))
               (numeric-result node name arguments strict?))
              ((assq name primitive-contracts)
               => (lambda (contract)
                    (if strict? (check-arguments node arguments (cadr contract)))
                    ;; AWI can store callback result envelopes in pairs/vectors.
                    ;; A heap read has no independent ordinary-value guarantee.
                    (if (and (= count (length (cadr contract))) (not (eq? (caddr contract) '?)))
                        (value-fact (caddr contract)) (unknown-fact))))
              ((eq? name 'values) (if (= count 1) (car arguments) (unknown-fact)))
              ((eq? name 'error) (make-fact 'Never #f #f '() '() #f))
              (else (unknown-fact)))))

    (define (record-result name arguments analysis)
      (let ((descriptor (and (pair? arguments) (fact-object (car arguments)))))
        (if (and descriptor (assq descriptor (analysis-records analysis)))
            (let ((type (list 'record descriptor)))
              (if (and (eq? name '%record?) (= (length arguments) 2))
                  (predicate-fact type (cadr arguments)) (value-fact type)))
            (unknown-fact))))

    (define (numeric-result node name arguments strict?)
      (let ((required (if (memq name '(quotient remainder modulo)) 'ExactInteger 'Number)))
        (if strict? (check-arguments node arguments (map (lambda (argument) required) arguments)))
        (cond ((memq name '(= < <= > >=)) (value-fact 'Boolean))
              ((or (memq name '(quotient remainder modulo))
                   (and (not (eq? name '/))
                        (every? (lambda (fact) (type-subtype? (fact-type fact) 'ExactInteger)) arguments)))
               (value-fact 'ExactInteger))
              (else (value-fact 'Number)))))

    (define primitive-contracts
      '((cons (Any Any) Pair) (car (Pair) ?) (cdr (Pair) ?)
        (eq? (Any Any) Boolean) (eqv? (Any Any) Boolean)
        (string-length (String) ExactInteger) (vector-length (Vector) ExactInteger)
        (bytevector-length (Bytevector) ExactInteger)
        (string-ref (String ExactInteger) Char) (vector-ref (Vector ExactInteger) ?)
        (bytevector-u8-ref (Bytevector ExactInteger) ExactInteger)
        (set-car! (Pair Any) Unspecified) (set-cdr! (Pair Any) Unspecified)
        (vector-set! (Vector ExactInteger Any) Unspecified)
        (string->symbol (String) Symbol) (symbol->string (Symbol) String)
        (char->integer (Char) ExactInteger) (integer->char (ExactInteger) Char))))

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-type-analysis)
    (import (snail-scheme test-utils))
    (begin
      (define (test-fact-identity)
        (let ((analysis (analyze-types '() '()))
              (first (ir:make-literal 1 #f)) (second (ir:make-literal 1 #f)))
          (record-fact! analysis first (value-fact 'ExactInteger))
          (expect (fact-type (analysis-fact analysis first)) 'ExactInteger)
          (expect (fact-type (analysis-fact analysis second)) '?)
          (let ((earlier (analysis-facts analysis)))
            (record-fact! analysis first (unknown-fact))
            (expect (fact-type (analysis-fact analysis first)) '?)
            (expect (fact-type (identity-map-ref earlier first #f)) 'ExactInteger))
          (expect (cdr (assq 'expressions (analysis-statistics analysis))) 2)))

      (define (test-type-analysis)
        (run-test test-fact-identity)
        (let ((first (ir:make-value-definition 'same-name #f))
              (second (ir:make-value-definition 'same-name #f)))
          (expect (common-filters (list (list first #t 'String)) (list (list second #t 'String))) '()))
        (expect (narrow '(U String ExactInteger) 'x '((x #t String))) 'String)
        (expect (narrow '(U String ExactInteger) 'x '((x #f String))) 'ExactInteger)
        (expect (narrow '? #f '((x #t String))) '?)
        (expect (common-filters '((x #t String)) '((y #t String))) '())
        (expect (predicate-type 'integer?) #f))))))

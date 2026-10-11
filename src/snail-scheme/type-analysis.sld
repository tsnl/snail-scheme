;; Pure type rules over resolved binding identities. The visitor supplies child
;; facts and consumes the returned evidence immediately; no expression is indexed.
;; Facts describe values after their explicit guards have executed.
(define-library (snail-scheme type-analysis)
  (export prepare-types make-type-scope scope-strict? strict-scope binding-type
          bind-fact branch-scope procedure-scope procedure-signature
          infer-literal infer-name infer-procedure infer-conditional infer-instantiation
          infer-call check-result check-recursive-instances validate-type
          checked-fact checked-guard call-fact call-guards call-edges
          value-fact unknown-fact normalized-fact fact-type fact-single? fact-callee
          fact-signature fact-body typing-declarations typing-primitives typing-assigned typing-bindings
          type-optimizations-enabled predicate-type)
  (import (scheme base) (scheme cxr)
          (snail-scheme types) (snail-scheme type-inference)
          (prefix (snail-scheme ir) ir:))
  (begin
    ;; ---- Transient evidence and immutable scopes ----

    (define type-optimizations-enabled (make-parameter #t))
    (define-record-type <instance>
      (make-instance callee types) instance?
      (callee instance-callee) (types instance-types))
    (define-record-type <callees>
      (make-callees members) callees? (members callees-members))
    (define-record-type <procedure>
      (make-procedure node signature result) procedure-fact?
      (node procedure-node) (signature callable-signature) (result procedure-result-fact))
    (define-record-type <fact>
      (make-fact type single? object yes no callee) fact?
      (type fact-type) (single? fact-single?) (object fact-object)
      (yes fact-yes) (no fact-no) (callee fact-callee))
    (define-record-type <checked>
      (make-checked fact guard) checked?
      (fact checked-fact) (guard checked-guard))
    (define-record-type <call>
      (make-call fact guards edges) call?
      (fact call-fact) (guards call-guards) (edges call-edges))

    (define (value-fact type) (make-fact type #t #f '() '() #f))
    (define (unknown-fact) (make-fact '? #f #f '() '() #f))
    (define (normalized-fact fact)
      (make-fact (fact-type fact) #t (fact-object fact)
                 (fact-yes fact) (fact-no fact) (fact-callee fact)))
    (define (entry-value key entries default)
      (let ((entry (assq key entries))) (if entry (cdr entry) default)))

    ;; The declaration scan records syntax and binding properties only. Scope
    ;; extensions share it, and add checked contracts under binding identities.
    (define-record-type <typing>
      (make-typing declarations primitives assigned bindings records) typing?
      (declarations typing-declarations) (primitives typing-primitives)
      (assigned typing-assigned) (bindings typing-bindings) (records typing-records))
    (define-record-type <scope>
      (make-scope typing declarations environment path strict? procedure) scope?
      (typing scope-typing) (declarations scope-declarations)
      (environment scope-environment) (path scope-path)
      (strict? scope-strict?) (procedure scope-procedure))

    (define (make-type-scope typing)
      (make-scope typing (typing-declarations typing) '() '() #f #f))
    (define (strict-scope scope)
      (make-scope (scope-typing scope) (scope-declarations scope) (scope-environment scope)
                  (scope-path scope) #t (scope-procedure scope)))
    (define (binding-type definition scope)
      (entry-value definition (scope-declarations scope) #f))
    (define (bind-fact definition fact scope)
      (make-scope (scope-typing scope) (scope-declarations scope)
                  (cons (cons definition (normalized-fact fact)) (scope-environment scope))
                  (scope-path scope) (scope-strict? scope) (scope-procedure scope)))
    (define (branch-scope scope test truth?)
      (make-scope (scope-typing scope) (scope-declarations scope) (scope-environment scope)
                  (combine-filters (scope-path scope) (truth-filters test truth?))
                  (scope-strict? scope) (scope-procedure scope)))

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

    (define (prepare-types items primitives)
      (let* ((nodes (all-nodes items))
             (assigned (map (lambda (node) (ir:name-definition (ir:assignment-target node)))
                            (select ir:assignment? nodes)))
             (bindings (map (lambda (node) (cons (ir:value-binding-definition node)
                                                 (ir:value-binding-initializer node)))
                            (select ir:value-binding? nodes)))
             (primitives (immutable-primitives primitives assigned bindings))
             (base (make-typing '() primitives assigned bindings '()))
             (records (register-records (select ir:record-schema? nodes) items base))
             (typing (make-typing '() primitives assigned bindings records)))
        (declare-types (append (record-declarations (select ir:record-schema? nodes))
                               (select ir:type-declaration? nodes)) typing)))

    ;; Every consumer uses this same stability decision. Resolved local names
    ;; have distinct identities; an import alias can still write the core one.
    (define (immutable-primitives primitives assigned bindings)
      (select (lambda (definition)
                (not (or (memq definition assigned) (assq definition bindings)))) primitives))

    (define (declare-types nodes typing)
      (if (null? nodes) typing
          (let* ((node (car nodes)) (definition (ir:type-declaration-definition node))
                 (type (ir:type-declaration-type node)))
            (check-declaration node typing)
            (declare-types (cdr nodes)
                           (make-typing (cons (cons definition type) (typing-declarations typing))
                                        (typing-primitives typing) (typing-assigned typing)
                                        (typing-bindings typing) (typing-records typing))))))

    (define (check-declaration node typing)
      (let* ((definition (ir:type-declaration-definition node)) (type (ir:type-declaration-type node))
             (initializer (entry-value definition (typing-bindings typing) #f)))
        (validate-type type typing (ir:type-declaration-loc node))
        (if (or (not initializer) (assq definition (typing-declarations typing)))
            (type-error-at (ir:type-declaration-loc node) "type declaration requires one local definition"))
        (if (function-type? type)
            (begin
              (if (memq definition (typing-assigned typing))
                  (type-error-at (ir:type-declaration-loc node) "cannot assign a function signature"))
              (if (ir:lambda? initializer) (check-lambda initializer type))))))

    (define (check-lambda node type)
      (if (not (and (not (ir:lambda-opt-rest-parameter node))
                    (= (length (ir:lambda-parameters node)) (length (type-arguments (all-body type))))))
          (type-error-at (node-location node) "function annotation requires a fixed-arity lambda of matching arity" type)))

    (define (every? predicate items)
      (or (null? items) (and (predicate (car items)) (every? predicate (cdr items)))))

    ;; ---- Nominal record schemas ----

    (define (typed-record? node)
      (not (every? (lambda (field) (eq? (cadr field) '?)) (ir:record-schema-fields node))))

    (define (register-records nodes items typing)
      (if (null? nodes) '()
          (let* ((node (car nodes)) (definition (ir:record-schema-definition node))
                 (stable? (and (memq node items) (not (memq definition (typing-assigned typing)))
                               (fresh-record-descriptor? definition typing))))
            (if (and (not stable?) (typed-record? node))
                (type-error-at (ir:record-schema-loc node) "typed records require a stable top-level descriptor"))
            (append (if stable? (list (cons definition node)) '())
                    (register-records (cdr nodes) items typing)))))

    ;; Metadata alone cannot certify fresh nominal identity: even a manually
    ;; supplied core schema must name an actual, immutable descriptor allocation.
    (define (fresh-record-descriptor? definition typing)
      (let* ((initializer (entry-value definition (typing-bindings typing) #f))
             (operator (and (ir:application? initializer) (ir:application-operator initializer))))
        (and (ir:name? operator)
             (memq (ir:name-definition operator) (typing-primitives typing))
             (eq? (ir:value-definition-name (ir:name-definition operator)) '%make-record-type))))

    (define (validate-type type context loc)
      (let ((typing (if (scope? context) (scope-typing context) context)))
        (validate-declared-type type typing loc)))

    (define (validate-declared-type type typing loc)
      (if (not (or (shallow-type? type) (function-type? type)))
          (type-error-at loc "annotations require a shallow type or a checked function signature" type))
      (cond ((nominal-type? type)
             (if (not (assq (cadr type) (typing-records typing)))
                 (type-error-at loc "nominal type requires a stable top-level record declaration" type)))
            ((function-type? type)
             (if (not (every? shallow-type? (cdr (all-body type))))
                 (type-error-at loc "function domains and results must be shallow types; nested All and arrows are unsupported" type))
             (for-each (lambda (part) (validate-type part typing loc)) (cdr (all-body type))))
            ((union-type? type) (for-each (lambda (part) (validate-type part typing loc)) (cdr type)))))

    (define (generated-declaration definition type)
      (ir:make-type-declaration definition type (ir:value-definition-loc definition)))

    (define (record-argument-type name node)
      (let ((field (assq name (ir:record-schema-fields node))))
        (if field (cadr field) (error "record constructor argument is not a field" name))))

    (define (record-declarations nodes)
      (apply append (map record-declaration nodes)))

    (define (record-declaration node)
      (if (not (typed-record? node)) '()
          (let ((type (list 'record (ir:record-schema-definition node))))
            (append
             (list (generated-declaration (ir:record-schema-constructor node)
                                          (append '(->) (map (lambda (name) (record-argument-type name node))
                                                             (ir:record-schema-arguments node)) (list type)))
                   (generated-declaration (ir:record-schema-predicate node) '(-> Any Boolean)))
             (apply append (map (lambda (field) (record-field-declarations field node type))
                                (ir:record-schema-fields node)))))))

    (define (record-field-declarations field node type)
      (if (and (not (eq? (cadr field) '?)) (not (memq (car field) (ir:record-schema-arguments node))))
          (error "typed record field must be initialized by its constructor" (car field)))
      (cons (generated-declaration (caddr field) (list '-> type (cadr field)))
            (if (cadddr field) (list (generated-declaration (cadddr field) (list '-> type (cadr field) 'Unspecified))) '())))

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

    (define (infer-name node scope)
      (let* ((definition (ir:name-definition node))
             (base (binding-fact definition scope))
             (stable? (not (memq definition (typing-assigned (scope-typing scope)))))
             (object (and stable? (or (fact-object base) definition)))
             (type (narrow (fact-type base) object (scope-path scope))))
        (make-fact type (fact-single? base) object
                   (if stable? (fact-yes base) '()) (if stable? (fact-no base) '())
                   (and stable? (fact-callee base)))))

    (define (binding-fact definition scope)
      (let ((declared (binding-type definition scope))
            (entry (assq definition (scope-environment scope)))
            (typing (scope-typing scope)))
        (cond ((memq definition (typing-assigned typing))
               (make-fact (or declared '?) (if entry (fact-single? (cdr entry)) #t) #f '() '() #f))
              (entry (cdr entry))
              ((memq definition (typing-primitives typing))
               (make-fact 'Procedure #t #f '() '() (ir:value-definition-name definition)))
              (else (make-fact (or declared '?) #t #f '() '() (binding-callee definition '() scope))))))

    ;; Forward aliases reveal declared implementations, never a body proof or
    ;; initialization guarantee. Only a visited binding publishes a summary.
    (define (binding-callee definition visited scope)
      (and (not (memq definition visited))
           (not (memq definition (typing-assigned (scope-typing scope))))
           (initializer-callee (entry-value definition (typing-bindings (scope-typing scope)) #f)
                               (binding-type definition scope) (cons definition visited) scope)))

    (define (initializer-callee node expected visited scope)
      (cond ((ir:lambda? node) (make-procedure node (and (function-type? expected) expected) (unknown-fact)))
            ((ir:name? node) (callee-view (binding-callee (ir:name-definition node) visited scope)
                                          expected (ir:name-loc node)))
            ((ir:instantiation? node)
             (let ((callee (initializer-callee (ir:instantiation-expression node) #f visited scope)))
               (and callee (make-instance callee (ir:instantiation-types node)))))
            ((ir:annotation? node)
             (callee-view (initializer-callee (ir:annotation-expression node) (ir:annotation-type node) visited scope)
                          (ir:annotation-type node) (ir:annotation-loc node)))
            ((ir:block? node)
             (let ((items (ir:block-items node)))
               (and (pair? items) (initializer-callee (car (reverse items)) expected visited scope))))
            ((ir:conditional? node)
             (let ((yes (initializer-callee (ir:conditional-consequent node) expected visited scope))
                   (no (initializer-callee (ir:conditional-opt-alternate node) expected visited scope)))
               (and yes no (make-callees (list yes no)))))
            (else #f)))

    (define (callee-view callee type loc)
      (cond ((callees? callee)
             (make-callees (map (lambda (member) (callee-view member type loc)) (callees-members callee))))
            ((and (arrow-type? type) (procedure-fact? callee) (all-type? (callable-signature callee)))
             (make-instance callee (infer-type-arguments (callable-signature callee)
                                                         (type-arguments type) (type-result type) loc)))
            (else callee)))

    (define (truth-filters fact truth?)
      (let ((filters ((if truth? fact-yes fact-no) fact)) (object (fact-object fact)))
        (if object (combine-filters filters (list (list object (not truth?) 'False))) filters)))

    (define (predicate-type name)
      (case name
        ((exact-integer?) 'ExactInteger) ((number?) 'Number)
        ((boolean?) 'Boolean) ((string?) 'String) ((symbol?) 'Symbol) ((char?) 'Char)
        ((pair?) 'Pair) ((null?) 'Null) ((vector?) 'Vector) ((bytevector?) 'Bytevector)
        ((procedure?) 'Procedure) (else #f)))

    (define (predicate-fact type argument)
      (let ((object (fact-object argument)))
        (make-fact 'Boolean #t #f (if object (list (list object #t type)) '())
                   (if object (list (list object #f type)) '()) #f)))

    ;; These predicates admit some complex representations. Their true arm
    ;; proves Number; their false arm cannot exclude all numbers.
    (define (numeric-predicate-fact argument)
      (let ((object (fact-object argument)))
        (make-fact 'Boolean #t #f (if object (list (list object #t 'Number)) '()) '() #f)))

    ;; ---- Local checking rules ----

    (define (infer-literal node) (value-fact (literal-type (ir:literal-value node))))

    ;; Return the required guard separately from its postcondition. The visitor
    ;; lowers this guard before letting a parent consume the outgoing fact.
    (define (check-result node fact expected)
      (let ((actual (fact-type fact)))
        (cond ((not expected) (make-checked fact #f))
              ((and (arrow-type? expected) (all-type? actual))
               (check-result node (instantiate-fact fact
                                                    (infer-type-arguments actual (type-arguments expected) (type-result expected)
                                                                          (node-location node)) node) expected))
              ((function-type? expected)
               (if (not (type-equal? actual expected))
                   (type-error-at (node-location node) "unsupported opaque function annotation" expected))
               (make-checked fact #f))
              ((not (or (type-compatible? actual expected) (and (ir:annotation? node) (eq? actual 'Any))))
               (type-error node actual expected))
              (else (checked-value node fact expected)))))

    (define (checked-value node fact expected)
      (let* ((actual (fact-type fact))
             (guard (and (or (not (fact-single? fact))
                             (and (not (memq expected '(Any ?))) (not (type-subtype? actual expected))))
                         (if (type-subtype? actual expected) 'Any expected))))
        (if guard (require-runtime-type guard node))
        (make-checked (make-fact (if (eq? expected '?) actual expected) #t (fact-object fact)
                                 (fact-yes fact) (fact-no fact) (fact-callee fact)) guard)))

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

    (define (infer-conditional test yes no)
      (let ((yes-path (truth-filters test #t)) (no-path (truth-filters test #f)))
        (make-fact (joined-type yes no) (and (fact-single? yes) (fact-single? no)) #f
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

    ;; ---- Procedures and verified binding contracts ----

    (define (procedure-signature node expected scope)
      (let ((signature (and (function-type? expected) expected)))
        (if signature
            (begin (validate-type signature scope (node-location node)) (check-lambda node signature)))
        signature))

    (define (procedure-scope node signature arguments scope)
      (let* ((parameters (ir:lambda-parameters node))
             (types (if signature (type-arguments (all-body signature)) (map (lambda (parameter) '?) parameters)))
             (facts (or arguments (map (lambda (type) (if signature (value-fact type) (unknown-fact))) types))))
        (make-scope (scope-typing scope)
                    (append (if signature (map cons parameters types) '()) (scope-declarations scope))
                    (append (map cons parameters (if arguments (map normalized-fact facts) facts)) (scope-environment scope))
                    (scope-path scope) (if arguments (scope-strict? scope) (and signature #t))
                    (if arguments (scope-procedure scope) (make-procedure node signature (unknown-fact))))))

    (define (infer-procedure node signature body)
      (make-fact (or signature 'Procedure) #t #f '() '() (make-procedure node signature body)))

    (define (substitute-filters filters parameters arguments)
      (apply append
             (map (lambda (filter)
                    (let loop ((parameters parameters) (arguments arguments))
                      (cond ((null? parameters) '())
                            ((eq? (car filter) (car parameters))
                             (let ((object (fact-object (car arguments))))
                               (if object (list (cons object (cdr filter))) '())))
                            (else (loop (cdr parameters) (cdr arguments)))))) filters)))

    (define (procedure-result procedure signature arguments)
      (let ((body (procedure-result-fact procedure))
            (parameters (ir:lambda-parameters (procedure-node procedure))))
        (if (not (= (length parameters) (length arguments))) (unknown-fact)
            (make-fact (if signature (type-result signature)
                           (if (function-type? (fact-type body)) 'Procedure (fact-type body)))
                       (or (and signature #t) (fact-single? body)) #f
                       (substitute-filters (fact-yes body) parameters arguments)
                       (substitute-filters (fact-no body) parameters arguments) #f))))

    ;; ---- Instantiated callable views ----

    (define (infer-instantiation node fact scope)
      (for-each (lambda (type)
                  (if (not (runtime-type? type))
                      (type-error-at (node-location node) "type arguments must be shallow types" type))
                  (validate-type type scope (node-location node))) (ir:instantiation-types node))
      (instantiate-fact fact (ir:instantiation-types node) node))

    (define (instantiate-fact fact types node)
      (if (not (every? shallow-type? types))
          (type-error-at (node-location node) "type arguments must be shallow types"))
      (let ((signature (instantiate-type (fact-type fact) types (node-location node))))
        (if (not (fact-callee fact))
            (type-error-at (node-location node) "inst requires a checked implementation"))
        (make-fact signature #t (fact-object fact) '() '() (make-instance (fact-callee fact) types))))

    ;; Operands and then the operator execute before call-boundary guards.
    (define (argument-guards node arguments signature)
      (if (not (= (length arguments) (length (type-arguments signature)))) '()
          (map (lambda (argument type)
                 (cond ((memq type '(? Any)) #f) ((runtime-type? type) type)
                       ((type-subtype? (fact-type argument) type) #f)
                       (else (require-runtime-type type node)))) arguments (type-arguments signature))))

    ;; ---- Recursive instantiation ----

    ;; Edges are output obligations, not expression evidence. Carry the caller's
    ;; declared signature so the completed graph needs no lambda->type table.
    (define (call-relationships node callee viewed? caller)
      (define (edges callee types)
        (cond ((instance? callee) (edges (instance-callee callee) (and viewed? (instance-types callee))))
              ((callees? callee) (apply append (map (lambda (member) (edges member types)) (callees-members callee))))
              ((and (procedure-fact? callee) caller (or types (not (all-type? (callable-signature callee)))))
               (list (list (procedure-node caller) (procedure-node callee) types node (callable-signature caller))))
              (else '())))
      (edges callee #f))

    (define (calls-reach? from target edges visited)
      (and (not (memq from visited))
           (or (eq? from target)
               (let loop ((edges-left edges))
                 (and (pair? edges-left)
                      (or (and (eq? from (caar edges-left))
                               (calls-reach? (cadar edges-left) target edges (cons from visited)))
                          (loop (cdr edges-left))))))))

    (define (check-recursive-instances edges)
      (for-each
       (lambda (edge)
         (let ((signature (car (cddddr edge))))
           (if (and (caddr edge) (calls-reach? (cadr edge) (car edge) edges '())
                    (not (and (all-type? signature) (type-equal? (caddr edge) (all-variables signature)))))
               (type-error-at (node-location (cadddr edge))
                              "polymorphic recursion requires the same type parameters in declaration order")))) edges))

    ;; ---- Applications and primitive contracts ----

    (define (infer-call node operator arguments expected scope)
      (let ((type (fact-type operator)) (callee (fact-callee operator)))
        (if (and (scope-strict? scope) (not (or (function-type? type) (memq type '(? Procedure Never)))))
            (type-error node type 'Procedure))
        (cond ((all-type? type)
               (infer-call node (instantiate-fact operator (call-type-arguments node operator arguments expected scope) node)
                           arguments expected scope))
              ((symbol? callee) (make-call (primitive-result node callee arguments scope) '() '()))
              ((or (arrow-type? type) (procedure-fact? callee) (instance? callee) (callees? callee))
               (checked-call-result node operator arguments scope))
              (else (make-call (unknown-fact) '() '())))))

    (define (call-type-arguments node operator arguments expected scope)
      (let ((callee (callee-procedure (fact-callee operator))) (caller (scope-procedure scope)))
        (if (and caller callee (eq? (procedure-node callee) (procedure-node caller)))
            (all-variables (callable-signature caller))
            (infer-type-arguments (fact-type operator) (map fact-type arguments) expected (node-location node)))))

    (define (checked-call-result node operator arguments scope)
      (let* ((callee (fact-callee operator)) (procedure (callee-procedure callee))
             (declared (and procedure (callable-signature procedure)))
             (signature (if (arrow-type? (fact-type operator)) (fact-type operator) (and declared (type-erasure declared)))))
        (if (and (arrow-type? (fact-type operator)) (not callee))
            (type-error-at (node-location node) "function view requires a checked implementation before use"))
        (if (and (scope-strict? scope) signature) (check-arguments node arguments (type-arguments signature)))
        (make-call (if procedure (procedure-result procedure signature arguments)
                       (if signature (value-fact (type-result signature)) (unknown-fact)))
                   (if (and signature (not (and declared (arrow-type? declared)))) (argument-guards node arguments signature) '())
                   (call-relationships node callee (and (arrow-type? (fact-type operator)) #t) (scope-procedure scope)))))

    (define (callee-procedure callee)
      (cond ((procedure-fact? callee) callee)
            ((instance? callee) (callee-procedure (instance-callee callee))) (else #f)))

    (define (fact-signature fact)
      (let ((procedure (callee-procedure (fact-callee fact))))
        (and procedure (callable-signature procedure))))

    (define (fact-body fact)
      (procedure-result-fact (callee-procedure (fact-callee fact))))

    (define (check-arguments node arguments expected)
      (if (not (= (length arguments) (length expected)))
          (type-error-at (node-location node) "typed call has wrong arity"))
      (for-each (lambda (argument type)
                  (if (not (type-compatible? (fact-type argument) type))
                      (type-error node (fact-type argument) type))) arguments expected))

    (define (primitive-result node name arguments scope)
      (let ((predicate (predicate-type name)) (count (length arguments)))
        (cond ((and predicate (= count 1)) (predicate-fact predicate (car arguments)))
              ((and (= count 1) (memq name '(real? inexact? exact? integer?)))
               (numeric-predicate-fact (car arguments)))
              ((memq name '(%make-record %record?)) (record-result name arguments (scope-typing scope)))
              ((memq name '(+ - * / = < <= > >= quotient remainder modulo))
               (numeric-result node name arguments (scope-strict? scope)))
              ((assq name primitive-contracts)
               => (lambda (contract)
                    (if (scope-strict? scope) (check-arguments node arguments (cadr contract)))
                    ;; AWI can store callback result envelopes in pairs/vectors.
                    ;; A heap read has no independent ordinary-value guarantee.
                    (if (and (= count (length (cadr contract))) (not (eq? (caddr contract) '?)))
                        (value-fact (caddr contract)) (unknown-fact))))
              ((eq? name 'values) (if (= count 1) (car arguments) (unknown-fact)))
              ((eq? name 'error) (make-fact 'Never #f #f '() '() #f))
              (else (unknown-fact)))))

    (define (record-result name arguments typing)
      (let ((descriptor (and (pair? arguments) (fact-object (car arguments)))))
        (if (and descriptor (assq descriptor (typing-records typing)))
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
      (define (test-scoped-facts)
        (let* ((definition (ir:make-value-definition 'x #f)) (name (ir:make-name definition #f))
               (scope (make-type-scope (prepare-types '() '())))
               (extended (bind-fact definition (value-fact '(U String ExactInteger)) scope))
               (test (predicate-fact 'String (infer-name name extended))))
          (expect (fact-type (infer-name name scope)) '?)
          (expect (fact-type (infer-name name (branch-scope extended test #t))) 'String)
          (expect (fact-type (infer-name name (branch-scope extended test #f))) 'ExactInteger)
          (expect (fact-type (infer-name name extended)) '(U String ExactInteger))))

      (define (test-guard-evidence)
        (let* ((node (ir:make-literal 1 #f)) (incoming (unknown-fact))
               (checked (check-result node incoming 'ExactInteger)))
          (expect (checked-guard checked) 'ExactInteger)
          (expect (fact-single? (checked-fact checked)) #t)
          (expect (fact-type (checked-fact checked)) 'ExactInteger)
          (expect (fact-single? incoming) #f)
          (expect (checked-guard (check-result node (checked-fact checked) 'ExactInteger)) #f)))

      (define (test-primitive-stability)
        (let* ((plus (ir:make-value-definition '+ #f))
               (shadow (ir:make-value-definition '+ #f))
               (name (ir:make-name plus #f))
               (assignment (ir:make-assignment name (ir:make-literal 42 #f) #f))
               (nested (ir:make-lambda '() #f assignment #f))
               (binding (ir:make-value-binding plus (ir:make-literal 42 #f) #f)))
          (expect (typing-primitives (prepare-types (list nested) (list plus))) '())
          (expect (typing-primitives (prepare-types (list binding) (list plus))) '())
          (let ((scope (bind-fact shadow (value-fact 'String)
                                  (make-type-scope (prepare-types '() (list plus))))))
            (expect (fact-type (infer-name name scope)) 'Procedure)
            (expect (fact-type (infer-name (ir:make-name shadow #f) scope)) 'String))))

      (define (test-type-analysis)
        (run-test test-scoped-facts)
        (run-test test-guard-evidence)
        (run-test test-primitive-stability)
        (let ((first (ir:make-value-definition 'same-name #f))
              (second (ir:make-value-definition 'same-name #f)))
          (expect (common-filters (list (list first #t 'String)) (list (list second #t 'String))) '()))
        (expect (narrow '(U String ExactInteger) 'x '((x #t String))) 'String)
        (expect (narrow '(U String ExactInteger) 'x '((x #f String))) 'ExactInteger)
        (expect (narrow '? #f '((x #t String))) '?)
        (expect (common-filters '((x #t String)) '((y #t String))) '())
        (expect (predicate-type 'integer?) #f))))))

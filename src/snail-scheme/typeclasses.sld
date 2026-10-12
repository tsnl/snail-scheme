;; Elaborate static interfaces into checked ordinary functions. Instances are
;; compilation data only; no dictionaries or runtime overload selection exist.
(define-library (snail-scheme typeclasses)
  (export elaborate-typeclasses)
  (import (scheme base) (scheme cxr) (snail-scheme types)
          (snail-scheme type-analysis)
          (prefix (snail-scheme ir) ir:) (prefix (snail-scheme library) library:))
  (begin

    ;; ---- Declaration and specialization state ----

    (define-record-type <method>
      (make-method definition class prototype signature) method?
      (definition method-definition) (class method-class)
      (prototype method-prototype) (signature method-signature))
    (define-record-type <instance>
      (make-instance source class types members items) instance?
      (source instance-source) (class instance-class) (types instance-types)
      (members instance-members) (items instance-items))
    (define-record-type <template>
      (make-template definition procedure signature) template?
      (definition template-definition) (procedure template-procedure) (signature template-signature))
    (define-record-type <specialization>
      (make-specialization template types definition body) specialization?
      (template specialization-template) (types specialization-types)
      (definition specialization-definition) (body specialization-body set-specialization-body!))
    (define-record-type <state>
      (make-state classes methods instances bindings declarations assigned extras analysis templates aliases specializations)
      state?
      (classes state-classes) (methods state-methods set-state-methods!)
      (instances state-instances set-state-instances!) (bindings state-bindings)
      (declarations state-declarations) (assigned state-assigned)
      (extras state-extras set-state-extras!) (analysis state-analysis set-state-analysis!)
      (templates state-templates set-state-templates!) (aliases state-aliases set-state-aliases!)
      (specializations state-specializations set-state-specializations!))

    (define current-state (make-parameter #f))
    (define (state) (current-state))
    (define (find predicate items)
      (and (pair? items) (if (predicate (car items)) (car items) (find predicate (cdr items)))))
    (define (select predicate items)
      (cond ((null? items) '()) ((predicate (car items)) (cons (car items) (select predicate (cdr items))))
            (else (select predicate (cdr items)))))
    (define (every? predicate items)
      (or (null? items) (and (predicate (car items)) (every? predicate (cdr items)))))
    (define (entry-value key entries) (let ((entry (assq key entries))) (and entry (cdr entry))))
    (define (located-error node message . details)
      (apply type-error-at (location node) message details))

    (define (location node)
      (cond ((ir:name? node) (ir:name-loc node)) ((ir:lambda? node) (ir:lambda-loc node))
            ((ir:assignment? node) (ir:assignment-loc node))
            ((ir:value-binding? node) (ir:value-binding-loc node))
            ((ir:type-declaration? node) (ir:type-declaration-loc node))
            ((ir:class-declaration? node) (ir:class-declaration-loc node))
            ((ir:instance-declaration? node) (ir:instance-declaration-loc node))
            ((ir:application? node) (ir:application-loc node))
            ((ir:annotation? node) (ir:annotation-loc node))
            ((ir:instantiation? node) (ir:instantiation-loc node)) (else #f)))

    (define (children node)
      (cond ((ir:lambda? node) (list (ir:lambda-body node)))
            ((ir:instance-declaration? node) (map cdr (ir:instance-declaration-methods node)))
            ((ir:block? node) (ir:block-items node))
            ((ir:value-binding? node) (list (ir:value-binding-initializer node)))
            ((ir:assignment? node) (list (ir:assignment-value node)))
            ((ir:application? node) (cons (ir:application-operator node) (ir:application-operands node)))
            ((ir:conditional? node)
             (append (list (ir:conditional-test node) (ir:conditional-consequent node))
                     (if (ir:conditional-opt-alternate node) (list (ir:conditional-opt-alternate node)) '())))
            ((ir:annotation? node) (list (ir:annotation-expression node)))
            ((ir:instantiation? node) (list (ir:instantiation-expression node))) (else '())))

    (define (nodes items)
      (apply append (map (lambda (node) (cons node (nodes (children node)))) items)))
    (define (class-node? node) (or (ir:class-declaration? node) (ir:instance-declaration? node)))
    (define (qualified-declaration? node)
      (and (ir:type-declaration? node) (constrained-type? (ir:type-declaration-type node))))

    ;; ---- Whole-program preparation ----

    (define (elaborate-typeclasses libraries primitives)
      (let* ((items (apply append (map library:library-body libraries))) (all (nodes items)))
        (if (not (find (lambda (node) (or (class-node? node) (qualified-declaration? node))) all)) libraries
            (parameterize ((current-state (initial-state items all)))
              (require-top-level-classes items all)
              (prepare-classes!)
              (prepare-instances! items)
              (analyze-program! items primitives)
              (prepare-templates! items)
              (validate-program items)
              (let ((rewritten (map rewrite-library libraries)))
                (let ((final (map materialize-library rewritten)))
                  (validate-erasure final)
                  final))))))

    (define (initial-state items all)
      (make-state (select ir:class-declaration? items) '() '()
                  (map (lambda (node) (cons (ir:value-binding-definition node)
                                            (ir:value-binding-initializer node))) (select ir:value-binding? items))
                  (map (lambda (node) (cons (ir:type-declaration-definition node)
                                            (ir:type-declaration-type node))) (select ir:type-declaration? all))
                  (map (lambda (node) (ir:name-definition (ir:assignment-target node))) (select ir:assignment? all))
                  '() #f '() '() '()))

    (define (require-top-level-classes items all)
      (for-each (lambda (node)
                  (if (and (class-node? node) (not (memq node items)))
                      (located-error node "classes and instances require module scope"))) all))

    (define (class-for definition node)
      (or (find (lambda (class) (eq? definition (ir:class-declaration-definition class))) (state-classes (state)))
          (located-error node "unknown typeclass" definition)))

    (define (class-definition? definition)
      (find (lambda (class) (eq? definition (ir:class-declaration-definition class))) (state-classes (state))))

    (define (class-constraint class types)
      (cons (ir:class-declaration-definition class) types))

    (define (prepare-classes!)
      (for-each
       (lambda (class)
         (for-each (lambda (row) (register-method! class row)) (ir:class-declaration-methods class)))
       (state-classes (state))))

    ;; An abstract prototype lets the checker verify generic bodies under the
    ;; class contract. Its literal body is a placeholder, never analyzed or emitted.
    (define (register-method! class row)
      (let* ((variables (ir:class-declaration-variables class)) (signature (cadr row))
             (loc (ir:class-declaration-loc class))
             (parameters (map (lambda (type) (ir:make-value-definition 'argument loc)) (type-arguments signature)))
             (body (ir:make-literal #f loc))
             (prototype (ir:make-lambda parameters #f body loc))
             (scheme (list 'All variables (list '=> (list (class-constraint class variables)) signature))))
        (set-state-methods! (state) (cons (make-method (car row) class prototype scheme) (state-methods (state))))))

    (define (method-for-procedure procedure)
      (find (lambda (method) (eq? procedure (method-prototype method))) (state-methods (state))))
    (define (method-for-definition definition)
      (find (lambda (method) (eq? definition (method-definition method))) (state-methods (state))))

    (define (concrete-head? type)
      (or (nominal-type? type) (and (symbol? type) (memq type scalar-type-names) (not (memq type '(? Never))))))

    (define (check-constraint constraint node)
      (let ((class (class-for (car constraint) node)))
        (if (not (= (length (cdr constraint)) (length (ir:class-declaration-variables class))))
            (located-error node "wrong number of typeclass arguments" constraint))
        class))

    (define (prepare-instances! items)
      (for-each prepare-instance! (select ir:instance-declaration? items)))

    (define (prepare-instance! node)
      (let* ((class (check-constraint (cons (ir:instance-declaration-class node) (ir:instance-declaration-types node)) node))
             (types (ir:instance-declaration-types node)) (rows (ir:instance-declaration-methods node)))
        (if (not (every? concrete-head? types)) (located-error node "instance heads require concrete scalar or nominal types"))
        (if (find-instance class types) (located-error node "duplicate typeclass instance" (class-constraint class types)))
        (check-instance-members class rows node)
        (let* ((members (map (lambda (method) (prepare-member class method types (cdr (assq (car method) rows)) node))
                             (ir:class-declaration-methods class)))
               (instance (make-instance node class types (map car members) (apply append (map cdr members)))))
          (set-state-instances! (state) (cons instance (state-instances (state)))))))

    (define (check-instance-members class rows node)
      (let ((names (map car rows)) (required (map car (ir:class-declaration-methods class))))
        (if (or (not (= (length names) (length required)))
                (not (every? (lambda (name) (memq name names)) required))
                (find (lambda (name) (> (length (select (lambda (other) (eq? name other)) names)) 1)) names))
            (located-error node "instance must implement every class method exactly once"))))

    (define (member-signature class row types)
      (type-substitute (cadr row) (map cons (ir:class-declaration-variables class) types)))

    (define (prepare-member class row types expression node)
      (let ((signature (member-signature class row types)))
        (cond ((ir:lambda? expression)
               (let* ((definition (ir:make-value-definition (ir:value-definition-name (car row)) (location node)))
                      (declaration (ir:make-type-declaration definition signature (location node)))
                      (binding (ir:make-value-binding definition expression (location node))))
                 (cons (cons (car row) definition) (list declaration binding))))
              ((ir:name? expression)
               (check-named-member! (ir:name-definition expression) signature node)
               (cons (cons (car row) (ir:name-definition expression)) '()))
              (else (located-error node "instance member must name a stable function or be a fixed lambda")))))

    (define (implementation-root definition visited node)
      (if (or (memq definition visited) (memq definition (state-assigned (state))))
          (located-error node "instance implementations require immutable function bindings" definition))
      (let ((initializer (entry-value definition (state-bindings (state)))))
        (cond ((ir:lambda? initializer) definition)
              ((ir:name? initializer) (implementation-root (ir:name-definition initializer) (cons definition visited) node))
              (else (located-error node "instance implementation requires a module-level lambda" definition)))))

    (define (check-named-member! definition signature node)
      (let* ((root (implementation-root definition '() node))
             (declared (or (entry-value definition (state-declarations (state)))
                           (entry-value root (state-declarations (state))))))
        (if (and declared (constrained-type? declared))
            (located-error node "instance implementations cannot require typeclass constraints" definition))
        (if (not declared) (add-signature! root signature node))
        (if (and (not (eq? root definition)) (not (entry-value definition (state-declarations (state)))))
            (add-signature! definition (or declared signature) node))))

    (define (add-signature! definition signature node)
      (let ((existing (find (lambda (item) (eq? definition (ir:type-declaration-definition item))) (state-extras (state)))))
        (if (and existing (not (type-equal? signature (ir:type-declaration-type existing))))
            (located-error node "one implementation needs compatible instance signatures" definition))
        (if (not existing)
            (set-state-extras! (state) (cons (ir:make-type-declaration definition signature (location node)) (state-extras (state)))))))

    (define (find-instance class types)
      (find (lambda (instance) (and (eq? class (instance-class instance)) (type-equal? types (instance-types instance))))
            (state-instances (state))))

    ;; ---- Parametric checking and static obligations ----

    ;; The ordinary checker exposes pure rules. This traversal retains only
    ;; overloaded uses and lambda signatures needed by specialization; emitter
    ;; facts and runtime guard recipes are not cached or transferred between passes.
    (define-record-type <evidence>
      (make-evidence uses signatures calls edges) evidence?
      (uses evidence-uses set-evidence-uses!)
      (signatures evidence-signatures set-evidence-signatures!)
      (calls evidence-calls set-evidence-calls!)
      (edges evidence-edges set-evidence-edges!))

    (define (prototype-items method)
      (list (ir:make-type-declaration (method-definition method) (method-signature method) #f)
            (ir:make-value-binding (method-definition method) (method-prototype method) #f)))

    (define (instance-for-source node)
      (find (lambda (instance) (eq? node (instance-source instance))) (state-instances (state))))

    (define (prepared-items items)
      (apply append
             (map (lambda (node)
                    (cond ((ir:class-declaration? node) '())
                          ((ir:instance-declaration? node) (instance-items (instance-for-source node)))
                          (else (list node)))) items)))

    (define (member-checks instance)
      (map (lambda (row)
             (ir:make-annotation (ir:make-name (cdr (assq (car row) (instance-members instance))) (location (instance-source instance)))
                                 (member-signature (instance-class instance) row (instance-types instance))
                                 (location (instance-source instance))))
           (ir:class-declaration-methods (instance-class instance))))

    (define (analyze-program! items primitives)
      (let ((input (append (apply append (map prototype-items (state-methods (state))))
                           (state-extras (state)) (prepared-items items)
                           (apply append (map member-checks (state-instances (state)))))))
        (set-state-analysis! (state) (make-evidence '() '() '() '()))
        (check-sequence input (make-type-scope (prepare-types input primitives)) #f)
        (check-recursive-instances (evidence-edges (state-analysis (state))))))

    (define (fact node) (or (entry-value node (evidence-uses (state-analysis (state)))) (unknown-fact)))
    (define (signature procedure) (entry-value procedure (evidence-signatures (state-analysis (state)))))

    (define (remember-use! node fact)
      (if (or (constrained-type? (fact-type fact))
              (and (fact-signature fact) (constrained-type? (fact-signature fact))))
          (let ((evidence (state-analysis (state))))
            (set-evidence-uses! evidence (cons (cons node fact) (evidence-uses evidence)))))
      fact)

    (define (check-expression node scope expected)
      (remember-use! node (checked-fact (check-result node (check-expression-rule node scope expected) expected))))

    ;; Exhaustive dispatch keeps the typeclass preflight separate from emission.
    ;; Every inference decision still belongs to type-analysis.sld's shared rules.
    (define (check-expression-rule node scope expected)
      (cond ((ir:literal? node) (infer-literal node))
            ((ir:name? node) (infer-name node scope))
            ((ir:lambda? node) (check-procedure node scope expected #f))
            ((ir:block? node) (check-sequence (ir:block-items node) scope expected))
            ((ir:application? node) (check-application node scope expected))
            ((ir:conditional? node) (check-conditional node scope expected))
            ((ir:annotation? node)
             (let ((type (ir:annotation-type node)))
               (validate-type type scope (location node))
               (checked-fact (check-result node (check-expression (ir:annotation-expression node)
                                                                  (strict-scope scope) (and (function-type? type) type)) type))))
            ((ir:instantiation? node)
             (infer-instantiation node (check-expression (ir:instantiation-expression node) (strict-scope scope) #f) scope))
            ((ir:value-binding? node)
             (check-initializer (ir:value-binding-definition node) (ir:value-binding-initializer node) scope)
             (value-fact 'Unspecified))
            ((ir:assignment? node)
             (check-initializer (ir:name-definition (ir:assignment-target node)) (ir:assignment-value node) scope)
             (value-fact 'Unspecified))
            ((or (ir:type-declaration? node) (ir:record-schema? node)) (value-fact 'Unspecified))
            (else (located-error node "unknown expression during typeclass checking"))))

    (define (check-initializer definition node scope)
      (let ((expected (binding-type definition scope)))
        (check-expression node (if expected (strict-scope scope) scope) expected)))

    (define (check-sequence items scope expected)
      (cond ((null? items) (value-fact 'Unspecified))
            ((ir:value-binding? (car items))
             (let* ((node (car items)) (definition (ir:value-binding-definition node))
                    (fact (check-initializer definition (ir:value-binding-initializer node) scope)))
               (check-sequence (cdr items) (bind-fact definition fact scope) expected)))
            ((null? (cdr items)) (check-expression (car items) scope expected))
            (else (check-expression (car items) scope #f) (check-sequence (cdr items) scope expected))))

    (define (check-procedure node scope expected arguments)
      (let* ((signature (and (not arguments) (procedure-signature node expected scope)))
             (body-scope (procedure-scope node signature arguments scope))
             (result-type (if signature (type-result (all-body signature)) (and arguments expected)))
             (body (if (method-for-procedure node) (value-fact result-type)
                       (check-expression (ir:lambda-body node) body-scope result-type)))
             (evidence (state-analysis (state))))
        (set-evidence-signatures! evidence (cons (cons node signature) (evidence-signatures evidence)))
        (infer-procedure node signature body)))

    (define (check-conditional node scope expected)
      (let* ((test (check-expression (ir:conditional-test node) scope #f))
             (yes (check-expression (ir:conditional-consequent node) (branch-scope scope test #t) expected))
             (no (if (ir:conditional-opt-alternate node)
                     (check-expression (ir:conditional-opt-alternate node) (branch-scope scope test #f) expected)
                     (value-fact 'Unspecified))))
        (infer-conditional test yes no)))

    (define (check-operands operands scope)
      (if (null? operands) '()
          (let ((first (check-expression (car operands) scope #f)))
            (cons first (check-operands (cdr operands) scope)))))

    (define (check-application node scope expected)
      (let* ((arguments (check-operands (ir:application-operands node) scope))
             (operator (ir:application-operator node)))
        (if (and (ir:lambda? operator) (not (ir:lambda-opt-rest-parameter operator))
                 (= (length arguments) (length (ir:lambda-parameters operator))))
            (fact-body (check-procedure operator scope expected arguments))
            (check-call node (check-expression operator scope #f) arguments expected scope))))

    (define (check-call node operator arguments expected scope)
      (let* ((evidence (state-analysis (state)))
             (types (and (constrained-type? (fact-type operator))
                         (map head-type (call-type-arguments node operator arguments expected scope))))
             (view (if types (instantiate-fact operator types node) operator))
             (plan (infer-call node view arguments expected scope)))
        (if types (set-evidence-calls! evidence (cons (cons node types) (evidence-calls evidence))))
        (set-evidence-edges! evidence (append (call-edges plan) (evidence-edges evidence)))
        (call-fact plan)))

    (define (prepare-templates! items)
      (for-each
       (lambda (node)
         (let ((initializer (ir:value-binding-initializer node)))
           (if (and (ir:lambda? initializer) (constrained-type? (signature initializer)))
               (set-state-templates! (state)
                                     (cons (make-template (ir:value-binding-definition node) initializer (signature initializer))
                                           (state-templates (state))))))) (select ir:value-binding? items))
      (for-each register-static-alias! (select ir:value-binding? items)))

    (define (template-for-procedure procedure)
      (find (lambda (template) (eq? procedure (template-procedure template))) (state-templates (state))))
    (define (template-for-definition definition)
      (find (lambda (template) (eq? definition (template-definition template))) (state-templates (state))))

    (define (register-static-alias! node)
      (let* ((expression (ir:value-binding-initializer node)) (type (fact-type (fact expression))))
        (if (and (constrained-type? type) (not (template-for-definition (ir:value-binding-definition node))))
            (if (and (ir:name? expression) (not (memq (ir:value-binding-definition node) (state-assigned (state)))))
                (set-state-aliases! (state) (cons (ir:value-binding-definition node) (state-aliases (state))))
                (located-error node "unresolved overloaded aliases require an immutable identifier reference")))))

    (define (static-name? node)
      (and (ir:name? node)
           (or (method-for-definition (ir:name-definition node)) (template-for-definition (ir:name-definition node))
               (memq (ir:name-definition node) (state-aliases (state))))))

    (define (callable-origin node)
      (let ((procedure (fact-procedure (fact node))))
        (or (method-for-procedure procedure) (template-for-procedure procedure))))

    (define (origin-signature origin)
      (if (method? origin) (method-signature origin) (template-signature origin)))

    (define (use-types node call)
      (or (and call (entry-value call (evidence-calls (state-analysis (state)))))
          (fact-type-arguments (fact node))))

    (define (substitute-types types substitutions)
      (map (lambda (type) (type-substitute type substitutions)) types))

    ;; Predicate refinements preserve a rigid variable's membership. Call checking
    ;; and selection use its declared class; a T result need not preserve the
    ;; argument's incidental narrower category.
    (define (head-type type)
      (if (and (pair? type) (eq? (car type) 'I))
          (or (find type-variable? (cdr type)) type) type))

    (define (use-constraints origin types)
      (let ((scheme (origin-signature origin)))
        (map (lambda (constraint)
               (cons (car constraint) (map head-type (substitute-types (cdr constraint) (map cons (all-variables scheme) types)))))
             (type-constraints scheme))))

    (define (check-obligation constraint assumptions node)
      (let ((class (check-constraint constraint node)) (types (cdr constraint)))
        (cond ((find (lambda (assumption) (type-equal? constraint assumption)) assumptions) #t)
              ((not (every? concrete-head? types))
               (located-error node "typeclass selection requires a concrete static type or a declared constraint" constraint))
              ((not (find-instance class types)) (located-error node "no typeclass instance" constraint)))))

    (define (validate-use node call assumptions)
      (let ((origin (callable-origin node)))
        (if origin
            (let ((types (use-types node call)))
              (if (not types) (located-error node "overloaded callable requires inst or a concrete function context"))
              (for-each (lambda (constraint) (check-obligation constraint assumptions node)) (use-constraints origin types))))))

    (define (validate-program items)
      (for-each (lambda (node) (validate-node node '())) (prepared-items items)))

    (define (validate-node node assumptions)
      (cond ((ir:name? node)
             (if (class-definition? (ir:name-definition node))
                 (located-error node "typeclasses have no runtime value"))
             (if (static-name? node) (validate-use node #f assumptions)))
            ((ir:assignment? node)
             (validate-node (ir:assignment-target node) assumptions)
             (validate-node (ir:assignment-value node) assumptions))
            ((ir:lambda? node)
             (let ((scheme (signature node)))
               (if (and (constrained-type? scheme) (not (template-for-procedure node)))
                   (located-error node "constrained functions require stable module-level lambdas"))
               (for-each (lambda (constraint) (check-constraint constraint node)) (type-constraints (or scheme 'Procedure)))
               (validate-node (ir:lambda-body node) (append (type-constraints (or scheme 'Procedure)) assumptions))))
            ((ir:application? node)
             (validate-use (ir:application-operator node) node assumptions)
             (if (not (static-name? (ir:application-operator node)))
                 (validate-node (ir:application-operator node) assumptions))
             (for-each (lambda (child) (validate-node child assumptions)) (ir:application-operands node)))
            ((ir:instantiation? node)
             (validate-use node #f assumptions)
             (if (and (callable-origin node) (not (pure-static-reference? (ir:instantiation-expression node))))
                 (located-error node "overloaded instantiation requires an identifier or static view"))
             ;; Plain polymorphic views can have compound payloads. Selecting
             ;; their result does not discharge class operations in that payload.
             (if (not (pure-static-reference? (ir:instantiation-expression node)))
                 (validate-node (ir:instantiation-expression node) assumptions)))
            ((ir:annotation? node)
             (validate-use node #f assumptions)
             (if (not (pure-static-reference? (ir:annotation-expression node)))
                 (validate-node (ir:annotation-expression node) assumptions)))
            ((ir:value-binding? node)
             (if (not (memq (ir:value-binding-definition node) (state-aliases (state))))
                 (validate-node (ir:value-binding-initializer node) assumptions)))
            (else (for-each (lambda (child) (validate-node child assumptions)) (children node)))))

    ;; ---- Concrete method values and generic specializations ----

    (define (selected-method method types node)
      (let* ((class (method-class method)) (instance (find-instance class types))
             (row (assq (method-definition method) (ir:class-declaration-methods class))))
        (if (not instance) (located-error node "no typeclass instance" (class-constraint class types)))
        ;; Preserve the implementation binding read, including forward-reference
        ;; errors. A statically known code address alone is not an initialized value.
        (ir:make-annotation (ir:make-name (cdr (assq (method-definition method) (instance-members instance))) (location node))
                            (member-signature class row types) (location node))))

    (define (selected-value node call substitutions)
      (let* ((origin (callable-origin node)) (inferred (and origin (use-types node call))))
        (if (not inferred) (located-error node "overloaded callable requires inst or a concrete function context"))
        (let ((types (substitute-types (map head-type inferred) substitutions)))
          (for-each (lambda (constraint) (check-obligation constraint '() node)) (use-constraints origin types))
          (if (method? origin) (selected-method origin types node)
              (ir:make-name (specialization-definition (specialize! origin types)) (location node))))))

    (define (find-specialization template types)
      (find (lambda (entry) (and (eq? template (specialization-template entry)) (type-equal? types (specialization-types entry))))
            (state-specializations (state))))

    ;; Reserve before rewriting: recursive and mutually recursive uses then see
    ;; the same callable entry. The ordinary checker rejects type-changing cycles.
    (define (specialize! template types)
      (or (find-specialization template types)
          (let* ((definition (ir:make-value-definition
                              (string->symbol (string-append "$specialize:" (symbol->string (ir:value-definition-name (template-definition template)))
                                                             ":" (number->string (length (state-specializations (state))))))
                              (ir:value-definition-loc (template-definition template))))
                 (entry (make-specialization template types definition #f))
                 (substitutions (map cons (all-variables (template-signature template)) types)))
            (set-state-specializations! (state) (cons entry (state-specializations (state))))
            (set-specialization-body! entry (rewrite-node (template-procedure template) substitutions '()))
            entry)))

    (define (fresh-binding definition)
      (cons definition (ir:make-value-definition (ir:value-definition-name definition) (ir:value-definition-loc definition))))

    (define (activation-bindings node)
      (cond ((ir:lambda? node) '())
            ((ir:value-binding? node) (cons (ir:value-binding-definition node) (activation-bindings (ir:value-binding-initializer node))))
            (else (apply append (map activation-bindings (children node))))))

    (define (rewrite-lambda node substitutions bindings)
      (let* ((parameters (ir:lambda-parameters node)) (rest (ir:lambda-opt-rest-parameter node))
             (locals (append parameters (if rest (list rest) '()) (activation-bindings (ir:lambda-body node))))
             (scope (if (null? substitutions) bindings (append (map fresh-binding locals) bindings))))
        (ir:make-lambda (map (lambda (definition) (or (entry-value definition scope) definition)) parameters)
                        (and rest (or (entry-value rest scope) rest))
                        (rewrite-node (ir:lambda-body node) substitutions scope) (ir:lambda-loc node))))

    (define (mapped-binding definition bindings) (or (entry-value definition bindings) definition))

    (define (rewrite-call node substitutions bindings)
      (let* ((operator (ir:application-operator node))
             (selected (cond ((static-name? operator) (selected-value operator node substitutions))
                             ((and (ir:instantiation? operator) (callable-origin operator) (pure-static-reference? operator)) (selected-value operator #f substitutions))
                             ((and (ir:annotation? operator) (callable-origin operator) (pure-static-reference? operator)) (selected-value operator #f substitutions))
                             (else (rewrite-node operator substitutions bindings)))))
        (ir:make-application selected (map (lambda (operand) (rewrite-node operand substitutions bindings)) (ir:application-operands node))
                             (ir:application-loc node))))

    (define (rewrite-node node substitutions bindings)
      (cond ((ir:literal? node) node)
            ((ir:name? node)
             (if (class-definition? (ir:name-definition node)) (located-error node "typeclasses have no runtime value"))
             (if (static-name? node) (selected-value node #f substitutions)
                 (ir:make-name (mapped-binding (ir:name-definition node) bindings) (ir:name-loc node))))
            ((ir:lambda? node) (rewrite-lambda node substitutions bindings))
            ((ir:application? node) (rewrite-call node substitutions bindings))
            ((ir:block? node) (ir:make-block (map (lambda (item) (rewrite-node item substitutions bindings)) (ir:block-items node)) (ir:block-loc node)))
            ((ir:conditional? node)
             (ir:make-conditional (rewrite-node (ir:conditional-test node) substitutions bindings)
                                  (rewrite-node (ir:conditional-consequent node) substitutions bindings)
                                  (and (ir:conditional-opt-alternate node) (rewrite-node (ir:conditional-opt-alternate node) substitutions bindings))
                                  (ir:conditional-loc node)))
            ((ir:value-binding? node)
             (ir:make-value-binding (mapped-binding (ir:value-binding-definition node) bindings)
                                    (rewrite-node (ir:value-binding-initializer node) substitutions bindings) (ir:value-binding-loc node)))
            ((ir:assignment? node)
             (if (class-definition? (ir:name-definition (ir:assignment-target node)))
                 (located-error node "typeclasses have no runtime value"))
             (ir:make-assignment (ir:make-name (mapped-binding (ir:name-definition (ir:assignment-target node)) bindings) #f)
                                 (rewrite-node (ir:assignment-value node) substitutions bindings) (ir:assignment-loc node)))
            ((ir:annotation? node)
             (if (and (callable-origin node) (pure-static-reference? (ir:annotation-expression node))) (selected-value node #f substitutions)
                 (ir:make-annotation (rewrite-node (ir:annotation-expression node) substitutions bindings)
                                     (type-substitute (ir:annotation-type node) substitutions) (ir:annotation-loc node))))
            ((ir:instantiation? node)
             (if (and (callable-origin node) (pure-static-reference? (ir:instantiation-expression node))) (selected-value node #f substitutions)
                 (ir:make-instantiation (rewrite-node (ir:instantiation-expression node) substitutions bindings)
                                        (substitute-types (ir:instantiation-types node) substitutions) (ir:instantiation-loc node))))
            ((ir:type-declaration? node)
             (ir:make-type-declaration (mapped-binding (ir:type-declaration-definition node) bindings)
                                       (type-substitute (ir:type-declaration-type node) substitutions) (ir:type-declaration-loc node)))
            ((ir:record-schema? node) (rewrite-record-schema node substitutions bindings))
            (else (located-error node "unresolved class expression survived elaboration"))))

    (define (pure-static-reference? node)
      (or (static-name? node)
          (and (ir:annotation? node) (pure-static-reference? (ir:annotation-expression node)))
          (and (ir:instantiation? node) (pure-static-reference? (ir:instantiation-expression node)))))

    (define (rewrite-record-schema node substitutions bindings)
      (ir:make-record-schema (mapped-binding (ir:record-schema-definition node) bindings)
                             (mapped-binding (ir:record-schema-constructor node) bindings)
                             (mapped-binding (ir:record-schema-predicate node) bindings) (ir:record-schema-arguments node)
                             (map (lambda (field)
                                    (list (car field) (type-substitute (cadr field) substitutions)
                                          (mapped-binding (caddr field) bindings) (and (cadddr field) (mapped-binding (cadddr field) bindings))))
                                  (ir:record-schema-fields node)) (ir:record-schema-loc node)))

    ;; ---- Library bodies and initialization sites ----

    (define (with-body library body)
      (library:make-library (library:library-name library) (library:library-imports library) (library:library-exports library)
                            (library:library-dependencies library) body (library:library-loc library)))

    (define (extra-signatures items)
      (select (lambda (declaration)
                (find (lambda (node) (and (ir:value-binding? node)
                                          (eq? (ir:value-binding-definition node) (ir:type-declaration-definition declaration)))) items))
              (state-extras (state))))

    (define (rewrite-library library)
      (let ((items (library:library-body library)))
        (with-body library (append (extra-signatures items) (apply append (map rewrite-top-item items))))))

    (define (rewrite-top-item node)
      (cond ((ir:class-declaration? node) '())
            ((ir:instance-declaration? node) (map (lambda (item) (rewrite-node item '() '())) (instance-items (instance-for-source node))))
            ((and (ir:type-declaration? node) (constrained-type? (ir:type-declaration-type node))) '())
            ((and (ir:value-binding? node) (template-for-definition (ir:value-binding-definition node))) (list node))
            ((and (ir:value-binding? node) (memq (ir:value-binding-definition node) (state-aliases (state)))) '())
            (else (list (rewrite-node node '() '())))))

    (define (specialization-items entry)
      (let* ((template (specialization-template entry)) (definition (specialization-definition entry))
             (substitutions (map cons (all-variables (template-signature template)) (specialization-types entry)))
             (type (type-substitute (all-body (template-signature template)) substitutions)))
        (list (ir:make-type-declaration definition type (ir:value-definition-loc definition))
              (ir:make-value-binding definition (specialization-body entry) (ir:value-definition-loc definition)))))

    (define (materialize-library library)
      (with-body library
                 (apply append
                        (map (lambda (node)
                               (let ((template (and (ir:value-binding? node) (template-for-definition (ir:value-binding-definition node)))))
                                 (if template
                                     (apply append (map specialization-items (reverse (select (lambda (entry) (eq? template (specialization-template entry)))
                                                                                              (state-specializations (state))))))
                                     (list node)))) (library:library-body library)))))

    ;; No class declarations, qualified signatures, or unresolved method names
    ;; can reach the emitter. This checks the compile-time-only contract itself.
    (define (validate-erasure libraries)
      (for-each (lambda (node)
                  (if (or (class-node? node) (qualified-declaration? node) (static-name? node))
                      (located-error node "unresolved typeclass operation survived elaboration")))
                (nodes (apply append (map library:library-body libraries))))))

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-typeclasses)
    (import (snail-scheme test-utils)
            (only (snail-scheme expand) make-core-library syntax-list->ir-library)
            (only (snail-scheme reader) string->reader)
            (only (snail-scheme syntax-parser) s-file)
            (only (snail-scheme parser) parse-result-value))
    (begin
      (define (test-elaboration text)
        (let* ((core (make-core-library '(scheme base) '(+ error string? string-length)))
               (forms (parse-result-value (s-file (string->reader "classes.scm" text))))
               (root (syntax-list->ir-library forms (lambda (name) (error "unexpected library" name)) (list core)))
               (primitives (map library:named-binding-definition (select (lambda (entry) (ir:value-definition? (library:named-binding-definition entry)))
                                                                         (library:library-exports core))))
               (result (elaborate-typeclasses (list core root) primitives)))
          (library:library-body (cadr result))))

      (define test-class-source
        "(import (scheme base))
         (define-class (Combine T) (: combine (-> T T T)))
         (define-instance (Combine i32) (combine (lambda (x y) x)))
         (define-instance (Combine String) (combine (lambda (x y) y)))
         (: twice (All (T) (=> ((Combine T)) (-> T T))))
         (define (twice x) (combine x x)) ")

      (define (test-static-elaboration)
        (let* ((body (test-elaboration (string-append test-class-source "(twice 1) (twice 2) (twice \"s\")")))
               (bindings (select ir:value-binding? body))
               (names (map (lambda (binding) (ir:value-definition-name (ir:value-binding-definition binding))) bindings)))
          (expect (length (select (lambda (name) (not (eq? name 'combine))) names)) 2)
          (expect (memq 'twice names) #f)
          (expect (find class-node? (nodes body)) #f)
          (expect (find qualified-declaration? (nodes body)) #f)))

      (define (test-class-obligations)
        (expect (guard (ex ((error-object? ex) #t))
                  (test-elaboration (string-append test-class-source "(combine #t #f)")) #f) #t)
        (expect (guard (ex ((error-object? ex) #t))
                  (test-elaboration (string-append test-class-source
                                                   "(define-instance (Combine i32) (combine (lambda (x y) x)))")) #f) #t))

      (define (test-instantiation-obligations)
        (let ((source (string-append test-class-source
                                     "(define-class (Pick T) (: pick (-> T T)))
                                     (define-instance (Pick i32) (pick (lambda (x) x)))
                                     (: id (All (A) (-> A A))) (define (id x) x)
                                     (: hidden (All (T) (=> ((Combine T)) (-> T T))))
                                     (define (hidden x) (inst (begin (pick x) id) i32) x)")))
          (expect (guard (ex ((error-object? ex) #t)) (test-elaboration source) #f) #t)))

      (define (test-unused-overloaded-values)
        (for-each
         (lambda (name)
           (let ((source (string-append test-class-source
                                        "(define (discard x) x)
                                        (: hidden (All (T) (=> ((Combine T)) (-> T T))))
                                        (define (hidden x) (discard " name ") x)")))
             (expect (guard (ex ((error-object? ex) #t)) (test-elaboration source) #f) #t)))
         '("combine" "Combine")))

      (define (test-unused-class-assignment)
        (let ((prefix (string-append test-class-source
                                     "(: hidden (All (T) (=> ((Combine T)) (-> T T)))) ")))
          (expect (guard (ex ((error-object? ex) #t))
                    (test-elaboration (string-append prefix "(define (hidden x) (set! Combine 42) x)")) #f) #t)
          (expect (pair? (test-elaboration (string-append prefix
                                                          "(define (hidden x) (define Combine 0) (set! Combine 42) x)"))) #t)))

      (define (test-class-result-refinement)
        (let ((source "(import (scheme base))
                       (define-class (Keep T) (: keep (-> T T)))
                       (define-instance (Keep Any) (keep (lambda (x) 42)))
                       (: measure (All (T) (=> ((Keep T)) (-> T ExactInteger))))
                       (define (measure x) (if (string? x) (string-length (keep x)) 0))"))
          (expect (guard (ex ((error-object? ex) #t)) (test-elaboration source) #f) #t)))

      (define (test-instance-assignment-inventory)
        (let ((prefix "(import (scheme base))
                       (define-class (C T) (: c (-> T T))) (define alias c) "))
          (expect (guard (ex ((error-object? ex) #t))
                    (test-elaboration (string-append prefix
                                                     "(define-instance (C i32) (c (lambda (x) (set! alias (lambda (y) y)) x)))")) #f) #t)
          (expect (pair? (test-elaboration (string-append prefix
                                                          "(define-instance (C i32) (c (lambda (x) (define alias 0) (set! alias 1) x)))"))) #t)))

      (define (test-typeclasses)
        (run-test test-static-elaboration)
        (run-test test-class-obligations)
        (run-test test-instantiation-obligations)
        (run-test test-unused-overloaded-values)
        (run-test test-unused-class-assignment)
        (run-test test-class-result-refinement)
        (run-test test-instance-assignment-inventory))))))

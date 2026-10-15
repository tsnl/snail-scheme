;; One located IR is shared by expansion, checking and specialization. Expansion
;; resolves identities and attaches declared syntax; every expression and binder
;; starts with its own Hole. Checking refines an owned copy, and specialization
;; makes concrete copies without changing a generic template or runtime site.
;; See doc/ir.md for variant layouts and phase invariants.
(define-library (snail-scheme ir)
  (export
   make-node node? node-kind node-type node-loc node-data node-constraints
   refine-node! children copy-ir-graph attach-declarations!
   make-value-definition value-definition? value-definition-name value-definition-loc
   binding-id? binding-origin
   prepare-binding! binding-scheme set-binding-scheme!
   binding-initializer set-binding-initializer! binding-kind binding-payload
   binding-declaration set-binding-declaration!
   make-value-binding value-binding?
   value-binding-definition
   value-binding-initializer value-binding-form
   value-binding-loc
   make-name name?
   name-definition
   name-substitutions
   name-loc
   make-literal literal?
   literal-value
   literal-number-spelling
   literal-loc
   make-application application?
   application-operator
   application-operands
   application-loc
   make-lambda lambda?
   lambda-parameters
   lambda-opt-rest-parameter
   lambda-body
   lambda-loc
   make-block block?
   block-bindings
   block-items
   block-loc
   make-conditional conditional?
   conditional-test
   conditional-consequent
   conditional-opt-alternate
   conditional-loc
   make-assignment assignment?
   assignment-target
   assignment-value
   assignment-loc
   make-type-declaration type-declaration?
   type-declaration-definition
   type-declaration-type
   type-declaration-loc
   make-annotation annotation?
   annotation-expression
   annotation-type
   annotation-loc
   make-instantiation instantiation?
   instantiation-expression
   instantiation-types
   instantiation-loc
   make-record-schema record-schema?
   record-schema-definition
   record-schema-constructor
   record-schema-predicate
   record-schema-arguments
   record-schema-fields
   record-schema-loc
   make-data-schema data-schema? data-schema-definition data-schema-variables data-schema-cases
   make-match match? match-subject match-arms
   make-class-declaration class-declaration?
   class-declaration-definition
   class-declaration-variables
   class-declaration-methods
   class-declaration-loc
   make-instance-declaration instance-declaration?
   instance-declaration-definition
   instance-declaration-class
   instance-declaration-types
   instance-declaration-methods
   instance-declaration-loc
   make-overload-declaration overload-declaration?
   overload-declaration-definition
   overload-declaration-member
   overload-declaration-implementation
   overload-declaration-loc
   make-extern-declaration extern-declaration?
   extern-declaration-definition
   extern-declaration-module
   extern-declaration-symbol
   extern-declaration-type
   extern-declaration-loc
   overload-declaration-type)
  (import (scheme base) (scheme cxr) (snail-scheme strict-types)
          (only (scheme hash-table) make-hash-table hash-table-set! hash-table-ref/default))
  (begin

    ;; ---- Located expressions and declarations ----

    (define-record-type <node>
      (make-node kind type loc data constraints) node?
      (kind node-kind set-node-kind!) (type node-type set-node-type!) (loc node-loc)
      (data node-data set-node-data!) (constraints node-constraints set-node-constraints!))
    (define (source-node kind loc data) (make-node kind (fresh-hole) loc data '()))
    (define (refine-node! node kind type data constraints)
      (set-node-kind! node kind) (set-node-type! node type)
      (set-node-data! node data) (set-node-constraints! node constraints) node)
    (define (kind? node kind) (and (node? node) (eq? (node-kind node) kind)))

    ;; ---- Resolved definitions own their schemes and initializer metadata ----

    ;; The definition is also the checked binding. A use instantiates its scheme;
    ;; it never solves the owner's quantified variables. Declaration syntax stays
    ;; separate from the inferred scheme so expansion does not perform inference.
    ;; An immutable origin survives owned compiler copies. Definition objects
    ;; themselves remain the mutable, canonical bindings within one compilation.
    (define-record-type <binding-id>
      (make-binding-id) binding-id?)
    (define-record-type <value-definition>
      (new-definition name loc origin scheme declaration initializer kind payload) value-definition?
      (name value-definition-name) (loc value-definition-loc)
      (origin binding-origin)
      (scheme binding-scheme set-binding-scheme!)
      (declaration binding-declaration set-binding-declaration!)
      (initializer binding-initializer set-binding-initializer!)
      (kind binding-kind set-binding-kind!) (payload binding-payload set-binding-payload!))
    (define (make-value-definition name loc)
      (new-definition name loc (make-binding-id)
                      (make-scheme '() (fresh-hole) '()) #f #f 'source #f))
    (define (prepare-binding! definition scheme initializer kind payload)
      (set-binding-scheme! definition scheme) (set-binding-initializer! definition initializer)
      (set-binding-kind! definition kind) (set-binding-payload! definition payload) definition)

    ;; ---- Concrete variant constructors and accessors ----

    ;; The source former survives unresolved copies for syntax inspection. Both
    ;; forms have the same runtime binding operation after lexical resolution.
    (define (make-value-binding definition initializer loc . former)
      (set-binding-initializer! definition initializer)
      (source-node 'bind loc (list definition initializer (if (pair? former) (car former) 'def))))
    (define (value-binding? node) (kind? node 'bind))
    (define (value-binding-definition node) (car (node-data node)))
    (define (value-binding-initializer node) (cadr (node-data node)))
    (define (value-binding-form node)
      (if (pair? (cddr (node-data node))) (caddr (node-data node)) 'def))
    (define value-binding-loc node-loc)

    ;; The second field records a checked use's instantiation, initially empty.
    (define (make-name definition loc) (source-node 'name loc (list definition '())))
    (define (name? node) (kind? node 'name))
    (define (name-definition node) (car (node-data node)))
    (define (name-substitutions node) (cadr (node-data node)))
    (define name-loc node-loc)

    (define (make-literal value loc . spelling)
      (source-node 'literal loc (list value (and (pair? spelling) (car spelling)))))
    (define (literal? node) (kind? node 'literal))
    (define (literal-value node) (car (node-data node)))
    (define (literal-number-spelling node)
      (and (pair? (cdr (node-data node))) (cadr (node-data node))))
    (define literal-loc node-loc)

    (define (make-application operator operands loc)
      (source-node 'call loc (list operator operands)))
    (define (application? node) (kind? node 'call))
    (define (application-operator node) (car (node-data node)))
    (define (application-operands node) (cadr (node-data node)))
    (define application-loc node-loc)

    (define (make-lambda parameters opt-rest-parameter body loc)
      (source-node 'lambda loc (list parameters opt-rest-parameter body)))
    (define (lambda? node) (kind? node 'lambda))
    (define (lambda-parameters node) (car (node-data node)))
    (define (lambda-opt-rest-parameter node) (cadr (node-data node)))
    (define (lambda-body node) (caddr (node-data node)))
    (define lambda-loc node-loc)

    (define (make-block items loc) (source-node 'block loc (list '() items)))
    (define (block? node) (kind? node 'block))
    (define (block-bindings node) (car (node-data node)))
    (define (block-items node) (cadr (node-data node)))
    (define block-loc node-loc)

    (define (make-conditional test consequent opt-alternate loc)
      (source-node 'if loc (list test consequent opt-alternate)))
    (define (conditional? node) (kind? node 'if))
    (define (conditional-test node) (car (node-data node)))
    (define (conditional-consequent node) (cadr (node-data node)))
    (define (conditional-opt-alternate node) (caddr (node-data node)))
    (define conditional-loc node-loc)

    (define (make-assignment target value loc)
      (source-node 'assignment loc (list target value)))
    (define (assignment? node) (kind? node 'assignment))
    (define (assignment-target node) (car (node-data node)))
    (define (assignment-value node) (cadr (node-data node)))
    (define assignment-loc node-loc)

    (define (make-type-declaration definition type loc)
      (source-node 'type-declaration loc (list definition type)))
    (define (type-declaration? node) (kind? node 'type-declaration))
    (define (type-declaration-definition node) (car (node-data node)))
    (define (type-declaration-type node) (cadr (node-data node)))
    (define type-declaration-loc node-loc)

    (define (make-annotation expression type loc)
      (source-node 'annotation loc (list expression type)))
    (define (annotation? node) (kind? node 'annotation))
    (define (annotation-expression node) (car (node-data node)))
    (define (annotation-type node) (cadr (node-data node)))
    (define annotation-loc node-loc)

    (define (make-instantiation expression types loc)
      (source-node 'instantiation loc (list expression types)))
    (define (instantiation? node) (kind? node 'instantiation))
    (define (instantiation-expression node) (car (node-data node)))
    (define (instantiation-types node) (cadr (node-data node)))
    (define instantiation-loc node-loc)

    (define (make-record-schema definition constructor predicate arguments fields loc)
      (source-node 'record-schema loc (list definition constructor predicate arguments fields)))
    (define (record-schema? node) (kind? node 'record-schema))
    (define (record-schema-definition node) (car (node-data node)))
    (define (record-schema-constructor node) (cadr (node-data node)))
    (define (record-schema-predicate node) (caddr (node-data node)))
    (define (record-schema-arguments node) (cadddr (node-data node)))
    (define (record-schema-fields node) (list-ref (node-data node) 4))
    (define record-schema-loc node-loc)

    ;; A closed sum owns constructor identities and typed fields. One case is a
    ;; nominal product. An arm stores its resolved constructor and an ordinary
    ;; lambda whose parameters scope the arm body; checking lowers it to let/if.
    (define (make-data-schema definition variables cases loc)
      (source-node 'data-schema loc (list definition variables cases)))
    (define (data-schema? node) (kind? node 'data-schema))
    (define (data-schema-definition node) (car (node-data node)))
    (define (data-schema-variables node) (cadr (node-data node)))
    (define (data-schema-cases node) (caddr (node-data node)))
    (define (make-match subject arms loc) (source-node 'match loc (list subject arms)))
    (define (match? node) (kind? node 'match))
    (define (match-subject node) (car (node-data node)))
    (define (match-arms node) (cadr (node-data node)))

    (define (make-class-declaration definition variables methods loc)
      (source-node 'class-declaration loc (list definition variables methods)))
    (define (class-declaration? node) (kind? node 'class-declaration))
    (define (class-declaration-definition node) (car (node-data node)))
    (define (class-declaration-variables node) (cadr (node-data node)))
    (define (class-declaration-methods node) (caddr (node-data node)))
    (define class-declaration-loc node-loc)

    (define (make-instance-declaration definition class types methods loc)
      (source-node 'instance-declaration loc (list definition class types methods)))
    (define (instance-declaration? node) (kind? node 'instance-declaration))
    (define (instance-declaration-definition node) (car (node-data node)))
    (define (instance-declaration-class node) (cadr (node-data node)))
    (define (instance-declaration-types node) (caddr (node-data node)))
    (define (instance-declaration-methods node) (cadddr (node-data node)))
    (define instance-declaration-loc node-loc)

    ;; Each row has its own member identity. A named implementation still names
    ;; its original runtime binding; this member does not introduce an early alias.
    (define (make-overload-declaration definition type implementation loc . signature-location)
      (let ((member (make-value-definition (value-definition-name definition) loc)))
        (when type
          (set-binding-declaration! member
                                    (make-type-declaration member type
                                                           (if (pair? signature-location)
                                                               (car signature-location) loc))))
        (set-binding-initializer! member implementation)
        (source-node 'overload-declaration loc (list definition member implementation))))
    (define (overload-declaration? node) (kind? node 'overload-declaration))
    (define (overload-declaration-definition node) (car (node-data node)))
    (define (overload-declaration-member node) (cadr (node-data node)))
    (define (overload-declaration-implementation node) (caddr (node-data node)))
    (define overload-declaration-loc node-loc)

    (define (make-extern-declaration definition module symbol type loc)
      (source-node 'extern-declaration loc (list definition module symbol type)))
    (define (extern-declaration? node) (kind? node 'extern-declaration))
    (define (extern-declaration-definition node) (car (node-data node)))
    (define (extern-declaration-module node) (cadr (node-data node)))
    (define (extern-declaration-symbol node) (caddr (node-data node)))
    (define (extern-declaration-type node) (cadddr (node-data node)))
    (define extern-declaration-loc node-loc)

    (define (overload-declaration-type node)
      (let ((declaration (binding-declaration (overload-declaration-member node))))
        (and declaration (type-declaration-type declaration))))

    ;; ---- Attached ordinary declarations ----

    ;; Retain colon nodes for the gradual checker. Strict checking reads the
    ;; signature from its unique definition; overload rows already own theirs.
    (define (attach-declarations! items)
      (let ((definitions (let collect ((items items))
                           (cond ((null? items) '())
                                 ((value-binding? (car items))
                                  (cons (value-binding-definition (car items))
                                        (collect (cdr items))))
                                 (else (collect (cdr items)))))))
        (for-each (lambda (node)
                    (when (type-declaration? node)
                      (attach-declaration! node definitions))) items)))
    (define (attach-declaration! node definitions)
      (let ((definition (type-declaration-definition node)))
        (when (memq definition definitions)
          (when (binding-declaration definition)
            (strict-error (node-loc node) "type declaration requires one local definition"))
          (set-binding-declaration! definition node))))

    ;; ---- Structural children preserve source dependency discovery ----

    (define (children node)
      (if (not (node? node)) '()
          (case (node-kind node)
            ((lambda) (list (lambda-body node)))
            ((block) (block-items node))
            ((call) (cons (application-operator node) (application-operands node)))
            ((bind) (list (value-binding-initializer node)))
            ((if) (list (conditional-test node) (conditional-consequent node)
                        (conditional-opt-alternate node)))
            ((annotation) (list (annotation-expression node)))
            ((instantiation) (list (instantiation-expression node)))
            ((match) (cons (match-subject node) (map cadr (match-arms node))))
            ((data-field data-test) (list (car (node-data node))))
            ((assignment) (list (assignment-value node)))
            ((let) (append (cadr (node-data node)) (list (caddr (node-data node)))))
            ((convert) (node-data node)) (else '()))))

    ;; ---- Compilation ownership ----

    ;; One identity hash table copies all roots together, including unused
    ;; initializers and primitive identities. Reserve before descending cycles.
    ;; Lookup never scans earlier copies; table iteration never chooses traversal
    ;; order. Distinct equal objects stay distinct. Locations are immutable data.
    ;; An optional identity mapping retains objects owned by an enclosing check.
    ;; Seeded objects are boundaries: their children are not copied or mutated.
    (define (copy-ir-graph roots . identity-mappings)
      (let ((copies (make-hash-table eq?)))
        (define (reserve original copy)
          (hash-table-set! copies original copy) copy)
        (define (copy-node node)
          (let ((copy (reserve node (make-node (node-kind node) #f (node-loc node) '() '()))))
            (refine-node! copy (node-kind node) (walk (node-type node))
                          (walk (node-data node)) (walk (node-constraints node)))))
        (define (copy-definition definition)
          (let ((copy (reserve definition
                               (new-definition (value-definition-name definition)
                                               (value-definition-loc definition)
                                               (binding-origin definition) #f #f #f 'source #f))))
            (set-binding-declaration! copy (walk (binding-declaration definition)))
            (prepare-binding! copy (walk (binding-scheme definition))
                              (walk (binding-initializer definition)) (binding-kind definition)
                              (walk (binding-payload definition)))))
        (define (copy-scheme scheme)
          (let ((copy (reserve scheme (make-scheme '() #f '()))))
            (set-scheme-variables! copy (walk (scheme-variables scheme)))
            (set-scheme-type! copy (walk (scheme-type scheme)))
            (set-scheme-constraints! copy (walk (scheme-constraints scheme))) copy))
        (define (copy-hole hole)
          (let ((copy (reserve hole (fresh-hole))))
            (set-hole-link! copy (walk (hole-link hole))) copy))
        (define (copy-pair pair)
          (let ((copy (reserve pair (cons #f #f))))
            (set-car! copy (walk (car pair))) (set-cdr! copy (walk (cdr pair))) copy))
        (define (copy-vector vector)
          (let ((copy (reserve vector (make-vector (vector-length vector)))))
            (let loop ((index 0))
              (unless (= index (vector-length vector))
                (vector-set! copy index (walk (vector-ref vector index)))
                (loop (+ index 1)))) copy))
        (define (walk object)
          ;; Every stored copy is an object, so #f means no reserved copy.
          (cond ((hash-table-ref/default copies object #f))
                ((node? object) (copy-node object))
                ((value-definition? object) (copy-definition object))
                ((scheme? object) (copy-scheme object))
                ((hole? object) (copy-hole object))
                ((rigid? object) (reserve object (fresh-rigid)))
                ((pair? object) (copy-pair object))
                ((vector? object) (copy-vector object))
                ((string? object) (reserve object (string-copy object)))
                ((bytevector? object) (reserve object (bytevector-copy object)))
                (else object)))
        (when (pair? identity-mappings)
          (for-each (lambda (entry) (reserve (car entry) (cdr entry))) (car identity-mappings)))
        (walk roots))))

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-ir)
    (import (snail-scheme test-utils) (only (snail-scheme source) make-loc))
    (begin
      (define (test-source-holes)
        (let* ((definition (make-value-definition 'x #f)) (use (make-name definition #f)))
          (expect (hole? (node-type use)) #t)
          (expect (hole? (scheme-type (binding-scheme definition))) #t)
          (expect (eq? (node-type use) (scheme-type (binding-scheme definition))) #f)
          (expect (eq? (name-definition use) definition) #t)))
      (define (test-definition-cycle)
        (let* ((definition (make-value-definition 'recur #f))
               (use (make-name definition #f)) (bind (make-value-binding definition use #f))
               (copies (copy-ir-graph (list bind use definition)))
               (copy (caddr copies)))
          (expect (eq? copy definition) #f)
          (expect (binding-id? (binding-origin definition)) #t)
          (expect (eq? (binding-origin copy) (binding-origin definition)) #t)
          (expect (eq? (value-binding-definition (car copies)) copy) #t)
          (expect (eq? (binding-initializer copy) (cadr copies)) #t)
          (expect (eq? (name-definition (cadr copies)) copy) #t)
          (unify! (scheme-type (binding-scheme copy)) 'I64 #f)
          (expect (hole-link (scheme-type (binding-scheme definition))) #f)))
      (define (test-copy-proof-sharing)
        (let* ((hole (fresh-hole)) (rigid (fresh-rigid))
               (scheme (make-scheme (list rigid) (function-type (list rigid) #f hole) '()))
               (substitutions (list (cons rigid hole)))
               (node (make-node 'name hole #f substitutions '())))
          (set-scheme-constraints! scheme (list (list 'Proof node scheme)))
          (let* ((copies (copy-ir-graph (list node scheme hole)))
                 (node-copy (car copies)) (scheme-copy (cadr copies)) (hole-copy (caddr copies)))
            (expect (eq? (node-type node-copy) hole-copy) #t)
            (expect (eq? (cdar (node-data node-copy)) hole-copy) #t)
            (expect (eq? (caar (node-data node-copy)) (car (scheme-variables scheme-copy))) #t)
            (expect (eq? (caddar (scheme-constraints scheme-copy)) scheme-copy) #t)
            (expect (eq? (car (scheme-variables scheme-copy)) rigid) #f)
            (unify! hole-copy 'Bool #f)
            (expect (hole-link hole) #f))))
      (define (test-copy-mutable-data)
        (let* ((text (string-copy "row")) (bytes (bytevector 1 2))
               (cycle (vector #f text bytes)) (other (string-copy text)))
          (vector-set! cycle 0 cycle)
          (let* ((copies (copy-ir-graph (list cycle text other))) (copy (car copies)))
            (expect (eq? (vector-ref copy 0) copy) #t)
            (expect (eq? (vector-ref copy 1) (cadr copies)) #t)
            (expect (eq? (cadr copies) (caddr copies)) #f)
            (string-set! (cadr copies) 0 #\R)
            (bytevector-u8-set! (vector-ref copy 2) 0 9)
            (expect text "row") (expect (bytevector-u8-ref bytes 0) 1))))
      (define (test-copy-retained-identities)
        (let* ((nominal (make-value-definition 'Box #f)) (class (make-value-definition 'Show #f))
               (ambient (fresh-rigid)) (local (fresh-rigid))
               (binding (make-value-definition 'loop #f))
               (scheme (make-scheme (list local) (list 'Data nominal ambient local)
                                    (list (list class local))))
               (use (make-name binding #f))
               (seeds (map (lambda (identity) (cons identity identity))
                           (list nominal class ambient))))
          (prepare-binding! binding scheme use 'value #f)
          (let* ((copies (copy-ir-graph (list binding use) seeds)) (copy (car copies))
                 (signature (binding-scheme copy)))
            (expect (eq? copy binding) #f)
            (expect (eq? (name-definition (cadr copies)) copy) #t)
            (expect (eq? (car (scheme-variables signature)) local) #f)
            (expect (eq? (cadr (scheme-type signature)) nominal) #t)
            (expect (eq? (caddr (scheme-type signature)) ambient) #t)
            (expect (eq? (caar (scheme-constraints signature)) class) #t))))
      (define (test-copy-pair-graph)
        (let* ((cycle (cons 'head '())) (other (cons 3 4))
               (tail (cons 3 4)) (root (vector cycle cycle tail other)))
          (set-cdr! cycle cycle)
          (let* ((copies (copy-ir-graph (list root cycle tail other)))
                 (copy (car copies)) (pair (cadr copies)))
            (expect (eq? (vector-ref copy 0) pair) #t)
            (expect (eq? (vector-ref copy 1) pair) #t)
            (expect (eq? (cdr pair) pair) #t)
            (expect (eq? (vector-ref copy 2) (caddr copies)) #t)
            (expect (caddr copies) '(3 . 4))
            (expect (eq? (caddr copies) (cadddr copies)) #f)
            (set-car! pair 'changed)
            (expect (car cycle) 'head) (expect (cadddr copies) '(3 . 4)))))
      (define (copy-test-graph count payload)
        (let loop ((left count) (nodes '()))
          (if (= left 0) nodes
              (loop (- left 1)
                    (cons (make-node 'probe 'I64 #f (list left payload) '()) nodes)))))
      (define (test-copy-wide-sharing)
        (let* ((shared (vector 'payload)) (source (copy-test-graph 2000 shared))
               (copies (copy-ir-graph source)) (payload (cadr (node-data (car copies)))))
          (expect (length copies) 2000)
          (expect (eq? payload shared) #f)
          (let loop ((source source) (copies copies) (index 1))
            (unless (null? source)
              (expect (eq? (car source) (car copies)) #f)
              (expect (car (node-data (car copies))) index)
              (expect (eq? (cadr (node-data (car copies))) payload) #t)
              (loop (cdr source) (cdr copies) (+ index 1))))
          (vector-set! payload 0 'changed)
          (expect (vector-ref shared 0) 'payload)))
      (define (test-attached-declarations)
        (let* ((loc (make-loc "declaration.scm" 3 4))
               (definition (make-value-definition 'answer #f))
               (bind (make-value-binding definition (make-literal 42 #f) #f))
               (declaration (make-type-declaration definition 'I64 loc)))
          (attach-declarations! (list declaration bind))
          (expect (eq? (binding-declaration definition) declaration) #t)
          (let* ((copy (copy-ir-graph (list bind declaration)))
                 (definition (value-binding-definition (car copy))))
            (expect (eq? (binding-declaration definition) (cadr copy)) #t))
          (expect (guard (failure (else (error-object-message failure)))
                    (attach-declarations! (list bind declaration)))
                  "declaration.scm:3:4: type declaration requires one local definition")))
      (define (test-overload-member-identity)
        (let* ((family (make-value-definition 'choose #f))
               (body (make-name (make-value-definition 'implementation #f) #f))
               (first (make-overload-declaration family '(-> I64 I64) body #f))
               (second (make-overload-declaration family '(-> Bool Bool) body #f)))
          (expect (eq? (overload-declaration-definition first)
                       (overload-declaration-definition second)) #t)
          (expect (eq? (overload-declaration-member first) (overload-declaration-member second)) #f)
          (expect (overload-declaration-type first) '(-> I64 I64))
          (expect (eq? (binding-initializer (overload-declaration-member first)) body) #t)))
      (define (test-ir)
        (run-test test-source-holes)
        (run-test test-definition-cycle)
        (run-test test-copy-proof-sharing)
        (run-test test-copy-mutable-data)
        (run-test test-copy-retained-identities)
        (run-test test-copy-pair-graph)
        (run-test test-copy-wide-sharing)
        (run-test test-attached-declarations)
        (run-test test-overload-member-identity))))
   (else)))

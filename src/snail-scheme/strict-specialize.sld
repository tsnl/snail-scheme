;; Turn checked polymorphic templates into concrete code and storage demands.
;; A source site owns the initialization event; a value owns one concrete
;; payload; a function owns code. Duplicating code never schedules initialization.
(define-library (snail-scheme strict-specialize)
  (export monomorphize mono-program-body mono-program-functions mono-program-globals mono-program-exports
          site-instances site-global? site-source site-token site-check site-values
          value-binding? value-type value-site value-initializer value-index
          value-parameter? value-source
          function-index function-type* function-parameters function-rest-binding
          function-body function-captures function-source)
  (import (scheme base) (scheme cxr) (snail-scheme strict-types) (snail-scheme strict-core)
          (only (snail-scheme ir)
                make-node node? node-kind node-type node-loc node-data node-constraints
                binding-scheme binding-initializer binding-kind binding-payload
                value-definition-name value-definition-loc)
          (snail-scheme strict-overloads)
          (only (snail-scheme wasm-extern) native-scalar-signature))
  (begin

    ;; ---- Source sites and concrete copies ----

    ;; Contexts preserve lexical identity while an enclosing function is copied.
    ;; A site belongs to that concrete lexical scope. Its instance list grows
    ;; when a use demands another type; its source bind event stays in place.

    (define-record-type <context>
      (make-context sites parent substitutions) context?
      (sites context-sites)
      (parent context-parent)
      (substitutions context-substitutions))
    (define-record-type <site>
      (make-site source context global? instances token check) site?
      (source site-source)
      (context site-context set-site-context!)
      (global? site-global?)
      (instances site-instances set-site-instances!)
      (token site-token set-site-token!)
      (check site-check set-site-check!))
    (define-record-type <value>
      (make-value source type site initializer index parameter?) value-binding?
      (source value-source)
      (type value-type)
      (site value-site)
      (initializer value-initializer set-value-initializer!)
      (index value-index)
      (parameter? value-parameter?))
    (define-record-type <function>
      (make-function index source type parameters rest body captures) function?
      (index function-index)
      (source function-source)
      (type function-type*)
      (parameters function-parameters set-function-parameters!)
      (rest function-rest-binding set-function-rest-binding!)
      (body function-body set-function-body!)
      (captures function-captures set-function-captures!))
    (define-record-type <program>
      (make-mono-program body functions globals exports) mono-program?
      (body mono-program-body)
      (functions mono-program-functions)
      (globals mono-program-globals)
      (exports mono-program-exports))
    (define-record-type <state>
      (make-state functions next-value globals depth instances classes) state?
      (functions state-functions set-state-functions!)
      (next-value state-next-value set-state-next-value!)
      (globals state-globals set-state-globals!)
      (depth state-depth set-state-depth!)
      (instances state-instances) (classes state-classes))

    ;; ---- Lexical identity and concrete substitutions ----

    (define (lookup key entries) (let ((entry (assq key entries))) (and entry (cdr entry))))
    (define (context-site binding context)
      (and context (or (lookup binding (context-sites context)) (context-site binding (context-parent context)))))
    (define (concrete type context loc)
      (require-concrete (substitute type (context-substitutions context)) loc))
    (define (new-value source type site parameter? state)
      (let ((value (make-value source type site #f (state-next-value state) parameter?)))
        (set-state-next-value! state (+ (state-next-value state) 1))
        value))
    (define (new-sites bindings parent global?)
      (let* ((sites (map (lambda (binding) (cons binding (make-site binding #f global? '() #f #f))) bindings))
             (context (make-context sites parent (context-substitutions parent))))
        (for-each (lambda (entry) (set-site-context! (cdr entry) context)) sites) context))

    ;; ---- Required substitutions and bounded instance reservation ----

    ;; The public function type alone is not a sufficient key. Body, capture,
    ;; and class evidence can mention variables absent from that signature.
    ;; Ignore a quantified variable only when neither body nor evidence uses it.

    (define (template-variables node)
      (if (not node) '()
          (identity-union (type-variables (cons (node-type node) (node-constraints node)))
                          (let walk ((data (node-data node)))
                            (cond ((node? data) (template-variables data))
                                  ((pair? data) (identity-union (walk (car data)) (walk (cdr data))))
                                  (else '()))))))
    (define (instance-substitutions binding substitutions context loc)
      (let ((needed (identity-union (type-variables (scheme-constraints (binding-scheme binding)))
                                    (template-variables (binding-initializer binding)))))
        (let collect ((variables (scheme-variables (binding-scheme binding))))
          (cond ((null? variables) '())
                ((not (memq (car variables) needed)) (collect (cdr variables)))
                (else (cons (cons (car variables)
                                  (concrete (or (lookup (car variables) substitutions) (car variables)) context loc))
                            (collect (cdr variables))))))))
    (define (matching-instance key instances)
      (cond ((null? instances) #f) ((type-equal? key (caar instances)) (cdar instances))
            (else (matching-instance key (cdr instances)))))
    (define (reserve-value! site type key loc state)
      (let ((value (new-value (site-source site) type site #f state)))
        (when (or (>= (state-depth state) 128) (>= (length (site-instances site)) 64))
          (strict-error loc "specialization limit exceeded; recursive instances keep changing" key))
        (set-site-instances! site (append (site-instances site) (list (cons key value))))
        value))
    (define (request-value site type substitutions caller loc state)
      (let* ((mapping (instance-substitutions (site-source site) substitutions caller loc))
             (key (cons type mapping))
             (prior (matching-instance key (site-instances site))))
        (or prior
            (let ((value (reserve-value! site type key loc state)))
              (initialize-instance! value mapping state)
              value))))
    ;; Reservation precedes cloning. Recursive uses can name the pending value.
    ;; Cloning builds code; the source bind will execute its initializer later.
    (define (initialize-instance! value mapping state)
      (let* ((site (value-site value)) (parent (site-context site))
             (context (make-context '() parent (append mapping (context-substitutions parent)))))
        (set-state-depth! state (+ (state-depth state) 1))
        (set-value-initializer! value (clone (binding-initializer (site-source site)) context state))
        (set-state-depth! state (- (state-depth state) 1))))

    ;; ---- Concrete expression copies ----

    (define (clone node context state)
      (require-overloads! (substitute (node-constraints node) (context-substitutions context))
                          (state-classes state) (state-instances state) (node-loc node))
      (let ((type (concrete (node-type node) context (node-loc node))))
        (case (node-kind node)
          ((name) (clone-name node type context state))
          ((lambda) (clone-lambda node type context state))
          ((block) (clone-block node context #f state))
          ((let) (clone-let node context state))
          ((bind) (clone-binding node context state))
          ((literal unit) (make-node (node-kind node) type (node-loc node) (node-data node) '()))
          ((call) (make-node 'call type (node-loc node)
                             (list (clone (car (node-data node)) context state)
                                   (map (lambda (node) (clone node context state)) (cadr (node-data node)))) '()))
          ((if convert) (make-node (node-kind node) type (node-loc node)
                                   (map (lambda (node) (clone node context state)) (node-data node)) '()))
          (else (strict-error (node-loc node) "unsupported checked core operation" (node-kind node))))))
    (define (clone-name node type context state)
      (check-obligations node context state)
      (let* ((original (car (node-data node)))
             (view (if (eq? (binding-kind original) 'method) (resolve-method node type context state) (node-data node)))
             (binding (car view)))
        (if (memq (binding-kind binding) '(primitive extern))
            (make-node (binding-kind binding) type (node-loc node) (list (binding-payload binding)) '())
            (make-node 'get type (node-loc node)
                       (list (name-value view type context (node-loc node) state)) '()))))
    (define (name-value view type context loc state)
      (let* ((binding (car view)) (site (context-site binding context)))
        (unless site (strict-error loc "missing lexical specialization site"))
        (if (memq (binding-kind binding) '(parameter mono-parameter))
            (cdar (site-instances site))
            (request-value site type (cadr view) context loc state))))
    (define (exact-instance constraint context loc state)
      (let* ((types (map (lambda (type) (concrete type context loc)) (cdr constraint)))
             (class (overload-class (car constraint) (state-classes state))))
        (if class
            (let ((view (select-overload-view class (car types) (state-instances state) loc #t)))
              (require-overloads! (overload-view-constraints view) (state-classes state) (state-instances state) loc)
              (for-each (lambda (goal) (exact-instance goal context loc state)) (overload-view-constraints view))
              (overload-view-instance view))
            (let find ((instances (state-instances state)))
              (cond ((null? instances) (strict-error loc "no exact static typeclass instance" constraint))
                    ((and (eq? (car constraint) (class-definition (instance-class (car instances))))
                          (type-equal? types (instance-types (car instances)))) (car instances))
                    (else (find (cdr instances))))))))
    (define (check-obligations node context state)
      (for-each (lambda (constraint) (exact-instance constraint context (node-loc node) state)) (node-constraints node)))
    (define (resolve-method node type context state)
      (let* ((method (car (node-data node)))
             (instance (exact-instance (car (node-constraints node)) context (node-loc node) state))
             (binding (cdr (assq method (instance-members instance)))))
        (let-values (((signature obligations substitutions) (instantiate (binding-scheme binding))))
          (unify! signature type (node-loc node))
          (require-overloads! obligations (state-classes state) (state-instances state) (node-loc node))
          (for-each (lambda (constraint) (exact-instance constraint context (node-loc node) state)) obligations)
          (list binding substitutions))))

    ;; ---- Preserve source initialization events ----

    ;; An effectful initializer cannot generalize. Demand it even when unused.
    ;; A generalized initializer may need several concrete payloads, but an
    ;; unused alias must still perform its original source read. Let actuals
    ;; use their caller context; recursive block bindings use their own scope.
    (define (prepare-initializer! site source-context loc state)
      (let* ((binding (site-source site)) (scheme (binding-scheme binding)))
        (if (null? (scheme-variables scheme))
            (request-value site (concrete (scheme-type scheme) source-context loc)
                           '() source-context loc state)
            (set-site-check! site
                             (initializer-check (binding-initializer binding) source-context state)))))
    (define (clone-binding node context state)
      (let ((site (context-site (car (node-data node)) context)))
        (prepare-initializer! site context (node-loc node) state)
        (make-node 'bind 'Unit (node-loc node) (list site) '())))
    ;; A nonexpansive name still reads a source binding, even if no concrete
    ;; payload instance is needed. A Unit token preserves that readiness effect
    ;; independently of the erased payload. It is allocated only when observed.
    ;; The source bind publishes it after required reads and initializers;
    ;; merely capturing the token does not read it.
    (define (readiness-token! site state)
      (or (site-token site)
          (let ((value (new-value (site-source site) 'Unit site #f state)))
            (set-value-initializer! value (make-node 'unit 'Unit #f '() '()))
            (set-site-token! site value) value)))
    (define (initializer-check node context state)
      (case (node-kind node)
        ((name)
         (let ((binding (car (node-data node))))
           (if (memq (binding-kind binding) '(primitive method extern)) (make-node 'unit 'Unit (node-loc node) '() '())
               (make-node 'get 'Unit (node-loc node)
                          (list (readiness-token! (context-site binding context) state)) '()))))
        ((convert) (initializer-check (car (node-data node)) context state))
        (else (make-node 'unit 'Unit (node-loc node) '() '()))))
    (define (clone-block node parent global? state)
      (let* ((context (new-sites (car (node-data node)) parent global?))
             (items (map (lambda (node) (clone node context state)) (cadr (node-data node)))))
        (when global? (set-state-globals! state (map cdr (context-sites context))))
        (make-node 'block (concrete (node-type node) context (node-loc node)) (node-loc node)
                   (list (map cdr (context-sites context)) items) '())))
    (define (clone-let node parent state)
      (let* ((context (new-sites (car (node-data node)) parent #f))
             (sites (map cdr (context-sites context))))
        (for-each (lambda (site) (prepare-initializer! site parent (node-loc node) state)) sites)
        (let ((body (clone (caddr (node-data node)) context state)))
          (make-node 'let (node-type body) (node-loc node) (list sites body) '()))))

    ;; ---- Reserve function code and parameters ----

    ;; A function is reserved before cloning its body. References to a recursive
    ;; binding therefore reuse its pending value rather than expanding forever.
    (define (clone-lambda node type parent state)
      (let* ((function (make-function (length (state-functions state)) node type '() #f #f '()))
             (fixed (car (node-data node))) (rest (cadr (node-data node)))
             (bindings (append fixed (if rest (list rest) '())))
             (types (append (function-domains type) (if rest (list (list 'List (function-rest type))) '())))
             (context (new-sites bindings parent #f))
             (values (map (lambda (entry type) (new-value (car entry) type (cdr entry) #t state)) (context-sites context) types)))
        (set-state-functions! state (append (state-functions state) (list function)))
        (for-each (lambda (entry value) (set-site-instances! (cdr entry) (list (cons 'parameter value)))) (context-sites context) values)
        (set-function-parameters! function (if rest (reverse (cdr (reverse values))) values))
        (set-function-rest-binding! function (and rest (car (reverse values))))
        (set-function-body! function (clone (caddr (node-data node)) context state))
        (make-node 'closure type (node-loc node) (list function) '())))

    ;; ---- Capture dependencies ----

    ;; Demand is complete before traversal: later uses may have added payloads
    ;; or readiness tokens to earlier sites. Backend storage uses this same list.
    (define (site-values sites)
      (apply append
             (map (lambda (site)
                    (append (if (site-token site) (list (site-token site)) '())
                            (map cdr (site-instances site)))) sites)))
    (define (site-initializers sites)
      (append (map value-initializer (site-values sites))
              (let collect ((sites sites))
                (cond ((null? sites) '()) ((site-check (car sites)) (cons (site-check (car sites)) (collect (cdr sites))))
                      (else (collect (cdr sites)))))))
    ;; Descend into work performed in this activation. A closure contributes
    ;; its captures, not its body; each function body is analyzed separately.
    (define (execution-children node)
      (case (node-kind node)
        ((bind) (site-initializers (node-data node)))
        ((block) (cadr (node-data node)))
        ((let) (append (site-initializers (car (node-data node))) (list (cadr (node-data node)))))
        ((call) (cons (car (node-data node)) (cadr (node-data node))))
        ((if convert) (node-data node)) (else '())))
    (define (local-values node)
      (identity-union (if (memq (node-kind node) '(block let)) (site-values (car (node-data node))) '())
                      (apply append (map local-values (execution-children node)))))
    (define (used-values node)
      (case (node-kind node)
        ((get) (node-data node)) ((closure) (function-captures (car (node-data node))))
        (else (apply append (map used-values (execution-children node))))))
    (define (function-free-values function)
      (let ((bound (append (function-parameters function) (if (function-rest-binding function) (list (function-rest-binding function)) '())
                           (local-values (function-body function)))))
        (let collect ((values (used-values (function-body function))) (result '()))
          (cond ((null? values) (reverse result))
                ((or (memq (car values) bound) (site-global? (value-site (car values))) (memq (car values) result))
                 (collect (cdr values) result))
                (else (collect (cdr values) (cons (car values) result)))))))
    ;; Nested closures can pass a captured value through several environments.
    ;; Iterate until every function carries those transitive requirements.
    (define (settle-captures! functions)
      (let ((changed? #f))
        (for-each (lambda (function)
                    (let ((captures (function-free-values function)))
                      (unless (same-values? captures (function-captures function))
                        (set-function-captures! function captures) (set! changed? #t)))) functions)
        (when changed? (settle-captures! functions))))
    (define (same-values? left right)
      (or (and (null? left) (null? right))
          (and (pair? left) (pair? right) (eq? (car left) (car right))
               (same-values? (cdr left) (cdr right)))))

    ;; ---- Select public scalar workers ----

    ;; A selected worker may capture managed values, but its public signature
    ;; shares the scalar import contract until a cross-module GC ABI exists.
    (define (check-export-signature type loc)
      (when (function-rest type) (strict-error loc "native export requires fixed scalar parameters"))
      (guard (failure (else (strict-error loc "native export requires scalar parameters and a scalar or Unit result")))
        (native-scalar-signature (function-domains type) (function-result type))))
    (define (named-global-sites name sites)
      (cond ((null? sites) '())
            ((eq? name (value-definition-name (site-source (car sites))))
             (cons (car sites) (named-global-sites name (cdr sites))))
            (else (named-global-sites name (cdr sites)))))
    (define (selected-export name sites loc)
      (when (eq? name 'main) (strict-error loc "main is reserved for one-shot initialization"))
      (let ((matches (named-global-sites name sites)))
        (unless (= (length matches) 1) (strict-error loc "export requires one unambiguous top-level binding" name))
        (let* ((site (car matches)) (binding (site-source site)) (scheme (binding-scheme binding))
               (loc (value-definition-loc binding)))
          (unless (and (eq? (binding-kind binding) 'value) (cadr (binding-payload binding))
                       (null? (scheme-variables scheme)) (function-type? (scheme-type scheme)))
            (strict-error loc "export requires an explicit concrete function declaration" name))
          (require-concrete (scheme-type scheme) loc)
          (check-export-signature (scheme-type scheme) loc)
          (cons name (cdar (site-instances site))))))
    (define (check-export-names names loc)
      (unless (null? names)
        (unless (symbol? (car names)) (strict-error loc "export name must be an identifier" (car names)))
        (when (memq (car names) (cdr names)) (strict-error loc "export names must be distinct" (car names)))
        (check-export-names (cdr names) loc)))

    ;; ---- Checked templates to a concrete program ----

    (define (monomorphize program . export-names)
      (let* ((state (make-state '() 0 '() 0 (program-instances program) (program-classes program))) (context (make-context '() #f '()))
             (body (clone-block (program-body program) context #t state)))
        (check-export-names export-names (node-loc body))
        (settle-captures! (state-functions state))
        (make-mono-program body (state-functions state) (state-globals state)
                           (map (lambda (name) (selected-export name (state-globals state) (node-loc body))) export-names))))))

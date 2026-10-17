;; Parsed libraries describe dependencies without obtaining them. Resolution
;; consumes an explicit map and makes owned IR; it never reads source or runs
;; initializers. Source identities survive copies through their origin IDs.
(define-library (lofi library)
  (export make-lofi-library make-expanding-library lofi-library? lofi-library-id lofi-library-name
          lofi-library-scope lofi-library-imports lofi-library-exports
          lofi-library-declarations lofi-library-bindings lofi-library-loc lofi-library-syntax
          make-scope-id scope-id?
          make-scoped-reference scoped-reference? reference-name reference-scope
          reference-role reference-loc
          make-import-selection import-selection? selection-kind selection-from selection-names
          make-lofi-import lofi-import? lofi-import-provider lofi-import-selection
          lofi-import-scope lofi-import-loc
          resolve-library-map resolve-source-library)
  (import
   (scheme base)
   (scheme cxr)
   (lofi resolved-library)
   (lofi ir)
   (lofi macros)
   (only (scheme hash-table) make-hash-table hash-table-set! hash-table-ref/default))
  (begin

    ;; ---- Parsed library values ----

    (define-record-type <scope-id>
      (make-scope-id) scope-id?)
    ;; Local lexical lookup has already happened. A remaining name can only
    ;; denote an import in this scope; a later local let cannot capture it.
    (define-record-type <scoped-reference>
      (make-scoped-reference name scope role loc) scoped-reference?
      (name reference-name)
      (scope reference-scope)
      (role reference-role)
      (loc reference-loc))
    (define-record-type <import-selection>
      (make-import-selection kind from names) import-selection?
      (kind selection-kind)
      (from selection-from)
      (names selection-names))
    (define-record-type <lofi-import>
      (make-lofi-import provider selection scope loc) lofi-import?
      (provider lofi-import-provider)
      (selection lofi-import-selection)
      (scope lofi-import-scope)
      (loc lofi-import-loc))
    (define-record-type <lofi-library>
      (new-lofi-library id name scope imports exports declarations bindings loc expander syntax) lofi-library?
      (id lofi-library-id)
      (name lofi-library-name)
      (scope lofi-library-scope)
      (imports lofi-library-imports) ; descriptive selections in source order
      (exports lofi-library-exports) ; public names with local or scoped references
      (declarations lofi-library-declarations) ; source nodes retain locations and lexical structure
      (bindings lofi-library-bindings) ; local names for import-conflict and family resolution
      (loc lofi-library-loc)
      (expander library-expander)
      (syntax lofi-library-syntax))
    (define (make-lofi-library name scope imports exports declarations bindings loc)
      (new-lofi-library (make-library-id) name scope imports exports declarations bindings loc #f #f))
    (define (make-expanding-library source expander syntax)
      (new-lofi-library (lofi-library-id source) (lofi-library-name source) (lofi-library-scope source)
                        (lofi-library-imports source) (lofi-library-exports source)
                        (lofi-library-declarations source) (lofi-library-bindings source)
                        (lofi-library-loc source) expander syntax))

    ;; ---- Import selection over a provider's public names ----

    (define (library-environment library)
      (map (lambda (entry) (cons (named-binding-name entry) (named-binding-definition entry)))
           (library-exports library)))
    (define (named-bindings environment)
      (map (lambda (entry) (make-named-binding (car entry) (cdr entry))) environment))
    (define (require-import name bindings loc)
      (or (assq name bindings) (error "unknown import" loc name)))
    (define (select-only bindings names loc)
      (for-each (lambda (name) (require-import name bindings loc)) names)
      (let select ((bindings bindings))
        (cond ((null? bindings) '())
              ((memq (caar bindings) names) (cons (car bindings) (select (cdr bindings))))
              (else (select (cdr bindings))))))
    (define (select-renamed bindings names loc)
      (for-each (lambda (rename) (require-import (car rename) bindings loc)) names)
      (let ((renamed (map (lambda (entry)
                            (let ((rename (assq (car entry) names)))
                              (cons (if rename (cdr rename) (car entry)) (cdr entry)))) bindings)))
        (reverse (merge-imports '() renamed loc))))
    (define (select-imports selection bindings loc)
      (case (selection-kind selection)
        ((all) bindings)
        ((only) (select-only (select-imports (selection-from selection) bindings loc)
                             (selection-names selection) loc))
        ((rename) (select-renamed (select-imports (selection-from selection) bindings loc)
                                  (selection-names selection) loc))
        (else (error "invalid import selection" loc))))
    (define (merge-imports environment additions loc)
      (if (null? additions) environment
          (let* ((entry (car additions)) (old (assq (car entry) environment)))
            (when (and old (not (eq? (cdr old) (cdr entry))))
              (error "conflicting imported bindings" loc (car entry)))
            (merge-imports (if old environment (cons entry environment)) (cdr additions) loc))))
    (define (import-environment imports)
      (let loop ((imports imports) (environment '()))
        (if (null? imports) environment
            (loop (cdr imports)
                  (merge-imports environment
                                 (map (lambda (entry) (cons (named-binding-name entry) (named-binding-definition entry)))
                                      (import-declaration-bindings (car imports)))
                                 (import-declaration-loc (car imports)))))))

    ;; ---- An explicit graph owns resolution state ----

    (define-record-type <resolution>
      (make-resolution libraries completed) resolution?
      (libraries resolution-libraries)
      (completed resolution-completed set-resolution-completed!))
    (define (library-key? key)
      (and (list? key) (pair? key)
           (let loop ((names key))
             (or (null? names) (and (symbol? (car names)) (loop (cdr names)))))))
    (define (check-library-map libraries parsed?)
      (unless (list? libraries) (error "expected a library map"))
      (unless (null? libraries)
        (let ((entry (car libraries)))
          (unless (and (pair? entry) (library-key? (car entry))
                       (if parsed? (lofi-library? (cdr entry)) (library? (cdr entry))))
            (error "invalid library map entry" entry))
          (when (assoc (car entry) (cdr libraries)) (error "duplicate library key" (car entry)))
          (check-library-map (cdr libraries) parsed?))))
    (define (resolve-library-map libraries)
      (check-library-map libraries #t)
      (let ((state (make-resolution libraries '())))
        (map (lambda (entry) (cons (car entry) (resolve-unit (cdr entry) state '()))) libraries)))
    ;; Compatibility belongs to the source adapter. The map API above accepts
    ;; only parsed values; old CLI callers can still supply resolved core/cache
    ;; libraries here. Checking later takes its own copy of every declaration.
    (define (resolve-source-library root libraries cached)
      (check-library-map libraries #t)
      (check-library-map cached #f)
      (for-each (lambda (entry)
                  (when (assoc (car entry) cached) (error "duplicate library key" (car entry)))) libraries)
      (resolve-unit root (make-resolution (append libraries cached) '()) '()))
    (define (resolve-provider declaration state pending)
      (let* ((key (lofi-import-provider declaration))
             (entry (assoc key (resolution-libraries state))))
        (unless entry (error "Lofi library not found" (lofi-import-loc declaration) key))
        (resolve-unit (cdr entry) state pending)))
    (define (resolve-import declaration scope state pending)
      (unless (eq? (lofi-import-scope declaration) scope)
        (error "import belongs to a different scope" (lofi-import-loc declaration)))
      (let* ((provider (resolve-provider declaration state pending))
             (bindings (select-imports (lofi-import-selection declaration)
                                       (library-environment provider) (lofi-import-loc declaration))))
        ;; Even an empty selection keeps its provider's initialization and instances.
        (make-import-declaration (list provider) (named-bindings bindings) #f (lofi-import-loc declaration))))
    (define (resolve-unit source state pending)
      (if (library? source) source
          (let* ((id (lofi-library-id source)) (known (assq id (resolution-completed state))))
            (cond (known (cdr known))
                  ((assq id pending)
                   (error "cyclic library import" (lofi-library-loc source)
                          (reverse (cons (lofi-library-name source) (map cdr pending)))))
                  (else (resolve-new-unit source state (cons (cons id (lofi-library-name source)) pending)))))))
    (define (resolve-new-unit source state pending)
      (let* ((imports (map (lambda (declaration)
                             (resolve-import declaration (lofi-library-scope source) state pending))
                           (lofi-library-imports source)))
             (environment (import-environment imports))
             (expanded (if (library-expander source) ((library-expander source) imports) source))
             (library (lower-library expanded imports (lofi-library-id source) environment)))
        (set-resolution-completed! state (cons (cons (lofi-library-id source) library)
                                               (resolution-completed state)))
        library))

    ;; ---- Replace scoped imports in an owned declaration graph ----

    (define (reference-accepts? reference definition)
      (let ((kind (binding-kind definition)))
        (case (reference-role reference)
          ((binding) #t)
          ((value) (not (memq kind '(datatype typeclass instance syntax syntax-form))))
          ((datatype) (eq? kind 'datatype))
          ((constraint) (memq kind '(typeclass overload)))
          (else #f))))
    (define (resolve-reference reference scope imports)
      (unless (eq? (reference-scope reference) scope)
        (error "reference belongs to a different import scope" (reference-loc reference)))
      (let ((entry (assq (reference-name reference) imports)))
        (unless entry (error "unbound Lofi name" (reference-loc reference) (reference-name reference)))
        (unless (reference-accepts? reference (cdr entry))
          (error "imported binding has the wrong kind" (reference-loc reference)
                 (reference-name reference) (reference-role reference)))
        (cdr entry)))
    (define (overload-aliases bindings imports)
      (let loop ((bindings bindings) (aliases '()))
        (if (null? bindings) aliases
            (let* ((local (cdar bindings)) (imported (assq (caar bindings) imports)))
              (when (and imported (not (and (eq? (binding-kind local) 'overload)
                                            (eq? (binding-kind (cdr imported)) 'overload))))
                (error "duplicate binding" (value-definition-loc local) (caar bindings)))
              (loop (cdr bindings) (if imported (cons (cons local (cdr imported)) aliases) aliases))))))
    (define (lower-declarations roots scope imports aliases)
      (let ((visited (make-hash-table eq?)))
        (define (walk-definition definition)
          (set-binding-declaration! definition (walk (binding-declaration definition)))
          (set-binding-initializer! definition (walk (binding-initializer definition)))
          definition)
        (define (walk-node node)
          (let ((data (walk (node-data node))))
            (if (eq? (node-kind node) 'static-kind)
                (begin
                  (unless (equal? (car data) (cadr data))
                    (error "static definition kind mismatch" (node-loc node) (cadr data)))
                  (caddr data))
                (begin (resolve-node-data! node data) node))))
        (define (walk object)
          (cond ((protected-reference? object) (resolve-protected-reference object))
                ((scoped-reference? object) (resolve-reference object scope imports))
                ((assq object aliases) => cdr)
                ((hash-table-ref/default visited object #f))
                ((or (value-definition? object) (node? object))
                 (hash-table-set! visited object object)
                 (let ((resolved (if (node? object) (walk-node object) (walk-definition object))))
                   (hash-table-set! visited object resolved) resolved))
                ((pair? object) (cons (walk (car object)) (walk (cdr object))))
                (else object)))
        (walk roots)))
    (define (lower-library source imports identity environment)
      (let* ((exports (lofi-library-exports source))
             (copies (copy-ir-graph (list (lofi-library-declarations source) (lofi-library-bindings source)
                                          (map named-binding-definition exports))))
             (aliases (overload-aliases (cadr copies) environment))
             (resolved (lower-declarations copies (lofi-library-scope source) environment aliases)))
        (rebase-transformers! (cadr resolved))
        (make-library (lofi-library-name source) imports
                      (map make-named-binding (map named-binding-name exports) (caddr resolved))
                      (map lofi-import-provider (lofi-library-imports source))
                      (car resolved) (lofi-library-loc source) identity)))))

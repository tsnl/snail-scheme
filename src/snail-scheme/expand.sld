;; Expand located syntax into the resolved HIR in hir.sld. See doc/hir.md.
;; Resolve imports, discover body bindings, then expand expressions. Macro rules
;; are parsed when installed, then matched and instantiated at each use.
;;
;; Environments are alists from identifier keys to value or macro definitions.
;; They are passed through recursive descent and never stored in HIR.
;; Definition identities are reserved before expanding bodies, then shared by
;; references, value bindings, and parameters without mutation.

(define-library (snail-scheme expand)
  (export expand-program expand-library macroexpand-1)
  (import (scheme base)
          (scheme cxr)
          (snail-scheme common)
          (snail-scheme syntax)
          (snail-scheme pattern)
          (snail-scheme hir))
  (begin
    ;;
    ;; Public API
    ;;

    ;; The loader receives a library-name datum and returns define-library syntax
    ;; or #f. (scheme base) is supplied internally. Each call starts a fresh library cache.
    (define (expand-program forms library-loader)
      (assert (list? forms))
      (assert (procedure? library-loader))
      (let-values (((imports body) (split-program-imports forms)))
        (expand-program-body imports body library-loader
                             (and (pair? forms) (syntax-loc (car forms))))))

    (define (expand-library form library-loader)
      (assert (procedure? library-loader))
      (let-values (((library cache transformers)
                    (expand-library-form form (library-parts form) library-loader
                                         (initial-library-cache) '() '())))
        library))

    ;; Perform one head transformation using the transient environment and
    ;; transformer alist. Builtin forms and ordinary calls return unchanged.
    ;; Operands remain syntax, including operands that the macro discards.
    (define (macroexpand-1 form environment transformers)
      (let ((rules (head-transformer form environment transformers)))
        (if rules (apply-transformer rules form environment) form)))

    ;;
    ;; Program and library
    ;;

    (define (expand-program-body imports body loader loc)
      (let*-values (((parsed bindings dependencies cache transformers)
                     (expand-import-declarations imports loader (initial-library-cache) '() '()))
                    ((items environment transformers)
                     (expand-body body '() bindings transformers 1000)))
        (make-program (map cdr parsed) (runtime-items items) dependencies loc)))

    (define (split-program-imports forms)
      (let loop ((forms forms) (imports '()))
        (if (and (pair? forms) (declaration? (car forms) 'import))
            (loop (cdr forms) (cons (car forms) imports))
            (values (reverse imports) forms))))

    (define (expand-library-form form parts loader cache transformers loading)
      (let ((bodies (map library-body-forms (cdr parts))))
        (expand-library-declarations form parts bodies loader cache transformers
                                     (cons (car parts) loading))))

    ;; Imports are visible to every body, regardless of declaration placement.
    (define (expand-library-declarations form parts bodies loader cache transformers loading)
      (let*-values (((imports bindings dependencies cache transformers)
                     (expand-import-declarations
                      (filter (lambda (form) (declaration? form 'import)) (cdr parts))
                      loader cache transformers loading))
                    ((chunks environment transformers)
                     (expand-body-chunks bodies '() bindings transformers 1000)))
        (values (build-library form parts chunks imports environment dependencies)
                cache transformers)))

    (define (build-library form parts chunks imports environment dependencies)
      (let-values (((parsed exports)
                    (rebuild-library-declarations (cdr parts) chunks imports environment)))
        (make-library (car parts) parsed exports dependencies (syntax-loc form))))

    (define (library-parts form)
      (if (not (declaration? form 'define-library)) (fail form "expected define-library"))
      (let ((parts (fields form '(_ name declaration ...))))
        (cons (library-name-datum (car parts)) (cadr parts))))

    (define (library-body-forms declaration)
      (cond
       ((declaration? declaration 'begin) (car (fields declaration '(_ item ...))))
       ((or (declaration? declaration 'import) (declaration? declaration 'export)) '())
       (else (fail declaration "unsupported library declaration"))))

    (define (rebuild-library-declarations declarations chunks imports environment)
      (let loop ((raw declarations) (chunks chunks) (parsed '()) (exports '()))
        (if (null? raw) (values (reverse parsed) (reverse exports))
            (let-values (((declaration additions)
                          (rebuild-library-declaration (car raw) (car chunks) imports environment)))
              (check-export-names additions exports (car raw))
              (loop (cdr raw) (cdr chunks) (cons declaration parsed)
                    (append (reverse additions) exports))))))

    (define (rebuild-library-declaration form items imports environment)
      (cond
       ((declaration? form 'import) (values (cdr (assq form imports)) '()))
       ((declaration? form 'export) (expand-export-declaration form environment))
       (else (values (make-library-body (runtime-items items) (syntax-loc form)) '()))))

    (define (expand-export-declaration form environment)
      (let ((specs (map (lambda (spec) (expand-export spec environment))
                        (car (fields form '(_ spec ...))))))
        (values (make-export-declaration specs (syntax-loc form))
                (map (lambda (spec)
                       (make-named-binding (export-spec-external-name spec)
                                           (export-spec-definition spec))) specs))))

    (define (initial-library-cache)
      (list (cons '(scheme base) (core-library))))

    ;; The returned cache and transformer alist include all newly loaded libraries.
    ;; The loading path belongs to this descent only; siblings receive the old path.
    (define (load-library name use loader cache transformers loading)
      (cond
       ((member name loading) (fail use "cyclic library import" name))
       ((assoc name cache) => (lambda (entry) (values (cdr entry) cache transformers)))
       (else (load-library-source name use (loader name) loader cache transformers loading))))

    (define (load-library-source name use source loader cache transformers loading)
      (if (not source) (fail use "library not found" name))
      (let ((parts (library-parts source)))
        (if (not (equal? name (car parts)))
            (fail use "library name does not match import" name))
        (let-values (((library cache transformers)
                      (expand-library-form source parts loader cache transformers loading)))
          (values library (cons (cons name library) cache) transformers))))

    ;;
    ;; Import and export
    ;;

    (define (expand-import-declarations forms loader cache transformers loading)
      (let loop ((forms forms) (parsed '()) (bindings '()) (dependencies '())
                 (cache cache) (transformers transformers))
        (if (null? forms)
            (values (reverse parsed) bindings (unique dependencies) cache transformers)
            (let-values (((declaration additions deps cache transformers)
                          (expand-import (car forms) loader cache transformers loading)))
              (loop (cdr forms) (cons (cons (car forms) declaration) parsed)
                    (merge-imports bindings additions (car forms))
                    (append dependencies deps) cache transformers)))))

    (define (expand-import form loader cache transformers loading)
      (let-values (((sets bindings dependencies cache transformers)
                    (expand-import-sets (car (fields form '(_ set ...)))
                                        loader cache transformers loading)))
        (values (make-import-declaration sets (environment-bindings bindings) (syntax-loc form))
                bindings dependencies cache transformers)))

    (define (expand-import-sets sets loader cache transformers loading)
      (let loop ((sets sets) (parsed '()) (bindings '()) (dependencies '())
                 (cache cache) (transformers transformers))
        (if (null? sets) (values (reverse parsed) bindings (unique dependencies) cache transformers)
            (let-values (((set additions deps cache transformers)
                          (expand-import-set (car sets) loader cache transformers loading)))
              (loop (cdr sets) (cons set parsed)
                    (merge-imports bindings additions (car sets))
                    (append dependencies deps) cache transformers)))))

    (define (expand-import-set form loader cache transformers loading)
      (let* ((parts (syntax-list form))
             (tag (and (pair? parts) (identifier-spelling (car parts)))))
        (if (memq tag '(only except prefix rename))
            (expand-modified-import-set form parts tag loader cache transformers loading)
            (expand-library-import form loader cache transformers loading))))

    (define (expand-modified-import-set form parts tag loader cache transformers loading)
      (if (< (length parts) 2) (fail form "missing import set"))
      (let*-values (((base bindings dependencies cache transformers)
                     (expand-import-set (cadr parts) loader cache transformers loading))
                    ((set bindings) (modify-import-set tag base bindings (cddr parts) form)))
        (values set bindings dependencies cache transformers)))

    (define (expand-library-import form loader cache transformers loading)
      (let ((name (library-name-datum form)))
        (let-values (((library cache transformers)
                      (load-library name form loader cache transformers loading)))
          (values (make-library-import name library (syntax-loc form))
                  (library-bindings library) (cons name (library-dependencies library))
                  cache transformers))))

    (define (library-bindings library)
      (map (lambda (binding) (cons (named-binding-name binding) (named-binding-definition binding)))
           (library-exports library)))

    (define (modify-import-set tag base bindings arguments form)
      (case tag
        ((only except) (restrict-imports tag base bindings arguments form))
        ((prefix) (prefix-imports base bindings arguments form))
        ((rename) (rename-imports base bindings arguments form))))

    (define (restrict-imports tag base bindings arguments form)
      (let ((names (map require-symbol arguments)))
        (check-distinct names form)
        (for-each (lambda (name)
                    (if (not (assq name bindings)) (fail form "unknown imported name" name))) names)
        (values ((if (eq? tag 'only) make-only-import make-except-import)
                 base names (syntax-loc form))
                (restrict-import-bindings tag names bindings))))

    (define (restrict-import-bindings tag names bindings)
      (filter (lambda (entry)
                (if (eq? tag 'only) (memq (car entry) names)
                    (not (memq (car entry) names)))) bindings))

    (define (prefix-imports base bindings arguments form)
      (if (not (= (length arguments) 1)) (fail form "expected import prefix"))
      (let ((prefix (require-symbol (car arguments))))
        (values (make-prefix-import base prefix (syntax-loc form))
                (map (lambda (entry)
                       (cons (string->symbol
                              (string-append (symbol->string prefix) (symbol->string (car entry))))
                             (cdr entry))) bindings))))

    (define (rename-imports base bindings arguments form)
      (let* ((renamings (parse-import-renamings arguments bindings form))
             (renamed (map (lambda (entry) (rename-import-binding entry renamings)) bindings)))
        (check-distinct (map car renamed) form)
        (values (make-rename-import base renamings (syntax-loc form)) renamed)))

    (define (parse-import-renamings arguments bindings form)
      (let ((renamings (map parse-import-rename arguments)))
        (check-distinct (map import-rename-from renamings) form)
        (for-each (lambda (rename)
                    (if (not (assq (import-rename-from rename) bindings))
                        (fail form "unknown renamed import" (import-rename-from rename))))
                  renamings)
        renamings))

    (define (rename-import-binding entry renamings)
      (let ((rename (find (lambda (r) (eq? (import-rename-from r) (car entry))) renamings)))
        (cons (if rename (import-rename-to rename) (car entry)) (cdr entry))))

    (define (parse-import-rename form)
      (let ((parts (fields form '(from to))))
        (make-import-rename (require-symbol (car parts)) (require-symbol (cadr parts))
                            (syntax-loc form))))

    (define (expand-export form environment)
      (let* ((names (parse-export-names form))
             (local (require-symbol (car names)))
             (external (require-symbol (cadr names)))
             (definition (lookup (car names) environment)))
        (if (not definition) (fail form "unbound export" local))
        (make-export-spec local external definition (syntax-loc form))))

    (define (parse-export-names form)
      (if (identifier-spelling form) (list form form)
          (let ((parts (syntax-list form)))
            (if (or (not (= (length parts) 3))
                    (not (eq? (identifier-spelling (car parts)) 'rename)))
                (fail form "expected export name or rename"))
            (cdr parts))))

    ;;
    ;; Body discovery and expansion
    ;;

    (define-record-type <pending-definition>
      (make-pending-definition binding initializer)
      pending-definition?
      (binding pending-definition-binding) ; identifier key . value-definition
      (initializer pending-definition-initializer))

    ;; Keep compile-time definitions until constructing a block's final expression.
    (define-record-type <eliminated-definition>
      (make-eliminated-definition)
      eliminated-definition?)

    ;; Builders receive all value definitions and installed transformers in the
    ;; body, but retain the macro names visible at their own source position.
    (define (expand-body forms outer initial transformers fuel)
      (let-values (((chunks environment transformers)
                    (expand-body-chunks (list forms) outer initial transformers fuel)))
        (values (car chunks) environment transformers)))

    (define (expand-body-chunks chunks outer initial transformers fuel)
      (let*-values (((local reservations)
                     (reserve-direct-definitions (apply append chunks) outer initial))
                    ((builders local transformers)
                     (prepare-body-chunks chunks outer local reservations transformers fuel)))
        (values (build-body-chunks builders (value-bindings local) transformers)
                (append local outer) transformers)))

    (define (build-body-chunks builders value-environment transformers)
      (map (lambda (chunk)
             (map (lambda (build) (build value-environment transformers)) chunk)) builders))

    (define (prepare-body-chunks chunks outer initial reservations transformers fuel)
      (let loop ((chunks chunks) (local initial) (builders '()) (transformers transformers))
        (if (null? chunks) (values (reverse builders) local transformers)
            (let-values (((current local transformers)
                          (prepare-body-items (car chunks) outer local reservations
                                              transformers fuel)))
              (loop (cdr chunks) local (cons current builders) transformers)))))

    (define (prepare-body-items forms outer local reservations transformers fuel)
      (if (null? forms) (values '() local transformers)
          (let*-values (((current local transformers)
                         (prepare-body-item (car forms) outer local reservations transformers fuel))
                        ((rest local transformers)
                         (prepare-body-items (cdr forms) outer local reservations
                                             transformers fuel)))
            (values (append current rest) local transformers))))

    (define (prepare-body-item input outer local reservations transformers fuel)
      (let-values (((form fuel) (expand-head input (append local outer) transformers fuel)))
        (prepare-expanded-body-item form outer local reservations transformers fuel)))

    (define (prepare-expanded-body-item form outer local reservations transformers fuel)
      (case (builtin-tag form (append local outer))
        ((begin)
         (prepare-body-items (car (fields form '(_ item ...))) outer local reservations
                             transformers fuel))
        ((define) (prepare-value-binding form outer local reservations transformers fuel))
        ((define-syntax) (prepare-macro-definition form outer local transformers))
        (else (prepare-expression form outer local transformers fuel))))

    (define (prepare-expression form outer local transformers fuel)
      (values (list (expression-builder form outer (macro-bindings local) fuel))
              local transformers))

    (define (expression-builder form outer macros fuel)
      (lambda (values transformers)
        (expand-expression form (append values macros outer) transformers fuel)))

    (define (prepare-value-binding form outer local reservations transformers fuel)
      (let* ((reservation (assq form reservations))
             (pending (if reservation (cdr reservation) (parse-definition form)))
             (binding (pending-definition-binding pending))
             (next (if reservation local (add-local-bindings local (list binding) form))))
        (values (list (value-binding-builder form pending outer (macro-bindings next) fuel))
                next transformers)))

    (define (value-binding-builder form pending outer macros fuel)
      (let ((build (expression-builder (pending-definition-initializer pending)
                                       outer macros fuel)))
        (lambda (values transformers)
          (make-value-binding (cdr (pending-definition-binding pending))
                              (build values transformers) (syntax-loc form)))))

    ;; Function-definition shorthand introduces the builtin lambda binding directly,
    ;; even when a source binding shadows the spelling lambda.
    (define (parse-definition form)
      (let ((parts (syntax-list form)))
        (if (< (length parts) 3) (fail form "incomplete definition"))
        (if (identifier-of (cadr parts))
            (parse-variable-definition form parts)
            (parse-procedure-definition form parts))))

    (define (parse-variable-definition form parts)
      (if (not (= (length parts) 3)) (fail form "expected one initializer"))
      (make-pending-definition (reserve-value-identifier (cadr parts)) (caddr parts)))

    (define (parse-procedure-definition form parts)
      (let* ((head (cadr parts))
             (view (and (list-syntax? head) (syntax-view head))))
        (if (not (pair? view)) (fail head "expected definition name or function header"))
        (make-pending-definition
         (reserve-value-identifier (car view))
         (make-list-syntax (cons (builtin-identifier-syntax 'lambda form)
                                 (cons (cdr view) (cddr parts))) '() (syntax-loc form)))))

    (define (builtin-identifier-syntax name source)
      (make-atom-syntax (make-identifier name (list name) (make-macro-definition name name #f))
                        (syntax-loc source)))

    (define (prepare-macro-definition form outer local transformers)
      (let* ((parts (fields form '(_ name rules)))
             (binding (reserve-macro-identifier (car parts)))
             (next (add-local-bindings local (list binding) form))
             (transformer (parse-transformer (cadr parts) (append next outer))))
        ;; Retain a marker until checking that a block ends with an expression.
        (values (list (lambda (values transformers) (make-eliminated-definition)))
                next (cons (cons (cdr binding) transformer) transformers))))

    (define (reserve-direct-definitions forms outer initial)
      (let loop ((forms forms) (local initial) (reserved '()) (macros '()))
        (if (null? forms) (values local reserved)
            (let-values (((remaining local reserved macros)
                          (reserve-direct-form (car forms) (cdr forms)
                                               outer local reserved macros)))
              (loop remaining local reserved macros)))))

    (define (reserve-direct-form form remaining outer local reserved macros)
      (case (builtin-tag form (append macros local outer))
        ((begin) (values (append (car (fields form '(_ item ...))) remaining)
                         local reserved macros))
        ((define) (reserve-value-definition form remaining local reserved macros))
        ((define-syntax) (reserve-syntax-definition form remaining local reserved macros))
        (else (values remaining local reserved macros))))

    (define (reserve-value-definition form remaining local reserved macros)
      (let* ((pending (parse-definition form))
             (binding (pending-definition-binding pending)))
        (values remaining (add-local-bindings local (list binding) form)
                (cons (cons form pending) reserved) macros)))

    ;; Later source forms see this keyword rather than an outer builtin.
    (define (reserve-syntax-definition form remaining local reserved macros)
      (let ((name (car (fields form '(_ name rules)))))
        (values remaining local reserved (cons (reserve-macro-identifier name) macros))))

    (define (reserve-macro-identifier syntax)
      (let ((id (require-identifier syntax)))
        (cons (identifier-key id)
              (make-macro-definition (identifier-name id) #f (syntax-loc syntax)))))

    (define (reserve-value-identifier syntax)
      (let ((id (require-identifier syntax)))
        (cons (identifier-key id)
              (make-value-definition (identifier-name id) (syntax-loc syntax)))))

    ;; Fuel follows a recursive expansion path, including descent into generated
    ;; builtin forms. Sibling expressions each receive their parent's remaining fuel.
    (define (expand-head form environment transformers fuel)
      (let ((rules (head-transformer form environment transformers)))
        (if rules
            (begin
              (if (= fuel 0) (fail form "macro expansion limit exceeded"))
              (expand-head (apply-transformer rules form environment)
                           environment transformers (- fuel 1)))
            (values form fuel))))

    ;;
    ;; Expression
    ;;

    (define (expand-expression input environment transformers fuel)
      (let-values (((form fuel) (expand-head input environment transformers fuel)))
        (cond
         ((identifier-of form) (resolve-name form environment))
         ((atom-syntax? form) (expand-literal form))
         ((vector-syntax? form) (make-literal (syntax-datum form) (syntax-loc form)))
         ((list-syntax? form) (expand-list-expression form environment transformers fuel))
         (else (fail form "expected core expression")))))

    (define (expand-list-expression form environment transformers fuel)
      (let ((tag (builtin-tag form environment)))
        (case tag
          ((define define-syntax) (fail form "definition in expression position"))
          ((syntax-rules) (fail form "transformer specification in expression position")))
        ((expression-handler tag) form environment transformers fuel)))

    (define (expression-handler tag)
      (case tag
        ((lambda) expand-lambda)
        ((quote) expand-quotation)
        ((if) expand-conditional)
        ((set!) expand-assignment)
        ((begin) expand-sequence)
        ((let-syntax letrec-syntax) expand-local-macros)
        (else expand-application)))

    (define (expand-quotation form environment transformers fuel)
      (make-literal (syntax-datum (car (fields form '(_ datum)))) (syntax-loc form)))

    (define (expand-literal form)
      (let ((value (atom-syntax-value form)))
        (if (not (self-evaluating? value)) (fail form "unsupported literal" value))
        (make-literal value (syntax-loc form))))

    (define (expand-conditional form environment transformers fuel)
      (let ((parts (cdr (syntax-list form))))
        (if (not (memv (length parts) '(2 3)))
            (fail form "expected if test, consequent, and optional alternate"))
        (make-conditional (expand-expression (car parts) environment transformers fuel)
                          (expand-expression (cadr parts) environment transformers fuel)
                          (and (pair? (cddr parts))
                               (expand-expression (caddr parts) environment transformers fuel))
                          (syntax-loc form))))

    (define (expand-assignment form environment transformers fuel)
      (let ((parts (fields form '(_ target value))))
        (make-assignment (resolve-name (car parts) environment)
                         (expand-expression (cadr parts) environment transformers fuel)
                         (syntax-loc form))))

    (define (expand-sequence form environment transformers fuel)
      (let ((parts (car (fields form '(_ expression ...)))))
        (build-block (map (lambda (part) (expand-expression part environment transformers fuel))
                          parts) form)))

    (define (expand-lambda form environment transformers fuel)
      (let ((parts (fields form '(_ formals item ...))))
        (let-values (((parameters rest bindings) (parse-lambda-formals (car parts))))
          (make-lambda parameters rest
                       (expand-block (cadr parts) (append bindings environment) '()
                                     transformers fuel form)
                       (syntax-loc form)))))

    ;; A proper list has fixed arity; a dotted tail or lone identifier binds rest.
    (define (parse-lambda-formals form)
      (let-values (((required rest) (lambda-formal-parts form)))
        (let* ((names (if (null? rest) required (append required (list rest))))
               (bindings (reserve-identifiers names form))
               (parameters (map (lambda (syntax) (lookup syntax bindings)) required))
               (rest-parameter (and (not (null? rest)) (lookup rest bindings))))
          (values parameters rest-parameter bindings))))

    (define (lambda-formal-parts form)
      (if (identifier-of form) (values '() form)
          (begin
            (if (not (list-syntax? form)) (fail form "expected lambda formals"))
            (syntax-sequence form))))

    (define (expand-block forms environment local transformers fuel source)
      (let-values (((items env transformers)
                    (expand-body forms environment local transformers fuel)))
        (build-block items source)))

    ;; Check the final item before removing compile-time definition markers.
    (define (build-block items source)
      (let ((reversed (reverse items)))
        (if (or (null? reversed) (not (runtime-expression? (car reversed))))
            (fail source "body requires a final expression"))
        (make-block (runtime-items (reverse (cdr reversed)))
                    (car reversed) (syntax-loc source))))

    (define (expand-local-macros form environment transformers fuel)
      (let* ((parts (fields form '(_ bindings item ...)))
             (bindings (map (lambda (binding) (fields binding '(name rules)))
                            (syntax-list (car parts))))
             (local (reserve-local-macros bindings form))
             (definition-environment (local-transformer-environment form local environment))
             (additions (parse-local-transformers bindings local definition-environment)))
        (expand-block (cadr parts) environment local (append additions transformers) fuel form)))

    (define (reserve-local-macros bindings form)
      (let ((local (map (lambda (binding) (reserve-macro-identifier (car binding))) bindings)))
        (check-distinct (map car local) form)
        local))

    (define (local-transformer-environment form local environment)
      (if (eq? (builtin-tag form environment) 'letrec-syntax)
          (append local environment) environment))

    (define (parse-local-transformers bindings local environment)
      (map (lambda (binding entry)
             (cons (cdr entry) (parse-transformer (cadr binding) environment)))
           bindings local))

    (define (expand-application form environment transformers fuel)
      (let ((parts (syntax-list form)))
        (if (null? parts) (fail form "empty list is not a core expression"))
        (make-application (expand-expression (car parts) environment transformers fuel)
                          (map (lambda (operand)
                                 (expand-expression operand environment transformers fuel))
                               (cdr parts))
                          (syntax-loc form))))

    (define (reserve-identifiers names source)
      (let ((bindings (map reserve-value-identifier names)))
        (check-distinct (map car bindings) source)
        bindings))

    ;;
    ;; Transformer
    ;;

    (define-record-type <macro-definition>
      (make-macro-definition name builtin loc)
      macro-definition?
      (name macro-definition-name)
      (builtin macro-definition-builtin)
      (loc macro-definition-loc))

    (define-record-type <rule>
      (make-rule dispatch template)
      rule?
      (dispatch rule-dispatch)
      (template rule-template))

    (define (parse-transformer specification environment)
      (let*-values (((ellipsis literal-syntax rules) (transformer-parts specification environment))
                    ((literals identities)
                     (parse-transformer-literals literal-syntax specification environment)))
        (map (lambda (rule) (parse-rule rule environment ellipsis literals identities)) rules)))

    (define (transformer-parts specification environment)
      (if (not (eq? (builtin-tag specification environment) 'syntax-rules))
          (fail specification "expected syntax-rules specification"))
      (let* ((parts (cdr (syntax-list specification)))
             (custom? (and (pair? parts) (identifier-of (car parts))))
             (ellipsis (if custom? (require-symbol (car parts)) '...))
             (rest (if custom? (cdr parts) parts)))
        (if (null? rest) (fail specification "syntax-rules requires literal list"))
        (values ellipsis (syntax-list (car rest)) (cdr rest))))

    (define (parse-transformer-literals syntax specification environment)
      (let ((literals (map require-symbol syntax))
            (identities (map (lambda (literal)
                               (cons (require-symbol literal)
                                     (or (lookup literal environment) (require-symbol literal))))
                             syntax)))
        (check-distinct literals specification)
        (values literals identities)))

    (define (parse-rule form environment ellipsis literals identities)
      (let* ((parts (fields form '(pattern template)))
             (raw (parse-rule-pattern (car parts)))
             (ranks (pattern-ranks raw ellipsis literals))
             (dispatch (build-syntax-dispatcher raw ellipsis literals identities ranks))
             (template (parse-rule-template (cadr parts) environment ranks ellipsis literals)))
        (make-rule dispatch template)))

    (define (parse-rule-pattern syntax)
      (let ((pattern (syntax-datum syntax)))
        (if (not (and (pair? pattern) (symbol? (car pattern))))
            (fail syntax "macro pattern requires an identifier head"))
        (cdr pattern)))

    ;; #f means this head is not a transformer; an empty rule list still is one.
    (define (head-transformer form environment transformers)
      (let ((definition (head-definition form environment)))
        (and (macro-definition? definition) (not (macro-definition-builtin definition))
             (let ((entry (assq definition transformers)))
               (if entry (cdr entry) (fail form "macro used before installation"))))))

    (define (apply-transformer rules input environment)
      (let ((arguments (close-syntax (cdr (syntax-view input)) environment)))
        (let loop ((rules rules))
          (if (null? rules) (fail input "no syntax-rules pattern matched")
              (let* ((rule (car rules)) (captures ((rule-dispatch rule) arguments)))
                (if captures
                    (instantiate-template (rule-template rule) captures)
                    (loop (cdr rules))))))))

    ;; Ranks are checked before installation, even for a rule that is never selected.
    (define (pattern-ranks pattern ellipsis literals)
      (pattern-variable-ranks pattern ellipsis literals 0))

    (define (pattern-variable-ranks pattern ellipsis literals depth)
      (cond
       ((symbol? pattern)
        (if (or (memq pattern literals) (eq? pattern '_)) '() (list (cons pattern depth))))
       ((vector? pattern) (pattern-element-ranks (vector->list pattern) ellipsis literals depth))
       ((pair? pattern) (pattern-element-ranks pattern ellipsis literals depth))
       (else '())))

    (define (pattern-element-ranks remaining ellipsis literals depth)
      (cond
       ((not (pair? remaining)) (pattern-variable-ranks remaining ellipsis literals depth))
       ((and (pair? (cdr remaining)) (active-ellipsis? (cadr remaining) ellipsis literals))
        (append (pattern-variable-ranks (car remaining) ellipsis literals (+ depth 1))
                (pattern-element-ranks (cddr remaining) ellipsis literals depth)))
       (else (append (pattern-variable-ranks (car remaining) ellipsis literals depth)
                     (pattern-element-ranks (cdr remaining) ellipsis literals depth)))))

    ;;
    ;; Template
    ;;

    (define-record-type <variable-template>
      (make-variable-template name rank source)
      variable-template?
      (name variable-template-name)
      (rank variable-template-rank)
      (source variable-template-source))

    (define-record-type <identifier-template>
      (make-identifier-template identifier loc)
      identifier-template?
      (identifier identifier-template-identifier)
      (loc identifier-template-loc))

    (define-record-type <constant-template>
      (make-constant-template value loc)
      constant-template?
      (value constant-template-value)
      (loc constant-template-loc))

    (define-record-type <list-template>
      (make-list-template elements opt-tail-template loc)
      list-template?
      (elements list-template-elements)
      (opt-tail-template list-template-opt-tail-template) ; #f for a proper list
      (loc list-template-loc))

    (define-record-type <vector-template>
      (make-vector-template elements loc)
      vector-template?
      (elements vector-template-elements)
      (loc vector-template-loc))

    (define-record-type <repeated-template>
      (make-repeated-template item drivers source)
      repeated-template?
      (item repeated-template-item)
      (drivers repeated-template-drivers)
      (source repeated-template-source))

    ;; A literal ellipsis and an escaped subtree both disable repetition syntax.
    (define (parse-rule-template syntax environment ranks ellipsis literals)
      (let ((opt-ellipsis (and (not (memq ellipsis literals)) ellipsis)))
        (parse-template (close-syntax syntax environment) ranks opt-ellipsis 0)))

    ;; Parse roles and repetition depths once. Instantiation only consumes plans.
    (define (parse-template syntax ranks opt-ellipsis depth)
      (cond
       ((atom-syntax? syntax)
        (parse-atom-template syntax ranks opt-ellipsis depth))
       ((vector-syntax? syntax)
        (parse-vector-template syntax ranks opt-ellipsis depth))
       ((list-syntax? syntax) (parse-list-template syntax ranks opt-ellipsis depth))
       (else (fail syntax "invalid template"))))

    (define (parse-atom-template syntax ranks opt-ellipsis depth)
      (if (identifier-of syntax)
          (parse-template-identifier syntax ranks opt-ellipsis depth)
          (make-constant-template (atom-syntax-value syntax) (syntax-loc syntax))))

    (define (parse-template-identifier syntax ranks opt-ellipsis depth)
      (let* ((id (require-identifier syntax)) (rank (assq (identifier-name id) ranks)))
        (if rank (parse-variable-template syntax (car rank) (cdr rank) depth)
            (parse-introduced-template syntax id opt-ellipsis))))

    (define (parse-variable-template syntax name rank depth)
      (if (not (or (= rank 0) (= rank depth)))
          (fail syntax "template variable used at wrong repetition depth" name))
      (make-variable-template name rank syntax))

    (define (parse-introduced-template syntax id opt-ellipsis)
      (if (eq? (identifier-name id) opt-ellipsis)
          (fail syntax "unexpected template ellipsis"))
      (make-identifier-template id (syntax-loc syntax)))

    (define (parse-vector-template syntax ranks opt-ellipsis depth)
      (make-vector-template
       (parse-template-elements (vector-syntax-elements syntax) ranks opt-ellipsis depth)
       (syntax-loc syntax)))

    (define (parse-list-template syntax ranks opt-ellipsis depth)
      (let-values (((items tail) (syntax-sequence syntax)))
        (if (template-escape? items opt-ellipsis)
            (parse-template (parse-template-escape items tail syntax) ranks #f depth)
            (make-list-template
             (parse-template-elements items ranks opt-ellipsis depth)
             (parse-template-tail tail ranks opt-ellipsis depth)
             (syntax-loc syntax)))))

    (define (parse-template-tail tail ranks opt-ellipsis depth)
      (and (not (null? tail)) (parse-template tail ranks opt-ellipsis depth)))

    (define (parse-template-elements items ranks opt-ellipsis depth)
      (if (null? items) '()
          (let* ((repeated? (template-repeated-elements? items opt-ellipsis))
                 (item (if repeated?
                           (parse-repeated-template (car items) ranks opt-ellipsis depth)
                           (parse-template (car items) ranks opt-ellipsis depth))))
            (cons item (parse-template-elements (if repeated? (cddr items) (cdr items))
                                                ranks opt-ellipsis depth)))))

    (define (parse-repeated-template syntax ranks opt-ellipsis depth)
      (let* ((item (parse-template syntax ranks opt-ellipsis (+ depth 1)))
             (drivers (template-drivers item depth)))
        (if (null? drivers) (fail syntax "template repetition requires a driver"))
        (make-repeated-template item drivers syntax)))

    (define (template-escape? items opt-ellipsis)
      (and opt-ellipsis (pair? items) (eq? (identifier-spelling (car items)) opt-ellipsis)))

    (define (parse-template-escape items tail syntax)
      (if (not (and (= (length items) 2) (null? tail))) (fail syntax "invalid ellipsis escape"))
      (cadr items))

    (define (template-repeated-elements? items opt-ellipsis)
      (and opt-ellipsis (pair? (cdr items))
           (eq? (identifier-spelling (cadr items)) opt-ellipsis)))

    ;; One fresh key per introduced identifier per invocation. Substituted syntax
    ;; keeps its keys; free template identifiers keep their binding fallback.
    (define (instantiate-template template captures)
      (build-template template captures (template-introductions template) '()))

    (define (build-template template captures introductions path)
      (cond
       ((variable-template? template) (substitute-template-variable template captures path))
       ((identifier-template? template) (introduce-template-identifier template introductions))
       ((constant-template? template)
        (make-atom-syntax (constant-template-value template) (constant-template-loc template)))
       ((vector-template? template) (build-vector-template template captures introductions path))
       ((list-template? template) (build-list-template template captures introductions path))
       (else (error "unknown template plan" template))))

    (define (substitute-template-variable template captures path)
      (capture-at captures (variable-template-name template)
                  (if (= (variable-template-rank template) 0) '() path)
                  (variable-template-source template)))

    (define (introduce-template-identifier template introductions)
      (let* ((id (identifier-template-identifier template))
             (key (cdr (assq (identifier-key id) introductions))))
        (make-atom-syntax (make-identifier (identifier-name id) key (identifier-binding id))
                          (identifier-template-loc template))))

    (define (build-vector-template template captures introductions path)
      (make-vector-syntax
       (build-template-elements (vector-template-elements template) captures introductions path)
       (vector-template-loc template)))

    (define (build-list-template template captures introductions path)
      (let ((tail (list-template-opt-tail-template template)))
        (make-list-syntax
         (build-template-elements (list-template-elements template) captures introductions path)
         (if tail (build-template tail captures introductions path) '())
         (list-template-loc template))))

    (define (build-template-elements items captures introductions path)
      (if (null? items) '()
          (let ((first (if (repeated-template? (car items))
                           (build-template-repetition (car items) captures introductions path)
                           (list (build-template (car items) captures introductions path)))))
            (append first (build-template-elements (cdr items) captures introductions path)))))

    (define (build-template-repetition template captures introductions path)
      (let ((count (template-repetition-count template captures path)))
        (let loop ((index 0) (result '()))
          (if (= index count) (reverse result)
              (loop (+ index 1)
                    (cons (build-template (repeated-template-item template) captures introductions
                                          (append path (list index))) result))))))

    (define (template-repetition-count template captures path)
      (let ((lengths (map (lambda (name)
                            (length (capture-at captures name path
                                                (repeated-template-source template))))
                          (repeated-template-drivers template))))
        (if (not (every? (lambda (size) (= size (car lengths))) lengths))
            (fail (repeated-template-source template) "incompatible template repetition lengths"))
        (car lengths)))

    (define (template-introductions template)
      (let loop ((pending (list template)) (introduced '()))
        (if (null? pending) introduced
            (let ((item (car pending)))
              (if (identifier-template? item)
                  (loop (cdr pending)
                        (add-template-introduction (identifier-template-identifier item)
                                                   introduced))
                  (loop (append (template-children item) (cdr pending)) introduced))))))

    (define (add-template-introduction id introduced)
      (if (assq (identifier-key id) introduced) introduced
          (cons (cons (identifier-key id) (list (identifier-name id))) introduced)))

    (define (template-drivers template depth)
      (if (variable-template? template)
          (if (> (variable-template-rank template) depth)
              (list (variable-template-name template)) '())
          (unique (apply append (map (lambda (child) (template-drivers child depth))
                                     (template-children template))))))

    (define (template-children template)
      (cond
       ((vector-template? template) (vector-template-elements template))
       ((repeated-template? template) (list (repeated-template-item template)))
       ((list-template? template)
        (let ((tail (list-template-opt-tail-template template)))
          (append (list-template-elements template) (if tail (list tail) '()))))
       (else '())))

    (define (capture-at captures name path source)
      (let loop ((value (cdr (assq name captures))) (path path))
        (if (null? path) value
            (if (and (list? value) (< (car path) (length value)))
                (loop (list-ref value (car path)) (cdr path))
                (fail source "invalid repetition extent" name)))))

    ;;
    ;; Syntax matching adapter
    ;;

    (define-record-type <syntax-constraint>
      (make-syntax-constraint name depth predicate)
      syntax-constraint?
      (name syntax-constraint-name)
      (depth syntax-constraint-depth)
      (predicate syntax-constraint-predicate))

    ;; Each node is projected to (datum-view original-syntax). Pattern variables
    ;; select the original; sequence patterns inspect the view. The datum matcher
    ;; remains unaware of syntax, locations, and binding identities.
    (define (build-syntax-dispatcher raw ellipsis literals identities ranks)
      ;; Parse the original grammar before introducing adapter variables.
      (pattern-dispatch ellipsis literals (list (cons raw (lambda (_) #t))))
      (let-values (((adapted constraints) (adapt-syntax-pattern raw ellipsis literals identities)))
        (let ((dispatch (pattern-dispatch ellipsis '()
                                          (list (cons adapted (lambda (captures) captures))))))
          (lambda (form) (match-syntax-pattern form dispatch constraints ranks)))))

    (define (match-syntax-pattern form dispatch constraints ranks)
      (let*-values (((input tails) (project-syntax form))
                    ((captures) (dispatch input)))
        (and captures
             (every? (lambda (constraint)
                       (syntax-constraint-matches? constraint captures tails form)) constraints)
             (restore-pattern-captures captures ranks tails form))))

    (define (restore-pattern-captures captures ranks tails source)
      (map (lambda (rank)
             (cons (car rank)
                   (restore-capture (cdr (assq (car rank) captures))
                                    (cdr rank) tails source))) ranks))

    (define (adapt-syntax-pattern raw ellipsis literals identities)
      (adapt-pattern-node raw ellipsis literals
                          (pattern-constraint-parser raw ellipsis literals identities) 0 '()))

    (define (adapt-pattern-node pattern ellipsis literals constrain depth constraints)
      (cond
       ((symbol? pattern) (adapt-identifier-pattern pattern literals constrain depth constraints))
       ((or (pair? pattern) (null? pattern) (vector? pattern))
        (adapt-pattern-sequence pattern ellipsis literals constrain depth constraints))
       (else (values (list pattern '_) constraints))))

    (define (adapt-identifier-pattern pattern literals constrain depth constraints)
      (if (memq pattern literals)
          (let-values (((name constraints) (constrain pattern depth constraints)))
            (values (list '_ name) constraints))
          (values (if (eq? pattern '_) '_ (list '_ pattern)) constraints)))

    (define (adapt-pattern-sequence pattern ellipsis literals constrain depth constraints)
      (let-values (((items constraints)
                    (adapt-pattern-elements (if (vector? pattern) (vector->list pattern) pattern)
                                            ellipsis literals constrain depth constraints)))
        (values (list (if (vector? pattern) (list->vector items) items) '_) constraints)))

    (define (adapt-pattern-elements remaining ellipsis literals constrain depth constraints)
      (cond
       ((null? remaining) (values '() constraints))
       ((pair? remaining)
        (adapt-pattern-pair remaining ellipsis literals constrain depth constraints))
       (else (adapt-pattern-tail remaining literals constrain depth constraints))))

    (define (adapt-pattern-pair remaining ellipsis literals constrain depth constraints)
      (let* ((repeated? (and (pair? (cdr remaining))
                             (active-ellipsis? (cadr remaining) ellipsis literals)))
             (rest (if repeated? (cddr remaining) (cdr remaining))))
        (let*-values (((item constraints)
                       (adapt-pattern-node (car remaining) ellipsis literals constrain
                                           (if repeated? (+ depth 1) depth) constraints))
                      ((tail constraints)
                       (adapt-pattern-elements rest ellipsis literals constrain depth constraints)))
          (values (cons item (if repeated? (cons ellipsis tail) tail)) constraints))))

    (define (adapt-pattern-tail pattern literals constrain depth constraints)
      (if (and (symbol? pattern) (not (memq pattern literals)))
          (values pattern constraints)
          (constrain pattern depth constraints)))

    (define (pattern-constraint-parser raw ellipsis literals identities)
      (lambda (pattern depth constraints)
        (let* ((name (unused-pattern-name (list raw (map syntax-constraint-name constraints))
                                          (cons ellipsis literals)))
               (predicate (pattern-constraint-predicate pattern identities)))
          (values name (cons (make-syntax-constraint name depth predicate) constraints)))))

    (define (pattern-constraint-predicate pattern identities)
      (let ((literal (and (symbol? pattern) (assq pattern identities))))
        (if literal (lambda (syntax) (literal-identity-matches? syntax (cdr literal)))
            (lambda (syntax) (equal? pattern (syntax-datum syntax))))))

    (define (literal-identity-matches? syntax identity)
      (let ((id (identifier-of syntax)))
        (and id (eqv? identity (or (identifier-binding id) (identifier-name id))))))

    (define (syntax-constraint-matches? constraint captures tails source)
      (let loop ((value (cdr (assq (syntax-constraint-name constraint) captures)))
                 (depth (syntax-constraint-depth constraint)))
        (if (= depth 0)
            ((syntax-constraint-predicate constraint) (restore-syntax value tails source))
            (every? (lambda (item) (loop item (- depth 1))) value))))

    (define (restore-capture value depth tails source)
      (if (= depth 0) (restore-syntax value tails source)
          (map (lambda (item) (restore-capture item (- depth 1) tails source)) value)))

    (define (restore-syntax value tails source)
      (cond
       ((syntax? value) value)
       ((assq value tails) => cdr)
       ((null? value) (make-list-syntax '() '() (syntax-loc source)))
       (else (fail source "missing syntax capture provenance"))))

    (define (project-syntax syntax)
      (cond
       ((atom-syntax? syntax) (values (list (atom-syntax-value syntax) syntax) '()))
       ((vector-syntax? syntax)
        (let-values (((elements tails) (project-syntax-elements (vector-syntax-elements syntax))))
          (values (list (list->vector elements) syntax) tails)))
       (else
        (let-values (((elements tails) (project-syntax-tail syntax)))
          (values (list elements syntax) tails)))))

    (define (project-syntax-elements syntax)
      (if (null? syntax) (values '() '())
          (let*-values (((first first-tails) (project-syntax (car syntax)))
                        ((rest rest-tails) (project-syntax-elements (cdr syntax))))
            (values (cons first rest) (append first-tails rest-tails)))))

    ;; Cdr captures refer to original tails or located list views, including tails
    ;; after a fixed prefix. An improper atom stays opaque to the datum matcher.
    (define (project-syntax-tail syntax)
      (let ((view (syntax-view syntax)))
        (cond
         ((pair? view)
          (let*-values (((first first-tails) (project-syntax (car view)))
                        ((rest rest-tails) (project-syntax-tail (cdr view))))
            (let ((input (cons first rest)))
              (values input (cons (cons input syntax) (append first-tails rest-tails))))))
         ((null? view) (values '() '()))
         (else (values syntax '())))))

    ;;
    ;; Identifier and syntax views
    ;;

    ;; Keys distinguish introduced identifiers from substituted identifiers with
    ;; the same spelling. A fallback is a definition identity, never an environment.
    ;; Binding positions install a new definition under the key; free occurrences
    ;; retain their definition-site fallback when no local binding overrides it.
    (define-record-type <identifier>
      (make-identifier name key binding)
      identifier?
      (name identifier-name)
      (key identifier-key)
      (binding identifier-binding))

    (define (identifier-of syntax)
      (and (atom-syntax? syntax)
           (let ((value (atom-syntax-value syntax)))
             (cond ((identifier? value) value)
                   ((symbol? value) (make-identifier value value #f))
                   (else #f)))))

    (define (identifier-spelling syntax)
      (let ((id (identifier-of syntax))) (and id (identifier-name id))))

    (define (require-identifier syntax)
      (or (identifier-of syntax) (fail syntax "expected identifier")))

    (define (require-symbol syntax)
      (identifier-name (require-identifier syntax)))

    (define (lookup syntax environment)
      (let ((id (identifier-of syntax)))
        (and id (let ((entry (assq (identifier-key id) environment)))
                  (if entry (cdr entry) (identifier-binding id))))))

    (define (resolve-name syntax environment)
      (let ((definition (lookup syntax environment)))
        (cond ((value-definition? definition) (make-name definition (syntax-loc syntax)))
              ((macro-definition? definition) (fail syntax "macro identifier is not a value"))
              (else (fail syntax "unbound identifier" (require-symbol syntax))))))

    (define (head-definition form environment)
      (let ((view (and (list-syntax? form) (syntax-view form))))
        (and (pair? view) (lookup (car view) environment))))

    (define (builtin-tag form environment)
      (let ((definition (head-definition form environment)))
        (and (macro-definition? definition)
             (macro-definition-builtin definition))))

    (define (close-syntax syntax environment)
      (cond
       ((identifier-of syntax) => (lambda (id) (close-identifier-syntax id syntax environment)))
       ((atom-syntax? syntax) syntax)
       ((vector-syntax? syntax)
        (make-vector-syntax (map (lambda (child) (close-syntax child environment))
                                 (vector-syntax-elements syntax))
                            (syntax-loc syntax)))
       (else (close-list-syntax syntax environment))))

    (define (close-identifier-syntax id syntax environment)
      (make-atom-syntax (make-identifier (identifier-name id) (identifier-key id)
                                         (lookup syntax environment))
                        (syntax-loc syntax)))

    (define (close-list-syntax syntax environment)
      (let ((tail (list-syntax-improper-tail syntax)))
        (make-list-syntax (map (lambda (child) (close-syntax child environment))
                               (list-syntax-elements syntax))
                          (if (null? tail) '() (close-syntax tail environment))
                          (syntax-loc syntax))))

    ;; Project one layer only: children remain located syntax for captures. A cdr
    ;; view preserves its children and location, including explicit dotted tails.
    (define (syntax-view syntax)
      (cond
       ((atom-syntax? syntax) (atom-syntax-value syntax))
       ((vector-syntax? syntax) (list->vector (vector-syntax-elements syntax)))
       ((list-syntax? syntax) (list-syntax-view syntax))
       (else syntax)))

    (define (list-syntax-view syntax)
      (let ((items (list-syntax-elements syntax)) (tail (list-syntax-improper-tail syntax)))
        (if (pair? items) (cons (car items) (list-syntax-rest syntax))
            (if (null? tail) '() (syntax-view tail)))))

    (define (list-syntax-rest syntax)
      (let ((rest (cdr (list-syntax-elements syntax))) (tail (list-syntax-improper-tail syntax)))
        (if (and (null? rest) (not (null? tail))) tail
            (make-list-syntax rest tail (syntax-loc syntax)))))

    (define (syntax-sequence syntax)
      (let loop ((syntax syntax) (items '()))
        (let ((view (syntax-view syntax)))
          (cond ((pair? view) (loop (cdr view) (cons (car view) items)))
                ((null? view) (values (reverse items) '()))
                (else (values (reverse items) syntax))))))

    (define (syntax-list syntax)
      (if (not (list-syntax? syntax)) (fail syntax "expected list"))
      (let-values (((items tail) (syntax-sequence syntax)))
        (if (not (null? tail)) (fail syntax "expected proper list"))
        items))

    (define (syntax-datum syntax)
      (cond ((identifier-spelling syntax) => (lambda (name) name))
            ((atom-syntax? syntax) (atom-syntax-value syntax))
            ((vector-syntax? syntax)
             (list->vector (map syntax-datum (vector-syntax-elements syntax))))
            (else (append (map syntax-datum (list-syntax-elements syntax))
                          (let ((tail (list-syntax-improper-tail syntax)))
                            (if (null? tail) '() (syntax-datum tail)))))))

    ;; Inspect one list layer; captured operands remain the original syntax records.
    (define (fields syntax raw-pattern)
      (let ((captures ((pattern-dispatch '... '()
                                         (list (cons raw-pattern (lambda (captures) captures))))
                       (syntax-list syntax))))
        (if (not captures) (fail syntax "malformed form" raw-pattern))
        (map cdr captures)))

    ;;
    ;; Environment and diagnostics
    ;;

    (define (runtime-expression? item)
      (not (or (value-binding? item) (eliminated-definition? item))))

    (define (runtime-items items)
      (filter (lambda (item) (not (eliminated-definition? item))) items))

    (define (value-bindings environment)
      (filter (lambda (entry) (value-definition? (cdr entry))) environment))

    (define (macro-bindings environment)
      (filter (lambda (entry) (macro-definition? (cdr entry))) environment))

    (define (add-local-bindings local additions source)
      (for-each (lambda (entry)
                  (if (assq (car entry) local)
                      (fail source "duplicate local definition" (car entry)))) additions)
      (append additions local))

    (define (merge-imports existing additions source)
      (let loop ((additions additions) (result existing))
        (if (null? additions) result
            (let* ((entry (car additions)) (previous (assq (car entry) result)))
              (if (and previous (not (eqv? (cdr previous) (cdr entry))))
                  (fail source "conflicting imported bindings" (car entry)))
              (loop (cdr additions) (if previous result (cons entry result)))))))

    (define (environment-bindings environment)
      (map (lambda (entry) (make-named-binding (car entry) (cdr entry))) environment))

    (define (check-export-names additions existing source)
      (check-distinct (append (map named-binding-name additions) (map named-binding-name existing))
                      source))

    (define (library-name-datum syntax)
      (let ((parts (map syntax-datum (syntax-list syntax))))
        (if (or (null? parts)
                (not (every? (lambda (part)
                               (or (symbol? part) (and (exact-integer? part) (>= part 0)))) parts)))
            (fail syntax "invalid library name"))
        parts))

    (define (declaration? form tag)
      (and (list-syntax? form) (pair? (syntax-view form))
           (eq? (identifier-spelling (car (syntax-view form))) tag)))

    (define (self-evaluating? value)
      (or (boolean? value) (number? value) (char? value) (string? value) (bytevector? value)))

    (define (active-ellipsis? name ellipsis literals)
      (and (eq? name ellipsis) (not (memq name literals))))

    (define (unused-pattern-name pattern literals)
      (define (contains? name datum)
        (cond ((symbol? datum) (eq? name datum))
              ((pair? datum) (or (contains? name (car datum)) (contains? name (cdr datum))))
              ((vector? datum) (contains? name (vector->list datum)))
              (else #f)))
      (let loop ((index 0))
        (let ((name (string->symbol (string-append "pattern-constraint-" (number->string index)))))
          (if (or (memq name literals) (contains? name pattern)) (loop (+ index 1)) name))))

    (define (check-distinct names source)
      (let loop ((names names))
        (if (pair? names)
            (begin (if (memq (car names) (cdr names)) (fail source "duplicate name" (car names)))
                   (loop (cdr names))))))

    (define (unique values)
      (let loop ((values values) (result '()))
        (if (null? values) (reverse result)
            (loop (cdr values)
                  (if (member (car values) result) result (cons (car values) result))))))

    (define (filter predicate values)
      (cond ((null? values) '())
            ((predicate (car values)) (cons (car values) (filter predicate (cdr values))))
            (else (filter predicate (cdr values)))))

    (define (find predicate values)
      (and (pair? values) (if (predicate (car values)) (car values) (find predicate (cdr values)))))

    (define (fail source message . details)
      (apply error message (and (syntax? source) (syntax-loc source)) details))

    (define (core-library)
      (make-library '(scheme base) '()
                    (append
                     (map (lambda (name)
                            (make-named-binding name (make-macro-definition name name #f)))
                          core-syntax-names)
                     (map (lambda (name) (make-named-binding name (make-value-definition name #f)))
                          core-primitive-names))
                    '() #f))

    (define core-syntax-names
      '(define define-syntax syntax-rules let-syntax letrec-syntax lambda quote if set! begin))

    (define core-primitive-names
      '(+ - * / = < <= > >= cons car cdr list append null? pair? list?
          not eq? eqv? equal? boolean? number? symbol? string? vector?
          vector vector-ref vector-length values call-with-values apply))

    ))

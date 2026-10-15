;; Concrete storage for the complete compiler workload. The adapter inserts
;; this body after imports; the same declarations run under the Chez control.
;; It does not implement or replace any of the source compiler's passes.

;; ---- Optional fields and mutable source pairs ----

(define-data (CompilerOption T)
  (compiler-none)
  (compiler-some (value T compiler-option-value)))
(define (compiler-present? value)
  (match value ((compiler-none) #f) ((compiler-some value) #t)))

;; A list link owns two independently allocated cells. List copies may share
;; a tail, but a newly constructed link never reuses either field cell.
;; Identity therefore remains stable when either field is replaced.
(define-data (CompilerList T)
  (compiler-empty)
  (compiler-link (first (Ref T) compiler-first-cell)
                 (rest (Ref (CompilerList T)) compiler-rest-cell)))
(define (compiler-cons first rest) (compiler-link (ref first) (ref rest)))
(define (compiler-car pair) (ref-get (compiler-first-cell pair)))
(define (compiler-cdr pair) (ref-get (compiler-rest-cell pair)))
(define (compiler-set-car! pair value) (ref-set! (compiler-first-cell pair) value))
(define (compiler-set-cdr! pair value) (ref-set! (compiler-rest-cell pair) value))
(define (compiler-null? value)
  (match value ((compiler-empty) #t) ((compiler-link first rest) #f)))
(: compiler-list-eq? (All (T) (-> (CompilerList T) (CompilerList T) Bool)))
(define (compiler-list-eq? left right)
  (match left
    ((compiler-empty) (compiler-null? right))
    ((compiler-link first rest)
     (and (not (compiler-null? right))
          (ref-eq? first (compiler-first-cell right))
          (ref-eq? rest (compiler-rest-cell right))))))
(: compiler-list (All (T) (-> (Rest T) (CompilerList T))))
(define (compiler-list . values)
  (define (copy values)
    (if (null? values) (compiler-empty)
        (compiler-cons (car values) (copy (cdr values)))))
  (copy values))
(: compiler-append (All (T) (-> (CompilerList T) (CompilerList T) (CompilerList T))))
(define (compiler-append first last)
  (if (compiler-null? first) last
      (compiler-cons (compiler-car first) (compiler-append (compiler-cdr first) last))))
(: compiler-map (All (A B) (-> (-> A B) (CompilerList A) (CompilerList B))))
(define (compiler-map procedure values)
  (if (compiler-null? values) (compiler-empty)
      (let ((first (procedure (compiler-car values))))
        (compiler-cons first (compiler-map procedure (compiler-cdr values))))))
(: compiler-for-each (All (A B) (-> (-> A B) (CompilerList A) Unit)))
(define (compiler-for-each procedure values)
  (unless (compiler-null? values)
    (procedure (compiler-car values))
    (compiler-for-each procedure (compiler-cdr values))))

;; An association entry has two independently typed fields. It is not a list
;; link: its second field can be a variable, operand, environment, or counter.
(define-data (CompilerPair A B)
  (compiler-pair (first (Ref A) compiler-pair-first-cell)
                 (rest (Ref B) compiler-pair-rest-cell)))
(define (compiler-make-pair first rest) (compiler-pair (ref first) (ref rest)))
(define (compiler-pair-first pair) (ref-get (compiler-pair-first-cell pair)))
(define (compiler-pair-rest pair) (ref-get (compiler-pair-rest-cell pair)))
(define (compiler-pair-first-set! pair value) (ref-set! (compiler-pair-first-cell pair) value))
(define (compiler-pair-rest-set! pair value) (ref-set! (compiler-pair-rest-cell pair) value))

;; ---- Located syntax retains its improper lists and input aliases ----

;; A list tail is either another source-list cell, the empty terminator, or
;; one located improper-tail expression. Vector elements remain located too.
(define-data CompilerCode
  (compiler-atom (value Datum compiler-atom-value))
  (compiler-source-list (spine CompilerSourceSpine compiler-source-spine))
  (compiler-source-vector (values (Vector CompilerSource) compiler-source-elements)))
(define-data CompilerSourceSpine
  (compiler-source-empty)
  (compiler-source-pair (first (Ref CompilerSource) compiler-source-first-cell)
                        (rest (Ref CompilerSourceSpine) compiler-source-rest-cell))
  (compiler-source-tail (value CompilerSource compiler-source-tail-value)))
(define-data CompilerLocation
  (compiler-unknown-location)
  (compiler-file-location (path String compiler-location-path)
                          (index I64 compiler-location-index)
                          (line I64 compiler-location-line)
                          (column I64 compiler-location-column))
  (compiler-expression-location (value Datum compiler-location-expression)
                                (source (CompilerOption CompilerSource) compiler-location-source)))
(define-data CompilerSource
  ;; Vector construction fills every element before publication. This explicit
  ;; temporary state is never a fabricated valid source expression.
  (compiler-uninitialized-source)
  (compiler-source (code (Ref CompilerCode) compiler-source-code-cell)
                    (location CompilerLocation compiler-source-location)))
(define (compiler-make-source code location) (compiler-source (ref code) location))
(define (compiler-source-code source) (ref-get (compiler-source-code-cell source)))
(define (compiler-source-code-set! source code)
  (ref-set! (compiler-source-code-cell source) code)
  source)

;; ---- Lexical identities and shared environment roots ----

(define-data CompilerBinding
  (compiler-global-binding)
  (compiler-temporary-binding)
  (compiler-procedure-binding (node CompilerNode compiler-binding-node)))
(define-data CompilerVariableName
  (compiler-anonymous-variable)
  (compiler-symbol-variable (name Symbol compiler-variable-symbol))
  (compiler-position-variable (position I64 compiler-variable-position)))
(define-data CompilerVariable
  (compiler-variable
    (name (Ref CompilerVariableName) compiler-variable-name-cell)
    (binding (Ref CompilerBinding) compiler-variable-binding-cell)
    (references (Ref (CompilerList CompilerNode)) compiler-variable-references-cell)
    (assignments (Ref (CompilerList CompilerNode)) compiler-variable-assignments-cell)
    (source (Ref (CompilerOption CompilerSource)) compiler-variable-source-cell)
    (info (Ref Datum) compiler-variable-info-cell)))
(define (compiler-make-variable name binding references assignments source)
  (compiler-variable (ref name) (ref binding) (ref references) (ref assignments)
                     (ref source) (ref (datum-boolean #f))))
(define (compiler-variable-eq? left right)
  (ref-eq? (compiler-variable-name-cell left) (compiler-variable-name-cell right)))

;; The upstream build deliberately disables Scheme macro evaluation. A macro
;; environment still has an explicit, fixed-signature list-of-arguments entry;
;; it never stores or dispatches an untyped procedure value.
(define-data CompilerMacro
  (compiler-macro (size I64 compiler-macro-size)
                   (expand (-> Datum Datum) compiler-macro-expand)))
(define-data CompilerEnvironment
  (compiler-environment
    (variables (Ref (CompilerList CompilerVariable)) compiler-environment-variable-cell)
    (macros (CompilerList (CompilerPair Symbol CompilerMacro)) compiler-environment-macros)
    (declarations (CompilerList Datum) compiler-environment-declarations)
    (parent (CompilerOption CompilerEnvironment) compiler-environment-parent)))

;; ---- Parse-tree cases and explicit cache validity ----

(define-data CompilerFreeVariables
  (compiler-free-invalid)
  (compiler-free-valid (variables (CompilerList CompilerVariable) compiler-free-variables)))
(define-data CompilerNodeCase
  (compiler-constant-case (value (Ref Datum) compiler-constant-cell))
  (compiler-reference-case (variable (Ref CompilerVariable) compiler-reference-cell))
  (compiler-assignment-case (variable (Ref CompilerVariable) compiler-assignment-cell))
  (compiler-definition-case (variable (Ref CompilerVariable) compiler-definition-cell))
  (compiler-test-case)
  (compiler-conjunction-case)
  (compiler-disjunction-case)
  (compiler-procedure-case
    (name (Ref (CompilerOption String)) compiler-procedure-name-cell)
    (minimum (Ref I64) compiler-procedure-minimum-cell)
    (rest (Ref Bool) compiler-procedure-rest-cell)
    (parameters (Ref (CompilerList CompilerVariable)) compiler-procedure-parameters-cell))
  (compiler-call-case)
  (compiler-future-case))
(define-data CompilerNode
  (compiler-node
    (case CompilerNodeCase compiler-node-case)
    (parent (Ref (CompilerOption CompilerNode)) compiler-node-parent-cell)
    (children (Ref (CompilerList CompilerNode)) compiler-node-children-cell)
    (free (Ref CompilerFreeVariables) compiler-node-free-cell)
    (environment (Ref CompilerEnvironment) compiler-node-environment-cell)
    (source (Ref (CompilerOption CompilerSource)) compiler-node-source-cell)))
(define (compiler-make-node case parent children free environment source)
  (compiler-node case (ref parent) (ref children) (ref free) (ref environment) (ref source)))
(define (compiler-node-eq? left right)
  (ref-eq? (compiler-node-parent-cell left) (compiler-node-parent-cell right)))

;; This follows node-children-set! and node-fv-invalidate! in the pinned source:
;; publish the new list, assign each child's parent, then invalidate this node
;; and its ancestors. Removed children keep their old parent links, as upstream.
(define (compiler-invalidate-free! node)
  (ref-set! (compiler-node-free-cell node) (compiler-free-invalid))
  (match (ref-get (compiler-node-parent-cell node))
    ((compiler-none) (unit))
    ((compiler-some parent) (compiler-invalidate-free! parent))))
(define (compiler-node-children-set! node children)
  (ref-set! (compiler-node-children-cell node) children)
  (compiler-for-each
    (lambda (child) (ref-set! (compiler-node-parent-cell child) (compiler-some node)))
    children)
  (compiler-invalidate-free! node))

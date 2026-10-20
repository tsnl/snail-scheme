;; Hindley-Milner checking with effect rows and typeclass evidence. Each
;; expression is rebuilt with its type; each variable records the type
;; arguments and the evidence of its instantiation, so later passes never
;; repeat inference or instance selection.
(define-library (lofi compiler check)
  (export
   Typed
   Typed-program
   Typed-items
   definition-scheme
   check-program)
  (import
   (scheme base)
   (scheme cxr)
   (srfi 1)
   (srfi 69)
   (lofi compiler shim)
   (lofi compiler read)
   (lofi compiler core))
  (begin

    ;; ---- Checker state ----

    ;; `locals` maps unique local names to monomorphic types. `schemes` holds
    ;; inferred schemes, and the provisional types of the group being inferred.
    ;; Constraints are collected per group and solved when it is complete.
    (struct Checker
      ((program Program)
       (counter (Ref I64))
       (locals HashTable)
       (schemes HashTable)
       (wanted (Ref (List Wanted)))))

    (enum Wanted
      (WantClass
       ((constraint Constraint)
        (cell (Ref Evidence))
        (loc Loc)))
      (WantLiteral
       ((value Datum)
        (type Type)
        (loc Loc))))

    ;; The checker's output: typed items in program order and every
    ;; definition's scheme.
    (struct Typed
      ((program Program)
       (items (List Item))
       (schemes HashTable)))

    (define (definition-scheme typed name)
      (hash-table-ref/default (Typed-schemes typed) name #f))

    (define (program-of ck)
      (Checker-program ck))

    ;; ---- Metavariables and unification ----

    (define (fresh-meta ck)
      (let ((id (+ (ref-get (Checker-counter ck)) 1)))
        (ref-set! (Checker-counter ck) id)
        (TVar id (ref #f))))

    (define (meta? type)
      (match type
        ((TVar _ _) #t)
        (_ #f)))

    ;; Follows bound metavariables, compressing the chain.
    (define (prune type)
      (match type
        ((TVar _ cell)
         (let ((bound (ref-get cell)))
           (if bound
               (let ((target (prune bound))) (ref-set! cell target) target)
               type)))
        (_ type)))

    (define (unify ck expected actual loc)
      (unless (unify? ck expected actual)
        (compile-error loc (string-append "type mismatch: expected " (type->string expected)
                                          ", found " (type->string actual)))))

    (define (unify? ck a b)
      (let ((a (prune a)) (b (prune b)))
        (cond ((eq? a b) #t)
              ((meta? a) (bind? a b))
              ((meta? b) (bind? b a))
              (else (unify-structure? ck a b)))))

    (define (unify-structure? ck a b)
      (match a
        ((TCon name args)
         (match b
           ((TCon other others) (and (eq? name other) (= (length args) (length others))
                                     (every (lambda (x y) (unify? ck x y)) args others)))
           (_ #f)))
        ((TFun params result row)
         (match b
           ((TFun others other-result other-row)
            (and (= (length params) (length others)) (every (lambda (x y) (unify? ck x y)) params others)
                 (unify? ck result other-result) (unify-rows? ck row other-row)))
           (_ #f)))
        ((TRow _ _) (unify-rows? ck a b))
        ((TRigid name) (match b ((TRigid other) (eq? name other)) (_ #f)))
        (_ #f)))

    (define (bind? meta type)
      (and (not (occurs? meta type))
           (begin (ref-set! (TVar-cell meta) type) #t)))

    (define (occurs? meta type)
      (let ((type (prune type)))
        (match type
          ((TVar _ _) (eq? type meta))
          ((TCon _ args) (any (lambda (arg) (occurs? meta arg)) args))
          ((TFun params result row)
           (or (any (lambda (param) (occurs? meta param)) params) (occurs? meta result) (occurs? meta row)))
          ((TRow _ tail) (and tail (occurs? meta tail)))
          (_ #f))))

    ;; ---- Effect rows ----

    ;; A row flattens to its labels and a tail: #f when closed, otherwise a
    ;; rigid variable or an unbound metavariable.
    (define (flatten-row row)
      (let ((row (prune row)))
        (match row
          ((TRow labels #f) (cons labels #f))
          ((TRow labels tail)
           (let ((rest (flatten-row tail)))
             (cons (lset-union eq? labels (car rest)) (cdr rest))))
          (_ (cons '() row)))))

    ;; Rows unify as sets: shared labels match, and each open tail absorbs the
    ;; labels only the other side has.
    (define (unify-rows? ck a b)
      (let* ((left (flatten-row a)) (right (flatten-row b))
             (only-left (lset-difference eq? (car left) (car right)))
             (only-right (lset-difference eq? (car right) (car left)))
             (left-tail (cdr left)) (right-tail (cdr right)))
        (cond ((and left-tail (eq? left-tail right-tail)) (and (null? only-left) (null? only-right)))
              ((and (meta? left-tail) (meta? right-tail))
               (let ((tail (fresh-meta ck)))
                 (and (bind? left-tail (TRow only-right tail)) (bind? right-tail (TRow only-left tail)))))
              ((meta? left-tail) (and (null? only-left) (bind? left-tail (TRow only-right right-tail))))
              ((meta? right-tail) (and (null? only-right) (bind? right-tail (TRow only-left left-tail))))
              (else (and (null? only-left) (null? only-right) (same-tail? left-tail right-tail))))))

    (define (same-tail? a b)
      (or (and (not a) (not b))
          (and a b (match a ((TRigid name) (match b ((TRigid other) (eq? name other)) (_ #f))) (_ #f)))))

    ;; Adds the effects of `latent` to the current row. A closed latent row is
    ;; opened first: performing at most those effects fits any larger row.
    (define (perform! ck latent row loc)
      (let ((flat (flatten-row latent)))
        (unless (unify? ck (TRow (car flat) (or (cdr flat) (fresh-meta ck))) row)
          (compile-error loc (string-append "this performs effects its context does not allow:"
                                            (row-labels->string (car flat)))))))

    (define (row-labels->string labels)
      (apply string-append (map (lambda (label) (string-append " " (short-name label))) labels)))

    (define (total? row)
      (null? (car (flatten-row row))))

    ;; ---- Instantiation ----

    (define (want-class! ck constraint loc)
      (let ((cell (ref #f)))
        (ref-set! (Checker-wanted ck) (cons (WantClass constraint cell loc) (ref-get (Checker-wanted ck))))
        (EvHole cell)))

    ;; Fresh metavariables for the quantified variables, a hole for each
    ;; constraint, and a fresh tail on a closed outermost row.
    (define (instantiate ck scheme loc)
      (let* ((metas (map (lambda (var) (cons var (fresh-meta ck))) (Scheme-vars scheme)))
             (type (open-row ck (substitute metas (Scheme-type scheme))))
             (evidence (map (lambda (constraint) (want-class! ck (substitute-constraint metas constraint) loc))
                            (Scheme-constraints scheme))))
        (values type (map cdr metas) evidence)))

    (define (open-row ck type)
      (match (prune type)
        ((TFun params result (TRow labels #f)) (TFun params result (TRow labels (fresh-meta ck))))
        (_ type)))

    (define (value-scheme value)
      (match value
        ((Defined scheme) scheme)
        ((Constructor _ scheme) scheme)
        ((Accessor _ _ scheme) scheme)
        ((Replacer _ _ scheme) scheme)
        ((Method _ scheme) scheme)
        ((Operation _ scheme) scheme)
        ((Primitive scheme) scheme)
        ((Foreign _ _ scheme) scheme)))

    (define (global-scheme ck name)
      (or (hash-table-ref/default (Checker-schemes ck) name #f)
          (let ((value (program-value (program-of ck) name)))
            (and value (value-scheme value)))))

    (define (variable-type ck name loc)
      (let ((local (hash-table-ref/default (Checker-locals ck) name #f)))
        (if local
            (values local '() '())
            (let ((scheme (global-scheme ck name)))
              (unless scheme (compile-error loc "internal error: no type for" name))
              (instantiate ck scheme loc)))))

    ;; ---- Expressions ----

    (define (typed term type loc)
      (Expr term type loc))

    (define (literal-type ck value loc)
      (cond ((boolean? value) (TCon 'Bool '()))
            ((char? value) (TCon 'Char '()))
            ((string? value) (TCon 'String '()))
            ((eq? value 'unit) (TCon 'Unit '()))
            (else (let ((type (fresh-meta ck)))
                    (ref-set! (Checker-wanted ck) (cons (WantLiteral value type loc) (ref-get (Checker-wanted ck))))
                    type))))

    ;; `row` is the effect row of the enclosing function body.
    (define (infer ck expr row)
      (let ((loc (Expr-loc expr)))
        (match (Expr-term expr)
          ((Lit value) (typed (Lit value) (literal-type ck value loc) loc))
          ((Var name _ _)
           (let-values (((type types evidence) (variable-type ck name loc)))
             (typed (Var name types evidence) type loc)))
          ((Lambda params body) (infer-lambda ck params body loc))
          ((App callee args) (infer-app ck callee args row loc))
          ((If test then else)
           (let* ((test (infer ck test row)) (then (infer ck then row)) (else (infer ck else row)))
             (unify ck (TCon 'Bool '()) (Expr-type test) (Expr-loc test))
             (unify ck (Expr-type then) (Expr-type else) (Expr-loc else))
             (typed (If test then else) (Expr-type then) loc)))
          ((Let name value body) (infer-let ck name value body row loc))
          ((Seq first rest)
           (let* ((first (infer ck first row)) (rest (infer ck rest row)))
             (typed (Seq first rest) (Expr-type rest) loc)))
          ((Match scrutinee clauses) (infer-match ck scrutinee clauses row loc))
          ((Ann inner type)
           (let ((inner (infer ck inner row)))
             (unify ck type (Expr-type inner) loc)
             inner))
          ((Handle effect implementations body) (infer-handle ck effect implementations body row loc)))))

    (define (infer-lambda ck params body loc)
      (let ((types (map (lambda (param)
                          (let ((type (fresh-meta ck)))
                            (hash-table-set! (Checker-locals ck) param type)
                            type))
                        params))
            (body-row (fresh-meta ck)))
        (let ((body (infer ck body body-row)))
          (typed (Lambda params body) (TFun types (Expr-type body) body-row) loc))))

    ;; Checks an expression against a known type: a lambda's parameters and
    ;; body row come from the type; anything else is inferred.
    (define (check-value ck expr type row)
      (match (Expr-term expr)
        ((Lambda params body)
         (match (prune type)
           ((TFun param-types result body-row)
            (if (= (length params) (length param-types))
                (begin
                  (for-each (lambda (param param-type) (hash-table-set! (Checker-locals ck) param param-type)) params param-types)
                  (let ((body (infer ck body body-row)))
                    (unify ck result (Expr-type body) (Expr-loc body))
                    (typed (Lambda params body) type (Expr-loc expr))))
                (infer ck expr row)))
           (_ (infer ck expr row))))
        (_ (infer ck expr row))))

    (define (infer-app ck callee args row loc)
      (let* ((callee (infer ck callee row))
             (args (map (lambda (arg) (infer ck arg row)) args))
             (result (fresh-meta ck)) (latent (fresh-meta ck)))
        (unify-call ck (Expr-type callee) args result latent loc)
        (perform! ck latent row loc)
        (typed (App callee args) result loc)))

    ;; Arguments are compared one by one, so a mismatch names its argument.
    (define (unify-call ck callee-type args result latent loc)
      (match (prune callee-type)
        ((TFun params callee-result row)
         (unless (= (length params) (length args))
           (compile-error loc (string-append "expected " (number->string (length params)) " arguments, found "
                                             (number->string (length args)))))
         (for-each (lambda (param arg) (unify ck param (Expr-type arg) (Expr-loc arg))) params args)
         (unify ck callee-result result loc)
         (unify ck row latent loc))
        ((TVar _ _) (unify ck callee-type (TFun (map Expr-type args) result latent) loc))
        (other (compile-error loc (string-append "not a function: " (type->string other))))))

    ;; A function's own name is visible in its body, with a monomorphic type.
    (define (infer-let ck name value body row loc)
      (let ((type (fresh-meta ck)))
        (when (match (Expr-term value) ((Lambda _ _) #t) (_ #f))
          (hash-table-set! (Checker-locals ck) name type))
        (let ((value (infer ck value row)))
          (unify ck type (Expr-type value) (Expr-loc value))
          (hash-table-set! (Checker-locals ck) name type)
          (let ((body (infer ck body row)))
            (typed (Let name value body) (Expr-type body) loc)))))

    (define (infer-match ck scrutinee clauses row loc)
      (let* ((scrutinee (infer ck scrutinee row)) (result (fresh-meta ck))
             (clauses (map (lambda (clause)
                             (let* ((body-loc (Expr-loc (Clause-body clause)))
                                    (pattern (check-pattern ck (Clause-pattern clause) (Expr-type scrutinee) body-loc))
                                    (body (infer ck (Clause-body clause) row)))
                               (unify ck result (Expr-type body) body-loc)
                               (Clause pattern body)))
                           clauses)))
        (when (null? clauses) (compile-error loc "a match needs at least one clause"))
        (check-coverage ck (map Clause-pattern clauses) loc)
        (typed (Match scrutinee clauses) result loc)))

    ;; Implementations run in the handler's outer context. The body may
    ;; perform the handled effect plus whatever the context allows: its row
    ;; is `{effect | rest}`, and `rest` flows to the outer row.
    (define (infer-handle ck effect implementations body row loc)
      (let ((operations (Effect-operations (program-effect (program-of ck) effect))))
        (unless (and (= (length operations) (length implementations))
                     (every (lambda (operation) (assq operation implementations)) operations))
          (compile-error loc "a handler implements each operation of its effect exactly once"))
        (let* ((implementations (map (lambda (entry) (infer-implementation ck entry row loc)) implementations))
               (rest (fresh-meta ck)) (body (infer ck body (TRow (list effect) rest))))
          (perform! ck rest row loc)
          (typed (Handle effect implementations body) (Expr-type body) loc))))

    (define (infer-implementation ck entry row loc)
      (let-values (((type types evidence) (instantiate ck (global-scheme ck (car entry)) loc)))
        (match type
          ((TFun params result _)
           (let ((value (infer ck (cdr entry) row)) (latent (fresh-meta ck)))
             (unify ck (TFun params result latent) (Expr-type value) (Expr-loc value))
             (perform! ck latent row (Expr-loc value))
             (cons (car entry) value))))))

    ;; ---- Patterns ----

    (define (check-pattern ck pattern type loc)
      (match pattern
        ((PWild _) (PWild type))
        ((PVar name _) (hash-table-set! (Checker-locals ck) name type) (PVar name type))
        ((PLit value _) (unify ck type (literal-type ck value loc) loc) (PLit value type))
        ((PCon constructor args _)
         (match (program-value (program-of ck) constructor)
           ((Constructor case scheme)
            (let-values (((constructor-type types evidence) (instantiate ck scheme loc)))
              (match constructor-type
                ((TFun fields result _)
                 (unless (= (length fields) (length args))
                   (compile-error loc (string-append (short-name constructor) " has " (number->string (length fields)) " fields")))
                 (unify ck type result loc)
                 (PCon constructor (map (lambda (arg field) (check-pattern ck arg field loc)) args fields) type)))))
           (_ (compile-error loc "not a constructor" (short-name constructor)))))))

    ;; ---- Coverage ----

    ;; Maranget's usefulness test. A clause is redundant if it is not useful
    ;; after the clauses before it; a match is exhaustive if a wildcard is not
    ;; useful after all of them.
    (define (check-coverage ck patterns loc)
      (let loop ((rows '()) (patterns patterns))
        (unless (null? patterns)
          (unless (useful? ck (reverse rows) (list (car patterns)))
            (compile-error loc "unreachable match clause"))
          (loop (cons (list (car patterns)) rows) (cdr patterns))))
      (when (useful? ck (map list patterns) (list (PWild #f)))
        (compile-error loc "match is not exhaustive")))

    ;; A pattern's head is (constructor . arity), with literals as
    ;; constructors of no fields; wildcards and variables have no head.
    (define (head-of pattern)
      (match pattern
        ((PCon constructor args _) (cons constructor (length args)))
        ((PLit value _) (cons value 0))
        (_ #f)))

    (define (pattern-args pattern)
      (match pattern
        ((PCon _ args _) args)
        (_ '())))

    (define (wildcards count)
      (make-list count (PWild #f)))

    (define (specialize rows key arity)
      (append-map (lambda (row)
                    (let ((head (head-of (car row))))
                      (cond ((not head) (list (append (wildcards arity) (cdr row))))
                            ((equal? (car head) key) (list (append (pattern-args (car row)) (cdr row))))
                            (else '()))))
                  rows))

    (define (default-rows rows)
      (append-map (lambda (row) (if (head-of (car row)) '() (list (cdr row)))) rows))

    (define (useful? ck rows vector)
      (if (null? vector)
          (null? rows)
          (let ((head (head-of (car vector))))
            (if head
                (useful? ck (specialize rows (car head) (cdr head)) (append (pattern-args (car vector)) (cdr vector)))
                (let ((all (complete-signature ck (delete-duplicates (filter-map (lambda (row) (head-of (car row))) rows)))))
                  (if all
                      (any (lambda (h) (useful? ck (specialize rows (car h) (cdr h)) (append (wildcards (cdr h)) (cdr vector)))) all)
                      (useful? ck (default-rows rows) (cdr vector))))))))

    ;; All heads of the matched type, if `seen` includes every one of them.
    (define (complete-signature ck seen)
      (let ((all (cond ((null? seen) #f)
                       ((boolean? (caar seen)) '((#t . 0) (#f . 0)))
                       ((symbol? (caar seen)) (constructor-heads ck (caar seen)))
                       (else #f))))
        (and all (every (lambda (head) (member head seen)) all) all)))

    (define (constructor-heads ck constructor)
      (match (program-value (program-of ck) constructor)
        ((Constructor case _)
         (map (lambda (case) (cons (Case-name case) (length (Case-fields case))))
              (DataType-cases (program-type (program-of ck) (Case-type case)))))))

    ;; ---- Solving ----

    ;; Literals are defaulted and range-checked first, then class constraints
    ;; are solved. Returns the class constraints that are still ambiguous.
    (define (solve! ck givens)
      (let ((wanted (reverse (ref-get (Checker-wanted ck)))))
        (ref-set! (Checker-wanted ck) '())
        (for-each (lambda (want) (match want ((WantLiteral value type loc) (solve-literal! ck value type loc)) (_ #f))) wanted)
        (filter (lambda (want)
                  (match want
                    ((WantClass constraint cell loc)
                     (let ((evidence (find-evidence ck constraint givens loc)))
                       (when evidence (ref-set! cell evidence))
                       (not evidence)))
                    (_ #f)))
                wanted)))

    (define (solve-literal! ck value type loc)
      (let ((default (if (exact-integer? value) 'I64 'F64)))
        (when (meta? (prune type)) (unify ck (TCon default '()) type loc))
        (match (prune type)
          ((TCon name '())
           (unless (literal-fits? value name)
             (compile-error loc (string-append "the literal " (number->string value) " does not fit " (symbol->string name)))))
          (other (compile-error loc (string-append "a numeric literal cannot have type " (type->string other)))))))

    (define (literal-fits? value type)
      (case type
        ((U8) (and (exact-integer? value) (<= 0 value 255)))
        ((I32) (and (exact-integer? value) (<= (- (expt 2 31)) value (- (expt 2 31) 1))))
        ((I64) (and (exact-integer? value) (<= (- (expt 2 63)) value (- (expt 2 63) 1))))
        ((F32 F64) #t)
        (else #f)))

    ;; Evidence from the enclosing definition's requirements, or from the
    ;; unique instance whose head matches. #f while the types are ambiguous.
    (define (find-evidence ck constraint givens loc)
      (let ((types (map resolve-type (Constraint-types constraint))))
        (and (not (any has-meta? types))
             (or (given-evidence (Constraint-class constraint) types givens)
                 (instance-evidence ck (Constraint-class constraint) types givens loc)))))

    (define (given-evidence class types givens)
      (let loop ((givens givens) (index 0))
        (cond ((null? givens) #f)
              ((and (eq? class (Constraint-class (car givens)))
                    (equal? types (Constraint-types (car givens))))
               (EvParam index))
              (else (loop (cdr givens) (+ index 1))))))

    (define (instance-evidence ck class types givens loc)
      (let loop ((instances (class-instances (program-of ck) class)))
        (if (null? instances)
            (compile-error loc (string-append "no instance for " (constraint->string class types)))
            (let* ((instance (car instances))
                   (bindings (match-types (Instance-vars instance) (Instance-types instance) types '())))
              (if bindings
                  (EvInstance (Instance-name instance)
                              (map (lambda (var) (cdr (assq var bindings))) (Instance-vars instance))
                              (map (lambda (requirement)
                                     (let ((requirement (substitute-constraint bindings requirement)))
                                       (or (find-evidence ck requirement givens loc)
                                           (compile-error loc (string-append "ambiguous requirement "
                                                                             (constraint->string (Constraint-class requirement) (Constraint-types requirement)))))))
                                   (Instance-requires instance)))
                  (loop (cdr instances)))))))

    ;; One-way matching of an instance head; only its own variables bind.
    (define (match-types vars patterns types bindings)
      (cond ((not bindings) #f)
            ((null? patterns) bindings)
            (else (match-types vars (cdr patterns) (cdr types) (match-type vars (car patterns) (car types) bindings)))))

    (define (match-type vars pattern type bindings)
      (match pattern
        ((TRigid name)
         (if (memq name vars)
             (let ((bound (assq name bindings)))
               (cond ((not bound) (cons (cons name type) bindings))
                     ((equal? (cdr bound) type) bindings)
                     (else #f)))
             (and (equal? pattern type) bindings)))
        ((TCon name args)
         (match type
           ((TCon other others) (and (eq? name other) (= (length args) (length others)) (match-types vars args others bindings)))
           (_ #f)))
        ((TFun params result _)
         (match type
           ((TFun others other-result _)
            (and (= (length params) (length others)) (match-types vars (cons result params) (cons other-result others) bindings)))
           (_ #f)))
        (_ #f)))

    (define (constraint->string class types)
      (type->string (TCon class types)))

    (define (has-meta? type)
      (match (prune type)
        ((TVar _ _) #t)
        ((TCon _ args) (any has-meta? args))
        ((TFun params result row) (or (any has-meta? params) (has-meta? result)))
        (_ #f)))

    ;; ---- Zonking ----

    ;; Replaces solved metavariables and keeps unsolved ones.
    (define (resolve-type type)
      (let ((type (prune type)))
        (match type
          ((TCon name args) (TCon name (map resolve-type args)))
          ((TFun params result row) (TFun (map resolve-type params) (resolve-type result) (resolve-type row)))
          ((TRow labels tail) (let ((flat (flatten-row type))) (TRow (car flat) (cdr flat))))
          (_ type))))

    ;; Replaces solved metavariables. An unsolved type defaults to Unit and an
    ;; unsolved row tail closes; nothing observable depends on either.
    (define (zonk type)
      (let ((type (prune type)))
        (match type
          ((TVar _ _) (TCon 'Unit '()))
          ((TCon name args) (TCon name (map zonk args)))
          ((TFun params result row) (TFun (map zonk params) (zonk result) (zonk-row row)))
          ((TRow _ _) (zonk-row type))
          (_ type))))

    (define (zonk-row row)
      (let ((flat (flatten-row row)))
        (TRow (car flat) (if (meta? (cdr flat)) #f (cdr flat)))))

    (define (zonk-evidence evidence)
      (match evidence
        ((EvHole cell) (zonk-evidence (ref-get cell)))
        ((EvInstance instance types subs) (EvInstance instance (map zonk types) (map zonk-evidence subs)))
        (_ evidence)))

    (define (zonk-expr expr)
      (let ((type (zonk (Expr-type expr))) (loc (Expr-loc expr)))
        (Expr (match (Expr-term expr)
                ((Lit value) (Lit value))
                ((Var name types evidence) (Var name (map zonk types) (map zonk-evidence evidence)))
                ((Lambda params body) (Lambda params (zonk-expr body)))
                ((App callee args) (App (zonk-expr callee) (map zonk-expr args)))
                ((If test then else) (If (zonk-expr test) (zonk-expr then) (zonk-expr else)))
                ((Let name value body) (Let name (zonk-expr value) (zonk-expr body)))
                ((Seq first rest) (Seq (zonk-expr first) (zonk-expr rest)))
                ((Match scrutinee clauses)
                 (Match (zonk-expr scrutinee)
                        (map (lambda (clause) (Clause (zonk-pattern (Clause-pattern clause)) (zonk-expr (Clause-body clause))))
                             clauses)))
                ((Handle effect implementations body)
                 (Handle effect (map (lambda (entry) (cons (car entry) (zonk-expr (cdr entry)))) implementations)
                         (zonk-expr body))))
              type loc)))

    (define (zonk-pattern pattern)
      (match pattern
        ((PWild type) (PWild (zonk type)))
        ((PVar name type) (PVar name (zonk type)))
        ((PLit value type) (PLit value (zonk type)))
        ((PCon constructor args type) (PCon constructor (map zonk-pattern args) (zonk type)))))

    ;; ---- Definitions ----

    ;; An unannotated group of mutually recursive definitions is inferred
    ;; together and generalized if every initializer is total.
    (define (check-group ck definitions)
      (for-each (lambda (definition)
                  (hash-table-set! (Checker-schemes ck) (Define-name definition) (mono-scheme (fresh-meta ck))))
                definitions)
      (let* ((results (map (lambda (definition) (infer-definition ck definition)) definitions))
             (stuck (solve! ck '())))
        (unless (null? stuck) (ambiguous-error stuck))
        (for-each (lambda (result) (check-host-effects ck (cdr result) (Expr-loc (car result)))) results)
        (generalize! ck definitions (every (lambda (result) (total? (cdr result))) results))
        (map (lambda (definition result) (Define (Define-name definition) (zonk-expr (car result))))
             definitions results)))

    (define (infer-definition ck definition)
      (let* ((row (fresh-meta ck)) (value (infer ck (Define-value definition) row)))
        (unify ck (Scheme-type (hash-table-ref (Checker-schemes ck) (Define-name definition))) (Expr-type value) (Expr-loc value))
        (cons value row)))

    (define (ambiguous-error stuck)
      (match (car stuck)
        ((WantClass constraint _ loc)
         (compile-error loc (string-append "ambiguous constraint "
                                           (constraint->string (Constraint-class constraint) (Constraint-types constraint))
                                           "; add a signature or an annotation")))))

    ;; Unsolved metavariables become the scheme's variables: `t1`, `t2`, ...
    (define (generalize! ck definitions total?)
      (let ((metas (if total?
                       (delete-duplicates
                        (append-map (lambda (definition) (free-metas (Scheme-type (hash-table-ref (Checker-schemes ck) (Define-name definition))))) definitions)
                        eq?)
                       '())))
        (let ((names (map (lambda (meta index) (string->symbol (string-append "t" (number->string index)))) metas (iota (length metas) 1))))
          (for-each (lambda (meta name) (ref-set! (TVar-cell meta) (TRigid name))) metas names)
          (for-each (lambda (definition)
                      (let ((name (Define-name definition)))
                        (hash-table-set! (Checker-schemes ck) name
                                         (Scheme names '() (zonk (Scheme-type (hash-table-ref (Checker-schemes ck) name)))))))
                    definitions))))

    (define (free-metas type)
      (let ((type (prune type)))
        (match type
          ((TVar _ _) (list type))
          ((TCon _ args) (append-map free-metas args))
          ((TFun params result row) (append (append-map free-metas params) (free-metas result) (free-metas row)))
          ((TRow _ tail) (if tail (free-metas tail) '()))
          (_ '()))))

    ;; A signature's variables are rigid and its constraints are given. A
    ;; function is checked against it directly, so a mismatch is reported
    ;; where it occurs.
    (define (check-annotated ck definition scheme)
      (let* ((row (fresh-meta ck)) (value (check-value ck (Define-value definition) (Scheme-type scheme) row))
             (loc (Expr-loc value)))
        (unify ck (Scheme-type scheme) (Expr-type value) loc)
        (when (and (pair? (Scheme-vars scheme)) (not (total? row)))
          (compile-error loc "a polymorphic definition must have a total initializer"))
        (let ((stuck (solve! ck (Scheme-constraints scheme))))
          (unless (null? stuck) (ambiguous-error stuck)))
        (check-host-effects ck row loc)
        (Define (Define-name definition) (zonk-expr value))))

    (define (check-statement ck expr)
      (let* ((row (fresh-meta ck)) (value (infer ck expr row)) (stuck (solve! ck '())))
        (unless (null? stuck) (ambiguous-error stuck))
        (check-host-effects ck row (Expr-loc value))
        (Do (zonk-expr value))))

    ;; Effects performed at program start need host implementations.
    (define (check-host-effects ck row loc)
      (for-each (lambda (label)
                  (unless (or (eq? label 'mut)
                              (let ((effect (program-effect (program-of ck) label)))
                                (= (length (Effect-host effect)) (length (Effect-operations effect)))))
                    (compile-error loc (string-append "the effect " (short-name label) " has no host implementation here"))))
                (car (flatten-row row))))

    ;; ---- Programs ----

    ;; Unannotated definitions are checked first, in dependency order; then
    ;; annotated definitions and statements, which only need schemes.
    (define (check-program program)
      (let* ((ck (Checker program (ref 0) (make-hash-table eq?) (make-hash-table eq?) (ref '())))
             (items (program-item-list program))
             (inferred (filter (lambda (item) (match item ((Define name _) (not (annotated-scheme program name))) (_ #f))) items))
             (results (make-hash-table eq?)))
        (for-each (lambda (group)
                    (for-each (lambda (result) (hash-table-set! results (Define-name result) result))
                              (check-group ck group)))
                  (definition-groups inferred))
        (let ((typed (map (lambda (item)
                            (match item
                              ((Define name _) (or (hash-table-ref/default results name #f)
                                                   (check-annotated ck item (annotated-scheme program name))))
                              ((Do expr) (check-statement ck expr))))
                          items)))
          (record-annotated-schemes! ck items)
          (Typed program typed (Checker-schemes ck)))))

    (define (annotated-scheme program name)
      (match (program-value program name)
        ((Defined scheme) scheme)
        (_ #f)))

    (define (record-annotated-schemes! ck items)
      (for-each (lambda (item)
                  (match item
                    ((Define name _)
                     (let ((scheme (annotated-scheme (program-of ck) name)))
                       (when scheme (hash-table-set! (Checker-schemes ck) name scheme))))
                    (_ #f)))
                items))

    ;; Tarjan's algorithm returns strongly connected components with each
    ;; component after the components it depends on.
    (define (definition-groups definitions)
      (let ((tarjan (Tarjan (make-hash-table eq?) (make-hash-table eq?) (make-hash-table eq?) (ref '()) (ref 0) (ref '()))))
        (for-each (lambda (definition) (hash-table-set! (Tarjan-by-name tarjan) (Define-name definition) definition)) definitions)
        (for-each (lambda (definition)
                    (unless (hash-table-exists? (Tarjan-index tarjan) (Define-name definition))
                      (visit! tarjan (Define-name definition))))
                  definitions)
        (reverse (ref-get (Tarjan-groups tarjan)))))

    (struct Tarjan
      ((by-name HashTable)
       (index HashTable)
       (low HashTable)
       (stack (Ref (List Symbol)))
       (counter (Ref I64))
       (groups (Ref (List (List Item))))))

    (define (visit! tarjan name)
      (let ((index (Tarjan-index tarjan)) (low (Tarjan-low tarjan)) (stack (Tarjan-stack tarjan))
            (by-name (Tarjan-by-name tarjan)))
        (hash-table-set! index name (ref-get (Tarjan-counter tarjan)))
        (hash-table-set! low name (ref-get (Tarjan-counter tarjan)))
        (ref-set! (Tarjan-counter tarjan) (+ (ref-get (Tarjan-counter tarjan)) 1))
        (ref-set! stack (cons name (ref-get stack)))
        (for-each (lambda (next)
                    (cond ((not (hash-table-exists? index next))
                           (visit! tarjan next)
                           (hash-table-set! low name (min (hash-table-ref low name) (hash-table-ref low next))))
                          ((memq next (ref-get stack))
                           (hash-table-set! low name (min (hash-table-ref low name) (hash-table-ref index next))))))
                  (filter (lambda (reference) (hash-table-exists? by-name reference))
                          (expr-references (Define-value (hash-table-ref by-name name)))))
        (when (= (hash-table-ref low name) (hash-table-ref index name))
          (pop-group! tarjan name))))

    (define (pop-group! tarjan name)
      (let loop ((group '()))
        (let ((top (car (ref-get (Tarjan-stack tarjan)))))
          (ref-set! (Tarjan-stack tarjan) (cdr (ref-get (Tarjan-stack tarjan))))
          (if (eq? top name)
              (ref-set! (Tarjan-groups tarjan)
                        (cons (map (lambda (n) (hash-table-ref (Tarjan-by-name tarjan) n)) (cons top group))
                              (ref-get (Tarjan-groups tarjan))))
              (loop (cons top group))))))

    (define (expr-references expr)
      (match (Expr-term expr)
        ((Lit _) '())
        ((Var name _ _) (list name))
        ((Lambda _ body) (expr-references body))
        ((App callee args) (append-map expr-references (cons callee args)))
        ((If test then else) (append-map expr-references (list test then else)))
        ((Let _ value body) (append (expr-references value) (expr-references body)))
        ((Seq first rest) (append (expr-references first) (expr-references rest)))
        ((Match scrutinee clauses) (append (expr-references scrutinee) (append-map (lambda (c) (expr-references (Clause-body c))) clauses)))
        ((Ann inner _) (expr-references inner))
        ((Handle _ implementations body) (append (append-map (lambda (e) (expr-references (cdr e))) implementations)
                                                 (expr-references body)))))

    ))

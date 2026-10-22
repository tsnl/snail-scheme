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
   (lofi base)
   (lofi table)
   (lofi compiler read)
   (lofi compiler core))
  (begin

    ;; ---- Checker state ----

    ;; `locals` maps unique local names to monomorphic types. `schemes` holds
    ;; inferred schemes, and the provisional types of the group being inferred.
    ;; While items are checked, constraints are only recorded in `pending`,
    ;; newest first, with their number in `pending-count`; they are decided
    ;; once, when the whole program has been checked. `open` names the
    ;; definitions whose types may still contain metavariables, and `givens`
    ;; the requirements of the annotated definition being checked.
    ;; `confining` names the row variable of a function body whose type
    ;; forbids `mut`: calls in that body may mutate, and `discharged` records
    ;; whether one did. `confined` holds the functions that did, to be checked
    ;; once their types are final.
    (struct Checker
      ((program Program)
       (counter (Ref I64))
       (locals (Table Type))
       (schemes (Ref (Table Scheme)))
       (givens (Ref (List Constraint)))
       (pending (Ref (List Wanted)))
       (pending-count (Ref I64))
       (open (Ref (List String)))
       (confining (Ref (Option I64)))
       (discharged (Ref Bool))
       (confined (Ref (List Expr)))))

    ;; A class constraint keeps the givens in scope where it arose.
    (enum Wanted
      (WantClass
       ((constraint Constraint)
        (cell (Ref (Option Evidence)))
        (givens (List Constraint))
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
       (schemes (Table Scheme))))

    (: definition-scheme (-> Typed String Scheme))
    (define (definition-scheme typed name)
      (match (table-ref (Typed-schemes typed) name)
        ((Some scheme) scheme)
        ((None) (panic (string-append "internal error: no scheme for " name)))))

    (: program-of (-> Checker Program))
    (define (program-of ck)
      (Checker-program ck))

    ;; ---- Metavariables and unification ----

    (: fresh-meta (-> Checker Type ! mut))
    (define (fresh-meta ck)
      (let ((id (+ (ref-get (Checker-counter ck)) 1)))
        (ref-set! (Checker-counter ck) id)
        (TVar id (ref (None)))))

    (: meta? (-> Type Bool))
    (define (meta? type)
      (match type
        ((TVar _ _) #t)
        (_ #f)))

    (: same-meta? (-> Type Type Bool))
    (define (same-meta? a b)
      (match a
        ((TVar id _) (match b ((TVar other _) (= id other)) (_ #f)))
        (_ #f)))

    ;; Follows bound metavariables, compressing the chain.
    (: prune (-> Type Type ! mut))
    (define (prune type)
      (match type
        ((TVar _ cell)
         (match (ref-get cell)
           ((Some bound)
            (let ((target (prune bound)))
              (ref-set! cell (Some target))
              target))
           ((None) type)))
        (_ type)))

    (: unify (-> Checker Type Type Loc Unit ! mut))
    (define (unify ck expected actual loc)
      (unless (unify? ck expected actual)
        (compile-error loc (string-append "type mismatch: expected " (type->string expected) ", found " (type->string actual)))))

    (: unify? (-> Checker Type Type Bool ! mut))
    (define (unify? ck a b)
      (let ((a (prune a)) (b (prune b)))
        (cond ((same-meta? a b) #t)
              ((meta? a) (bind? a b))
              ((meta? b) (bind? b a))
              (else (unify-structure? ck a b)))))

    (: unify-all? (-> Checker (List Type) (List Type) Bool ! mut))
    (define (unify-all? ck as bs)
      (and (= (length as) (length bs)) (every? (lambda (pair) (unify? ck (Pair-first pair) (Pair-second pair))) (zip as bs))))

    (: unify-structure? (-> Checker Type Type Bool ! mut))
    (define (unify-structure? ck a b)
      (match a
        ((TCon name args)
         (match b
           ((TCon other others) (and (string=? name other) (unify-all? ck args others)))
           (_ #f)))
        ((TFun params result row)
         (match b
           ((TFun others other-result other-row)
            (and (unify-all? ck params others) (unify? ck result other-result) (unify-rows? ck row other-row)))
           (_ #f)))
        ((TRow _ _) (unify-rows? ck a b))
        ((TRigid name)
         (match b
           ((TRigid other) (string=? name other))
           (_ #f)))
        (_ #f)))

    (: bind? (-> Type Type Bool ! mut))
    (define (bind? meta type)
      (and (not (occurs? meta type))
           (begin (ref-set! (TVar-cell meta) (Some type)) #t)))

    (: occurs? (-> Type Type Bool ! mut))
    (define (occurs? meta type)
      (let ((type (prune type)))
        (match type
          ((TVar _ _) (same-meta? type meta))
          ((TCon _ args) (any? (lambda (arg) (occurs? meta arg)) args))
          ((TFun params result row)
           (or (any? (lambda (param) (occurs? meta param)) params) (occurs? meta result) (occurs? meta row)))
          ((TRow _ (Some tail)) (occurs? meta tail))
          (_ #f))))

    ;; ---- Effect rows ----

    ;; A row flattens to its labels and a tail: none when closed, otherwise a
    ;; rigid variable or an unbound metavariable.
    (: flatten-row (-> Type (Pair (List String) (Option Type)) ! mut))
    (define (flatten-row row)
      (let ((row (prune row)))
        (match row
          ((TRow labels (None)) (Pair labels (None)))
          ((TRow labels (Some tail))
           (let ((rest (flatten-row tail)))
             (Pair (label-union labels (Pair-first rest)) (Pair-second rest))))
          (_ (Pair (Nil) (Some row))))))

    (: meta-tail? (-> (Option Type) Bool))
    (define (meta-tail? tail)
      (match tail
        ((Some type) (meta? type))
        ((None) #f)))

    (: same-tail? (-> (Option Type) (Option Type) Bool))
    (define (same-tail? a b)
      (match a
        ((None) (match b ((None) #t) ((Some _) #f)))
        ((Some (TRigid name)) (match b ((Some (TRigid other)) (string=? name other)) (_ #f)))
        ((Some x) (match b ((Some y) (same-meta? x y)) ((None) #f)))))

    ;; Rows unify as sets: shared labels match, and each open tail absorbs the
    ;; labels only the other side has.
    (: unify-rows? (-> Checker Type Type Bool ! mut))
    (define (unify-rows? ck a b)
      (let* ((left (flatten-row a)) (right (flatten-row b))
             (only-left (label-difference (Pair-first left) (Pair-first right)))
             (only-right (label-difference (Pair-first right) (Pair-first left)))
             (left-tail (Pair-second left)) (right-tail (Pair-second right)))
        (cond ((same-tail? left-tail right-tail) (and (null? only-left) (null? only-right)))
              ((and (meta-tail? left-tail) (meta-tail? right-tail))
               (let ((tail (Some (fresh-meta ck))))
                 (and (bind? (tail-type left-tail) (TRow only-right tail)) (bind? (tail-type right-tail) (TRow only-left tail)))))
              ((meta-tail? left-tail) (and (null? only-left) (bind? (tail-type left-tail) (TRow only-right right-tail))))
              ((meta-tail? right-tail) (and (null? only-right) (bind? (tail-type right-tail) (TRow only-left left-tail))))
              (else #f))))

    (: tail-type (-> (Option Type) Type))
    (define (tail-type tail)
      (match tail
        ((Some type) type)
        ((None) (panic "internal error: closed row"))))

    ;; Adds the effects of `latent` to the current row. A closed latent row is
    ;; opened first: performing at most those effects fits any larger row.
    ;; In a confining body, `mut` is discharged rather than added.
    (: perform! (-> Checker Type Type Loc Unit ! mut))
    (define (perform! ck latent row loc)
      (let* ((flat (flatten-row latent))
             (labels (if (confining-row? ck row) (discharge-mut ck (Pair-first flat)) (Pair-first flat)))
             (tail (match (Pair-second flat) ((Some tail) tail) ((None) (fresh-meta ck)))))
        (unless (unify? ck (TRow labels (Some tail)) row)
          (compile-error loc (string-append "this performs effects its context does not allow:" (labels->string labels))))))

    (: discharge-mut (-> Checker (List String) (List String) ! mut))
    (define (discharge-mut ck labels)
      (when (member? "mut" labels)
        (ref-set! (Checker-discharged ck) #t))
      (filter (lambda (label) (not (string=? label "mut"))) labels))

    (: confining-row? (-> Checker Type Bool ! mut))
    (define (confining-row? ck row)
      (match (Pair (ref-get (Checker-confining ck)) row)
        ((Pair (Some number) (TVar id _)) (= number id))
        (_ #f)))

    (: total? (-> Type Bool ! mut))
    (define (total? row)
      (null? (Pair-first (flatten-row row))))

    ;; ---- Instantiation ----

    (: want! (-> Checker Wanted Unit ! mut))
    (define (want! ck wanted)
      (ref-set! (Checker-pending ck) (Cons wanted (ref-get (Checker-pending ck))))
      (ref-set! (Checker-pending-count ck) (+ (ref-get (Checker-pending-count ck)) 1)))

    (: want-class! (-> Checker Constraint Loc Evidence ! mut))
    (define (want-class! ck constraint loc)
      (let ((cell (ref (None))))
        (want! ck (WantClass constraint cell (ref-get (Checker-givens ck)) loc))
        (EvHole cell)))

    ;; A use of a variable: its type, the types its quantified variables
    ;; took, and the evidence for its constraints.
    (struct Instantiated
      ((type Type)
       (types (List Type))
       (evidence (List Evidence))))

    ;; Fresh metavariables for the quantified variables, a hole for each
    ;; constraint, and a fresh tail on a closed outermost row.
    (: instantiate (-> Checker Scheme Loc Instantiated ! mut))
    (define (instantiate ck scheme loc)
      (let* ((metas (map (lambda (var) (Pair var (fresh-meta ck))) (Scheme-vars scheme)))
             (type (open-row ck (substitute metas (Scheme-type scheme))))
             (evidence (map (lambda (constraint) (want-class! ck (substitute-constraint metas constraint) loc))
                            (Scheme-constraints scheme))))
        (Instantiated type (map Pair-second metas) evidence)))

    (: open-row (-> Checker Type Type ! mut))
    (define (open-row ck type)
      (match (prune type)
        ((TFun params result (TRow labels (None))) (TFun params result (TRow labels (Some (fresh-meta ck)))))
        (_ type)))

    (: global-scheme (-> Checker String (Option Scheme) ! mut))
    (define (global-scheme ck name)
      (match (table-ref (ref-get (Checker-schemes ck)) name)
        ((Some scheme) (Some scheme))
        ((None)
         (match (program-value (program-of ck) name)
           ((Some value) (value-scheme value))
           ((None) (None))))))

    ;; Names are unique, so a local's type is in scope exactly where its
    ;; binding form passes the extended checker.
    (: bind-local (-> Checker String Type Checker))
    (define (bind-local ck name type)
      (Checker-locals-set ck (table-set (Checker-locals ck) name type)))

    (: bind-locals (-> Checker (List String) (List Type) Checker))
    (define (bind-locals ck names types)
      (fold-left (lambda (ck pair) (bind-local ck (Pair-first pair) (Pair-second pair))) ck (zip names types)))

    (: set-scheme! (-> Checker String Scheme Unit ! mut))
    (define (set-scheme! ck name scheme)
      (ref-set! (Checker-schemes ck) (table-set (ref-get (Checker-schemes ck)) name scheme)))

    (: variable-type (-> Checker String Loc Instantiated ! mut))
    (define (variable-type ck name loc)
      (match (table-ref (Checker-locals ck) name)
        ((Some local) (Instantiated local (Nil) (Nil)))
        ((None)
         (match (global-scheme ck name)
           ((Some scheme) (instantiate ck scheme loc))
           ((None) (compile-error loc (string-append "internal error: no type for " name)))))))

    ;; ---- Expressions ----

    (: literal-type (-> Checker Datum Loc Type ! mut))
    (define (literal-type ck value loc)
      (match value
        ((DBool _) (TCon "Bool" (Nil)))
        ((DChar _) (TCon "Char" (Nil)))
        ((DString _) (TCon "String" (Nil)))
        ((DBytes _) (TCon "Vector" (list (TCon "U8" (Nil)))))
        ((DUnit) (TCon "Unit" (Nil)))
        (_ (let ((type (fresh-meta ck)))
             (want! ck (WantLiteral value type loc))
             type))))

    ;; `row` is the effect row of the enclosing function body.
    (: infer (-> Checker Expr Type Expr ! mut))
    (define (infer ck expr row)
      (let ((loc (Expr-loc expr)))
        (match (Expr-term expr)
          ((Lit value) (Expr (Lit value) (literal-type ck value loc) loc))
          ((Var name _ _)
           (let ((use (variable-type ck name loc)))
             (Expr (Var name (Instantiated-types use) (Instantiated-evidence use)) (Instantiated-type use) loc)))
          ((Lambda params body) (infer-lambda ck params body loc))
          ((App callee args) (infer-app ck callee args row loc))
          ((If test then otherwise)
           (let* ((test (infer ck test row)) (then (infer ck then row)) (otherwise (infer ck otherwise row)))
             (unify ck (TCon "Bool" (Nil)) (Expr-type test) (Expr-loc test))
             (unify ck (Expr-type then) (Expr-type otherwise) (Expr-loc otherwise))
             (Expr (If test then otherwise) (Expr-type then) loc)))
          ((Let name value body) (infer-let ck name value body row loc))
          ((Seq first rest)
           (let* ((first (infer ck first row)) (rest (infer ck rest row)))
             (Expr (Seq first rest) (Expr-type rest) loc)))
          ((Match scrutinee clauses) (infer-match ck scrutinee clauses row loc))
          ((Ann inner type)
           (let ((inner (infer ck inner row)))
             (unify ck type (Expr-type inner) loc)
             inner))
          ((Handle effect implementations body) (infer-handle ck effect implementations body row loc))
          ;; The direction is decided once types are ground: to Any, from
          ;; Any, or nothing when the types already agree.
          ((Convert inner target) (Expr (Convert (infer ck inner row) target) target loc)))))

    (: infer-lambda (-> Checker (List String) Expr Loc Expr ! mut))
    (define (infer-lambda ck params body loc)
      (let ((types (map (lambda (param) (fresh-meta ck)) params))
            (body-row (fresh-meta ck)))
        (let ((body (infer (bind-locals ck params types) body body-row)))
          (Expr (Lambda params body) (TFun types (Expr-type body) body-row) loc))))

    ;; Checks an expression against a known type: a lambda's parameters and
    ;; body row come from the type; anything else is inferred. A body whose
    ;; row forbids `mut` may still mutate storage it allocates; the function
    ;; is confined once its types are final.
    (: check-value (-> Checker Expr Type Type Expr ! mut))
    (define (check-value ck expr type row)
      (match (Expr-term expr)
        ((Lambda params body)
         (match (prune type)
           ((TFun param-types result body-row)
            (if (= (length params) (length param-types))
                (let* ((inner (bind-locals ck params param-types))
                       (body (if (forbids-mut? body-row) (check-confining-body inner body body-row (Expr-loc expr)) (infer inner body body-row)))
                       (value (Expr (Lambda params body) type (Expr-loc expr))))
                  (unify ck result (Expr-type body) (Expr-loc body))
                  (when (ref-get (Checker-discharged ck))
                    (ref-set! (Checker-discharged ck) #f)
                    (ref-set! (Checker-confined ck) (Cons value (ref-get (Checker-confined ck)))))
                  value)
                (infer ck expr row)))
           (_ (infer ck expr row))))
        (_ (infer ck expr row))))

    ;; The body's row is a variable bound to the type's row, so `perform!` can
    ;; recognize it and let calls in this body, but not in lambdas inside it,
    ;; mutate.
    (: check-confining-body (-> Checker Expr Type Loc Expr ! mut))
    (define (check-confining-body ck body body-row loc)
      (let ((row (fresh-meta ck)) (outer (ref-get (Checker-confining ck))))
        (unify ck row body-row loc)
        (ref-set! (Checker-confining ck) (Some (meta-number row)))
        (let ((checked (infer ck body row)))
          (ref-set! (Checker-confining ck) outer)
          checked)))

    (: meta-number (-> Type I64))
    (define (meta-number meta)
      (match meta
        ((TVar id _) id)
        (_ -1)))

    ;; A row forbids `mut` unless it lists it or is open to more labels.
    (: forbids-mut? (-> Type Bool ! mut))
    (define (forbids-mut? row)
      (let ((flat (flatten-row row)))
        (not (or (member? "mut" (Pair-first flat)) (meta-tail? (Pair-second flat))))))

    (: infer-app (-> Checker Expr (List Expr) Type Loc Expr ! mut))
    (define (infer-app ck callee args row loc)
      (let* ((callee (infer ck callee row))
             (args (map (lambda (arg) (infer ck arg row)) args))
             (result (fresh-meta ck)) (latent (fresh-meta ck)))
        (unify-call ck (Expr-type callee) args result latent loc)
        (perform! ck latent row loc)
        (Expr (App callee args) result loc)))

    ;; Arguments are compared one by one, so a mismatch names its argument.
    (: unify-call (-> Checker Type (List Expr) Type Type Loc Unit ! mut))
    (define (unify-call ck callee-type args result latent loc)
      (match (prune callee-type)
        ((TFun params callee-result row)
         (unless (= (length params) (length args))
           (compile-error loc (string-append "expected " (i64->string (length params)) " arguments, found "
                                             (i64->string (length args)))))
         (for-each (lambda (pair) (unify ck (Pair-first pair) (Expr-type (Pair-second pair)) (Expr-loc (Pair-second pair))))
                   (zip params args))
         (unify ck callee-result result loc)
         (unify ck row latent loc))
        ((TVar _ _) (unify ck callee-type (TFun (map Expr-type args) result latent) loc))
        (other (compile-error loc (string-append "not a function: " (type->string other))))))

    ;; A function's own name is visible in its body, with a monomorphic type.
    (: infer-let (-> Checker String Expr Expr Type Loc Expr ! mut))
    (define (infer-let ck name value body row loc)
      (let* ((type (fresh-meta ck)) (inner (bind-local ck name type))
             (value (infer (if (lambda-expr? value) inner ck) value row)))
        (unify ck type (Expr-type value) (Expr-loc value))
        (let ((body (infer inner body row)))
          (Expr (Let name value body) (Expr-type body) loc))))

    (: infer-match (-> Checker Expr (List Clause) Type Loc Expr ! mut))
    (define (infer-match ck scrutinee clauses row loc)
      (let* ((scrutinee (infer ck scrutinee row)) (result (fresh-meta ck))
             (clauses (map (lambda (clause)
                             (let* ((body-loc (Expr-loc (Clause-body clause)))
                                    (checked (check-pattern ck (Clause-pattern clause) (Expr-type scrutinee) body-loc))
                                    (body (infer (Pair-second checked) (Clause-body clause) row)))
                               (unify ck result (Expr-type body) body-loc)
                               (Clause (Pair-first checked) body)))
                           clauses)))
        (when (null? clauses) (compile-error loc "a match needs at least one clause"))
        (check-coverage ck (map Clause-pattern clauses) loc)
        (Expr (Match scrutinee clauses) result loc)))

    ;; Implementations run in the handler's outer context. The body may
    ;; perform the handled effect plus whatever the context allows: its row
    ;; is `{effect | rest}`, and `rest` flows to the outer row.
    (: infer-handle (-> Checker String (List (Pair String Expr)) Expr Type Loc Expr ! mut))
    (define (infer-handle ck effect implementations body row loc)
      (let ((operations (Effect-operations (program-effect (program-of ck) effect))))
        (unless (and (= (length operations) (length implementations))
                     (every? (lambda (operation) (any? (lambda (entry) (string=? (Pair-first entry) operation)) implementations))
                             operations))
          (compile-error loc "a handler implements each operation of its effect exactly once"))
        (let* ((implementations (map (lambda (entry) (infer-implementation ck entry row loc)) implementations))
               (rest (fresh-meta ck)) (body (infer ck body (TRow (list effect) (Some rest)))))
          (perform! ck rest row loc)
          (Expr (Handle effect implementations body) (Expr-type body) loc))))

    (: infer-implementation (-> Checker (Pair String Expr) Type Loc (Pair String Expr) ! mut))
    (define (infer-implementation ck entry row loc)
      (match (global-scheme ck (Pair-first entry))
        ((Some scheme)
         (match (Instantiated-type (instantiate ck scheme loc))
           ((TFun params result _)
            (let ((value (infer ck (Pair-second entry) row)) (latent (fresh-meta ck)))
              (unify ck (TFun params result latent) (Expr-type value) (Expr-loc value))
              (perform! ck latent row (Expr-loc value))
              (Pair (Pair-first entry) value)))
           (_ (panic "internal error: an operation is a function"))))
        ((None) (panic "internal error: unknown operation"))))

    ;; ---- Patterns ----

    ;; The typed pattern, and the checker its body sees: extended by the
    ;; pattern's variables.
    (: check-pattern (-> Checker Pattern Type Loc (Pair Pattern Checker) ! mut))
    (define (check-pattern ck pattern type loc)
      (match pattern
        ((PWild _) (Pair (PWild type) ck))
        ((PVar name _) (Pair (PVar name type) (bind-local ck name type)))
        ((PLit value _) (begin (unify ck type (literal-type ck value loc) loc) (Pair (PLit value type) ck)))
        ((PCon constructor args _)
         (match (program-value (program-of ck) constructor)
           ((Some (Constructor case scheme))
            (match (Instantiated-type (instantiate ck scheme loc))
              ((TFun fields result _)
               (unless (= (length fields) (length args))
                 (compile-error loc (string-append (short-name constructor) " has " (i64->string (length fields)) " fields")))
               (unify ck type result loc)
               (let ((checked (fold-left (lambda (done pair)
                                           (let ((field (check-pattern (Pair-second done) (Pair-first pair) (Pair-second pair) loc)))
                                             (Pair (Cons (Pair-first field) (Pair-first done)) (Pair-second field))))
                                         (Pair (Nil) ck) (zip args fields))))
                 (Pair (PCon constructor (reverse (Pair-first checked)) type) (Pair-second checked))))
              (_ (panic "internal error: a constructor is a function"))))
           (_ (compile-error loc (string-append "not a constructor: " (short-name constructor))))))))

    ;; ---- Coverage ----

    ;; Maranget's usefulness test. A clause is redundant if it is not useful
    ;; after the clauses before it; a match is exhaustive if a wildcard is not
    ;; useful after all of them.
    (: check-coverage (-> Checker (List Pattern) Loc Unit))
    (define (check-coverage ck patterns loc)
      (let loop ((rows (Nil)) (patterns patterns))
        (match patterns
          ((Cons pattern rest)
           (unless (useful? ck (reverse rows) (list pattern))
             (compile-error loc "unreachable match clause"))
           (loop (Cons (list pattern) rows) rest))
          ((Nil) (unit))))
      (when (useful? ck (map (lambda (pattern) (list pattern)) patterns) (list (PWild unchecked)))
        (compile-error loc "match is not exhaustive")))

    ;; A pattern's head is a constructor and its arity, or a literal, which
    ;; is a constructor without fields. Wildcards and variables have none.
    (enum Head
      (HCon
       ((name String)
        (arity I64)))
      (HLit
       ((value Datum))))

    (: head-of (-> Pattern (Option Head)))
    (define (head-of pattern)
      (match pattern
        ((PCon constructor args _) (Some (HCon constructor (length args))))
        ((PLit value _) (Some (HLit value)))
        (_ (None))))

    (: head=? (-> Head Head Bool))
    (define (head=? a b)
      (match a
        ((HCon name _) (match b ((HCon other _) (string=? name other)) (_ #f)))
        ((HLit value) (match b ((HLit other) (datum=? value other)) (_ #f)))))

    (: head-arity (-> Head I64))
    (define (head-arity head)
      (match head
        ((HCon _ arity) arity)
        ((HLit _) 0)))

    (: pattern-args (-> Pattern (List Pattern)))
    (define (pattern-args pattern)
      (match pattern
        ((PCon _ args _) args)
        (_ (Nil))))

    (: wildcards (-> I64 (List Pattern)))
    (define (wildcards count)
      (map (lambda (index) (PWild unchecked)) (iota count)))

    (: specialize (-> (List (List Pattern)) Head (List (List Pattern))))
    (define (specialize rows head)
      (concatenate
       (map (lambda (row)
              (match row
                ((Cons first rest)
                 (match (head-of first)
                   ((None) (list (append (wildcards (head-arity head)) rest)))
                   ((Some other) (if (head=? other head) (list (append (pattern-args first) rest)) (Nil)))))
                ((Nil) (Nil))))
            rows)))

    (: default-rows (-> (List (List Pattern)) (List (List Pattern))))
    (define (default-rows rows)
      (concatenate
       (map (lambda (row)
              (match row
                ((Cons first rest) (match (head-of first) ((None) (list rest)) ((Some _) (Nil))))
                ((Nil) (Nil))))
            rows)))

    (: row-heads (-> (List (List Pattern)) (List Head)))
    (define (row-heads rows)
      (concatenate
       (map (lambda (row)
              (match row
                ((Cons first _) (match (head-of first) ((Some head) (list head)) ((None) (Nil))))
                ((Nil) (Nil))))
            rows)))

    (: useful? (-> Checker (List (List Pattern)) (List Pattern) Bool))
    (define (useful? ck rows vector)
      (match vector
        ((Nil) (null? rows))
        ((Cons first rest)
         (match (head-of first)
           ((Some head) (useful? ck (specialize rows head) (append (pattern-args first) rest)))
           ((None)
            (match (complete-signature ck (delete-duplicates head=? (row-heads rows)))
              ((Some all)
               (any? (lambda (head) (useful? ck (specialize rows head) (append (wildcards (head-arity head)) rest))) all))
              ((None) (useful? ck (default-rows rows) rest))))))))

    ;; All heads of the matched type, if `seen` includes every one of them.
    (: complete-signature (-> Checker (List Head) (Option (List Head))))
    (define (complete-signature ck seen)
      (let ((all (match seen
                   ((Cons (HLit (DBool _)) _) (list (HLit (DBool #t)) (HLit (DBool #f))))
                   ((Cons (HCon constructor _) _) (constructor-heads ck constructor))
                   (_ (Nil)))))
        (if (and (not (null? all)) (every? (lambda (head) (any? (lambda (other) (head=? head other)) seen)) all))
            (Some all)
            (None))))

    (: constructor-heads (-> Checker String (List Head)))
    (define (constructor-heads ck constructor)
      (match (program-value (program-of ck) constructor)
        ((Some (Constructor case _))
         (map (lambda (case) (HCon (Case-name case) (length (Case-fields case))))
              (DataType-cases (program-type (program-of ck) (Case-type case)))))
        (_ (Nil))))

    ;; ---- Solving ----

    ;; Runs once, after every item is checked: literals whose type nothing
    ;; determined default to F64 or I64, every literal is range-checked, and
    ;; every class constraint is solved with the givens it arose under. Solving
    ;; binds no metavariables, so waiting until now loses nothing.
    (: solve-pending! (-> Checker Unit ! mut))
    (define (solve-pending! ck)
      (let ((pending (reverse (ref-get (Checker-pending ck)))))
        (for-each (lambda (want) (default-literal! ck want #t)) pending)
        (for-each (lambda (want) (default-literal! ck want #f)) pending)
        (for-each (lambda (want)
                    (match want
                      ((WantLiteral value type loc) (check-literal value type loc))
                      (_ (unit))))
                  pending)
        (for-each (lambda (want)
                    (match want
                      ((WantClass constraint cell givens loc) (solve-class! ck constraint cell givens loc))
                      (_ (unit))))
                  pending)))

    (: default-literal! (-> Checker Wanted Bool Unit ! mut))
    (define (default-literal! ck want float?)
      (match want
        ((WantLiteral value type loc)
         (when (and (float-literal? value float?) (meta? (prune type)))
           (unify ck (TCon (if float? "F64" "I64") (Nil)) type loc)))
        (_ (unit))))

    (: float-literal? (-> Datum Bool Bool))
    (define (float-literal? value float?)
      (match value
        ((DFloat _) float?)
        (_ (not float?))))

    (: check-literal (-> Datum Type Loc Unit ! mut))
    (define (check-literal value type loc)
      (match (prune type)
        ((TCon name (Nil))
         (unless (literal-fits? value name)
           (compile-error loc (string-append "the literal " (datum->string value) " does not fit " name))))
        (other (compile-error loc (string-append "a numeric literal cannot have type " (type->string other))))))

    (: literal-fits? (-> Datum String Bool))
    (define (literal-fits? value type)
      (match value
        ((DInt n)
         (case type
           (("U8") (and (<= 0 n) (<= n 255)))
           (("I32") (and (<= -2147483648 n) (<= n 2147483647)))
           (("I64" "F32" "F64") #t)
           (else #f)))
        ((DFloat _) (or (string=? type "F32") (string=? type "F64")))
        (_ #f)))

    (: solve-class! (-> Checker Constraint (Ref (Option Evidence)) (List Constraint) Loc Unit ! mut))
    (define (solve-class! ck constraint cell givens loc)
      (match (find-evidence ck constraint givens loc)
        ((Some evidence) (ref-set! cell (Some evidence)))
        ((None)
         (compile-error loc (string-append "ambiguous constraint "
                                           (constraint->string (Constraint-class constraint)
                                                               (map resolve-type (Constraint-types constraint)))
                                           "; add a signature or an annotation")))))

    ;; Evidence from the enclosing definition's requirements, or from the
    ;; unique instance whose head matches. None while the types are ambiguous.
    (: find-evidence (-> Checker Constraint (List Constraint) Loc (Option Evidence) ! mut))
    (define (find-evidence ck constraint givens loc)
      (let ((types (map resolve-type (Constraint-types constraint))))
        (if (any? has-meta? types)
            (None)
            (match (given-evidence (Constraint-class constraint) types givens)
              ((Some evidence) (Some evidence))
              ((None) (Some (instance-evidence ck (Constraint-class constraint) types givens loc)))))))

    (: given-evidence (-> String (List Type) (List Constraint) (Option Evidence)))
    (define (given-evidence class types givens)
      (match (list-index (lambda (given) (and (string=? class (Constraint-class given)) (types=? types (Constraint-types given))))
                         givens)
        ((Some index) (Some (EvParam index)))
        ((None) (None))))

    (: instance-evidence (-> Checker String (List Type) (List Constraint) Loc Evidence ! mut))
    (define (instance-evidence ck class types givens loc)
      (let loop ((instances (class-instances (program-of ck) class)))
        (match instances
          ((Nil) (compile-error loc (string-append "no instance for " (constraint->string class types))))
          ((Cons instance rest)
           (match (match-types (Instance-vars instance) (Instance-types instance) types (Nil))
             ((Some bindings)
              (EvInstance (Instance-name instance)
                          (map (lambda (var) (match (assoc-ref bindings var) ((Some type) type) ((None) (TCon "Unit" (Nil)))))
                               (Instance-vars instance))
                          (map (lambda (requirement) (requirement-evidence ck (substitute-constraint bindings requirement) givens loc))
                               (Instance-requires instance))))
             ((None) (loop rest)))))))

    (: requirement-evidence (-> Checker Constraint (List Constraint) Loc Evidence ! mut))
    (define (requirement-evidence ck requirement givens loc)
      (match (find-evidence ck requirement givens loc)
        ((Some evidence) evidence)
        ((None)
         (compile-error loc (string-append "ambiguous requirement "
                                           (constraint->string (Constraint-class requirement) (Constraint-types requirement)))))))

    ;; One-way matching of an instance head; only its own variables bind.
    (: match-types (-> (List String) (List Type) (List Type) Substitution (Option Substitution)))
    (define (match-types vars patterns types bindings)
      (if (= (length patterns) (length types))
          (fold-left (lambda (result pair)
                       (match result
                         ((Some bindings) (match-type vars (Pair-first pair) (Pair-second pair) bindings))
                         ((None) (None))))
                     (Some bindings) (zip patterns types))
          (None)))

    (: match-type (-> (List String) Type Type Substitution (Option Substitution)))
    (define (match-type vars pattern type bindings)
      (match pattern
        ((TRigid name)
         (if (member? name vars)
             (match (assoc-ref bindings name)
               ((None) (Some (Cons (Pair name type) bindings)))
               ((Some bound) (if (type=? bound type) (Some bindings) (None))))
             (if (type=? pattern type) (Some bindings) (None))))
        ((TCon name args)
         (match type
           ((TCon other others) (if (string=? name other) (match-types vars args others bindings) (None)))
           (_ (None))))
        ((TFun params result _)
         (match type
           ((TFun others other-result _) (match-types vars (Cons result params) (Cons other-result others) bindings))
           (_ (None))))
        (_ (None))))

    (: constraint->string (-> String (List Type) String ! mut))
    (define (constraint->string class types)
      (type->string (TCon class types)))

    (: has-meta? (-> Type Bool ! mut))
    (define (has-meta? type)
      (match (prune type)
        ((TVar _ _) #t)
        ((TCon _ args) (any? has-meta? args))
        ((TFun params result _) (or (any? has-meta? params) (has-meta? result)))
        (_ #f)))

    ;; ---- Zonking ----

    ;; Replaces solved metavariables and keeps unsolved ones.
    (: resolve-type (-> Type Type ! mut))
    (define (resolve-type type)
      (let ((type (prune type)))
        (match type
          ((TCon name args) (TCon name (map resolve-type args)))
          ((TFun params result row) (TFun (map resolve-type params) (resolve-type result) (resolve-type row)))
          ((TRow _ _) (let ((flat (flatten-row type))) (TRow (Pair-first flat) (Pair-second flat))))
          (_ type))))

    ;; Replaces solved metavariables. An unsolved type defaults to Unit and an
    ;; unsolved row tail closes; nothing observable depends on either.
    (: zonk (-> Type Type ! mut))
    (define (zonk type)
      (let ((type (prune type)))
        (match type
          ((TVar _ _) (TCon "Unit" (Nil)))
          ((TCon name args) (TCon name (map zonk args)))
          ((TFun params result row) (TFun (map zonk params) (zonk result) (zonk-row row)))
          ((TRow _ _) (zonk-row type))
          (_ type))))

    (: zonk-row (-> Type Type ! mut))
    (define (zonk-row row)
      (let ((flat (flatten-row row)))
        (TRow (Pair-first flat) (if (meta-tail? (Pair-second flat)) (None) (Pair-second flat)))))

    (: zonk-evidence (-> Evidence Evidence ! mut))
    (define (zonk-evidence evidence)
      (match evidence
        ((EvHole cell)
         (match (ref-get cell)
           ((Some solved) (zonk-evidence solved))
           ((None) (panic "internal error: unsolved evidence"))))
        ((EvInstance instance types subs) (EvInstance instance (map zonk types) (map zonk-evidence subs)))
        (_ evidence)))

    (: zonk-expr (-> Expr Expr ! mut))
    (define (zonk-expr expr)
      (Expr (match (Expr-term expr)
              ((Lit value) (Lit value))
              ((Var name types evidence) (Var name (map zonk types) (map zonk-evidence evidence)))
              ((Lambda params body) (Lambda params (zonk-expr body)))
              ((App callee args) (App (zonk-expr callee) (map zonk-expr args)))
              ((If test then otherwise) (If (zonk-expr test) (zonk-expr then) (zonk-expr otherwise)))
              ((Let name value body) (Let name (zonk-expr value) (zonk-expr body)))
              ((Seq first rest) (Seq (zonk-expr first) (zonk-expr rest)))
              ((Match scrutinee clauses)
               (Match (zonk-expr scrutinee)
                      (map (lambda (clause) (Clause (zonk-pattern (Clause-pattern clause)) (zonk-expr (Clause-body clause)))) clauses)))
              ((Ann inner type) (Ann (zonk-expr inner) (zonk type)))
              ((Convert inner target) (Convert (zonk-expr inner) (zonk target)))
              ((Handle effect implementations body)
               (Handle effect (map (lambda (entry) (Pair (Pair-first entry) (zonk-expr (Pair-second entry)))) implementations)
                       (zonk-expr body))))
            (zonk (Expr-type expr)) (Expr-loc expr)))

    (: zonk-pattern (-> Pattern Pattern ! mut))
    (define (zonk-pattern pattern)
      (match pattern
        ((PWild type) (PWild (zonk type)))
        ((PVar name type) (PVar name (zonk type)))
        ((PLit value type) (PLit value (zonk type)))
        ((PCon constructor args type) (PCon constructor (map zonk-pattern args) (zonk type)))))

    ;; ---- Confined mutation ----

    ;; A function whose type forbids `mut` may still mutate storage that it
    ;; allocates, as long as none of that storage outlives the call. That holds
    ;; when nothing the function can reach from outside, its parameters, its
    ;; result or a name it reads, can hold mutable storage: then the only
    ;; storage it can mutate is its own, and none of it escapes. Effect
    ;; operations count as names it reads, so storage cannot leave through an
    ;; operation's arguments either, and since implementations return exactly
    ;; once, nothing resumes the function twice. Primitives, constructors and
    ;; field operations act only on their arguments, so a function may always
    ;; use them. Only functions whose bodies did mutate are checked.
    (: check-confined (-> Typed Expr Unit ! mut))
    (define (check-confined typed function)
      (match (Pair (Expr-term function) (Expr-type function))
        ((Pair (Lambda params _) (TFun param-types result _))
         (let ((program (Typed-program typed)))
           (for-each (lambda (pair)
                       (when (holds-storage? program (Pair-second pair))
                         (confinement-error function (string-append "its parameter " (local-name (Pair-first pair)) ", a "
                                                                    (type->string (Pair-second pair)) ","))))
                     (zip params param-types))
           (when (holds-storage? program result)
             (confinement-error function (string-append "its result, a " (type->string result) ",")))
           (for-each (lambda (read) (check-outside-read typed read)) (outside-reads function))))
        (_ (unit))))

    (: confinement-error (-> Expr String Unit))
    (define (confinement-error function culprit)
      (compile-error (Expr-loc function)
                     (string-append "this function's type does not allow mut, so it may mutate only storage it allocates, but "
                                    culprit " could hold storage from outside")))

    ;; A local's source name: its unique name without the `.N` suffix.
    (: local-name (-> String String))
    (define (local-name name)
      (match (last-dot name)
        ((Some index) (substring name 0 index))
        ((None) name)))

    (: last-dot (-> String (Option I64)))
    (define (last-dot name)
      (let loop ((index (- (string-length name) 1)))
        (cond ((< index 0) (None))
              ((char=? (string-ref name index) #\.) (Some index))
              (else (loop (- index 1))))))

    ;; A local of an enclosing definition is judged by its type; a global by
    ;; its declared or inferred type, since instantiating a row variable can
    ;; only bring in effects the function itself performs.
    (: check-outside-read (-> Typed Expr Unit ! mut))
    (define (check-outside-read typed read)
      (match (Expr-term read)
        ((Var name _ _)
         (when (reaches-storage? typed name (Expr-type read))
           (compile-error (Expr-loc read)
                          (string-append "this function's type does not allow mut, so it may mutate only storage it allocates, but "
                                         (short-name name) " could hold storage from outside"))))
        (_ (unit))))

    (: reaches-storage? (-> Typed String Type Bool))
    (define (reaches-storage? typed name type)
      (let ((program (Typed-program typed)))
        (match (program-value program name)
          ((Some (Primitive _)) #f)
          ((Some (Constructor _ _)) #f)
          ((Some (Accessor _ _ _)) #f)
          ((Some (Replacer _ _ _)) #f)
          ((Some value) (holds-storage? program (global-type typed name value)))
          ((None) (holds-storage? program type)))))

    (: global-type (-> Typed String Value Type))
    (define (global-type typed name value)
      (match (table-ref (Typed-schemes typed) name)
        ((Some scheme) (Scheme-type scheme))
        ((None)
         (match (value-scheme value)
           ((Some scheme) (Scheme-type scheme))
           ((None) (panic (string-append "internal error: no type for " name)))))))

    ;; Whether a value of the type can hold or reach mutable storage: a `Ref`,
    ;; an `Array`, an `Any` that may hide one, data with such a field, or a
    ;; function that may perform `mut`. Code cannot use a value of a type
    ;; variable as storage, so type variables hold none.
    (: holds-storage? (-> Program Type Bool))
    (define (holds-storage? program type)
      (holds-storage-within? program type (Nil)))

    (: holds-storage-within? (-> Program Type (List String) Bool))
    (define (holds-storage-within? program type visiting)
      (match type
        ((TCon name args)
         (or (member? name (list "Ref" "Array" "Any"))
             (any? (lambda (arg) (holds-storage-within? program arg visiting)) args)
             (and (not (member? name visiting)) (fields-hold-storage? program name (Cons name visiting)))))
        ((TFun params result row)
         (or (row-mutates? row) (any? (lambda (part) (holds-storage-within? program part visiting)) (Cons result params))))
        (_ #f)))

    (: row-mutates? (-> Type Bool))
    (define (row-mutates? row)
      (match row
        ((TRow labels _) (member? "mut" labels))
        (_ #f)))

    ;; Builtin types other than `Ref`, `Array` and `Any` have no fields.
    (: fields-hold-storage? (-> Program String (List String) Bool))
    (define (fields-hold-storage? program name visiting)
      (and (not (any? (lambda (entry) (string=? (Pair-first entry) name)) builtin-types))
           (any? (lambda (case) (any? (lambda (field) (holds-storage-within? program (Field-type field) visiting)) (Case-fields case)))
                 (DataType-cases (program-type program name)))))

    ;; The variable reads in `expr` of names it does not bind. Names are
    ;; unique, so a name bound anywhere inside is bound at all its reads.
    (: outside-reads (-> Expr (List Expr)))
    (define (outside-reads expr)
      (let ((bound (binders expr)))
        (filter (lambda (read)
                  (match (Expr-term read)
                    ((Var name _ _) (not (member? name bound)))
                    (_ #f)))
                (variable-reads expr))))

    (: variable-reads (-> Expr (List Expr)))
    (define (variable-reads expr)
      (match (Expr-term expr)
        ((Var _ _ _) (list expr))
        (_ (concatenate (map variable-reads (subexpressions expr))))))

    (: binders (-> Expr (List String)))
    (define (binders expr)
      (append (match (Expr-term expr)
                ((Lambda params _) params)
                ((Let name _ _) (list name))
                ((Match _ clauses) (concatenate (map (lambda (clause) (pattern-variables (Clause-pattern clause))) clauses)))
                (_ (Nil)))
              (concatenate (map binders (subexpressions expr)))))

    (: pattern-variables (-> Pattern (List String)))
    (define (pattern-variables pattern)
      (match pattern
        ((PVar name _) (list name))
        ((PCon _ args _) (concatenate (map pattern-variables args)))
        (_ (Nil))))

    (: subexpressions (-> Expr (List Expr)))
    (define (subexpressions expr)
      (match (Expr-term expr)
        ((Lit _) (Nil))
        ((Var _ _ _) (Nil))
        ((Lambda _ body) (list body))
        ((App callee args) (Cons callee args))
        ((If test then otherwise) (list test then otherwise))
        ((Let _ value body) (list value body))
        ((Seq first rest) (list first rest))
        ((Match scrutinee clauses) (Cons scrutinee (map Clause-body clauses)))
        ((Ann inner _) (list inner))
        ((Convert inner _) (list inner))
        ((Handle _ implementations body) (append (map Pair-second implementations) (list body)))))

    ;; ---- Definitions ----

    ;; An unannotated group of mutually recursive definitions is inferred
    ;; together. A group of functions is generalized; any other group stays
    ;; monomorphic, so later uses can still decide its types.
    (: check-group (-> Checker (List Item) (List Item) ! mut))
    (define (check-group ck definitions)
      (let ((before (ref-get (Checker-pending-count ck))))
        (for-each (lambda (definition) (set-scheme! ck (Define-name definition) (mono-scheme (fresh-meta ck))))
                  definitions)
        (let ((results (map (lambda (definition) (infer-definition ck definition)) definitions)))
          (for-each (lambda (result) (check-host-effects ck (Pair-second result) (Expr-loc (Pair-first result)))) results)
          (when (every? (lambda (definition) (lambda-expr? (Define-value definition))) definitions)
            (generalize! ck definitions (take (ref-get (Checker-pending ck)) (- (ref-get (Checker-pending-count ck)) before))))
          (ref-set! (Checker-open ck) (append (map Define-name definitions) (ref-get (Checker-open ck))))
          (map (lambda (pair) (Define (Define-name (Pair-first pair)) (Pair-first (Pair-second pair)))) (zip definitions results)))))

    ;; The checked value and the effect row of its initializer.
    (: infer-definition (-> Checker Item (Pair Expr Type) ! mut))
    (define (infer-definition ck definition)
      (let* ((row (fresh-meta ck)) (value (infer ck (Define-value definition) row)))
        (unify ck (scheme-type ck (Define-name definition)) (Expr-type value) (Expr-loc value))
        (Pair value row)))

    (: scheme-type (-> Checker String Type ! mut))
    (define (scheme-type ck name)
      (match (table-ref (ref-get (Checker-schemes ck)) name)
        ((Some scheme) (Scheme-type scheme))
        ((None) (panic (string-append "internal error: no scheme for " name)))))

    ;; A metavariable becomes a quantified variable (`t1`, `t2`, ...) unless
    ;; something that outlives the group still mentions it: another
    ;; definition's type, or a constraint of this group.
    (: generalize! (-> Checker (List Item) (List Wanted) Unit ! mut))
    (define (generalize! ck definitions wanted)
      (let* ((fixed (map meta-id (append (concatenate (map (lambda (name) (free-metas (scheme-type ck name))) (ref-get (Checker-open ck))))
                                         (concatenate (map wanted-metas wanted)))))
             (metas (filter (lambda (meta) (not (member? (meta-id meta) fixed)))
                            (delete-duplicates same-meta?
                                               (concatenate (map (lambda (d) (free-metas (scheme-type ck (Define-name d)))) definitions)))))
             (names (map (lambda (index) (string-append "t" (i64->string (+ index 1)))) (iota (length metas)))))
        (for-each (lambda (pair) (ref-set! (TVar-cell (Pair-first pair)) (Some (TRigid (Pair-second pair))))) (zip metas names))
        (for-each (lambda (definition)
                    (let ((name (Define-name definition)))
                      (set-scheme! ck name (Scheme names (Nil) (resolve-type (scheme-type ck name))))))
                  definitions)))

    (: meta-id (-> Type I64))
    (define (meta-id meta)
      (match meta
        ((TVar id _) id)
        (_ -1)))

    (: wanted-metas (-> Wanted (List Type) ! mut))
    (define (wanted-metas want)
      (match want
        ((WantClass constraint _ _ _) (concatenate (map free-metas (Constraint-types constraint))))
        ((WantLiteral _ type _) (free-metas type))))

    (: free-metas (-> Type (List Type) ! mut))
    (define (free-metas type)
      (let ((type (prune type)))
        (match type
          ((TVar _ _) (list type))
          ((TCon _ args) (concatenate (map free-metas args)))
          ((TFun params result row) (append (concatenate (map free-metas params)) (append (free-metas result) (free-metas row))))
          ((TRow _ (Some tail)) (free-metas tail))
          (_ (Nil)))))

    ;; A signature's variables are rigid and its constraints are given. A
    ;; function is checked against it directly, so a mismatch is reported
    ;; where it occurs.
    (: check-annotated (-> Checker Item Scheme Item ! mut))
    (define (check-annotated ck definition scheme)
      (ref-set! (Checker-givens ck) (Scheme-constraints scheme))
      (let* ((row (fresh-meta ck)) (value (check-value ck (Define-value definition) (Scheme-type scheme) row))
             (loc (Expr-loc value)))
        (unify ck (Scheme-type scheme) (Expr-type value) loc)
        (when (and (not (null? (Scheme-vars scheme))) (not (total? row)))
          (compile-error loc "a polymorphic definition must have a total initializer"))
        (check-host-effects ck row loc)
        (ref-set! (Checker-givens ck) (Nil))
        (Define (Define-name definition) value)))

    (: check-statement (-> Checker Expr Item ! mut))
    (define (check-statement ck expr)
      (let* ((row (fresh-meta ck)) (value (infer ck expr row)))
        (check-host-effects ck row (Expr-loc value))
        (Do value)))

    ;; The host passes and receives scalars only, and implements every effect
    ;; an exposed function performs.
    (: check-exposed (-> Checker String Loc Unit ! mut))
    (define (check-exposed ck name loc)
      (match (global-scheme ck name)
        ((Some (Scheme (Nil) (Nil) (TFun params result row)))
         (unless (every? host-scalar? (Cons result params))
           (compile-error loc "an exposed function takes and returns scalars only"))
         (check-host-effects ck row loc))
        (_ (compile-error loc "an exposed function must be a monomorphic function"))))

    (: host-scalar? (-> Type Bool))
    (define (host-scalar? type)
      (match type
        ((TCon name (Nil)) (member? name (list "I32" "I64" "F32" "F64" "Bool" "Char" "Unit")))
        (_ #f)))

    ;; Effects performed at program start need host implementations.
    (: check-host-effects (-> Checker Type Loc Unit ! mut))
    (define (check-host-effects ck row loc)
      (for-each (lambda (label)
                  (unless (or (string=? label "mut")
                              (let ((effect (program-effect (program-of ck) label)))
                                (= (length (Effect-host effect)) (length (Effect-operations effect)))))
                    (compile-error loc (string-append "the effect " (short-name label) " has no host implementation here"))))
                (Pair-first (flatten-row row))))

    ;; ---- Programs ----

    ;; Unannotated definitions are checked first, in dependency order; then
    ;; annotated definitions and statements, which only need schemes. Then
    ;; every constraint is solved and every type zonked.
    (: check-program (-> Program Typed ! mut))
    (define (check-program program)
      (let* ((ck (Checker program (ref 0) empty-table (ref empty-table) (ref (Nil)) (ref (Nil)) (ref 0) (ref (Nil)) (ref (None)) (ref #f) (ref (Nil))))
             (items (program-items program)) (inferred (check-inferred ck items))
             (typed (map (lambda (item) (check-item ck inferred item)) items)))
        (solve-pending! ck)
        (for-each (lambda (item)
                    (match item
                      ((Expose name _ loc) (check-exposed ck name loc))
                      (_ (unit))))
                  items)
        (let ((typed (Typed program (map zonk-item typed) (final-schemes ck items))))
          (for-each (lambda (function) (check-confined typed (zonk-expr function))) (ref-get (Checker-confined ck)))
          typed)))

    ;; Checks the definitions without signatures, a group at a time in
    ;; dependency order, and returns them by name.
    (: check-inferred (-> Checker (List Item) (Table Item) ! mut))
    (define (check-inferred ck items)
      (fold-left (lambda (results group)
                   (fold-left (lambda (results result) (table-set results (Define-name result) result)) results (check-group ck group)))
                 empty-table
                 (definition-groups (filter (lambda (item)
                                              (match item
                                                ((Define name _) (match (annotated-scheme (program-of ck) name) ((None) #t) ((Some _) #f)))
                                                (_ #f)))
                                            items))))

    (: check-item (-> Checker (Table Item) Item Item ! mut))
    (define (check-item ck results item)
      (match item
        ((Define name _)
         (match (table-ref results name)
           ((Some result) result)
           ((None)
            (match (annotated-scheme (program-of ck) name)
              ((Some scheme) (check-annotated ck item scheme))
              ((None) (panic "internal error: unchecked definition"))))))
        ((Do expr) (check-statement ck expr))
        ((Expose _ _ _) item)))

    (: zonk-item (-> Item Item ! mut))
    (define (zonk-item item)
      (match item
        ((Define name value) (Define name (zonk-expr value)))
        ((Do value) (Do (zonk-expr value)))
        (_ item)))

    ;; Inferred schemes with their remaining metavariables defaulted, and the
    ;; signatures of annotated definitions.
    (: final-schemes (-> Checker (List Item) (Table Scheme) ! mut))
    (define (final-schemes ck items)
      (for-each (lambda (name)
                  (match (table-ref (ref-get (Checker-schemes ck)) name)
                    ((Some scheme)
                     (set-scheme! ck name (Scheme (Scheme-vars scheme) (Scheme-constraints scheme) (zonk (Scheme-type scheme)))))
                    ((None) (unit))))
                (ref-get (Checker-open ck)))
      (for-each (lambda (item)
                  (match item
                    ((Define name _)
                     (match (annotated-scheme (program-of ck) name)
                       ((Some scheme) (set-scheme! ck name scheme))
                       ((None) (unit))))
                    (_ (unit))))
                items)
      (ref-get (Checker-schemes ck)))

    (: annotated-scheme (-> Program String (Option Scheme)))
    (define (annotated-scheme program name)
      (match (program-value program name)
        ((Some (Defined scheme)) scheme)
        (_ (None))))

    ;; ---- Dependency order ----

    ;; Tarjan's algorithm returns strongly connected components with each
    ;; component after the components it depends on. The search state is a
    ;; value, and each step returns the next one.
    (struct Tarjan
      ((by-name (Table Item))
       (index (Table I64))
       (low (Table I64))
       (stack (List String))
       (on-stack (Table Bool))
       (counter I64)
       (groups (List (List Item)))))

    (: definition-groups (-> (List Item) (List (List Item))))
    (define (definition-groups definitions)
      (let* ((by-name (fold-left (lambda (table definition) (table-set table (Define-name definition) definition)) empty-table definitions))
             (start (Tarjan by-name empty-table empty-table (Nil) empty-table 0 (Nil)))
             (done (fold-left (lambda (tarjan definition)
                                (if (table-contains? (Tarjan-index tarjan) (Define-name definition))
                                    tarjan
                                    (visit tarjan (Define-name definition))))
                              start definitions)))
        (reverse (Tarjan-groups done))))

    (: table-number (-> (Table I64) String I64))
    (define (table-number table key)
      (match (table-ref table key)
        ((Some number) number)
        ((None) 0)))

    (: visit (-> Tarjan String Tarjan))
    (define (visit tarjan name)
      (let* ((number (Tarjan-counter tarjan))
             (entered (Tarjan (Tarjan-by-name tarjan)
                              (table-set (Tarjan-index tarjan) name number)
                              (table-set (Tarjan-low tarjan) name number)
                              (Cons name (Tarjan-stack tarjan))
                              (table-set (Tarjan-on-stack tarjan) name #t)
                              (+ number 1)
                              (Tarjan-groups tarjan)))
             (explored (fold-left (lambda (tarjan next) (follow tarjan name next)) entered (dependencies tarjan name))))
        (if (= (table-number (Tarjan-low explored) name) (table-number (Tarjan-index explored) name))
            (pop-group explored name)
            explored)))

    ;; Lowers `name`'s link through its edge to `next`, visiting `next`
    ;; first if the search has not reached it.
    (: follow (-> Tarjan String String Tarjan))
    (define (follow tarjan name next)
      (cond ((not (table-contains? (Tarjan-index tarjan) next))
             (let ((visited (visit tarjan next)))
               (lower visited name (table-number (Tarjan-low visited) next))))
            ((match (table-ref (Tarjan-on-stack tarjan) next) ((Some on) on) ((None) #f))
             (lower tarjan name (table-number (Tarjan-index tarjan) next)))
            (else tarjan)))

    (: lower (-> Tarjan String I64 Tarjan))
    (define (lower tarjan name number)
      (Tarjan-low-set tarjan (table-set (Tarjan-low tarjan) name (min (table-number (Tarjan-low tarjan) name) number))))

    (: dependencies (-> Tarjan String (List String)))
    (define (dependencies tarjan name)
      (filter (lambda (reference) (table-contains? (Tarjan-by-name tarjan) reference))
              (match (table-ref (Tarjan-by-name tarjan) name)
                ((Some (Define _ value)) (expr-references value))
                (_ (Nil)))))

    (: pop-group (-> Tarjan String Tarjan))
    (define (pop-group tarjan name)
      (let loop ((tarjan tarjan) (group (Nil)))
        (match (Tarjan-stack tarjan)
          ((Cons top rest)
           (let ((popped (Tarjan-on-stack-set (Tarjan-stack-set tarjan rest) (table-set (Tarjan-on-stack tarjan) top #f))))
             (if (string=? top name)
                 (Tarjan-groups-set popped (Cons (map (lambda (member) (named-definition popped member)) (Cons top group))
                                                 (Tarjan-groups popped)))
                 (loop popped (Cons top group)))))
          ((Nil) (panic "internal error: empty Tarjan stack")))))

    (: named-definition (-> Tarjan String Item))
    (define (named-definition tarjan name)
      (match (table-ref (Tarjan-by-name tarjan) name)
        ((Some item) item)
        ((None) (panic "internal error: lost definition"))))

    ))

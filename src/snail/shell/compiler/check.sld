;; Hindley-Milner checking with effect rows and typeclass evidence. Each
;; expression is rebuilt with its type; each variable records the type
;; arguments and the evidence of its instantiation, so later passes never
;; repeat inference or instance selection.
(define-library (snail shell compiler check)
  (export
   Typed
   definition-scheme
   check-program
   check-library)
  (import
   (snail core base)
   (snail core table)
   (snail shell compiler read)
   (snail shell compiler core)
   (snail shell compiler capabilities)
   (snail shell compiler ownership)
   (snail shell compiler conversions))
  (begin

    ;; ---- Checker state ----

    ;; The checker is plain data, threaded through the pass: a step takes one
    ;; and hands back the one it learned in. Its fields fall into two kinds.
    ;;
    ;; Scope, which a sub-check may replace and which the caller gets back
    ;; unchanged: `program`, `locals` mapping unique local names to
    ;; monomorphic types, `givens` the requirements of the annotated
    ;; definition being checked and `copy` the type variables it declares
    ;; ω, `confining` the row variable of a function body whose type
    ;; forbids `mut`, so calls in that body may mutate, and `signed` the
    ;; row variable of a function body checked against its signature, so
    ;; calls in that body record what they perform.
    ;;
    ;; What it has learned, which flows forward out of every sub-check:
    ;; `counter` numbering metavariables and evidence holes, `solution`,
    ;; `schemes` holding inferred schemes and the provisional types of the
    ;; group being inferred, `pending` recording constraints newest first
    ;; with their number in `pending-count` — they are decided once, when the
    ;; whole program has been checked — `open` naming the definitions whose
    ;; types may still contain metavariables, `discharged` recording whether
    ;; a call in a confining body mutated, `confined` holding the functions
    ;; that did, to be checked once their types are final, and `performed`
    ;; the effects that calls in the `signed` body performed.
    (struct Checker
      ((program Program)
       (locals (Table Type))
       (givens (List Constraint))
       (copy (List String))
       (instances (List String))
       (resolving (List Constraint))
       (confining (Option I64))
       (signed (Option I64))
       (counter I64)
       (solution Solution)
       (schemes (Table Scheme))
       (pending (List Wanted))
       (pending-count I64)
       (open (List String))
       (discharged Bool)
       (confined (List Expr))
       (performed (List String))))

    ;; A sequence of steps that each take the checker and hand it back,
    ;; written as `let*` is. `(name (step argument ...))` binds the step's
    ;; value; `(then (step argument ...))` is for a step that only learns and
    ;; hands back the checker alone. Every step is a call, with the checker
    ;; passed as its first argument, and the checker is named by an
    ;; identifier: each step rebinds that name, so the body and every later
    ;; step see the newest one and nothing can read a checker a step has
    ;; moved past. `then` is this form's own keyword, so a step cannot bind
    ;; a value under that name.
    (define-syntax learning
      (syntax-rules (then)
        ((_ ck () body ...) (begin body ...))
        ((_ ck ((then (f argument ...)) step ...) body ...)
         (let ((ck (f ck argument ...))) (learning ck (step ...) body ...)))
        ((_ ck ((name (f argument ...)) step ...) body ...)
         (match (f ck argument ...)
           ((Pair name ck) (learning ck (step ...) body ...))))))

    ;; A sub-check that ran under its own scope, resumed in the caller's:
    ;; everything it learned stays, every scoped field is the caller's again.
    ;; One place names which fields are which, so a sub-check cannot leak the
    ;; scope it ran under.
    (: resumed (impl (Fn Checker Checker -> Checker)))
    (define (resumed outer inner)
      (Checker (::program outer)
               (::locals outer)
               (::givens outer)
               (::copy outer)
               (::instances outer)
               (::resolving outer)
               (::confining outer)
               (::signed outer)
               (::counter inner)
               (::solution inner)
               (::schemes inner)
               (::pending inner)
               (::pending-count inner)
               (::open inner)
               (::discharged inner)
               (::confined inner)
               (::performed inner)))

    ;; What checking has learned: each metavariable's identity to the type it
    ;; stands for, and each evidence hole's to its evidence. A `Type` and an
    ;; `Expr` are plain data, so reading one means reading it through a
    ;; solution. `check-library` allocates one, refines it, and zonks it away
    ;; before returning, so neither it nor a metavariable outlives the call.
    (struct Solution
      ((types (Table Type))
       (evidence (Table Evidence))))

    (: empty-solution Solution)
    (define empty-solution (Solution empty-table empty-table))

    ;; Identities are dense small integers from one counter, so a key is just
    ;; its decimal text.
    (: identity-key (impl (Fn I64 -> String)))
    (define (identity-key id)
      (i64->string id))

    (: solved-type (impl (Fn Solution I64 -> (Option Type))))
    (define (solved-type solution id)
      (table-ref (::types solution) (identity-key id)))

    (: solved-evidence (impl (Fn Solution I64 -> (Option Evidence))))
    (define (solved-evidence solution id)
      (table-ref (::evidence solution) (identity-key id)))

    ;; A class constraint keeps the givens in scope where it arose, and the
    ;; type variables declared ω there, which decide what a drop releases
    ;; and a clone shares;
    ;; a Copy requirement keeps those variables too.
    (enum Wanted
      (WantClass
       ((constraint Constraint)
        (hole I64)
        (givens (List Constraint))
        (copy (List String))
        (instances (List String))
        (loc Loc)))
      (WantLiteral
       ((value Datum)
        (type Type)
        (loc Loc)))
      (WantCopy
       ((type Type)
        (copy (List String))
        (loc Loc))))

    ;; The checker's output: typed items in program order and every
    ;; definition's scheme.
    (struct Typed
      ((program Program)
       (items (List Item))
       (schemes (Table Scheme))))

    (: definition-scheme (impl (Fn Typed String -> Scheme)))
    (define (definition-scheme typed name)
      (match (table-ref (::schemes typed) name)
        ((Some scheme) scheme)
        ((None) (panic (string-append "internal error: no scheme for " name)))))

    (: program-of (impl (Fn Checker -> Program)))
    (define (program-of ck)
      (::program ck))

    (: solution (impl (Fn Checker -> Solution)))
    (define (solution ck)
      (::solution ck))

    ;; A linear query reads a type's structure, so it needs the solution
    ;; applied first; a metavariable on its own is not known to be linear.
    (: linear? (impl (Fn Checker Type -> Bool)))
    (define (linear? ck type)
      (linear-type? (program-of ck) (::copy ck) (resolve-type (solution ck) type)))

    (: bind-solved (impl (Fn Checker Type Type -> Checker)))
    (define (bind-solved ck meta type)
      (Checker-solution-set ck
                            (Solution (table-set (::types (solution ck))
                                                 (identity-key (TVar-id meta))
                                                 type)
                                      (::evidence (solution ck)))))

    (: fresh-identity (impl (Fn Checker -> (Pair I64 Checker))))
    (define (fresh-identity ck)
      (let ((id (+ (::counter ck) 1)))
        (Pair id (Checker-counter-set ck id))))

    ;; ---- Metavariables and unification ----

    (: fresh-meta (impl (Fn Checker -> (Pair Type Checker))))
    (define (fresh-meta ck)
      (learning ck ((id (fresh-identity)))
                (Pair (TVar id) ck)))

    (: meta? (impl (Fn Type -> Bool)))
    (define (meta? type)
      (match type
        ((TVar _) #t)
        (_ #f)))

    (: same-meta? (impl (Fn Type Type -> Bool)))
    (define (same-meta? a b)
      (match a
        ((TVar id) (match b ((TVar other) (= id other)) (_ #f)))
        (_ #f)))

    ;; The type a metavariable stands for, following a chain of bindings.
    ;; `bind?` always binds a pruned type, so a chain is short.
    (: prune (impl (Fn Solution Type -> Type)))
    (define (prune solution type)
      (match type
        ((TVar id)
         (match (solved-type solution id)
           ((Some bound) (prune solution bound))
           ((None) type)))
        (_ type)))

    (: unify (impl (Fn Checker Type Type Loc -> Checker ! compile)))
    (define (unify ck expected actual loc)
      (learning ck ((agreed (unify? expected actual)))
                (if agreed
                    ck
                    (compile-error loc
                                   (string-append "type mismatch: expected "
                                                  (type->string
                                                   (resolve-type (solution ck) expected))
                                                  ", found "
                                                  (type->string
                                                   (resolve-type (solution ck) actual)))))))

    ;; Unification both answers and learns, so it hands back both. A failed
    ;; attempt may still have bound metavariables along the way; the caller
    ;; reports the mismatch and goes no further, so nothing reads them.
    (: unify? (impl (Fn Checker Type Type -> (Pair Bool Checker))))
    (define (unify? ck a b)
      (let ((a (prune (solution ck) a)) (b (prune (solution ck) b)))
        (cond ((same-meta? a b) (Pair #t ck))
              ((meta? a) (bind? ck a b))
              ((meta? b) (bind? ck b a))
              (else (unify-structure? ck a b)))))

    (: unify-all? (impl (Fn Checker (List Type) (List Type) -> (Pair Bool Checker))))
    (define (unify-all? ck as bs)
      (if (= (length as) (length bs))
          (fold-left (lambda (done pair)
                       (if (::first done)
                           (unify? (::second done) (::first pair) (::second pair))
                           done))
                     (Pair #t ck) (zip as bs))
          (Pair #f ck)))

    (: unify-structure? (impl (Fn Checker Type Type -> (Pair Bool Checker))))
    (define (unify-structure? ck a b)
      (match a
        ((TCon name args)
         (match b
           ((TCon other others) (if (string=? name other) (unify-all? ck args others) (Pair #f ck)))
           (_ (Pair #f ck))))
        ((TFun params result row)
         (match b
           ((TFun others other-result other-row)
            (unify-function? ck params result row others other-result other-row))
           (_ (Pair #f ck))))
        ((TRow _ _) (unify-rows? ck a b))
        ((TRigid name)
         (match b
           ((TRigid other) (Pair (string=? name other) ck))
           (_ (Pair #f ck))))
        (_ (Pair #f ck))))

    ;; Parameters, result and row in turn, stopping at the first disagreement.
    (: unify-function?
       (impl (Fn Checker (List Type) Type Type (List Type) Type Type -> (Pair Bool Checker))))
    (define (unify-function? ck params result row others other-result other-row)
      (learning ck ((parameters (unify-all? params others)))
                (if (not parameters)
                    (Pair #f ck)
                    (learning ck ((results (unify? result other-result)))
                              (if (not results) (Pair #f ck) (unify-rows? ck row other-row))))))

    (: bind? (impl (Fn Checker Type Type -> (Pair Bool Checker))))
    (define (bind? ck meta type)
      (if (occurs? (solution ck) meta type)
          (Pair #f ck)
          (Pair #t (bind-solved ck meta type))))

    (: occurs? (impl (Fn Solution Type Type -> Bool)))
    (define (occurs? solution meta type)
      (let ((type (prune solution type)))
        (match type
          ((TVar _) (same-meta? type meta))
          ((TCon _ args) (any? (lambda (arg) (occurs? solution meta arg)) args))
          ((TFun params result row)
           (or (any? (lambda (param) (occurs? solution meta param)) params)
               (occurs? solution meta result) (occurs? solution meta row)))
          ((TRow _ (Some tail)) (occurs? solution meta tail))
          (_ #f))))

    ;; ---- Effect rows ----

    ;; A row flattens to its labels and a tail: none when closed, otherwise a
    ;; rigid variable or an unbound metavariable.
    (: flatten-row (impl (Fn Solution Type -> (Pair (List String) (Option Type)))))
    (define (flatten-row solution row)
      (let ((row (prune solution row)))
        (match row
          ((TRow labels (None)) (Pair labels (None)))
          ((TRow labels (Some tail))
           (let ((rest (flatten-row solution tail)))
             (Pair (label-union labels (::first rest)) (::second rest))))
          (_ (Pair (Nil) (Some row))))))

    (: meta-tail? (impl (Fn (Option Type) -> Bool)))
    (define (meta-tail? tail)
      (match tail
        ((Some type) (meta? type))
        ((None) #f)))

    (: same-tail? (impl (Fn (Option Type) (Option Type) -> Bool)))
    (define (same-tail? a b)
      (match a
        ((None) (match b ((None) #t) ((Some _) #f)))
        ((Some (TRigid name)) (match b ((Some (TRigid other)) (string=? name other)) (_ #f)))
        ((Some x) (match b ((Some y) (same-meta? x y)) ((None) #f)))))

    ;; Rows unify as sets: shared labels match, and each open tail absorbs the
    ;; labels only the other side has.
    (: unify-rows? (impl (Fn Checker Type Type -> (Pair Bool Checker))))
    (define (unify-rows? ck a b)
      (let* ((left (flatten-row (solution ck) a)) (right (flatten-row (solution ck) b))
             (only-left (label-difference (::first left) (::first right)))
             (only-right (label-difference (::first right) (::first left)))
             (left-tail (::second left)) (right-tail (::second right)))
        (cond
         ((same-tail? left-tail right-tail) (Pair (and (null? only-left) (null? only-right)) ck))
         ((and (meta-tail? left-tail) (meta-tail? right-tail))
          (learning ck ((meta (fresh-meta))
                        (bound-left (bind? (tail-type left-tail) (TRow only-right (Some meta)))))
                    (if (not bound-left)
                        (Pair #f ck)
                        (bind? ck (tail-type right-tail) (TRow only-left (Some meta))))))
         ((meta-tail? left-tail)
          (if (null? only-left)
              (bind? ck (tail-type left-tail) (TRow only-right right-tail))
              (Pair #f ck)))
         ((meta-tail? right-tail)
          (if (null? only-right)
              (bind? ck (tail-type right-tail) (TRow only-left left-tail))
              (Pair #f ck)))
         (else (Pair #f ck)))))

    (: tail-type (impl (Fn (Option Type) -> Type)))
    (define (tail-type tail)
      (match tail
        ((Some type) type)
        ((None) (panic "internal error: closed row"))))

    ;; Calls require inclusion, not row equality: e fits console + e for every
    ;; substitution of e. A shared tail proves inclusion when its known labels
    ;; fit. Otherwise inference opens closed latent rows before unification.
    ;; In a confining body, `mut` is discharged before either check.
    (: perform (impl (Fn Checker Type Type Loc -> Checker ! compile)))
    (define (perform ck latent row loc)
      (let ((flat (flatten-row (solution ck) latent)))
        (learning ck ((labels (performed-labels row (::first flat)))
                      (then
                       (record-performed row (append labels (tail-variable (::second flat))))))
                  (let ((context (flatten-row (solution ck) row)))
                    (if (and (same-tail? (::second flat) (::second context))
                             (null? (label-difference labels (::first context))))
                        ck
                        (learning ck ((tail (row-tail (::second flat)))
                                      (included (unify? (TRow labels (Some tail)) row)))
                                  (if included
                                      ck
                                      (compile-error loc
                                                     (string-append
                                                      "this performs effects its context does not allow:"
                                                      (labels->string
                                                       (append labels
                                                               (tail-variable
                                                                (::second flat)))))))))))))

    ;; In a confining body `mut` is discharged before the row is compared.
    (: performed-labels (impl (Fn Checker Type (List String) -> (Pair (List String) Checker))))
    (define (performed-labels ck row labels)
      (if (confining-row? ck row) (discharge-mut ck labels) (Pair labels ck)))

    ;; A latent row's own tail, or a fresh one when it is closed.
    (: row-tail (impl (Fn Checker (Option Type) -> (Pair Type Checker))))
    (define (row-tail ck tail)
      (match tail
        ((Some tail) (Pair tail ck))
        ((None) (fresh-meta ck))))

    (: discharge-mut (impl (Fn Checker (List String) -> (Pair (List String) Checker))))
    (define (discharge-mut ck labels)
      (Pair (filter (lambda (label) (not (string=? label "mut"))) labels)
            (if (member? "mut" labels) (Checker-discharged-set ck #t) ck)))

    (: confining-row? (impl (Fn Checker Type -> Bool)))
    (define (confining-row? ck row)
      (row-variable? (::confining ck) row))

    ;; Whether `row` is the row variable that `variable` names, if any.
    (: row-variable? (impl (Fn (Option I64) Type -> Bool)))
    (define (row-variable? variable row)
      (match (Pair variable row)
        ((Pair (Some number) (TVar id)) (= number id))
        (_ #f)))

    ;; A call in the signed body performs its labels, and its tail when that
    ;; is a quantified variable. A metavariable tail performs nothing of its
    ;; own: inclusion binds it to whatever the row has left over.
    (: record-performed (impl (Fn Checker Type (List String) -> Checker)))
    (define (record-performed ck row effects)
      (if (row-variable? (::signed ck) row)
          (Checker-performed-set ck (label-union (::performed ck) effects))
          ck))

    (: tail-variable (impl (Fn (Option Type) -> (List String))))
    (define (tail-variable tail)
      (match tail
        ((Some (TRigid name)) (list name))
        (_ (Nil))))

    ;; The effects a declared row names that no call performed: its labels
    ;; and its tail variable, less those `performed` records.
    (: unperformed-effects (impl (Fn Type (List String) -> (List String))))
    (define (unperformed-effects declared performed)
      (let ((flat (flatten-row empty-solution declared)))
        (label-difference (append (::first flat) (tail-variable (::second flat))) performed)))

    (: total? (impl (Fn Solution Type -> Bool)))
    (define (total? solution row)
      (null? (::first (flatten-row solution row))))

    ;; ---- Instantiation ----

    (: want (impl (Fn Checker Wanted -> Checker)))
    (define (want ck wanted)
      (Checker-pending-count-set (Checker-pending-set ck (Cons wanted (::pending ck)))
                                 (+ (::pending-count ck) 1)))

    (: want-class (impl (Fn Checker Constraint Loc -> (Pair Evidence Checker))))
    (define (want-class ck constraint loc)
      (learning ck ((hole (fresh-identity))
                    (then
                     (want (WantClass constraint
                                      hole
                                      (::givens ck)
                                      (::copy ck)
                                      (::instances ck)
                                      loc))))
                (Pair (EvHole hole) ck)))

    ;; A use of a variable: its type, the types its quantified variables
    ;; took, and the evidence for its constraints.
    (struct Instantiated
      ((type Type)
       (types (List Type))
       (evidence (List Evidence))))

    ;; Fresh metavariables for the quantified variables, a hole for each
    ;; constraint, and a fresh tail on a closed outermost row.
    (: instantiate (impl (Fn Checker Scheme Loc -> (Pair Instantiated Checker))))
    (define (instantiate ck scheme loc)
      (learning ck ((metas (fresh-bindings (::vars scheme)))
                    (type (open-row (substitute metas (::type scheme))))
                    (evidence (each (lambda (ck constraint)
                                      (want-class ck (substitute-constraint metas constraint) loc))
                                    (::constraints scheme)))
                    (then (want-each (copy-requirements ck scheme metas loc))))
                (Pair (Instantiated type (map ::second metas) evidence) ck)))

    ;; The types a use binds to the variables its scheme declares ω must be
    ;; ω where it is: concrete types without a linear part, or variables the
    ;; enclosing definition declares ω in turn. The other variables may
    ;; take linear types.
    (: copy-requirements (impl (Fn Checker Scheme Substitution Loc -> (List Wanted))))
    (define (copy-requirements ck scheme metas loc)
      (map (lambda (meta) (WantCopy (::second meta) (::copy ck) loc))
           (filter (lambda (meta) (member? (::first meta) (::copy scheme))) metas)))

    ;; A fresh metavariable per quantified variable, in order.
    (: fresh-bindings (impl (Fn Checker (List String) -> (Pair Substitution Checker))))
    (define (fresh-bindings ck vars)
      (each ck
            (lambda (ck var) (learning ck ((meta (fresh-meta))) (Pair (Pair var meta) ck)))
            vars))

    (: want-each (impl (Fn Checker (List Wanted) -> Checker)))
    (define (want-each ck wanted)
      (fold-left want ck wanted))

    ;; `step` over each item in order, threading the checker and collecting
    ;; the values, so a sequence of learning steps is itself one step.
    (: each
       (All (A B e) (requires (Copy B))
            (impl (Fn Checker
                      (dyn (Fn Checker A -> (Pair B Checker) ! e))
                      (List A)
                      ->
                      (Pair (List B) Checker)
                      ! e))))
    (define (each ck step items)
      (let ((done (fold-left (lambda (done item)
                               (match (step (::second done) item)
                                 ((Pair value ck) (Pair (Cons value (::first done)) ck))))
                             (Pair (Nil) ck) items)))
        (Pair (reverse (::first done)) (::second done))))

    (: open-row (impl (Fn Checker Type -> (Pair Type Checker))))
    (define (open-row ck type)
      (match (prune (solution ck) type)
        ((TFun params result (TRow labels (None)))
         (learning ck ((tail (fresh-meta)))
                   (Pair (TFun params result (TRow labels (Some tail))) ck)))
        ((TCon name (Cons arrow captures))
         (if (concrete-callable? type)
             (learning ck ((arrow (open-row arrow)))
                       (Pair (TCon name (Cons arrow captures)) ck))
             (Pair type ck)))
        (_ (Pair type ck))))

    (: global-scheme (impl (Fn Checker String -> (Option Scheme))))
    (define (global-scheme ck name)
      (match (table-ref (::schemes ck) name)
        ((Some scheme) (Some scheme))
        ((None)
         (match (program-value (program-of ck) name)
           ((Some value)
            (match (value-scheme value)
              ((Some scheme) (Some (named-callable-scheme name scheme)))
              ((None) (None))))
           ((None) (None))))))

    ;; Names are unique, so a local's type is in scope exactly where its
    ;; binding form passes the extended checker.
    (: bind-local (impl (Fn Checker String Type -> Checker)))
    (define (bind-local ck name type)
      (Checker-locals-set ck (table-set (::locals ck) name type)))

    (: bind-locals (impl (Fn Checker (List String) (List Type) -> Checker)))
    (define (bind-locals ck names types)
      (fold-left (lambda (ck pair) (bind-local ck (::first pair) (::second pair)))
                 ck
                 (zip names types)))

    (: set-scheme (impl (Fn Checker String Scheme -> Checker)))
    (define (set-scheme ck name scheme)
      (Checker-schemes-set ck (table-set (::schemes ck) name scheme)))

    (: variable-type (impl (Fn Checker String Loc -> (Pair Instantiated Checker) ! compile)))
    (define (variable-type ck name loc)
      (match (table-ref (::locals ck) name)
        ((Some local) (Pair (Instantiated local (Nil) (Nil)) ck))
        ((None)
         (match (global-scheme ck name)
           ((Some scheme) (instantiate ck scheme loc))
           ((None) (compile-error loc (string-append "internal error: no type for " name)))))))

    ;; ---- Expressions ----

    (: literal-type (impl (Fn Checker Datum Loc -> (Pair Type Checker))))
    (define (literal-type ck value loc)
      (match value
        ((DBool _) (Pair (TCon "Bool" (Nil)) ck))
        ((DChar _) (Pair (TCon "Char" (Nil)) ck))
        ((DString _) (Pair (TCon "String" (Nil)) ck))
        ((DBytes _) (Pair (TCon "Vector" (list (TCon "U8" (Nil)))) ck))
        ((DUnit) (Pair (TCon "Unit" (Nil)) ck))
        (_ (learning ck ((type (fresh-meta))
                         (then (want (WantLiteral value type loc))))
                     (Pair type ck)))))

    ;; `row` is the effect row of the enclosing function body.
    (: infer (impl (Fn Checker Expr Type -> (Pair Expr Checker) ! compile)))
    (define (infer ck expr row)
      (let ((loc (::loc expr)))
        (match (::term expr)
          ((Lit value)
           (learning ck ((type (literal-type value loc)))
                     (Pair (Expr (Lit value) type loc) ck)))
          ((Var name _ _)
           (learning ck ((use (variable-type name loc)))
                     (Pair (Expr (Var name (::types use) (::evidence use))
                                 (::type use)
                                 loc)
                           ck)))
          ((Lambda params body captures?) (infer-lambda ck params body captures? loc))
          ((App callee args) (infer-app ck callee args row loc))
          ;; `then` is `learning`'s own keyword, so the branches are named
          ;; for what they are rather than by their field names.
          ((If test consequent alternative)
           (learning ck ((test (infer test row))
                         (consequent (infer consequent row))
                         (alternative (infer alternative row))
                         (test (fit (TCon "Bool" (Nil)) test row (::loc test)))
                         (then (unify (::type consequent)
                                      (::type alternative)
                                      (::loc alternative))))
                     (Pair (Expr (If test consequent alternative) (::type consequent) loc) ck)))
          ((Let name value body) (infer-let ck name value body row loc))
          ((Seq first rest)
           (learning ck ((first (infer first row))
                         (rest (infer rest row)))
                     (Pair (Expr (Seq first rest) (::type rest) loc) ck)))
          ((Match scrutinee clauses) (infer-match ck scrutinee clauses row loc))
          ((ScopedInstances sets body)
           (scoped ck (instance-scope ck sets loc) body row))
          ((Ann inner type)
           (learning ck ((inner (check-value inner type row)))
                     (fit ck type inner row loc)))
          ((Handle effect implementations body)
           (infer-handle ck effect implementations body row loc))
          ;; The direction is decided once types are ground: to Any, from
          ;; Any, or nothing when the types already agree.
          ((Convert inner target)
           (learning ck ((inner (infer inner row)))
                     (fit ck target inner row loc)))
          ((TryConvert inner target)
           (learning ck ((inner (infer inner row))
                         (inner (fit (TCon "Any" (Nil)) inner row (::loc inner))))
                     (Pair (Expr (TryConvert inner target) (cast-result-type target) loc) ck)))
          ;; Whether an Any holds a value of the target type.
          ((TypeTest inner target)
           (learning ck ((inner (infer inner row))
                         (inner (fit (TCon "Any" (Nil)) inner row (::loc inner))))
                     (Pair (Expr (TypeTest inner target) (TCon "Bool" (Nil)) loc) ck))))))

    (: instance-scope (impl (Fn Checker (List String) Loc -> Checker ! compile)))
    (define (instance-scope ck sets loc)
      (let ((sets (delete-duplicates string=? (append sets (::instances ck)))))
        (check-active-instances (program-of ck) sets loc)
        (Checker-instances-set ck sets)))

    (: infer-lambda
       (impl (Fn Checker (List String) Expr Bool Loc -> (Pair Expr Checker) ! compile)))
    (define (infer-lambda ck params body captures? loc)
      (learning ck ((types (each (lambda (ck param) (fresh-meta ck)) params))
                    (value (infer-lambda-at params body captures? types loc))
                    (type (lambda-contract params body
                                           (TCon "$impl.Fn" (list (::type value))) loc)))
                (Pair (Expr (::term value) type loc) ck)))

    ;; A lambda whose parameter types are known before its body is seen.
    (: infer-lambda-at
       (impl (Fn Checker (List String) Expr Bool (List Type) Loc -> (Pair Expr Checker) ! compile)))
    (define (infer-lambda-at ck params body captures? types loc)
      (learning ck ((body-row (fresh-meta))
                    (body (scoped (bind-locals ck params types) body body-row))
                    (then (cleanup-lambda params types body body-row)))
                (Pair
                 (Expr (Lambda params body captures?) (TFun types (::type body) body-row) loc)
                 ck)))

    ;; A sub-check under `inner`'s scope, resumed in this checker's. `inner`
    ;; is built from this one, so everything it learns flows back; only its
    ;; scope is discarded.
    (: within
       (All (A e)
            (impl (Fn Checker
                      Checker
                      (dyn (Fn Checker -> (Pair A Checker) ! e))
                      ->
                      (Pair A Checker)
                      ! e))))
    (define (within ck inner check)
      (match (check inner)
        ((Pair value done) (Pair value (resumed ck done)))))

    ;; Checks an expression against a known type: a lambda's parameters and
    ;; body row come from the type; anything else is inferred. A body whose
    ;; row forbids `mut` may still mutate storage it allocates; the function
    ;; is confined once its types are final.
    (: check-value (impl (Fn Checker Expr Type Type -> (Pair Expr Checker) ! compile)))
    (define (check-value ck expr type row)
      (match (Pair (::term expr) (prune (solution ck) type))
        ((Pair (ScopedInstances sets body) _)
         (within ck (instance-scope ck sets (::loc expr))
                 (lambda (inner) (check-value inner body type row))))
        ((Pair (App callee args) _)
         (infer-app-at ck callee args row (::loc expr) (Some type)))
        ((Pair (If test consequent alternative) _)
         (learning ck ((test (check-result test (TCon "Bool" (Nil)) row))
                       (consequent (check-result consequent type row))
                       (alternative (check-result alternative type row)))
                   (Pair (Expr (If test consequent alternative) type (::loc expr)) ck)))
        ((Pair (Let name value body) _)
         (learning ck ((local (local-placeholder name value))
                       (value (infer-let-value name local value row))
                       (then (unify local (::type value) (::loc value)))
                       (body (within (bind-local ck name local)
                                     (lambda (inner) (check-result inner body type row)))))
                   (Pair (Expr (Let name value body) type (::loc expr)) ck)))
        ((Pair (Seq first rest) _)
         (learning ck ((first (infer first row)) (rest (check-result rest type row)))
                   (Pair (Expr (Seq first rest) type (::loc expr)) ck)))
        ((Pair (Match scrutinee clauses) _)
         (infer-match-at ck scrutinee clauses type row (::loc expr)))
        ((Pair (Lambda params body captures?) (TFun param-types result body-row))
         (if (= (length params) (length param-types))
             (check-lambda ck expr params body captures? type param-types result body-row)
             (infer ck expr row)))
        ;; A function at a fn is checked at its signature, then given the fn.
        ((Pair _ (TCon "fn" (Cons arrow (Nil))))
         (learning ck ((value (check-value expr arrow row)))
                   (fit ck type value row (::loc value))))
        ((Pair (Lambda params body captures?) (TCon _ (Cons arrow _)))
         (cond ((impl-callable? type)
                (learning ck ((concrete (lambda-contract params body type (::loc expr))))
                          (check-value ck expr concrete row)))
               ((concrete-callable? type)
                (match arrow
                  ((TFun types result effects)
                   (check-lambda ck expr params body captures? type types result effects))
                  (_ (panic "internal error: a concrete callable has a signature"))))
               ((match (callable-kind type)
                  ((Some kind) (member? kind (list "FnMut" "FnOnce"))) (_ #f))
                (learning ck ((concrete (lambda-contract params body type (::loc expr))))
                          (check-value ck expr concrete row)))
               (else (infer ck expr row))))
        ((Pair (Lambda params body _) _)
         (check-constrained-lambda ck expr params body type row))
        (_ (infer ck expr row))))

    ;; A generic callable argument gets its signature from the outstanding
    ;; class requirement before its body is checked. Its identity stays
    ;; concrete; only an explicit dyn field chooses erased storage.
    (: check-constrained-lambda
       (impl (Fn Checker Expr (List String) Expr Type Type -> (Pair Expr Checker) ! compile)))
    (define (check-constrained-lambda ck expr params body type row)
      (let ((requirements (fold-right (lambda (wanted rest)
                                        (match wanted
                                          ((WantClass constraint _ _ _ _ _) (Cons constraint rest))
                                          (_ rest))) (Nil) (::pending ck))))
        (match (given-callable ck type requirements (list "Fn" "FnMut" "FnOnce"))
          ((Some (Pair "FnOnce" (TVar _))) (infer-once-argument ck expr row))
          ((Some (Pair kind arrow))
           (learning ck ((concrete (lambda-contract params body
                                                    (TCon (string-append "$impl." kind)
                                                          (list arrow))
                                                    (::loc expr))))
                     (check-value ck expr concrete row)))
          ((None) (infer ck expr row)))))

    (: check-result (impl (Fn Checker Expr Type Type -> (Pair Expr Checker) ! compile)))
    (define (check-result ck expr type row)
      (learning ck ((expr (check-value expr type row)))
                (fit ck type expr row (::loc expr))))

    (: lambda-contract (impl (Fn Checker (List String) Expr Type Loc -> (Pair Type Checker))))
    (define (lambda-contract ck params body contract loc)
      (learning ck ((identity (fresh-identity)))
                (match (Pair (callable-kind contract) (callable-arrow contract))
                  ((Pair (Some kind) (Some arrow))
                   (Pair (concrete-callable kind
                                            (string-append (loc->string loc) "."
                                                           (i64->string identity))
                                            arrow (capture-types ck params body)) ck))
                  (_ (panic "internal error: a lambda has a callable contract")))))

    (: capture-types (impl (Fn Checker (List String) Expr -> (List Type))))
    (define (capture-types ck params body)
      (fold-right (lambda (name types)
                    (match (if (member? name params) (None) (table-ref (::locals ck) name))
                      ((Some type) (Cons type types))
                      ((None) types)))
                  (Nil) (expr-references body)))

    ;; A lambda checked against its type. The body's row is a variable bound
    ;; to the type's row, so `perform` can recognize it: calls in this body,
    ;; but not in lambdas inside it, record in `performed` what they
    ;; perform. A body whose row forbids `mut` is checked as confining; if a
    ;; call in it did mutate, the function goes to `confined` and the flag
    ;; is cleared for the next one.
    (: check-lambda
       (impl (Fn Checker
                 Expr
                 (List String)
                 Expr
                 Bool
                 Type
                 (List Type)
                 Type
                 Type
                 -> (Pair Expr Checker)
                 ! compile)))
    (define (check-lambda ck expr params body captures? type param-types result body-row)
      (let ((outer ck))
        (learning ck ((then (Checker-discharged-set #f))
                      (row (fresh-meta))
                      (then (unify row body-row (::loc expr)))
                      (body
                       (within (signed-body (bind-locals ck params param-types) row)
                               (lambda (inner)
                                 (match (if (forbids-mut? (solution inner) body-row)
                                            (check-confining-body inner body result row)
                                            (check-value inner body result row))
                                   ((Pair body inner)
                                    (match (fit inner result body row (::loc body))
                                      ((Pair body inner)
                                       (Pair body
                                             (cleanup-lambda inner
                                                             params
                                                             param-types
                                                             body
                                                             row))))))))))
                  (let* ((value (Expr (Lambda params body captures?) type (::loc expr)))
                         (done (if (::discharged ck)
                                   (Checker-confined-set ck (Cons value (::confined ck))) ck)))
                    (Pair value (finish-lambda-scope outer done))))))

    ;; A nested function's effects do not replace what its enclosing body
    ;; already performed. Its own confinement proof remains in `confined`.
    (: finish-lambda-scope (impl (Fn Checker Checker -> Checker)))
    (define (finish-lambda-scope outer done)
      (let ((done (Checker-discharged-set done (::discharged outer))))
        (match (::signed outer)
          ((Some _) (Checker-performed-set done (::performed outer)))
          ((None) done))))

    ;; The scope of a body checked against its signature, whose row
    ;; variable is `row`: nothing is performed in it yet.
    (: signed-body (impl (Fn Checker Type -> Checker)))
    (define (signed-body ck row)
      (Checker-performed-set (Checker-signed-set ck (Some (meta-number row))) (Nil)))

    ;; `perform` recognizes the body's row variable and lets calls in this
    ;; body, but not in lambdas inside it, mutate. `confining` is scope, so
    ;; the caller gets its own back.
    (: check-confining-body (impl (Fn Checker Expr Type Type -> (Pair Expr Checker) ! compile)))
    (define (check-confining-body ck body type row)
      (within ck (Checker-confining-set ck (Some (meta-number row)))
              (lambda (inner) (check-value inner body type row))))

    (: meta-number (impl (Fn Type -> I64)))
    (define (meta-number meta)
      (match meta
        ((TVar id) id)
        (_ -1)))

    ;; A row forbids `mut` unless it lists it or is open to more labels.
    (: forbids-mut? (impl (Fn Solution Type -> Bool)))
    (define (forbids-mut? solution row)
      (let ((flat (flatten-row solution row)))
        (not (or (member? "mut" (::first flat)) (meta-tail? (::second flat))))))

    (: infer-app (impl (Fn Checker Expr (List Expr) Type Loc -> (Pair Expr Checker) ! compile)))
    (define (infer-app ck callee args row loc)
      (infer-app-at ck callee args row loc (None)))

    (: infer-app-at (impl (Fn Checker Expr (List Expr) Type Loc (Option Type)
                              -> (Pair Expr Checker) ! compile)))
    (define (infer-app-at ck callee args row loc expected)
      (let ((before (::pending-count ck)))
        (learning ck ((callee (infer callee row))
                      (then (result-context callee expected loc))
                      (args (infer-arguments callee args row))
                      (callee (borrowed-accessor callee args before))
                      (result (fresh-meta))
                      (latent (fresh-meta))
                      (args (unify-call (::type callee) args result latent row loc))
                      (callee (mark-invocation callee))
                      (then (improve-types before))
                      (then (perform latent row loc))
                      (then (solve-found-rows before row)))
                  (Pair (Expr (App callee args) result loc) ck))))

    ;; Matching result constructors carry an explicit storage boundary
    ;; inward. This also reaches callbacks of producers such as map.
    (: result-context (impl (Fn Checker Expr (Option Type) Loc -> Checker ! compile)))
    (define (result-context ck callee expected loc)
      (match (Pair (callable-contract ck (::type callee) (::givens ck)) expected)
        ((Pair (Some (Pair _ (TFun _ (TCon result args) _))) (Some type))
         (match (prune (solution ck) type)
           ((TCon target _) (if (string=? target result)
                                (unify ck type (TCon result args) loc) ck))
           (_ ck)))
        (_ ck)))

    (: infer-arguments
       (impl (Fn Checker Expr (List Expr) Type -> (Pair (List Expr) Checker) ! compile)))
    (define (infer-arguments ck callee args row)
      (match (callable-contract ck (::type callee) (::givens ck))
        ((Some (Pair _ (TFun params _ _)))
         (if (= (length params) (length args))
             (each ck (lambda (ck pair)
                        (if (projection-call? ck callee)
                            (check-value ck (::second pair) (::first pair) row)
                            (check-result ck (::second pair) (::first pair) row)))
                   (zip params args))
             (each ck (lambda (ck arg) (infer ck arg row)) args)))
        (_ (each ck (lambda (ck arg) (infer ck arg row)) args))))

    ;; Projections first inspect their receiver to choose an owned or
    ;; borrowed field signature. Other parameters constrain later arguments.
    (: projection-call? (impl (Fn Checker Expr -> Bool)))
    (define (projection-call? ck callee)
      (match (::term callee)
        ((Var name _ _)
         (match (program-value (program-of ck) name)
           ((Some (Accessor _ _ _)) #t)
           ((Some (Method class _)) (field-class? class))
           (_ #f)))
        (_ #f)))

    ;; A literal once body consumes its captures. Giving that lambda the
    ;; actual FnOnce identity removes a special ownership-checking mode.
    (: infer-once-argument (impl (Fn Checker Expr Type -> (Pair Expr Checker) ! compile)))
    (define (infer-once-argument ck expr row)
      (learning ck ((value (infer expr row)))
                (Pair (if (and (lambda-expr? expr) (concrete-callable? (::type value)))
                          (match (::type value)
                            ((TCon name (Cons arrow captures))
                             (Expr (::term value) (concrete-callable "FnOnce" name arrow captures)
                                   (::loc value)))
                            (_ value))
                          value) ck)))

    ;; An immutable accessor reads through a Borrow without changing
    ;; it into an owner. Copy fields leave as owned values; linear fields
    ;; remain borrowed. Ordinary function calls never unwrap Borrow.
    (: borrowed-accessor (impl (Fn Checker Expr (List Expr) I64 -> (Pair Expr Checker) ! compile)))
    (define (borrowed-accessor ck callee args before)
      (match (Pair (::term callee) args)
        ((Pair (Var name _ _) (Cons record (Nil)))
         (if (borrow-type? (prune (solution ck) (::type record)))
             (match (program-value (program-of ck) name)
               ((Some (Accessor case index _))
                (borrowed-field ck callee record (list-ref (::fields case) index)))
               ((Some (Method class _))
                (if (field-class? class)
                    (borrowed-method ck callee record class before)
                    (Pair callee ck)))
               (_ (Pair callee ck)))
             (Pair callee ck)))
        (_ (Pair callee ck))))

    ;; Field shorthand must resolve to a real slot before it can lend it.
    ;; A computed field or a generic requirement could consume its owner.
    (: borrowed-method (impl (Fn Checker Expr Expr String I64 -> (Pair Expr Checker) ! compile)))
    (define (borrowed-method ck callee record class before)
      (match (::type callee)
        ((TFun (Cons owner (Nil)) result _)
         (learning ck ((then (unify owner
                                    (borrow-target (prune (solution ck) (::type record)))
                                    (::loc record)))
                       (then (improve-types before))
                       (evidence (requirement-evidence (Constraint class (list owner result))
                                                       (::givens ck) (::copy ck)
                                                       (::loc record))))
                   (match (link-field (program-of ck) class (list evidence))
                     ((Ok field) (borrowed-field ck callee record field))
                     ((Err _)
                      (compile-error (::loc record)
                                     "a Borrow requires a concrete immutable field accessor")))))
        (_ (panic "internal error: a field method does not have one argument"))))

    (: borrowed-field (impl (Fn Checker Expr Expr Field -> (Pair Expr Checker) ! compile)))
    (define (borrowed-field ck callee record field)
      (when (::mutable? field)
        (compile-error (::loc record) "a Borrow can read only immutable fields"))
      (match (::type callee)
        ((TFun (Cons owner (Nil)) result row)
         (learning ck ((then (unify owner
                                    (borrow-target (prune (solution ck) (::type record)))
                                    (::loc record))))
                   (Pair (Expr (::term callee)
                               (TFun (list (::type record))
                                     (if (linear? ck result)
                                         (TCon "Borrow" (list result)) result)
                                     row)
                               (::loc callee)) ck)))
        (_ (panic "internal error: an accessor does not have one argument"))))

    ;; Arguments are compared one by one, so a mismatch names its argument,
    ;; and each meets its parameter's type (`fit`), which may give it the
    ;; type Fn.
    (: unify-call
       (impl
        (Fn Checker Type (List Expr) Type Type Type Loc -> (Pair (List Expr) Checker) ! compile)))
    (define (unify-call ck callee-type args result latent context loc)
      (match (prune (solution ck) callee-type)
        ((TFun params callee-result row)
         (unless (= (length params) (length args))
           (compile-error loc
                          (string-append "expected "
                                         (i64->string (length params))
                                         " arguments, found "
                                         (i64->string (length args)))))
         (learning ck ((then (fit-known-arguments params args context))
                       (args (each (lambda (ck pair)
                                     (fit ck
                                          (::first pair)
                                          (::second pair)
                                          context
                                          (::loc (::second pair))))
                                   (zip params args)))
                       (then (unify callee-result result loc))
                       (then (unify row latent loc)))
                   (Pair args ck)))
        ((TVar _) (Pair args (unify ck callee-type (TFun (map ::type args) result latent) loc)))
        ;; Calling a `FnOnce` calls the procedure it holds; ownership consumes
        ;; it. Calling a `fn` calls the code it is.
        ((TCon "FnOnce" (Cons procedure (Nil)))
         (unify-call ck procedure args result latent context loc))
        ((TCon "fn" (Cons procedure (Nil)))
         (unify-call ck procedure args result latent context loc))
        (other
         (match (callable-contract ck other (::givens ck))
           ((Some contract) (unify-call ck (::second contract) args result latent context loc))
           ((None) (compile-error loc (string-append "not a function: " (type->string other))))))))

    ;; The strongest available receiver contract decides a call. A generic
    ;; callable's contract comes from its requirement, not from Copy and not
    ;; from a particular implementation that may later instantiate it.
    (: callable-contract (impl (Fn Checker Type (List Constraint) -> (Option (Pair String Type)))))
    (define (callable-contract ck type givens)
      (let ((type (prune (solution ck) type)))
        (match (Pair (callable-kind type) (callable-arrow type))
          ((Pair (Some kind) (Some arrow)) (Some (Pair kind arrow)))
          (_ (given-callable ck type givens (list "Fn" "FnMut" "FnOnce"))))))

    (: given-callable
       (impl (Fn Checker Type (List Constraint) (List String) -> (Option (Pair String Type)))))
    (define (given-callable ck type givens kinds)
      (match kinds
        ((Nil) (None))
        ((Cons kind rest)
         (match (find (lambda (given)
                        (and (string=? (::class given) (callable-class kind))
                             (type=? type (prune (solution ck) (list-ref (::types given) 0)))))
                      givens)
           ((Some given) (Some (Pair kind (prune (solution ck) (list-ref (::types given) 1)))))
           ((None) (given-callable ck type givens rest))))))

    (: mark-invocation (impl (Fn Checker Expr -> (Pair Expr Checker))))
    (define (mark-invocation ck callee)
      (let ((type (prune (solution ck) (::type callee))))
        (if (or (concrete-callable? type)
                (match type ((TRigid _) #t) ((TCon "FnMut" _) #t) (_ #f)))
            (match (callable-contract ck (::type callee) (::givens ck))
              ((Some contract)
               (Pair (Expr (Ann callee (TCon "$invoke" (list (TCon (::first contract) (Nil))
                                                             (::second contract))))
                           (::type callee) (::loc callee)) ck))
              ((None) (Pair callee ck)))
            (Pair callee ck))))

    ;; Concrete arguments constrain shared type variables before an Any
    ;; can instantiate one. This changes inference order, never evaluation
    ;; order: `(f boxed 1)` and `(f 1 boxed)` both select f at I64 when its
    ;; two parameters share a type. With only Any arguments it selects Any.
    (: fit-known-arguments (impl (Fn Checker (List Type) (List Expr) Type -> Checker ! compile)))
    (define (fit-known-arguments ck params args row)
      (fold-left (lambda (ck pair)
                   (let ((arg (::second pair)))
                     (if (any-type? (prune (solution ck) (::type arg)))
                         ck
                         (::second (fit ck (::first pair) arg row (::loc arg))))))
                 ck (zip params args)))

    ;; A value meets the type it is checked at: a parameter's, an
    ;; annotation's or a signature's. At a fn, a `fn` or the name of a
    ;; top-level function is given that type, since neither has an
    ;; environment: `check-closed` proves it of a `fn`, and the expander
    ;; records which globals are functions. No other value has type fn
    ;; unless it already does. Any crosses this boundary through an explicit
    ;; Convert in the checked IR. Variables still unify normally; a rigid
    ;; variable is not a runtime type to test. The final conversion and
    ;; ownership checks enforce the same restrictions as explicit casts.
    (: fit (impl (Fn Checker Type Expr Type Loc -> (Pair Expr Checker) ! compile)))
    (define (fit ck expected expr row loc)
      (let ((expected (prune (solution ck) expected))
            (actual (prune (solution ck) (::type expr))))
        (cond ((impl-callable? expected) (fit-callable-contract ck expected expr row loc))
              ((and (concrete-callable? actual) (not (concrete-callable? expected))
                    (not (match expected ((TCon "fn" _) #t) (_ #f)))
                    (match (callable-arrow expected) ((Some _) #t) ((None) #f)))
               (erase-callable ck expected expr row loc))
              (else (match (Pair expected actual)
                      ((Pair (TCon "Any" (Nil)) (TCon "Any" (Nil))) (Pair expr ck))
                      ((Pair (TCon "Any" (Nil)) (TVar _))
                       (fit-any-literal ck expected expr (::type expr) row loc))
                      ((Pair (TVar _) (TCon "Any" (Nil)))
                       (fit-any-literal ck expected expr expected row loc))
                      ((Pair (TVar _) _) (Pair expr (unify ck expected (::type expr) loc)))
                      ((Pair _ (TVar _)) (Pair expr (unify ck expected (::type expr) loc)))
                      ((Pair (TCon "Any" (Nil)) _)
                       (convert-value ck expr expected row loc))
                      ((Pair _ (TCon "Any" (Nil)))
                       (convert-value ck expr expected row loc))
                      ((Pair (TCon "fn" (Cons arrow (Nil))) _)
                       (fit-code-pointer ck expected arrow expr loc))
                      ((Pair (TFun _ _ _) (TCon "fn" _))
                       (compile-error loc
                                      "a fn is not a closure; wrap it in a lambda, as (lambda (x) (f x))"))
                      (_ (Pair expr (unify ck expected (::type expr) loc))))))))

    (: fit-code-pointer (impl (Fn Checker Type Type Expr Loc -> (Pair Expr Checker) ! compile)))
    (define (fit-code-pointer ck expected arrow expr loc)
      (if (match (prune (solution ck) (::type expr)) ((TCon "fn" _) #t) (_ #f))
          (Pair expr (unify ck expected (::type expr) loc))
          (begin
            (unless (environment-free? ck expr)
              (compile-error loc
                             (string-append "only a fn or a top-level function has type "
                                            (type->string
                                             (resolve-type (solution ck) expected))
                                            "; a lambda, or a local bound to one, may capture")))
            (Pair (Expr (::term expr) expected (::loc expr))
                  (unify ck arrow (fn-arrow (::type expr)) loc)))))

    (: fit-callable-contract
       (impl (Fn Checker Type Expr Type Loc -> (Pair Expr Checker) ! compile)))
    (define (fit-callable-contract ck expected expr row loc)
      (match (Pair (callable-kind expected) (callable-arrow expected))
        ((Pair (Some kind) (Some arrow))
         (match (callable-evidence ck (Constraint (callable-class kind)
                                                  (list (::type expr) arrow))
                                   (::givens ck) loc)
           ((Some proved) (Pair expr (::second proved)))
           ((None) (compile-error loc "a callable implementation type must be known"))))
        (_ (panic "internal error: an impl contract has a callable signature"))))

    (: erase-callable (impl (Fn Checker Type Expr Type Loc -> (Pair Expr Checker) ! compile)))
    (define (erase-callable ck expected expr row loc)
      (match (Pair (callable-kind expected) (callable-arrow expected))
        ((Pair (Some kind) (Some arrow))
         (let ((ck (improve-callable ck (Constraint (callable-class kind)
                                                    (list (::type expr) arrow))
                                     (::givens ck) loc)))
           (when (and (string=? kind "Fn") (linear? ck (::type expr)))
             (compile-error loc
                            "dyn Fn storage requires Copy captures; keep the concrete impl callable to retain owned captures"))
           (Pair (Expr (Ann expr expected) expected (::loc expr)) ck)))
        (_ (panic "internal error: callable erasure has a calling signature"))))

    ;; A numeric literal's variable is already constrained to a number.
    ;; Keep that constraint across an Any boundary: ordinary literal
    ;; defaulting (or a later use) chooses its concrete type, not Any.
    (: fit-any-literal (impl (Fn Checker Type Expr Type Type Loc -> (Pair Expr Checker) ! compile)))
    (define (fit-any-literal ck expected expr type row loc)
      (if (any? (lambda (want)
                  (match want
                    ((WantLiteral _ literal _)
                     (same-meta? (prune (solution ck) type) (prune (solution ck) literal)))
                    (_ #f)))
                (::pending ck))
          (convert-value ck expr expected row loc)
          (Pair expr (unify ck expected (::type expr) loc))))

    ;; Only an established Any boundary reaches here. An unconstrained
    ;; variable unified in fit; a literal's variable is known to be numeric,
    ;; so extracting it from Any is fallible before its width is chosen.
    (: convert-value (impl (Fn Checker Expr Type Type Loc -> (Pair Expr Checker) ! compile)))
    (define (convert-value ck value target row loc)
      ;; Reject known ineligible endpoints before a later host-row error
      ;; can hide the boundary. Final validation repeats this with solved
      ;; types; zonk here only closes unknowns for this negative check.
      (for-each (lambda (type)
                  (refuse-hidden-effects "type-convert" type loc)
                  (refuse-function-reference "type-convert" type loc))
                (list (zonk (solution ck) (::type value)) (zonk (solution ck) target)))
      (let ((ck (if (and (any-type? (prune (solution ck) (::type value)))
                         (not (any-type? (prune (solution ck) target))))
                    (require-conversion ck target row loc)
                    ck)))
        (Pair (Expr (Convert value target) target loc) ck)))

    (: require-conversion (impl (Fn Checker Type Type Loc -> Checker ! compile)))
    (define (require-conversion ck target row loc)
      (let ((flat (flatten-row (solution ck) row)))
        (unless (or (member? dyn-cast-label (::first flat)) (meta-tail? (::second flat)))
          (compile-error loc
                         (string-append "conversion from Any to "
                                        (type->string (resolve-type (solution ck) target))
                                        " requires dyn-cast; handle or declare dyn-cast, or use try-convert")))
        (perform ck (TRow (list dyn-cast-label) (None)) row loc)))

    (: environment-free? (impl (Fn Checker Expr -> Bool)))
    (define (environment-free? ck expr)
      (match (::term expr)
        ((Lambda _ _ captures?) (not captures?))
        ((Var name _ _)
         (match (program-value (program-of ck) name)
           ((Some (Defined _ _ function?)) function?)
           (_ #f)))
        (_ #f)))

    ;; A function's own name is visible in its body, with a monomorphic type.
    (: infer-let (impl (Fn Checker String Expr Expr Type Loc -> (Pair Expr Checker) ! compile)))
    (define (infer-let ck name value body row loc)
      (learning ck ((type (local-placeholder name value))
                    (value (infer-let-value name type value row))
                    (then (unify type (::type value) (::loc value)))
                    (body (scoped (bind-local ck name type) body row)))
                (Pair (Expr (Let name value body) (::type body) loc) ck)))

    ;; Reserve a lambda's identity before checking recursive references.
    ;; Captures are resolved in the outer scope, never including itself.
    (: local-placeholder (impl (Fn Checker String Expr -> (Pair Type Checker))))
    (define (local-placeholder ck name value)
      (match (::term value)
        ((Lambda params body _)
         (learning ck ((types (each (lambda (ck param) (fresh-meta ck)) params))
                       (result (fresh-meta)) (row (fresh-meta)))
                   (Pair (concrete-callable "Fn" name (TFun types result row)
                                            (capture-types ck params body)) ck)))
        (_ (fresh-meta ck))))

    ;; A `let`'s own name is visible in its value only when the value is a
    ;; lambda, so a recursive local function can call itself.
    (: infer-let-value (impl (Fn Checker String Type Expr Type -> (Pair Expr Checker) ! compile)))
    (define (infer-let-value ck name type value row)
      (if (lambda-expr? value)
          (within ck (bind-local ck name type)
                  (lambda (inner) (infer-local-lambda inner value type)))
          (infer ck value row)))

    (: infer-local-lambda (impl (Fn Checker Expr Type -> (Pair Expr Checker) ! compile)))
    (define (infer-local-lambda ck value type)
      (match (Pair (::term value) (fn-arrow type))
        ((Pair (Lambda params body captures?) (TFun types _ _))
         (learning ck ((value (infer-lambda-at params body captures? types (::loc value)))
                       (then (unify (fn-arrow type) (::type value) (::loc value))))
                   (Pair (Expr (::term value) type (::loc value)) ck)))
        (_ (panic "internal error: a local lambda has a reserved signature"))))

    ;; `expr` inferred under `inner`'s scope, resumed in this checker's.
    (: scoped (impl (Fn Checker Checker Expr Type -> (Pair Expr Checker) ! compile)))
    (define (scoped ck inner expr row)
      (within ck inner (lambda (scope) (infer scope expr row))))

    (: infer-match (impl (Fn Checker Expr (List Clause) Type Loc -> (Pair Expr Checker) ! compile)))
    (define (infer-match ck scrutinee clauses row loc)
      (learning ck ((result (fresh-meta)))
                (infer-match-at ck scrutinee clauses result row loc)))

    (: infer-match-at
       (impl (Fn Checker Expr (List Clause) Type Type Loc -> (Pair Expr Checker) ! compile)))
    (define (infer-match-at ck scrutinee clauses result row loc)
      (learning ck ((scrutinee (infer scrutinee row))
                    (clauses (each (lambda (ck clause)
                                     (infer-clause ck clause (::type scrutinee) result row))
                                   clauses)))
                (if (null? clauses)
                    (check-empty-match ck (::type scrutinee) loc)
                    (check-coverage ck (map ::pattern clauses) loc))
                (Pair (Expr (Match scrutinee clauses) result loc) ck)))

    ;; A match with no clauses is exhaustive only on a type with no cases,
    ;; which has no value to reach it with.
    (: check-empty-match (impl (Fn Checker Type Loc -> Unit ! compile)))
    (define (check-empty-match ck type loc)
      (unless (match (resolve-type (solution ck) type)
                ((TCon name _)
                 (match (table-ref (::types (program-of ck)) name)
                   ((Some data) (and (::enum? data) (null? (::cases data))))
                   ((None) #f)))
                (_ #f))
        (compile-error loc
                       "a match needs at least one clause, unless its value's type has no cases")))

    ;; One clause: its pattern binds for its body alone, and every body has
    ;; the match's result type.
    (: infer-clause (impl (Fn Checker Clause Type Type Type -> (Pair Clause Checker) ! compile)))
    (define (infer-clause ck clause scrutinee-type result row)
      (let ((body-loc (::loc (::body clause))))
        (learning ck ((checked (check-pattern (::pattern clause) scrutinee-type body-loc))
                      (body (within (::scope checked)
                                    (lambda (inner)
                                      (check-result inner (::body clause) result row)))))
                  (Pair (Clause (::pattern checked) body) ck))))

    ;; Implementations run in the handler's outer context. The body may
    ;; perform the handled effect plus whatever the context allows: its row
    ;; is `{effect | rest}`, and `rest` flows to the outer row. The handler's
    ;; result is the body's, which a control implementation also returns.
    ;;
    ;; `resume` performs the outer row, the handle's context, as Koka's
    ;; does, and not `rest`. Resuming points the handler's outside at the
    ;; handlers where `resume` is called, and the handler is deep, so the
    ;; rest of the body and each implementation it reaches again perform
    ;; there. The context is the row both flow into; their exact union would
    ;; need an inclusion that unification cannot state once a rigid tail is
    ;; involved. So a stored resumption names every effect of the code
    ;; around its handle, even one only that code performs.
    (: infer-handle
       (impl (Fn Checker
                 String
                 (List (Pair String Expr))
                 Expr
                 Type
                 Loc
                 ->
                 (Pair Expr Checker)
                 ! compile)))
    (define (infer-handle ck effect implementations body row loc)
      (let* ((info (program-effect (program-of ck) effect)) (operations (::operations info)))
        (unless (and (= (length operations) (length implementations))
                     (every? (lambda (operation)
                               (any? (lambda (entry) (string=? (::first entry) operation))
                                     implementations))
                             operations))
          (compile-error loc "a handler implements each operation of its effect exactly once"))
        (learning ck ((result (fresh-meta))
                      (rest (fresh-meta))
                      (implementations
                       (each (lambda (ck entry)
                               (infer-implementation ck
                                                     entry
                                                     (Answer (::control info) result)
                                                     row
                                                     loc))
                             implementations))
                      (body (infer body (TRow (list effect) (Some rest))))
                      (body (fit result body (TRow (list effect) (Some rest)) (::loc body)))
                      (then (perform rest row loc)))
                  (Pair (Expr (Handle effect implementations body) result loc) ck))))

    ;; What a control implementation is given and returns: `resume` takes the
    ;; operation's answer and runs the rest of the body, under the handler
    ;; again, to the handler's result.
    (struct Answer
      ((control (List String))
       (result Type)))

    ;; An implementation may perform its operation's latent row, which its
    ;; performer is charged; what else it performs, its context must allow.
    (: infer-implementation
       (impl (Fn Checker
                 (Pair String Expr)
                 Answer
                 Type
                 Loc
                 ->
                 (Pair (Pair String Expr) Checker)
                 ! compile)))
    (define (infer-implementation ck entry answer row loc)
      (match (program-value (program-of ck) (::first entry))
        ((Some (Operation effect scheme))
         (learning ck ((use (instantiate scheme loc)))
                   (match (::type use)
                     ((TFun params result _)
                      (learning ck ((rest (fresh-meta)))
                                (let ((expected
                                       (implementation-type (::first entry) answer params result
                                                            (latent-row
                                                             (operation-latent effect scheme)
                                                             rest)
                                                            row)))
                                  (learning ck ((value
                                                 (infer-implementation-value (::second entry)
                                                                             expected
                                                                             row))
                                                (value (fit expected value row (::loc value)))
                                                (then (perform rest row (::loc value))))
                                            (Pair (Pair (::first entry) value) ck)))))
                     (_ (panic "internal error: an operation is a function")))))
        (_ (panic "internal error: unknown operation"))))

    ;; The row an implementation may perform: the latent labels, open to
    ;; `rest`, or `rest` alone.
    (: latent-row (impl (Fn (List String) Type -> Type)))
    (define (latent-row labels rest)
      (if (null? labels) rest (TRow labels (Some rest))))

    ;; An implementation that is a lambda takes its parameter types from the
    ;; operation, so its body knows `resume` is one-shot when it calls it.
    (: infer-implementation-value
       (impl (Fn Checker Expr Type Type -> (Pair Expr Checker) ! compile)))
    (define (infer-implementation-value ck value expected row)
      (match (Pair (::term value) expected)
        ((Pair (Lambda params body captures?) (TFun types result _))
         (if (= (length params) (length types))
             (learning ck ((value (infer-lambda-at params body captures? types (::loc value))))
                       (fit-lambda-result ck value result))
             (infer ck value row)))
        (_ (infer ck value row))))

    ;; An implementation is checked at its operation's result without
    ;; changing the inferred row or adapting an already existing function.
    (: fit-lambda-result (impl (Fn Checker Expr Type -> (Pair Expr Checker) ! compile)))
    (define (fit-lambda-result ck value result)
      (match (Pair (::term value) (::type value))
        ((Pair (Lambda params body captures?) (TFun types _ row))
         (learning ck ((body (fit result body row (::loc body))))
                   (Pair
                    (Expr (Lambda params body captures?) (TFun types result row) (::loc value))
                    ck)))
        (_ (panic "internal error: fitting the result of a non-lambda"))))

    ;; An implementation returns the operation's answer to its caller. A
    ;; control operation's implementation returns the handler's result, and
    ;; is also handed `resume`, which it calls or drops exactly once, unless the
    ;; operation answers Never, when nothing could resume it. `resume`
    ;; performs `context`, the row of the code around the handle.
    (: implementation-type (impl (Fn String Answer (List Type) Type Type Type -> Type)))
    (define (implementation-type operation answer params result latent context)
      (cond ((not (member? operation (::control answer))) (TFun params result latent))
            ((never-type? result) (TFun params (::result answer) latent))
            (else (TFun (append params
                                (list (TCon "FnOnce"
                                            (list (TFun (list result)
                                                        (::result answer)
                                                        context)))))
                        (::result answer)
                        latent))))

    ;; ---- Patterns ----

    ;; The typed pattern, and the checker its body sees: extended by the
    ;; pattern's variables.
    ;; A checked pattern: the typed pattern, and the scope its body sees,
    ;; which is this checker extended by the pattern's variables. Checking a
    ;; pattern also learns, so it hands back a checker of its own as well.
    (struct Checked
      ((pattern Pattern)
       (scope Checker)))

    (: check-pattern (impl (Fn Checker Pattern Type Loc -> (Pair Checked Checker) ! compile)))
    (define (check-pattern ck pattern type loc)
      (match pattern
        ((PWild _) (Pair (Checked (PWild type) ck) ck))
        ((PVar name _) (Pair (Checked (PVar name type) (bind-local ck name type)) ck))
        ((PLit value _)
         (learning ck ((literal (literal-type value loc))
                       (then (unify type literal loc)))
                   (Pair (Checked (PLit value type) ck) ck)))
        ((PCon constructor args _)
         (match (program-value (program-of ck) constructor)
           ((Some (Constructor case scheme))
            (learning ck ((use (instantiate scheme loc)))
                      (match (::type use)
                        ((TFun fields result _)
                         (unless (= (length fields) (length args))
                           (compile-error loc
                                          (string-append (short-name constructor)
                                                         " has "
                                                         (i64->string (length fields))
                                                         " fields")))
                         (check-mutable-positions case args loc)
                         (let ((owned (borrow-target (prune (solution ck) type))))
                           (learning ck ((then (unify owned result loc))
                                         (checked (check-fields constructor
                                                                owned
                                                                args
                                                                (borrowed-fields ck type fields)
                                                                loc)))
                                     (Pair checked ck))))
                        (_ (panic "internal error: a constructor is a function")))))
           (_
            (compile-error loc (string-append "not a constructor: " (short-name constructor))))))))

    ;; A mutable field is read through its accessor, which performs `mut`,
    ;; so a pattern can only skip it.
    (: check-mutable-positions (impl (Fn Case (List Pattern) Loc -> Unit ! compile)))
    (define (check-mutable-positions case args loc)
      (for-each (lambda (pair)
                  (match (Pair (::mutable? (::first pair)) (::second pair))
                    ((Pair #f _) (unit))
                    ((Pair #t (PWild _)) (unit))
                    ((Pair #t _)
                     (compile-error loc
                                    (string-append "a pattern cannot read the mutable field "
                                                   (::name (::first pair))
                                                   "; write _ there and read it with "
                                                   (short-name (::name case))
                                                   "-"
                                                   (::name (::first pair)))))))
                (zip (::fields case) args)))

    ;; A constructor pattern on a borrow binds its fields as field reads
    ;; through a borrow do: a Copy field as an owned value, a linear field
    ;; as a borrow. The pattern's own type is the referent's, which names
    ;; the struct the emitter reads. Mutable positions are already wildcards.
    (: borrowed-fields (impl (Fn Checker Type (List Type) -> (List Type))))
    (define (borrowed-fields ck scrutinee fields)
      (if (borrow-type? (prune (solution ck) scrutinee))
          (map (lambda (field) (if (linear? ck field) (TCon "Borrow" (list field)) field)) fields)
          fields))

    ;; A constructor pattern's fields, checked in order into one scope:
    ;; names are unique, so the fields' locals simply join.
    (: check-fields
       (impl (Fn Checker
                 String
                 Type
                 (List Pattern)
                 (List Type)
                 Loc
                 ->
                 (Pair Checked Checker)
                 ! compile)))
    (define (check-fields ck constructor type args fields loc)
      (learning ck ((done (each (lambda (ck pair)
                                  (check-pattern ck (::first pair) (::second pair) loc))
                                (zip args fields))))
                (Pair (Checked (PCon constructor (map ::pattern done) type)
                               (fold-left
                                (lambda (scope field) (merged-locals scope (::scope field)))
                                ck
                                done))
                      ck)))

    ;; Every local a field pattern bound, added to the scope so far.
    (: merged-locals (impl (Fn Checker Checker -> Checker)))
    (define (merged-locals scope field)
      (Checker-locals-set scope (table-union (::locals scope) (::locals field))))

    ;; ---- Coverage ----

    ;; Maranget's usefulness test. A clause is redundant if it is not useful
    ;; after the clauses before it; a match is exhaustive if a wildcard is not
    ;; useful after all of them.
    (: check-coverage (impl (Fn Checker (List Pattern) Loc -> Unit ! compile)))
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

    (: head-of (impl (Fn Pattern -> (Option Head))))
    (define (head-of pattern)
      (match pattern
        ((PCon constructor args _) (Some (HCon constructor (length args))))
        ((PLit value _) (Some (HLit value)))
        (_ (None))))

    (: head=? (impl (Fn Head Head -> Bool)))
    (define (head=? a b)
      (match a
        ((HCon name _) (match b ((HCon other _) (string=? name other)) (_ #f)))
        ((HLit value) (match b ((HLit other) (datum=? value other)) (_ #f)))))

    (: head-arity (impl (Fn Head -> I64)))
    (define (head-arity head)
      (match head
        ((HCon _ arity) arity)
        ((HLit _) 0)))

    (: pattern-args (impl (Fn Pattern -> (List Pattern))))
    (define (pattern-args pattern)
      (match pattern
        ((PCon _ args _) args)
        (_ (Nil))))

    (: wildcards (impl (Fn I64 -> (List Pattern))))
    (define (wildcards count)
      (map (lambda (index) (PWild unchecked)) (iota count)))

    (: specialize (impl (Fn (List (List Pattern)) Head -> (List (List Pattern)))))
    (define (specialize rows head)
      (concatenate
       (map (lambda (row)
              (match row
                ((Cons first rest)
                 (match (head-of first)
                   ((None) (list (append (wildcards (head-arity head)) rest)))
                   ((Some other)
                    (if (head=? other head) (list (append (pattern-args first) rest)) (Nil)))))
                ((Nil) (Nil))))
            rows)))

    (: default-rows (impl (Fn (List (List Pattern)) -> (List (List Pattern)))))
    (define (default-rows rows)
      (concatenate
       (map (lambda (row)
              (match row
                ((Cons first rest) (match (head-of first) ((None) (list rest)) ((Some _) (Nil))))
                ((Nil) (Nil))))
            rows)))

    (: row-heads (impl (Fn (List (List Pattern)) -> (List Head))))
    (define (row-heads rows)
      (concatenate
       (map (lambda (row)
              (match row
                ((Cons first _) (match (head-of first) ((Some head) (list head)) ((None) (Nil))))
                ((Nil) (Nil))))
            rows)))

    (: useful? (impl (Fn Checker (List (List Pattern)) (List Pattern) -> Bool)))
    (define (useful? ck rows vector)
      (match vector
        ((Nil) (null? rows))
        ((Cons first rest)
         (match (head-of first)
           ((Some head) (useful? ck (specialize rows head) (append (pattern-args first) rest)))
           ((None)
            (match (complete-signature ck (delete-duplicates head=? (row-heads rows)))
              ((Some all)
               (any? (lambda (head)
                       (useful? ck
                                (specialize rows head)
                                (append (wildcards (head-arity head)) rest)))
                     all))
              ((None) (useful? ck (default-rows rows) rest))))))))

    ;; All heads of the matched type, if `seen` includes every one of them.
    (: complete-signature (impl (Fn Checker (List Head) -> (Option (List Head)))))
    (define (complete-signature ck seen)
      (let ((all (match seen
                   ((Cons (HLit (DBool _)) _) (list (HLit (DBool #t)) (HLit (DBool #f))))
                   ((Cons (HCon constructor _) _) (constructor-heads ck constructor))
                   (_ (Nil)))))
        (if (and (not (null? all))
                 (every? (lambda (head) (any? (lambda (other) (head=? head other)) seen)) all))
            (Some all)
            (None))))

    (: constructor-heads (impl (Fn Checker String -> (List Head))))
    (define (constructor-heads ck constructor)
      (match (program-value (program-of ck) constructor)
        ((Some (Constructor case _))
         (map (lambda (case) (HCon (::name case) (length (::fields case))))
              (::cases (program-type (program-of ck) (::type case)))))
        (_ (Nil))))

    ;; ---- Solving ----

    ;; Runs once, after every item is checked: literals whose type nothing
    ;; determined default to F64 or I64, every literal is range-checked, and
    ;; every class constraint is solved with the givens it arose under.
    ;; Field types and associated outputs are improved before and after
    ;; literal defaulting. A row class also charges the effects its inputs
    ;; determine: most are solved at their call (`solve-found-rows`), while
    ;; constraints whose inputs a later use decides wait until here.
    (: solve-pending (impl (Fn Checker -> Checker ! compile)))
    (define (solve-pending ck)
      (let ((pending (reverse (::pending ck))))
        (learning ck ((then (improve-types 0))
                      (then (default-literals pending #t))
                      (then (default-literals pending #f))
                      (then (improve-types 0)))
                  (for-each (lambda (want)
                              (match want
                                ((WantLiteral value type loc) (check-literal ck value type loc))
                                ((WantCopy type copy loc) (check-copy ck type copy loc))
                                (_ (unit))))
                            pending)
                  (fold-left (lambda (ck want)
                               (match want
                                 ((WantClass constraint hole givens copy sets loc)
                                  (resumed ck (solve-class (Checker-instances-set ck sets)
                                                           constraint hole givens copy loc)))
                                 (_ ck)))
                             ck pending))))

    (: default-literals (impl (Fn Checker (List Wanted) Bool -> Checker ! compile)))
    (define (default-literals ck pending float?)
      (fold-left (lambda (ck want) (default-literal ck want float?)) ck pending))

    (: default-literal (impl (Fn Checker Wanted Bool -> Checker ! compile)))
    (define (default-literal ck want float?)
      (match want
        ((WantLiteral value type loc)
         (if (and (float-literal? value float?) (meta? (prune (solution ck) type)))
             (unify ck (TCon (if float? "F64" "I64") (Nil)) type loc)
             ck))
        (_ ck)))

    (: float-literal? (impl (Fn Datum Bool -> Bool)))
    (define (float-literal? value float?)
      (match value
        ((DFloat _) float?)
        (_ (not float?))))

    (: check-literal (impl (Fn Checker Datum Type Loc -> Unit ! compile)))
    (define (check-literal ck value type loc)
      (match (prune (solution ck) type)
        ((TCon name (Nil))
         (unless (literal-fits? value name)
           (compile-error loc
                          (string-append "the literal "
                                         (datum->string value)
                                         " does not fit "
                                         name))))
        (other (compile-error loc
                              (string-append "a numeric literal cannot have type "
                                             (type->string other))))))

    (: literal-fits? (impl (Fn Datum String -> Bool)))
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

    (: solve-class
       (impl (Fn Checker Constraint I64 (List Constraint) (List String) Loc -> Checker ! compile)))
    (define (solve-class ck constraint hole givens copy loc)
      (cond ((determined-class? ck (::class constraint))
             (solve-found ck constraint hole givens copy (None) loc))
            ((string=? (::class constraint) unboxed-class)
             (solve-unboxed ck constraint hole givens loc))
            (else
             (match (find-evidence ck constraint givens copy loc)
               ((Some (Pair evidence ck)) (with-evidence ck hole evidence))
               ((None) (compile-error loc (unsolved-constraint ck constraint givens)))))))

    ;; `(Unboxed T)` holds when a value of T is one Wasm slot, which the
    ;; type's representation decides: a scalar, a reference, or a struct of
    ;; one unboxed field. It has no instances; a type variable needs the
    ;; requirement in scope. The evidence is derived, as a drop's is, and
    ;; nothing reads it.
    (: unboxed-class String)
    (define unboxed-class "snail.core.base:Unboxed")

    (: solve-unboxed (impl (Fn Checker Constraint I64 (List Constraint) Loc -> Checker ! compile)))
    (define (solve-unboxed ck constraint hole givens loc)
      (match (::types constraint)
        ((Cons type (Nil))
         (let ((type (resolve-type (solution ck) type)))
           (cond ((has-meta? (solution ck) type)
                  (compile-error loc (ambiguous-constraint ck constraint)))
                 ((unboxed? (program-of ck) type) (with-evidence ck hole (EvDerived (None))))
                 (else
                  (match (given-evidence unboxed-class (list type) givens)
                    ((Some evidence) (with-evidence ck hole evidence))
                    ((None)
                     (compile-error loc
                                    (string-append (type->string type)
                                                   " is not unboxed: an array element is one Wasm slot, so hold a struct of several fields as a struct of arrays"))))))))
        (_ (panic "internal error: Unboxed has one type"))))

    (: unboxed? (impl (Fn Program Type -> Bool)))
    (define (unboxed? program type)
      (if (concrete-callable? type) #t
          (match type
            ((TFun _ _ _) #t)
            ((TCon name args)
             (or (member? name
                          (list "U8"
                                "I32"
                                "I64"
                                "F32"
                                "F64"
                                "Bool"
                                "Char"
                                "Unit"
                                "String"
                                "Any"
                                "Funcref"
                                "Array" "Vector" "Ref" "FnOnce" "FnMut" "fn"))
                 (let ((data (program-type program name)))
                   (or (::enum? data)
                       (match (::cases data)
                         ((Cons case _)
                          (match (::fields case)
                            ((Cons field (Nil))
                             (unboxed? program
                                       (substitute (zip (::params data) args)
                                                   (::type field))))
                            (_ #f)))
                         ((Nil) #f))))))
            (_ #f))))

    ;; An unsolved field constraint whose record type is known names the
    ;; field the type lacks; any other unsolved constraint is ambiguous.
    (: unsolved-constraint (impl (Fn Checker Constraint (List Constraint) -> String)))
    (define (unsolved-constraint ck constraint givens)
      (let ((class (::class constraint)))
        (match (Pair (field-class? class) (::types constraint))
          ((Pair #t (Cons record _))
           (let ((record (resolve-type (solution ck) record)))
             (if (or (has-meta? (solution ck) record)
                     (match (field-type-of ck class record givens)
                       ((Some _) #t)
                       ((None) #f)))
                 (ambiguous-constraint ck constraint)
                 (missing-field ck class record))))
          (_ (ambiguous-constraint ck constraint)))))

    ;; The diagnostic for a field a record type lacks. A read through a
    ;; Borrow is rewritten to its referent's field only where the record is
    ;; already known to be a Borrow when the read is checked, so a read in
    ;; an unannotated lambda or named let needs an annotation.
    (: missing-field (impl (Fn Checker String Type -> String)))
    (define (missing-field ck class record)
      (let ((field (substring class 2 (string-length class))))
        (match (Pair (borrow-type? record) (field-type-of ck class (borrow-target record) (Nil)))
          ((Pair #t (Some _))
           (string-append "field "
                          field
                          " of "
                          (type->string record)
                          " was checked before the borrow's type was known; "
                          "annotate the parameter, or write ("
                          class
                          " (ann b "
                          (type->string record)
                          "))"))
          (_ (string-append (type->string record) " has no field " field)))))

    ;; Rows and associated outputs are determined arguments. The remaining
    ;; input arguments select evidence; that evidence establishes outputs
    ;; by equality and supplies the rows its methods perform.
    (: determined-class? (impl (Fn Checker String -> Bool)))
    (define (determined-class? ck class)
      (let ((class (program-class (program-of ck) class)))
        (not (null? (append (::rows class) (::outputs class))))))

    ;; A row class's constraint, solved in the row of the call it was raised
    ;; in when `context` gives one.
    (: solve-found
       (impl (Fn Checker
                 Constraint
                 I64
                 (List Constraint)
                 (List String)
                 (Option Type)
                 Loc
                 -> Checker
                 ! compile)))
    (define (solve-found ck constraint hole givens copy context loc)
      (match (found-evidence ck constraint givens copy context loc)
        ((Pair evidence ck) (with-evidence ck hole evidence))))

    (: found-evidence
       (impl (Fn Checker
                 Constraint
                 (List Constraint)
                 (List String)
                 (Option Type)
                 Loc
                 -> (Pair Evidence Checker)
                 ! compile)))
    (define (found-evidence ck constraint givens copy context loc)
      (if (lifecycle-class? (::class constraint))
          (lifecycle-evidence ck constraint givens copy context loc)
          (determined-evidence ck constraint givens copy context loc)))

    ;; A row class other than Drop and Clone is chosen as any class is, by
    ;; its types alone: the requirement given for them, or the one instance
    ;; whose head matches them. What that performs at each row parameter is
    ;; charged to the constraint's row there.
    (: determined-evidence
       (impl (Fn Checker
                 Constraint
                 (List Constraint)
                 (List String)
                 (Option Type)
                 Loc
                 -> (Pair Evidence Checker)
                 ! compile)))
    (define (determined-evidence ck constraint givens copy context loc)
      (let* ((class (program-class (program-of ck) (::class constraint)))
             (types (map (lambda (type) (resolve-type (solution ck) type))
                         (::types constraint))))
        (when (any? (lambda (type) (has-meta? (solution ck) type)) (type-arguments class types))
          (compile-error loc (ambiguous-constraint ck constraint)))
        (match (determined-source ck class types givens copy loc)
          ((Pair (Pair evidence performed) ck)
           (Pair evidence
                 (fold-left (lambda (ck charged)
                              (charge ck (::first charged) (::second charged) context loc))
                            ck
                            (zip performed (row-arguments class types))))))))

    ;; The evidence for a row class's types, and the row it performs at each
    ;; row parameter: a requirement given for them performs its own rows.
    (: determined-source
       (impl (Fn Checker
                 Class
                 (List Type)
                 (List Constraint)
                 (List String)
                 Loc
                 -> (Pair (Pair Evidence (List Type)) Checker)
                 ! compile)))
    (define (determined-source ck class types givens copy loc)
      (match (list-index (lambda (given) (given-for? class types given)) givens)
        ((Some index)
         (let ((given (::types (list-ref givens index))))
           (Pair (Pair (EvParam index) (row-arguments class given))
                 (unify-outputs ck class given types loc))))
        ((None) (determined-instance ck class types givens copy loc))))

    (: given-for? (impl (Fn Class (List Type) Constraint -> Bool)))
    (define (given-for? class types given)
      (and (string=? (::name class) (::class given))
           (types=? (type-arguments class types) (type-arguments class (::types given)))))

    ;; Inputs bind the instance's selecting variables. The remaining row
    ;; and output variables start fresh, and ordered prerequisites establish
    ;; them before the selected head constrains the caller's output slots.
    (: determined-instance
       (impl (Fn Checker
                 Class
                 (List Type)
                 (List Constraint)
                 (List String)
                 Loc
                 -> (Pair (Pair Evidence (List Type)) Checker)
                 ! compile)))
    (define (determined-instance ck class types givens copy loc)
      (match (matching-instance ck class types loc)
        ((Pair instance bindings)
         (let ((outer ck) (ck (enter-instance ck class types loc)))
           (learning ck ((determined (fresh-bindings
                                      (filter (lambda (var) (not (assoc-contains? bindings var)))
                                              (::vars instance))))
                         (evidence
                          (instance-application instance bindings determined givens copy loc)))
                     (let ((head (map (lambda (type) (substitute (append determined bindings) type))
                                      (::types instance))))
                       (Pair (Pair evidence (row-arguments class head))
                             (resumed outer (unify-outputs ck class head types loc)))))))))

    (: enter-instance (impl (Fn Checker Class (List Type) Loc -> Checker ! compile)))
    (define (enter-instance ck class types loc)
      (when (or (>= (length (::resolving ck)) 128)
                (any? (lambda (goal) (given-for? class types goal)) (::resolving ck)))
        (compile-error loc "instance requirements do not terminate"))
      (Checker-resolving-set ck
                             (Cons (Constraint (::name class) types) (::resolving ck))))

    (: assoc-contains? (impl (Fn Substitution String -> Bool)))
    (define (assoc-contains? bindings name)
      (match (assoc-ref bindings name)
        ((Some _) #t)
        ((None) #f)))

    (: unify-outputs (impl (Fn Checker Class (List Type) (List Type) Loc -> Checker ! compile)))
    (define (unify-outputs ck class established wanted loc)
      (fold-left (lambda (ck pair) (unify ck (::first pair) (::second pair) loc))
                 ck (zip (output-arguments class established) (output-arguments class wanted))))

    (: with-evidence (impl (Fn Checker I64 Evidence -> Checker)))
    (define (with-evidence ck hole evidence)
      (Checker-solution-set ck (Solution (::types (solution ck))
                                         (table-set (::evidence (solution ck))
                                                    (identity-key hole)
                                                    evidence))))

    (: ambiguous-constraint (impl (Fn Checker Constraint -> String)))
    (define (ambiguous-constraint ck constraint)
      (string-append "ambiguous constraint "
                     (constraint->string (::class constraint)
                                         (map (lambda (type) (resolve-type (solution ck) type))
                                              (::types constraint)))
                     "; add a signature or an annotation"))

    ;; A lifecycle class's row, as `(Drop e T)`'s, is found from T, not
    ;; matched: dropping or cloning a T runs what the type says
    ;; (`lifecycle-rows`), and each row that performs is performed in `e`.
    ;; Mono finds what runs again from the ground type, so the evidence only
    ;; records the plan charged. `context` is the row of the call the
    ;; constraint was raised in, when it is solved there.
    (: lifecycle-evidence
       (impl (Fn Checker
                 Constraint
                 (List Constraint)
                 (List String)
                 (Option Type)
                 Loc
                 -> (Pair Evidence Checker)
                 ! compile)))
    (define (lifecycle-evidence ck constraint givens copy context loc)
      (match (::types constraint)
        ((Cons row (Cons type (Nil)))
         (let ((type (resolve-type (solution ck) type))
               (class (::class constraint))
               (program (program-of ck)))
           (when (has-meta? (solution ck) type)
             (compile-error loc (ambiguous-constraint ck constraint)))
           (match (lifecycle-rows program class copy givens type)
             ((Ok rows)
              (Pair (EvDerived (checked-plan program class copy type))
                    (fold-left (lambda (ck performed) (charge ck performed row context loc))
                               ck
                               rows)))
             ((Err message) (compile-error loc message)))))
        (_ (panic "internal error: a lifecycle class has a row and a type"))))

    ;; A drop or a clone performs `performed` in its own row. When that row
    ;; has joined the call's context, as it has when the method is called
    ;; there or handed to a callee that calls it, the context performs it
    ;; too, which a signed body counts (`record-performed`); one only
    ;; stored, as in a struct, charges nothing here.
    (: charge (impl (Fn Checker Type Type (Option Type) Loc -> Checker ! compile)))
    (define (charge ck performed row context loc)
      (let ((ck (perform ck performed row loc)))
        (match context
          ((Some context)
           (if (same-tail? (::second (flatten-row (solution ck) row))
                           (::second (flatten-row (solution ck) context)))
               (record-performed ck
                                 context
                                 (let ((flat (flatten-row (solution ck) performed)))
                                   (append (::first flat) (tail-variable (::second flat)))))
               ck))
          ((None) ck))))

    ;; A row is charged where it is written: once a call is checked, each
    ;; constraint of a row class raised in it whose types are known by now
    ;; is solved in the call's scope, so a signed body is seen to perform
    ;; what its drops, clones and methods do. One whose types a later use
    ;; decides waits for `solve-pending`.
    (: solve-found-rows (impl (Fn Checker I64 Type -> Checker ! compile)))
    (define (solve-found-rows ck before context)
      (let* ((count (- (::pending-count ck) before))
             (recent (take (::pending ck) count))
             (older (list-drop (::pending ck) count)))
        (if (any? (lambda (want) (known-class-inputs? ck want)) recent)
            (match (fold-left (lambda (progress want) (solve-known-row progress want context))
                              (Pair (Nil) ck)
                              (reverse recent))
              ((Pair kept ck)
               (Checker-pending-count-set (Checker-pending-set ck (append kept older))
                                          (+ before (length kept)))))
            ck)))

    ;; One wanted constraint, oldest first: solved when it is a row class's
    ;; constraint of known types, and otherwise kept, newest first, as
    ;; `pending` keeps them.
    (: solve-known-row
       (impl
        (Fn (Pair (List Wanted) Checker) Wanted Type -> (Pair (List Wanted) Checker) ! compile)))
    (define (solve-known-row progress want context)
      (match progress
        ((Pair kept ck)
         (match want
           ((WantClass constraint hole givens copy sets loc)
            (if (known-class-inputs? ck want)
                (Pair kept (resumed ck (solve-found (Checker-instances-set ck sets)
                                                    constraint
                                                    hole
                                                    givens
                                                    copy
                                                    (Some context)
                                                    loc)))
                (Pair (Cons want kept) ck)))
           (_ (Pair (Cons want kept) ck))))))

    (: known-class-inputs? (impl (Fn Checker Wanted -> Bool)))
    (define (known-class-inputs? ck want)
      (match want
        ((WantClass constraint _ _ _ _ _)
         (let ((class (::class constraint)))
           (and (determined-class? ck class)
                (not (any? (lambda (type) (has-meta? (solution ck) type))
                           (type-arguments (program-class (program-of ck) class)
                                           (::types constraint)))))))
        (_ #f)))

    ;; A field constraint `(::f R T)` decides T from R: the one instance
    ;; whose record type matches R gives the field's type, or a given
    ;; constraint on the same R does. It runs where a call is checked, once
    ;; the arguments have given R, over the constraints raised since
    ;; `before`, and again over every constraint before solving, for an R a
    ;; later use decided. Associated outputs use the same improvement
    ;; loop, since one established output can determine another input.
    (: improve-types (impl (Fn Checker I64 -> Checker ! compile)))
    (define (improve-types ck before)
      (let ((wanted (reverse (take (::pending ck) (- (::pending-count ck) before)))))
        (let loop ((ck ck))
          (let ((next (fold-left improve-output ck wanted)))
            (if (types=? (improvement-types ck wanted) (improvement-types next wanted))
                next (loop next))))))

    (: improvement-types (impl (Fn Checker (List Wanted) -> (List Type))))
    (define (improvement-types ck wanted)
      (concatenate (map (lambda (want)
                          (match want
                            ((WantClass constraint _ _ _ _ _)
                             (map (lambda (type) (resolve-type (solution ck) type))
                                  (::types constraint)))
                            (_ (Nil)))) wanted)))

    (: improve-output (impl (Fn Checker Wanted -> Checker ! compile)))
    (define (improve-output ck want)
      (match want
        ((WantClass constraint _ givens copy sets loc)
         (if (callable-class? (::class constraint))
             (improve-callable ck constraint givens loc)
             (let ((class (program-class (program-of ck) (::class constraint))))
               (if (and (not (null? (::outputs class))) (known-class-inputs? ck want))
                   (resumed ck (::second (determined-source (Checker-instances-set ck sets) class
                                                            (map (lambda (type)
                                                                   (resolve-type (solution ck)
                                                                                 type))
                                                                 (::types constraint))
                                                            givens copy loc)))
                   (resumed ck (improve-field (Checker-instances-set ck sets) want))))))
        (_ ck)))

    (: improve-callable (impl (Fn Checker Constraint (List Constraint) Loc -> Checker ! compile)))
    (define (improve-callable ck requirement givens loc)
      (match (::types requirement)
        ((Cons receiver (Cons signature (Nil)))
         (match (callable-contract ck receiver givens)
           ((Some contract)
            (unless (callable-implies? (::first contract) (short-name (::class requirement)))
              (compile-error loc (string-append (::first contract) " does not satisfy "
                                                (short-name (::class requirement)))))
            (unify ck signature (::second contract) loc))
           ((None) ck)))
        (_ (panic "internal error: a callable requirement has a receiver and signature"))))

    (: improve-field (impl (Fn Checker Wanted -> Checker ! compile)))
    (define (improve-field ck want)
      (match want
        ((WantClass (Constraint class (Cons record (Cons field (Nil)))) _ givens _ _ loc)
         (if (field-class? class)
             (match (field-type-of ck class (resolve-type (solution ck) record) givens)
               ((Some type) (unify ck type field loc))
               ((None) ck))
             ck))
        (_ ck)))

    ;; The field's type for a record type: from the one instance whose
    ;; record type matches a constructor, or the one given whose record
    ;; type equals a variable. None while the record is unknown or
    ;; nothing decides it.
    (: field-type-of (impl (Fn Checker String Type (List Constraint) -> (Option Type))))
    (define (field-type-of ck class record givens)
      (match record
        ((TCon _ _)
         (one (concatenate (map (lambda (instance) (instance-field-type instance record))
                                (visible-instances (program-of ck) class (::instances ck))))))
        (_ (one (concatenate (map (lambda (given) (given-field-type ck class given record))
                                  givens))))))

    (: one (impl (Fn (List Type) -> (Option Type))))
    (define (one types)
      (match types
        ((Cons type (Nil)) (Some type))
        (_ (None))))

    (: instance-field-type (impl (Fn Instance Type -> (List Type))))
    (define (instance-field-type instance record)
      (match (::types instance)
        ((Cons head (Cons type (Nil)))
         (match (match-type (::vars instance) head record (Nil))
           ((Some bindings) (list (substitute bindings type)))
           ((None) (Nil))))
        (_ (Nil))))

    (: given-field-type (impl (Fn Checker String Constraint Type -> (List Type))))
    (define (given-field-type ck class given record)
      (match (::types given)
        ((Cons head (Cons type (Nil)))
         (if (and (string=? class (::class given))
                  (types=? (list (resolve-type (solution ck) head)) (list record)))
             (list type)
             (Nil)))
        (_ (Nil))))

    ;; Evidence from the enclosing definition's requirements, or from the
    ;; unique instance whose head matches. None while the types are ambiguous.
    (: find-evidence
       (impl (Fn Checker
                 Constraint
                 (List Constraint)
                 (List String)
                 Loc
                 -> (Option (Pair Evidence Checker))
                 ! compile)))
    (define (find-evidence ck constraint givens copy loc)
      (if (callable-class? (::class constraint))
          (callable-evidence ck constraint givens loc)
          (let ((types
                 (map (lambda (type) (resolve-type (solution ck) type)) (::types constraint))))
            (if (any? (lambda (type) (has-meta? (solution ck) type)) types)
                (None)
                (match (given-evidence (::class constraint) types givens)
                  ((Some evidence) (Some (Pair evidence ck)))
                  ((None)
                   (Some
                    (instance-evidence ck (::class constraint) types givens copy loc))))))))

    (: callable-evidence
       (impl (Fn Checker
                 Constraint
                 (List Constraint)
                 Loc
                 ->
                 (Option (Pair Evidence Checker))
                 ! compile)))
    (define (callable-evidence ck requirement givens loc)
      (let ((receiver (prune (solution ck) (list-ref (::types requirement) 0))))
        (match (callable-contract ck receiver givens)
          ((Some _)
           (Some (Pair (EvDerived (None)) (improve-callable ck requirement givens loc))))
          ((None)
           (if (meta? receiver) (None)
               (compile-error loc (string-append (type->string receiver) " does not satisfy "
                                                 (short-name (::class requirement)))))))))

    (: given-evidence (impl (Fn String (List Type) (List Constraint) -> (Option Evidence))))
    (define (given-evidence class types givens)
      (match (list-index (lambda (given)
                           (and (string=? class (::class given))
                                (types=? types (::types given))))
                         givens)
        ((Some index) (Some (EvParam index)))
        ((None) (None))))

    (: instance-evidence
       (impl (Fn Checker
                 String
                 (List Type)
                 (List Constraint)
                 (List String)
                 Loc
                 -> (Pair Evidence Checker)
                 ! compile)))
    (define (instance-evidence ck class types givens copy loc)
      (match (matching-instance ck (program-class (program-of ck) class) types loc)
        ((Pair instance bindings)
         (instance-application ck instance bindings (Nil) givens copy loc))))

    ;; The instance whose head matches a constraint's types, and what that
    ;; binds its variables to. Rows take no part: they are found from the
    ;; instance chosen, so no two instances of a class have the same types.
    (: matching-instance
       (impl (Fn Checker Class (List Type) Loc -> (Pair Instance Substitution) ! compile)))
    (define (matching-instance ck class types loc)
      (let loop ((instances
                  (visible-instances (program-of ck) (::name class) (::instances ck))))
        (match instances
          ((Nil)
           (compile-error loc
                          (match (Pair (field-class? (::name class)) types)
                            ((Pair #t (Cons record _)) (missing-field ck (::name class) record))
                            (_ (string-append "no instance for "
                                              (constraint->string (::name class) types))))))
          ((Cons instance rest)
           (match (match-types (::vars instance)
                               (type-arguments class (::types instance))
                               (type-arguments class types)
                               (Nil))
             ((Some bindings) (Pair instance bindings))
             ((None) (loop rest)))))))

    ;; An instance applied where its head matched with `bindings`: a
    ;; variable it requires Copy must be given an unrestricted type, and
    ;; each of its requirements is satisfied there in turn, with `rows`
    ;; giving the variables a row class's instance ends its rows with.
    (: instance-application
       (impl (Fn Checker
                 Instance
                 Substitution
                 Substitution
                 (List Constraint)
                 (List String)
                 Loc
                 -> (Pair Evidence Checker)
                 ! compile)))
    (define (instance-application ck instance bindings rows givens copy loc)
      (match (instance-copy-refusal (program-of ck) copy instance bindings)
        ((Some refusal) (compile-error loc refusal))
        ((None)
         (match (each ck
                      (lambda (ck requirement)
                        (requirement-evidence ck
                                              (substitute-constraint (append rows bindings)
                                                                     requirement)
                                              givens
                                              copy
                                              loc))
                      (::requires instance))
           ((Pair subs ck)
            (Pair (EvInstance (::name instance)
                              (applied-types instance (append rows bindings))
                              subs)
                  ck))))))

    ;; The types the head's match gave the instance's variables, in order.
    (: applied-types (impl (Fn Instance Substitution -> (List Type))))
    (define (applied-types instance bindings)
      (map (lambda (var)
             (match (assoc-ref bindings var)
               ((Some type) type)
               ((None) (TCon "Unit" (Nil)))))
           (::vars instance)))

    ;; A requirement of a row class, as `(Drop e A)` or `(Store e S)`, is
    ;; solved as its use is: what the type it gives `A` performs is charged
    ;; to its row `e`. Any other is found as a constraint is.
    (: requirement-evidence
       (impl (Fn Checker
                 Constraint
                 (List Constraint)
                 (List String)
                 Loc
                 -> (Pair Evidence Checker)
                 ! compile)))
    (define (requirement-evidence ck requirement givens copy loc)
      (if (determined-class? ck (::class requirement))
          (found-evidence ck requirement givens copy (None) loc)
          (match (find-evidence ck requirement givens copy loc)
            ((Some found) found)
            ((None) (compile-error loc (ambiguous-requirement requirement))))))

    (: ambiguous-requirement (impl (Fn Constraint -> String)))
    (define (ambiguous-requirement requirement)
      (string-append "ambiguous requirement "
                     (constraint->string (::class requirement)
                                         (::types requirement))))

    (: constraint->string (impl (Fn String (List Type) -> String)))
    (define (constraint->string class types)
      (if (field-class? class)
          (string-append "(" class " " (string-join (map type->string types) " ") ")")
          (type->string (TCon class types))))

    (: has-meta? (impl (Fn Solution Type -> Bool)))
    (define (has-meta? solution type)
      (match (prune solution type)
        ((TVar _) #t)
        ((TCon _ args) (any? (lambda (arg) (has-meta? solution arg)) args))
        ((TFun params result _)
         (or (any? (lambda (param) (has-meta? solution param)) params) (has-meta? solution result)))
        (_ #f)))

    ;; ---- Zonking ----

    ;; Replaces solved metavariables and keeps unsolved ones.
    (: resolve-type (impl (Fn Solution Type -> Type)))
    (define (resolve-type solution type)
      (let ((type (prune solution type)))
        (match type
          ((TCon name args) (TCon name (map (lambda (arg) (resolve-type solution arg)) args)))
          ((TFun params result row)
           (TFun (map (lambda (param) (resolve-type solution param)) params)
                 (resolve-type solution result) (resolve-type solution row)))
          ((TRow _ _)
           (let ((flat (flatten-row solution type))) (TRow (::first flat) (::second flat))))
          (_ type))))

    ;; Replaces solved metavariables. An unsolved type defaults to Unit and an
    ;; unsolved row tail closes; nothing observable depends on either.
    (: zonk (impl (Fn Solution Type -> Type)))
    (define (zonk solution type)
      (let ((type (prune solution type)))
        (match type
          ((TVar _) (TCon "Unit" (Nil)))
          ((TCon name args) (TCon name (map (lambda (arg) (zonk solution arg)) args)))
          ((TFun params result row)
           (TFun (map (lambda (param) (zonk solution param)) params)
                 (zonk solution result)
                 (zonk-row solution row)))
          ((TRow _ _) (zonk-row solution type))
          (_ type))))

    (: zonk-row (impl (Fn Solution Type -> Type)))
    (define (zonk-row solution row)
      (let ((flat (flatten-row solution row)))
        (TRow (::first flat) (if (meta-tail? (::second flat)) (None) (::second flat)))))

    (: zonk-evidence (impl (Fn Solution Evidence -> Evidence)))
    (define (zonk-evidence solution evidence)
      (match evidence
        ((EvHole hole)
         (match (solved-evidence solution hole)
           ((Some solved) (zonk-evidence solution solved))
           ((None) (panic "internal error: unsolved evidence"))))
        ((EvInstance instance types subs)
         (EvInstance instance (map (lambda (type) (zonk solution type)) types)
                     (map (lambda (sub) (zonk-evidence solution sub)) subs)))
        (_ evidence)))

    (: zonk-expr (impl (Fn Solution Expr -> Expr)))
    (define (zonk-expr solution expr)
      (Expr (match (::term expr)
              ((Lit value) (Lit value))
              ((Var name types evidence)
               (Var name
                    (map (lambda (type) (zonk solution type)) types)
                    (map (lambda (e) (zonk-evidence solution e)) evidence)))
              ((Lambda params body captures?) (Lambda params (zonk-expr solution body) captures?))
              ((App callee args)
               (App (zonk-expr solution callee) (map (lambda (arg) (zonk-expr solution arg)) args)))
              ((If test then otherwise)
               (If (zonk-expr solution test)
                   (zonk-expr solution then)
                   (zonk-expr solution otherwise)))
              ((Let name value body)
               (Let name (zonk-expr solution value) (zonk-expr solution body)))
              ((Seq first rest) (Seq (zonk-expr solution first) (zonk-expr solution rest)))
              ((Match scrutinee clauses)
               (Match (zonk-expr solution scrutinee)
                      (map (lambda (clause) (Clause (zonk-pattern solution (::pattern clause))
                                                    (zonk-expr solution (::body clause))))
                           clauses)))
              ((ScopedInstances _ _) (panic "internal error: instance scope survived checking"))
              ((Ann inner type) (Ann (zonk-expr solution inner) (zonk solution type)))
              ((Convert inner target) (Convert (zonk-expr solution inner) (zonk solution target)))
              ((TryConvert inner target)
               (TryConvert (zonk-expr solution inner) (zonk solution target)))
              ((TypeTest inner target) (TypeTest (zonk-expr solution inner) (zonk solution target)))
              ((Handle effect implementations body)
               (Handle effect
                       (map (lambda (entry)
                              (Pair (::first entry) (zonk-expr solution (::second entry))))
                            implementations)
                       (zonk-expr solution body))))
            (zonk solution (::type expr)) (::loc expr)))

    (: zonk-pattern (impl (Fn Solution Pattern -> Pattern)))
    (define (zonk-pattern solution pattern)
      (match pattern
        ((PWild type) (PWild (zonk solution type)))
        ((PVar name type) (PVar name (zonk solution type)))
        ((PLit value type) (PLit value (zonk solution type)))
        ((PCon constructor args type)
         (PCon constructor
               (map (lambda (arg) (zonk-pattern solution arg)) args)
               (zonk solution type)))))

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
    (: check-confined (impl (Fn Typed Expr -> Unit ! compile)))
    (define (check-confined typed function)
      (match (Pair (::term function) (fn-arrow (::type function)))
        ((Pair (Lambda params _ _) (TFun param-types result _))
         (let ((program (::program typed)))
           (for-each (lambda (pair)
                       (when (holds-storage? program (::second pair))
                         (confinement-error function
                                            (string-append "its parameter "
                                                           (local-name (::first pair))
                                                           ", a "
                                                           (type->string (::second pair)) ","))))
                     (zip params param-types))
           (when (holds-storage? program result)
             (confinement-error function
                                (string-append "its result, a " (type->string result) ",")))
           (for-each (lambda (read) (check-outside-read typed read)) (outside-reads function))))
        (_ (unit))))

    (: confinement-error (impl (Fn Expr String -> Unit ! compile)))
    (define (confinement-error function culprit)
      (compile-error (::loc function)
                     (string-append
                      "this function's type does not allow mut, so it may mutate only storage it allocates, but "
                      culprit " could hold storage from outside")))

    ;; A local of an enclosing definition is judged by its type; a global by
    ;; its declared or inferred type, since instantiating a row variable can
    ;; only bring in effects the function itself performs.
    (: check-outside-read (impl (Fn Typed Expr -> Unit ! compile)))
    (define (check-outside-read typed read)
      (match (::term read)
        ((Var name _ _)
         (when (reaches-storage? typed name (::type read))
           (compile-error (::loc read)
                          (string-append
                           "this function's type does not allow mut, so it may mutate only storage it allocates, but "
                           (short-name name) " could hold storage from outside"))))
        (_ (unit))))

    (: reaches-storage? (impl (Fn Typed String Type -> Bool)))
    (define (reaches-storage? typed name type)
      (let ((program (::program typed)))
        (match (program-value program name)
          ((Some (Primitive _)) #f)
          ((Some (Constructor _ _)) #f)
          ((Some (Accessor _ _ _)) #f)
          ((Some (Replacer _ _ _)) #f)
          ((Some (Setter _ _ _)) #f)
          ((Some (Swapper _ _ _)) #f)
          ((Some value)
           (and (not (primitive-alias? typed name))
                (holds-storage? program (global-type typed name value))))
          ((None) (holds-storage? program type)))))

    ;; A definition that is another name for a primitive, as the array
    ;; operations in (snail core base) are, acts only on its arguments too.
    ;; The program's items hold every library's definitions, so the alias
    ;; is found from any library that reads it.
    (: primitive-alias? (impl (Fn Typed String -> Bool)))
    (define (primitive-alias? typed name)
      (let ((program (::program typed)))
        (any? (lambda (item)
                (match item
                  ((Define defined value)
                   (and (string=? defined name)
                        (match (::term value)
                          ((Var target _ _)
                           (match (program-value program target)
                             ((Some (Primitive _)) #t)
                             (_ #f)))
                          (_ #f))))
                  (_ #f)))
              (program-items program))))

    (: global-type (impl (Fn Typed String Value -> Type)))
    (define (global-type typed name value)
      (match (table-ref (::schemes typed) name)
        ((Some scheme) (::type scheme))
        ((None)
         (match (value-scheme value)
           ((Some scheme) (::type scheme))
           ((None) (panic (string-append "internal error: no type for " name)))))))

    ;; Whether a value of the type can hold or reach mutable storage: an
    ;; `Array`, an `Any` that may hide one, data with a mutable field, a
    ;; `Ref` among them, or with a field of such a type, or a function that
    ;; may perform `mut`. Code cannot use a value of a type variable as
    ;; storage, so type variables hold none.
    (: holds-storage? (impl (Fn Program Type -> Bool)))
    (define (holds-storage? program type)
      (holds-storage-within? program type (Nil)))

    (: holds-storage-within? (impl (Fn Program Type (List String) -> Bool)))
    (define (holds-storage-within? program type visiting)
      (match type
        ((TCon name args)
         (or (member? name (list "Array" "Any"))
             (any? (lambda (arg) (holds-storage-within? program arg visiting)) args)
             (and (not (member? name visiting))
                  (fields-hold-storage? program name (Cons name visiting)))))
        ((TFun params result row)
         (or (row-mutates? row)
             (any? (lambda (part) (holds-storage-within? program part visiting))
                   (Cons result params))))
        (_ #f)))

    ;; A function that performs `host` may run anything the host
    ;; implements, mutation among it.
    (: row-mutates? (impl (Fn Type -> Bool)))
    (define (row-mutates? row)
      (match row
        ((TRow labels _) (or (member? "mut" labels) (member? "host" labels)))
        (_ #f)))

    ;; Builtin types other than `Array` and `Any` have no fields.
    (: fields-hold-storage? (impl (Fn Program String (List String) -> Bool)))
    (define (fields-hold-storage? program name visiting)
      (and (not (concrete-callable? (TCon name (Nil))))
           (not (any? (lambda (entry) (string=? (::first entry) name)) builtin-types))
           (any? (lambda (case)
                   (any?
                    (lambda (field)
                      (or (::mutable? field)
                          (holds-storage-within? program (::type field) visiting)))
                    (::fields case)))
                 (::cases (program-type program name)))))

    ;; The variable reads in `expr` of names it does not bind. Names are
    ;; unique, so a name bound anywhere inside is bound at all its reads.
    ;; Keep occurrences: handler captures need each read's method evidence.
    (: outside-reads (impl (Fn Expr -> (List Expr))))
    (define (outside-reads expr)
      (let ((bound (binders expr)))
        (filter (lambda (read)
                  (match (::term read)
                    ((Var name _ _) (not (member? name bound)))
                    (_ #f)))
                (variable-reads expr))))

    (: variable-reads (impl (Fn Expr -> (List Expr))))
    (define (variable-reads expr)
      (match (::term expr)
        ((Var _ _ _) (list expr))
        (_ (concatenate (map variable-reads (expr-children expr))))))

    (: binders (impl (Fn Expr -> (List String))))
    (define (binders expr)
      (append (match (::term expr)
                ((Lambda params _ _) params)
                ((Let name _ _) (list name))
                ((Match _ clauses)
                 (concatenate
                  (map (lambda (clause) (pattern-variables (::pattern clause))) clauses)))
                (_ (Nil)))
              (concatenate (map binders (expr-children expr)))))

    (: pattern-variables (impl (Fn Pattern -> (List String))))
    (define (pattern-variables pattern)
      (match pattern
        ((PVar name _) (list name))
        ((PCon _ args _) (concatenate (map pattern-variables args)))
        (_ (Nil))))

    ;; ---- Places ----

    ;; `set!` and `replace!` write a place: a cell's content, `(ref-get r)`,
    ;; or a chain of struct-field reads from one, which the backend stores
    ;; into the slots of the cell. Each link must be a struct's own field,
    ;; read by its accessor or by a path through the struct's instance: an
    ;; enum's case, a computed field and a field read through a requirement
    ;; have no slot to write. Items are checked once their types are final,
    ;; so a path's instance is known.
    (: check-places-item (impl (Fn Program Item -> Unit ! compile)))
    (define (check-places-item program item)
      (match item
        ((Define _ value) (check-places program value))
        ((Do value) (check-places program value))
        (_ (unit))))

    (: check-places (impl (Fn Program Expr -> Unit ! compile)))
    (define (check-places program expr)
      (match (::term expr)
        ((App callee (Cons place (Cons _ (Nil))))
         (match (::term callee)
           ((Var name _ _)
            (when (or (string=? name "prim:set!") (string=? name "prim:replace!"))
              (check-place-links program place)))
           (_ (unit))))
        (_ (unit)))
      (for-each (lambda (child) (check-places program child)) (expr-children expr)))

    ;; Links are followed inward to the first mutable field, whose record is
    ;; an ordinary expression.
    (: check-place-links (impl (Fn Program Expr -> Unit ! compile)))
    (define (check-place-links program place)
      (match (place-link program place)
        ((Ok (Pair field inner))
         (unless (::mutable? field) (check-place-links program inner)))
        ((Err problem) (compile-error (::loc place) problem))))

    (: place-link (impl (Fn Program Expr -> (Result (Pair Field Expr) String))))
    (define (place-link program expr)
      (match (::term expr)
        ((Ann inner _) (place-link program inner))
        ((App callee (Cons record (Nil)))
         (match (::term callee)
           ((Var name _ evidence)
            (match (link-field program name evidence)
              ((Ok field) (Ok (Pair field record)))
              ((Err problem) (Err problem))))
           (_ (Err not-a-place))))
        (_ (Err not-a-place))))

    (: not-a-place String)
    (define not-a-place
      "a place is a cell's content, (ref-get cell), or a chain of struct fields read from one")

    (: link-field (impl (Fn Program String (List Evidence) -> (Result Field String))))
    (define (link-field program name evidence)
      (match (program-value program name)
        ((Some (Accessor case index _)) (struct-field program case index))
        ((Some (Method class _))
         (if (field-class? class)
             (match evidence
               ((Cons (EvInstance instance _ _) _)
                (match (field-instance-accessor program class instance)
                  ((Some (Accessor case index _)) (struct-field program case index))
                  (_ (Err "cannot write a computed field: its instance has no slot to write"))))
               (_ (Err
                   "cannot write a field through a requirement: the record's type must be known")))
             (Err not-a-place)))
        (_ (Err not-a-place))))

    (: struct-field (impl (Fn Program Case I64 -> (Result Field String))))
    (define (struct-field program case index)
      (if (::enum? (program-type program (::type case)))
          (Err "cannot write through an enum's case; replace the whole enum")
          (Ok (list-ref (::fields case) index))))

    ;; ---- Closed functions ----

    ;; A closure that may not capture reads no local of the code around it:
    ;; only its parameters, the locals it binds, globals, and, when a `let`
    ;; binds it, its own name, which the backend reads from the closure
    ;; itself. Names are unique, so a read of a name it does not bind is a
    ;; read from outside, and one the program does not know is a local.
    (: check-closed-item (impl (Fn Program Item -> Unit ! compile)))
    (define (check-closed-item program item)
      (match item
        ((Define _ value) (check-closed program (Nil) value))
        ((Do value) (check-closed program (Nil) value))
        (_ (unit))))

    ;; `own` is the name a `let` binds the closure to, if it does.
    (: check-closed (impl (Fn Program (List String) Expr -> Unit ! compile)))
    (define (check-closed program own expr)
      (match (::term expr)
        ((Lambda _ _ captures?)
         (unless captures?
           (match (filter (lambda (read) (captured-read? program own read)) (outside-reads expr))
             ((Cons read _)
              (compile-error (::loc read)
                             (string-append "a fn has no environment, so it cannot read the local "
                                            (local-name (var-name read))
                                            "; use lambda")))
             ((Nil) (unit)))))
        (_ (unit)))
      (match (::term expr)
        ((Let name value body)
         (check-closed program (list name) value)
         (check-closed program (Nil) body))
        (_ (for-each (lambda (child) (check-closed program (Nil) child)) (expr-children expr)))))

    (: captured-read? (impl (Fn Program (List String) Expr -> Bool)))
    (define (captured-read? program own read)
      (let ((name (var-name read)))
        (and (not (member? name own))
             (match (program-value program name)
               ((Some _) #f)
               ((None) #t)))))

    (: var-name (impl (Fn Expr -> String)))
    (define (var-name read)
      (match (::term read)
        ((Var name _ _) name)
        (_ (panic "internal error: a read is a variable"))))

    ;; ---- Conversions ----

    ;; An Any's TypeId keys its type without rows, so converting a function
    ;; that performs effects would let a caller forget them: a call through
    ;; the converted function would be charged nothing, and never tested for
    ;; a yield. Once a library's types are final, and before specialization
    ;; erases ordinary effects, each conversion refuses such a type, so an
    ;; Any never holds a function with effects and the rows a TypeId leaves
    ;; out are empty.
    (: check-conversions (impl (Fn Item -> Unit ! compile)))
    (define (check-conversions item)
      (match item
        ((Define _ value) (check-expression-conversions value))
        ((Do value) (check-expression-conversions value))
        (_ (unit))))

    (: check-expression-conversions (impl (Fn Expr -> Unit ! compile)))
    (define (check-expression-conversions expr)
      (match (::term expr)
        ((Convert inner target)
         (refuse-hidden-effects "type-convert" (::type inner) (::loc expr))
         (refuse-hidden-effects "type-convert" target (::loc expr))
         (refuse-function-reference "type-convert" (::type inner) (::loc expr))
         (refuse-function-reference "type-convert" target (::loc expr))
         (check-through-any (::type inner) target (::loc expr)))
        ((TryConvert inner target)
         (refuse-hidden-effects "try-convert" target (::loc expr))
         (refuse-function-reference "try-convert" target (::loc expr))
         (check-through-any (::type inner) target (::loc expr)))
        ((TypeTest _ target)
         (check-boundary-type target (::loc expr))
         (refuse-hidden-effects "type-test" target (::loc expr))
         (refuse-function-reference "type-test" target (::loc expr)))
        (_ (unit)))
      (for-each check-expression-conversions (expr-children expr)))

    ;; A conversion changes nothing, or boxes into Any, or checks a value out
    ;; of it: there is no other representation change for it to make.
    (: check-through-any (impl (Fn Type Type Loc -> Unit ! compile)))
    (define (check-through-any source target loc)
      (check-boundary-type source loc)
      (check-boundary-type target loc)
      (unless (or (string=? (type-key source) (type-key target))
                  (any-type? source)
                  (any-type? target))
        (compile-error loc
                       (string-append "type-convert converts to or from Any, not from "
                                      (type->string source)
                                      " to "
                                      (type->string target)))))

    ;; An Any holds a reference to a GC object, and a fn's code reference
    ;; is not one, so neither side of a conversion is an Fn. Data holding
    ;; one is an object, and crosses.
    (: refuse-function-reference (impl (Fn String Type Loc -> Unit ! compile)))
    (define (refuse-function-reference form type loc)
      (match type
        ((TCon "fn" _)
         (compile-error loc
                        (string-append form
                                       " cannot take "
                                       (type->string type)
                                       ": an Any holds no function reference; wrap it in a lambda")))
        (_ (unit))))

    (: refuse-hidden-effects (impl (Fn String Type Loc -> Unit ! compile)))
    (define (refuse-hidden-effects form type loc)
      (match (hidden-effects type)
        ((Some part)
         (compile-error loc
                        (string-append "an Any does not record what a function performs, so "
                                       form
                                       " cannot take "
                                       (type->string type)
                                       (match part
                                         ((TRigid name)
                                          (string-append ", since " name " may stand for one"))
                                         (_ "")))))
        ((None) (unit))))

    ;; ---- Cleanup effects ----

    ;; Inference accounts for drops on exceptional edges before a function's
    ;; row closes. These are owned values, not just values read afterwards:
    ;; a Never branch can leave a resource it never mentions. Control later
    ;; materializes the same ownership edges as frame droppers.
    (: cleanup-scope
       (impl (Fn Checker (List (Pair String Type)) Expr Bool -> (List (Pair String Type)))))
    (define (cleanup-scope ck scope expr taken?)
      (let ((names (consumed-references (program-of ck) expr)))
        (filter (lambda (entry)
                  (if taken? (member? (::first entry) names)
                      (not (member? (::first entry) names)))) scope)))

    (: cleanup-row (impl (Fn Checker Expr -> Type)))
    (define (cleanup-row ck callee)
      (match (::term callee)
        ((Ann inner (TCon "$invoke" (Cons _ (Cons signature (Nil)))))
         (match (prune (solution ck) (::type inner))
           ((TRigid _) (cleanup-arrow-row ck signature))
           (_ (cleanup-row ck inner))))
        ((Ann inner _) (cleanup-row ck inner))
        ((Var name types evidence)
         (match (program-value (program-of ck) name)
           ((Some (Method class _))
            (if (lifecycle-class? class) empty-row
                (cleanup-arrow-row ck
                                   (cleanup-method-type ck
                                                        class
                                                        name
                                                        types
                                                        evidence
                                                        (::type callee)))))
           (_ (cleanup-arrow-row ck (cleanup-global-type ck name types (::type callee))))))
        (_ (cleanup-arrow-row ck (::type callee)))))

    (: cleanup-global-type (impl (Fn Checker String (List Type) Type -> Type)))
    (define (cleanup-global-type ck name types fallback)
      (match (global-scheme ck name)
        ((Some scheme) (substitute (zip (::vars scheme) types) (::type scheme)))
        ((None) fallback)))

    ;; A method use's row is opened to its context during checking. Its
    ;; selected instance's head supplies the declared rows instead. Every
    ;; implementation is checked against this contract, so there is no need
    ;; to look up its separate definition to recover the same information.
    (: cleanup-method-type
       (impl (Fn Checker String String (List Type) (List Evidence) Type -> Type)))
    (define (cleanup-method-type ck class name types evidence fallback)
      (cleanup-global-type ck name
                           (selected-method-arguments
                            (program-of ck) class types
                            (map (lambda (value) (cleanup-evidence ck value)) evidence))
                           fallback))

    (: cleanup-evidence (impl (Fn Checker Evidence -> Evidence)))
    (define (cleanup-evidence ck evidence)
      (match evidence
        ((EvHole id)
         (match (solved-evidence (solution ck) id)
           ((Some value) (cleanup-evidence ck value))
           ((None) evidence)))
        (_ evidence)))

    (: cleanup-arrow-row (impl (Fn Checker Type -> Type)))
    (define (cleanup-arrow-row ck type)
      (match (fn-arrow (resolve-type (solution ck) type))
        ((TFun _ _ row) row)
        (_ empty-row)))

    (: cleanup-control (impl (Fn Checker Type -> (List String))))
    (define (cleanup-control ck row)
      (let ((flat (flatten-row (solution ck) row)))
        (append (filter (lambda (label)
                          (match (table-ref (::effects (program-of ck)) label)
                            ((Some effect) (not (null? (::control effect))))
                            ((None) #f))) (::first flat))
                (match (::second flat) ((None) (Nil)) (_ (list "?control"))))))

    ;; Which yields escape an expression, without entering lambdas. Declared
    ;; global rows avoid mistaking a pure call's opened use row for an effect.
    (: cleanup-yields (impl (Fn Checker Expr -> (List String))))
    (define (cleanup-yields ck expr)
      (match (::term expr)
        ((Lambda _ _ _) (Nil))
        ((Convert inner target)
         (label-union (cleanup-yields ck inner)
                      (if (and (any-type? (resolve-type (solution ck) (::type inner)))
                               (not (any-type? (resolve-type (solution ck) target))))
                          (list dyn-cast-label) (Nil))))
        ((App callee args)
         (label-union (cleanup-control ck (cleanup-row ck callee))
                      (cleanup-yields-all ck (Cons callee args))))
        ((Handle effect implementations body)
         (label-union (label-difference (cleanup-yields ck body) (list effect))
                      (fold-left (lambda (effects entry)
                                   (let ((value (::second entry)))
                                     (label-union effects
                                                  (match (::term value)
                                                    ((Lambda _ body _) (cleanup-yields ck body))
                                                    (_ (cleanup-control ck
                                                                        (cleanup-row ck value)))))))
                                 (Nil) implementations)))
        (_ (cleanup-yields-all ck (expr-children expr)))))

    (: cleanup-yields-all (impl (Fn Checker (List Expr) -> (List String))))
    (define (cleanup-yields-all ck exprs)
      (fold-left (lambda (effects expr) (label-union effects (cleanup-yields ck expr)))
                 (Nil)
                 exprs))

    (: charge-cleanup
       (impl (Fn Checker (List (Pair String Type)) (List String) Type Loc -> Checker ! compile)))
    (define (charge-cleanup ck scope handled row loc)
      (fold-left (lambda (ck entry)
                   (let ((type (resolve-type (solution ck) (::second entry))))
                     (if (or (has-meta? (solution ck) type) (not (linear? ck type))) ck
                         (match (lifecycle-rows (program-of ck) drop-class
                                                (::copy ck) (::givens ck) type)
                           ((Ok rows)
                            (fold-left (lambda (ck drop-row)
                                         (let ((flat (flatten-row (solution ck) drop-row)))
                                           (perform ck
                                                    (TRow
                                                     (label-difference (::first flat) handled)
                                                     (::second flat)) row loc))) ck rows))
                           ((Err _) ck))))) ck scope))

    ;; Earlier operands remain owned while later operands run. They are
    ;; represented as temporary owners here; ANF gives them real names later.
    (: cleanup-operands
       (impl
        (Fn Checker (List (Pair String Type)) (List String) (List Expr) Type -> Checker ! compile)))
    (define (cleanup-operands ck scope handled exprs row)
      (match exprs
        ((Cons value rest)
         (let ((ck (infer-cleanup ck scope handled value row)))
           (cleanup-operands ck
                             (Cons (Pair "cleanup:operand" (::type value))
                                   (cleanup-scope ck scope value #f))
                             handled rest row)))
        ((Nil) ck)))

    (: cleanup-pattern (impl (Fn Pattern -> (List (Pair String Type)))))
    (define (cleanup-pattern pattern)
      (match pattern
        ((PVar name type) (list (Pair name type)))
        ((PCon _ args _) (concatenate (map cleanup-pattern args)))
        (_ (Nil))))

    (: infer-cleanup
       (impl (Fn Checker (List (Pair String Type)) (List String) Expr Type -> Checker ! compile)))
    (define (infer-cleanup ck scope handled expr row)
      (match (::term expr)
        ((Lambda _ _ _) ck)
        ((Let name value body)
         (let ((ck (infer-cleanup ck scope handled value row)))
           (infer-cleanup ck (Cons (Pair name (::type value)) (cleanup-scope ck scope value #f))
                          handled body row)))
        ((Seq first rest)
         (infer-cleanup (infer-cleanup ck scope handled first row)
                        (cleanup-scope ck scope first #f) handled rest row))
        ((If test then otherwise)
         (let* ((ck (infer-cleanup ck scope handled test row))
                (after (cleanup-scope ck scope test #f)))
           (infer-cleanup (infer-cleanup ck after handled then row) after handled otherwise row)))
        ((Match value clauses)
         (let* ((ck (infer-cleanup ck scope handled value row))
                (after (cleanup-scope ck scope value #f)))
           (fold-left (lambda (ck clause)
                        (infer-cleanup ck (append (cleanup-pattern (::pattern clause)) after)
                                       handled (::body clause) row)) ck clauses)))
        ((Handle effect implementations body)
         (let* ((ck (cleanup-operands ck scope handled (map ::second implementations) row))
                (ck (infer-cleanup ck
                                   (cleanup-scope ck scope body #t)
                                   (Cons effect handled)
                                   body
                                   row)))
           (if (null? (cleanup-yields ck expr)) ck
               (charge-cleanup ck (cleanup-scope ck scope expr #f) handled row (::loc expr)))))
        ((App callee args)
         (let ((ck (cleanup-operands ck scope handled (Cons callee args) row)))
           (if (null? (cleanup-control ck (cleanup-row ck callee))) ck
               (charge-cleanup ck (cleanup-scope ck scope expr #f) handled row (::loc expr)))))
        ((Convert inner _)
         (let ((ck (infer-cleanup ck scope handled inner row)))
           (if (null? (cleanup-yields ck expr)) ck
               (charge-cleanup ck (cleanup-scope ck scope inner #f) handled row (::loc expr)))))
        (_ (fold-left (lambda (ck child) (infer-cleanup ck scope handled child row))
                      ck (expr-children expr)))))

    (: cleanup-lambda (impl (Fn Checker (List String) (List Type) Expr Type -> Checker ! compile)))
    (define (cleanup-lambda ck params types body row)
      ;; A locally caught yield can still drop owners whose cleanup effects
      ;; escape the handler, so inspect the body even when no yield escapes.
      (let ((captured (concatenate
                       (map (lambda (name)
                              (match (table-ref (::locals ck) name)
                                ((Some type)
                                 (if (member? name params) (Nil) (list (Pair name type))))
                                ((None) (Nil))))
                            (expr-references body)))))
        (infer-cleanup ck (append (zip params types) captured) (Nil) body row)))

    ;; ---- Definitions ----

    ;; An unannotated group of mutually recursive definitions is inferred
    ;; together. A group of functions is generalized; any other group stays
    ;; monomorphic, so later uses can still decide its types.
    (: check-group
       (impl (Fn Checker (List Item) (List String) -> (Pair (List Item) Checker) ! compile)))
    (define (check-group ck definitions exposed)
      (let ((before (::pending-count ck)))
        (learning ck ((then (provisional-schemes definitions))
                      (results (each infer-definition definitions))
                      (then (host-effects results))
                      (then (generalize-group definitions before exposed)))
                  (Pair (map (lambda (pair)
                               (Define (Define-name (::first pair))
                                 (::first (::second pair))))
                             (zip definitions results))
                        (Checker-open-set ck
                                          (append (map Define-name definitions)
                                                  (::open ck)))))))

    ;; Each definition in the group starts with a monomorphic metavariable, so
    ;; the group's members can refer to one another while it is inferred.
    (: provisional-schemes (impl (Fn Checker (List Item) -> Checker)))
    (define (provisional-schemes ck definitions)
      (fold-left (lambda (ck definition)
                   (learning ck ((type (local-placeholder (Define-name definition)
                                                          (Define-value definition))))
                             (set-scheme ck (Define-name definition) (mono-scheme type))))
                 ck definitions))

    (: host-effects (impl (Fn Checker (List (Pair Expr Type)) -> Checker ! compile)))
    (define (host-effects ck results)
      (fold-left (lambda (ck result)
                   (check-host-effects ck (::second result) (::loc (::first result))))
                 ck results))

    ;; A group of functions is generalized over the constraints it raised;
    ;; any other group stays monomorphic, so later uses can still decide it.
    (: generalize-group (impl (Fn Checker (List Item) I64 (List String) -> Checker)))
    (define (generalize-group ck definitions before exposed)
      (if (every? (lambda (definition) (lambda-expr? (Define-value definition))) definitions)
          (generalize ck
                      definitions
                      (take (::pending ck) (- (::pending-count ck) before))
                      exposed)
          ck))

    ;; The checked value and the effect row of its initializer.
    (: infer-definition (impl (Fn Checker Item -> (Pair (Pair Expr Type) Checker) ! compile)))
    (define (infer-definition ck definition)
      (learning ck ((row (fresh-meta))
                    (value (infer-definition-value (Define-value definition)
                                                   (scheme-type ck (Define-name definition)) row))
                    (then (infer-cleanup (Nil) (Nil) value row))
                    (then (unify (scheme-type ck (Define-name definition))
                                 (::type value)
                                 (::loc value))))
                (Pair (Pair value row) ck)))

    (: infer-definition-value (impl (Fn Checker Expr Type Type -> (Pair Expr Checker) ! compile)))
    (define (infer-definition-value ck value type row)
      (if (lambda-expr? value)
          (infer-local-lambda ck value type)
          (infer ck value row)))

    (: scheme-type (impl (Fn Checker String -> Type)))
    (define (scheme-type ck name)
      (match (table-ref (::schemes ck) name)
        ((Some scheme) (::type scheme))
        ((None) (panic (string-append "internal error: no scheme for " name)))))

    ;; A metavariable becomes a quantified variable (`t1`, `t2`, ...) unless
    ;; something that outlives the group still mentions it: another
    ;; definition's type, or a constraint of this group.
    (: generalize (impl (Fn Checker (List Item) (List Wanted) (List String) -> Checker)))
    (define (generalize ck definitions wanted exposed)
      (let* ((fixed (map meta-id
                         (append (concatenate (map (lambda (name)
                                                     (free-metas (solution ck)
                                                                 (scheme-type ck name)))
                                                   (::open ck)))
                                 (append (concatenate
                                          (map (lambda (want) (wanted-metas (solution ck) want))
                                               wanted))
                                         (exposed-row-metas ck definitions exposed)))))
             (metas (filter (lambda (meta) (not (member? (meta-id meta) fixed)))
                            (delete-duplicates same-meta?
                                               (concatenate (map (lambda (d)
                                                                   (free-metas (solution ck)
                                                                               (scheme-type ck
                                                                                            (Define-name d))))
                                                                 definitions)))))
             (names (map (lambda (index) (string-append "t" (i64->string (+ index 1))))
                         (iota (length metas))))
             ;; Generalization binds a metavariable to a quantified name, like
             ;; any other solution; nothing distinguishes the two afterwards.
             (bound (fold-left (lambda (ck pair)
                                 (bind-solved ck (::first pair) (TRigid (::second pair))))
                               ck (zip metas names))))
        (fold-left (lambda (ck definition)
                     (let ((name (Define-name definition)))
                       (set-scheme ck
                                   name
                                   (Scheme names
                                           (Nil)
                                           (Nil)
                                           (resolve-type (solution ck) (scheme-type ck name))))))
                   bound definitions)))

    ;; A foreign caller supplies no row argument. Keep an inferred export's
    ;; row open for instance solving instead of quantifying that row. Its
    ;; ordinary type variables still generalize and are refused by expose.
    (: exposed-row-metas (impl (Fn Checker (List Item) (List String) -> (List Type))))
    (define (exposed-row-metas ck definitions exposed)
      (concatenate
       (map (lambda (definition)
              (if (member? (Define-name definition) exposed)
                  (match (fn-arrow
                          (resolve-type (solution ck) (scheme-type ck (Define-name definition))))
                    ((TFun _ _ row) (free-metas (solution ck) row))
                    (_ (Nil)))
                  (Nil))) definitions)))

    (: meta-id (impl (Fn Type -> I64)))
    (define (meta-id meta)
      (match meta
        ((TVar id) id)
        (_ -1)))

    ;; A type bound to a Copy variable. A variable of the enclosing
    ;; definition that it does not declare ω is linear, so the definition
    ;; must declare it; a concrete linear type cannot be bound at all.
    (: check-copy (impl (Fn Checker Type (List String) Loc -> Unit ! compile)))
    (define (check-copy ck type copy loc)
      (match (copy-refusal (program-of ck)
                           copy
                           (resolve-type (solution ck) type)
                           "a type variable requires an unrestricted type")
        ((Some refusal) (compile-error loc refusal))
        ((None) (unit))))

    (: wanted-metas (impl (Fn Solution Wanted -> (List Type))))
    (define (wanted-metas solution want)
      (match want
        ((WantClass constraint _ _ _ _ _)
         (concatenate
          (map (lambda (type) (free-metas solution type)) (::types constraint))))
        ((WantLiteral _ type _) (free-metas solution type))
        ((WantCopy _ _ _) (Nil))))

    (: free-metas (impl (Fn Solution Type -> (List Type))))
    (define (free-metas solution type)
      (let ((type (prune solution type)))
        (match type
          ((TVar _) (list type))
          ((TCon _ args) (concatenate (map (lambda (arg) (free-metas solution arg)) args)))
          ((TFun params result row)
           (append (concatenate (map (lambda (param) (free-metas solution param)) params))
                   (append (free-metas solution result) (free-metas solution row))))
          ((TRow _ (Some tail)) (free-metas solution tail))
          (_ (Nil)))))

    ;; A signature's variables are rigid and its constraints are given. A
    ;; function is checked against it directly, so a mismatch is reported
    ;; where it occurs.
    ;; `givens` is scope: the requirements hold while this definition is
    ;; checked and no longer, so the sub-check runs under its own checker.
    (: check-annotated (impl (Fn Checker Item Scheme -> (Pair Item Checker) ! compile)))
    (define (check-annotated ck definition scheme)
      (check-associated-givens (program-of ck) (::constraints scheme)
                               (::loc (Define-value definition)))
      (within ck
              (Checker-copy-set (Checker-givens-set ck
                                                    (if (null? (::vars scheme))
                                                        (Nil)
                                                        (::constraints scheme)))
                                (::copy scheme))
              (lambda (inner) (check-annotated-value inner definition scheme))))

    ;; A projection has one witness. Distinct rows or output equalities
    ;; cannot disambiguate two requirements with the same selecting inputs.
    (: check-associated-givens (impl (Fn Program (List Constraint) Loc -> Unit ! compile)))
    (define (check-associated-givens program givens loc)
      (match givens
        ((Nil) (unit))
        ((Cons given rest)
         (let ((class (program-class program (::class given))))
           (when (and (not (null? (::outputs class)))
                      (any? (lambda (other) (given-for? class (::types given) other))
                            rest))
             (compile-error loc "associated projection matches multiple requirements"))
           (check-associated-givens program rest loc)))))

    (: check-annotated-value (impl (Fn Checker Item Scheme -> (Pair Item Checker) ! compile)))
    (define (check-annotated-value ck definition scheme)
      ;; Monomorphic roots run without evidence parameters. Their closed
      ;; requirements must be proved, not assumed by their initializer.
      (learning ck ((then (want-closed-requirements scheme (::loc (Define-value definition))))
                    (row (fresh-meta))
                    (value (check-value (Define-value definition) (::type scheme) row))
                    (value (fit (::type scheme) value row (::loc value)))
                    (then (infer-cleanup (Nil) (Nil) value row))
                    (then (check-host-effects row (::loc value))))
                (when (and (not (null? (::vars scheme))) (not (total? (solution ck) row)))
                  (compile-error (::loc value)
                                 "a polymorphic definition must have a total initializer"))
                (check-performed ck definition scheme)
                (Pair (Define (Define-name definition) value) ck)))

    ;; A signature's row says what calling the function may do, so it may
    ;; not name an effect the body never performs. A lambda was checked by
    ;; `check-lambda`, so `performed` holds what its body performed. An
    ;; instance method has its class's row, which this instance may need
    ;; less of, and a value other than a lambda has no body of its own, so
    ;; neither is held to it. A default is: its `default` entry is its
    ;; signature (expand.sld's `snail-defaults`).
    (: check-performed (impl (Fn Checker Item Scheme -> Unit ! compile)))
    (define (check-performed ck definition scheme)
      (match (Pair (signature-loc (program-of ck) (Define-name definition))
                   (fn-arrow (::type scheme)))
        ((Pair (Some loc) (TFun _ _ row))
         (match (if (lambda-expr? (Define-value definition))
                    (unperformed-effects row (::performed ck))
                    (Nil))
           ((Nil) (unit))
           (effects (let ((label (definition-label (program-of ck) (Define-name definition))))
                      (compile-error loc (unperformed-message label effects))))))
        (_ (unit))))

    ;; How an error names a definition: a default by its operation, since
    ;; its global's name is generated.
    (: definition-label (impl (Fn Program String -> String)))
    (define (definition-label program name)
      (match (find (lambda (default) (string=? (::second default) name))
                   (concatenate (map ::defaults (table-values (::effects program)))))
        ((Some default) (string-append "the default of " (short-name (::first default))))
        ((None) (short-name name))))

    (: unperformed-message (impl (Fn String (List String) -> String)))
    (define (unperformed-message label effects)
      (let ((one (= (length effects) 1)))
        (string-append label
                       " declares the effect"
                       (if one "" "s")
                       (labels->string effects)
                       " but never performs " (if one "it" "them"))))

    (: want-closed-requirements (impl (Fn Checker Scheme Loc -> Checker)))
    (define (want-closed-requirements ck scheme loc)
      (if (null? (::vars scheme))
          (fold-left (lambda (ck constraint) (::second (want-class ck constraint loc)))
                     ck
                     (::constraints scheme))
          ck))

    ;; A program's body runs as its first task when it links the scheduler,
    ;; under the handler of every effect declared `around-main`, so the
    ;; body may perform those besides what the host implements.
    (: check-statement (impl (Fn Checker Expr -> (Pair Item Checker) ! compile)))
    (define (check-statement ck expr)
      (learning ck ((row (fresh-meta))
                    (value (infer expr row))
                    (then (infer-cleanup (Nil) (Nil) value row))
                    (then (check-body-effects row (::loc value))))
                (Pair (Do value) ck)))

    (: check-body-effects (impl (Fn Checker Type Loc -> Checker ! compile)))
    (define (check-body-effects ck row loc)
      (check-effects-with ck row loc (lambda (effect) (::around-main effect))))

    ;; The host may retain unrestricted values, holding managed references
    ;; opaquely. Linear ownership cannot cross this unrestricted boundary.
    ;; The trusted host respects Snail-Core types and implements the declared effects.
    ;; What is exposed is a definition's code: a foreign function, a
    ;; constructor or an operation has none.
    (: check-exposed (impl (Fn Checker String Bool Loc -> Checker ! compile)))
    (define (check-exposed ck name dynamic loc)
      (match (program-value (program-of ck) name)
        ((Some (Defined _ _ _)) (unit))
        (_ (compile-error loc "an exposed function must be defined")))
      (match (global-scheme ck name)
        ((Some (Scheme (Nil) (Nil) _ type))
         (check-exposed-type ck (resolve-type (solution ck) type) dynamic loc))
        (_ (compile-error loc "an exposed function must be a monomorphic function"))))

    ;; Inferred values may still name their solved metavariable here. Host
    ;; exports obey the same boundary whether their type was written or inferred.
    (: check-exposed-type (impl (Fn Checker Type Bool Loc -> Checker ! compile)))
    (define (check-exposed-type ck type dynamic loc)
      (check-boundary-type type loc)
      (match (fn-arrow type)
        ((TFun params result row)
         (when (any? (lambda (type) (linear? ck type)) (Cons result params))
           (compile-error loc "an exposed function cannot take or return a linear value"))
         (when dynamic (check-dynamic ck (Cons result params) row loc))
         (check-host-effects ck row loc))
        (_ (compile-error loc "an exposed function must be a monomorphic function"))))

    ;; A program that loads a dynamic export trusts nothing of it but its
    ;; signature, which names each type by its TypeId, so every parameter
    ;; and the result must be data that a TypeId describes. Effects are
    ;; erased before the backend writes the signature, so a program that
    ;; loads the function could not check them: a dynamic export is pure.
    (: check-dynamic (impl (Fn Checker (List Type) Type Loc -> Unit ! compile)))
    (define (check-dynamic ck types row loc)
      (unless (every?
               (lambda (type) (first-order-type? (program-of ck) (resolve-type (solution ck) type)))
               types)
        (compile-error loc
                       "a dynamic export takes and returns only data, with no function or Any inside"))
      (unless (null? (::first (flatten-row (solution ck) row)))
        (compile-error loc
                       "a dynamic export cannot perform effects: the program that loads it could not check them")))

    ;; Effects performed at program start need defaults for every
    ;; operation; the builtin effects are the host's own.
    (: check-host-effects (impl (Fn Checker Type Loc -> Checker ! compile)))
    (define (check-host-effects ck row loc)
      (check-effects-with ck row loc (lambda (effect) #f)))

    ;; The effects of `row` must each be the host's: builtin, with a default
    ;; for every operation, or `allowed` otherwise.
    (: check-effects-with
       (impl (Fn Checker Type Loc (dyn (Fn Effect -> Bool)) -> Checker ! compile)))
    (define (check-effects-with ck row loc allowed)
      (for-each (lambda (label)
                  (unless (or (member? label (list "mut" "host"))
                              (let ((effect (program-effect (program-of ck) label)))
                                (or (allowed effect)
                                    (= (length (::defaults effect))
                                       (length (::operations effect))))))
                    (compile-error loc
                                   (string-append "the effect "
                                                  (short-name label)
                                                  " has no host implementation here"))))
                (::first (flatten-row (solution ck) row)))
      ck)

    ;; ---- Programs ----

    ;; A program is checked a library at a time, in program order, so each
    ;; library's types are settled within it, as they must be when libraries
    ;; are compiled apart: an unannotated value takes its type from its own
    ;; library, never from a library that imports it.
    (: check-program (impl (Fn Program -> Typed ! compile)))
    (define (check-program program)
      (let loop ((libraries (library-items program (program-items program)))
                 (items (Nil))
                 (schemes empty-table))
        (match libraries
          ((Cons library rest)
           (let ((typed (check-library program schemes (::second library))))
             (loop rest (append items (::items typed)) (::schemes typed))))
          ((Nil) (Typed program items schemes)))))

    ;; One library's items, checked after the libraries before it: `schemes`
    ;; holds their definitions' schemes, and the result holds those and the
    ;; new ones. Unannotated definitions are checked first, in dependency
    ;; order; then annotated definitions and statements, which only need
    ;; schemes. Then every constraint is solved and every type zonked.
    (: check-library (impl (Fn Program (Table Scheme) (List Item) -> Typed ! compile)))
    (define (check-library program schemes items)
      (let ((ck (Checker program
                         empty-table
                         (Nil)
                         (Nil)
                         (Nil)
                         (Nil)
                         (None)
                         (None)
                         0
                         empty-solution
                         schemes
                         (Nil)
                         0
                         (Nil)
                         #f
                         (Nil)
                         (Nil))))
        (learning ck ((typed (check-items items))
                      (then (solve-pending))
                      (then (check-exposures items)))
                  (let ((result
                         (Typed program
                                (map (lambda (item) (zonk-item (solution ck) item)) typed)
                                (final-schemes ck items))))
                    (for-each check-conversions (::items result))
                    (let ((result
                           (Typed-items-set result (lower-conversions (::items result)))))
                      (check-final result
                                   (map (lambda (function) (zonk-expr (solution ck) function))
                                        (::confined ck)))
                      result)))))

    ;; The checks of a library whose types are final. Each item's, and each
    ;; confining function's, are its own, so the library fails with what
    ;; every one found, in source order.
    (: check-final (impl (Fn Typed (List Expr) -> Unit ! compile)))
    (define (check-final typed confined)
      (let ((program (::program typed)) (schemes (::schemes typed)))
        (check-owned-fields program)
        (fail-if-found
         (in-source-order
          (append (failures-of (lambda (item) (check-final-item program schemes item))
                               (::items typed))
                  (failures-of (lambda (function) (check-confined typed function)) confined))))))

    (: check-final-item (impl (Fn Program (Table Scheme) Item -> Unit ! compile)))
    (define (check-final-item program schemes item)
      (check-closed-item program item)
      (check-places-item program item)
      (check-item-ownership program schemes item))

    (: check-exposures (impl (Fn Checker (List Item) -> Checker ! compile)))
    (define (check-exposures ck items)
      (fold-left (lambda (ck item)
                   (match item
                     ((Expose name _ dynamic loc) (check-exposed ck name dynamic loc))
                     (_ ck)))
                 ck items))

    ;; Checks the definitions without signatures, a group at a time in
    ;; dependency order, then every item with the groups' results by name.
    ;; A group that fails defines names whose users go unchecked; a
    ;; definition with a signature fails nothing else, since its users
    ;; need only that. A library whose items failed stops with what each
    ;; one found, in source order, before its constraints are solved: a
    ;; constraint of an item that checked may mention a type a failed one
    ;; would have decided, and would report an ambiguity that fixing the
    ;; first error removes. So an instance error shows once the type errors
    ;; are gone.
    (: check-items (impl (Fn Checker (List Item) -> (Pair (List Item) Checker) ! compile)))
    (define (check-items ck items)
      (let* ((exposed (concatenate (map (lambda (item)
                                          (match item ((Expose name _ _ _) (list name)) (_ (Nil))))
                                        items)))
             (groups (each-recovered (Recovered ck (Nil) (Nil) (Nil))
                                     group-references
                                     (lambda (group) (map Define-name group))
                                     (lambda (ck group) (check-group ck group exposed))
                                     (unannotated-groups ck items)))
             (results (fold-left
                       (lambda (results result) (table-set results (Define-name result) result))
                       empty-table (concatenate (::values groups))))
             (checked (each-recovered (Recovered (::checker groups)
                                                 (Nil)
                                                 (::found groups)
                                                 (::failed groups))
                                      item-references
                                      (lambda (item) (Nil))
                                      (lambda (ck item) (check-item ck results item))
                                      items)))
        (fail-if-found (in-source-order (::found checked)))
        (Pair (::values checked) (::checker checked))))

    (: group-references (impl (Fn (List Item) -> (List String))))
    (define (group-references definitions)
      (concatenate (map (lambda (definition) (expr-references (Define-value definition)))
                        definitions)))

    ;; A definition refers to itself too, so one whose group failed is
    ;; not checked again.
    (: item-references (impl (Fn Item -> (List String))))
    (define (item-references item)
      (match item
        ((Define name value) (Cons name (expr-references value)))
        ((Do value) (expr-references value))
        ((Expose name _ _ _) (list name))))

    (: unannotated-groups (impl (Fn Checker (List Item) -> (List (List Item)))))
    (define (unannotated-groups ck items)
      (definition-groups
        (filter (lambda (item)
                  (match item
                    ((Define name _)
                     (match (annotated-scheme (program-of ck) name) ((None) #t) ((Some _) #f)))
                    (_ #f)))
                items)))

    (: check-item (impl (Fn Checker (Table Item) Item -> (Pair Item Checker) ! compile)))
    (define (check-item ck results item)
      (match item
        ((Define name _)
         (match (table-ref results name)
           ((Some result) (Pair result ck))
           ((None)
            (match (annotated-scheme (program-of ck) name)
              ((Some scheme) (check-annotated ck item scheme))
              ((None) (panic "internal error: unchecked definition"))))))
        ((Do expr) (check-statement ck expr))
        ((Expose _ _ _ _) (Pair item ck))))

    (: zonk-item (impl (Fn Solution Item -> Item)))
    (define (zonk-item solution item)
      (match item
        ((Define name value) (Define name (zonk-expr solution value)))
        ((Do value) (Do (zonk-expr solution value)))
        (_ item)))

    ;; Inferred schemes with their remaining metavariables defaulted, and the
    ;; signatures of annotated definitions.
    (: final-schemes (impl (Fn Checker (List Item) -> (Table Scheme))))
    (define (final-schemes ck items)
      (let ((defaulted (fold-left (lambda (ck name)
                                    (match (table-ref (::schemes ck) name)
                                      ((Some scheme)
                                       (set-scheme ck
                                                   name
                                                   (Scheme (::vars scheme)
                                                           (::constraints scheme)
                                                           (::copy scheme)
                                                           (zonk (solution ck)
                                                                 (::type scheme)))))
                                      ((None) ck)))
                                  ck (::open ck))))
        (::schemes
         (fold-left (lambda (ck item)
                      (match item
                        ((Define name _)
                         (match (annotated-scheme (program-of ck) name)
                           ((Some scheme) (set-scheme ck name scheme))
                           ((None) ck)))
                        (_ ck)))
                    defaulted items))))

    (: annotated-scheme (impl (Fn Program String -> (Option Scheme))))
    (define (annotated-scheme program name)
      (match (program-value program name)
        ((Some (Defined (Some scheme) _ _)) (Some (named-callable-scheme name scheme)))
        (_ (None))))

    (: named-callable-scheme (impl (Fn String Scheme -> Scheme)))
    (define (named-callable-scheme name scheme)
      (if (impl-callable? (::type scheme))
          (match (Pair (callable-kind (::type scheme)) (callable-arrow (::type scheme)))
            ((Pair (Some kind) (Some arrow))
             (Scheme (::vars scheme) (::constraints scheme) (::copy scheme)
                     (concrete-callable kind name arrow (Nil))))
            (_ scheme))
          scheme))

    ;; Where a definition's own signature was written, if it has one.
    (: signature-loc (impl (Fn Program String -> (Option Loc))))
    (define (signature-loc program name)
      (match (program-value program name)
        ((Some (Defined _ loc _)) loc)
        (_ (None))))

    ;; ---- Recovering ----

    ;; A library's items are checked past one that fails, so one compile
    ;; reports each independent error. A failed item's step is undone: the
    ;; checker goes on from where it was before the item, which threading
    ;; makes exact, and records what the item found and the names it
    ;; defines. An item that refers to one of those is not checked at all,
    ;; since without that definition's type its errors would only echo the
    ;; first, and the names it defines fail with it. The fold holds the
    ;; checker, the values of the items that checked, newest first, what
    ;; the failed ones found, and the names whose users go unchecked.
    (struct (Recovered B)
      ((checker Checker)
       (values (List B))
       (found (List SourceDiagnostic))
       (failed (List String))))

    ;; `step` over each item, as `each` does, past the items that fail.
    ;; `references` and `names` say what an item refers to and defines.
    (: each-recovered
       (All (A B) (requires (Copy A) (Copy B))
            (impl (Fn (Recovered B)
                      (dyn (Fn A -> (List String)))
                      (dyn (Fn A -> (List String)))
                      (dyn (Fn Checker A -> (Pair B Checker) ! compile))
                      (List A)
                      -> (Recovered B) ! compile))))
    (define (each-recovered start references names step items)
      (let ((done (fold-left (lambda (done item) (recover done references names step item))
                             start
                             items)))
        (Recovered-values-set done (reverse (::values done)))))

    (: recover
       (All (A B) (requires (Copy A) (Copy B))
            (impl (Fn (Recovered B)
                      (dyn (Fn A -> (List String)))
                      (dyn (Fn A -> (List String)))
                      (dyn (Fn Checker A -> (Pair B Checker) ! compile))
                      A
                      -> (Recovered B) ! compile))))
    (define (recover done references names step item)
      (let ((failed (::failed done)))
        (if (any? (lambda (name) (member? name failed)) (references item))
            (Recovered-failed-set done (append (names item) failed))
            (match (recovering (lambda () (step (::checker done) item)))
              ((Ok (Pair value ck))
               (Recovered ck (Cons value (::values done)) (::found done) failed))
              ((Err found)
               (Recovered-failed-set
                (Recovered-found-set done (append (::found done) (diagnostics->list found)))
                (append (names item) failed)))))))

    ;; ---- Dependency order ----

    ;; The definitions in groups that refer to one another, each group after
    ;; the groups it refers to. Definitions are numbered in program order.
    (: definition-groups (impl (Fn (List Item) -> (List (List Item)))))
    (define (definition-groups definitions)
      (let* ((nodes (list->vector definitions))
             (numbers (fold-left (lambda (table index)
                                   (table-set table (Define-name (vector-ref nodes index)) index))
                                 empty-table (iota (vector-length nodes)))))
        (map (lambda (component) (map (lambda (index) (vector-ref nodes index)) component))
             (strong-components
              (vector-map (lambda (definition) (definition-edges numbers definition)) nodes)))))

    ;; The numbers of the definitions `definition` refers to, in order of
    ;; first reference.
    (: definition-edges (impl (Fn (Table I64) Item -> (List I64))))
    (define (definition-edges numbers definition)
      (match definition
        ((Define _ value)
         (fold-right (lambda (name edges)
                       (match (table-ref numbers name)
                         ((Some index) (Cons index edges))
                         ((None) edges)))
                     (Nil) (expr-references value)))
        (_ (Nil))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-check)
    (import
     (snail stage0 testing))
    (begin
      ;; Which declared effects a body left unperformed, and how the error
      ;; names them. Whole programs exercise the rule and its exemptions in
      ;; tests/programs/error-unperformed-effect and declared-effects.
      (define (test-check)
        (expect (unperformed-effects (TRow (list "mut" "snail.core.io:console") (None))
                                     (list "snail.core.io:console"))
                (list "mut"))
        (expect (unperformed-effects (TRow (list "mut") (Some (TRigid "e"))) (list "mut"))
                (list "e"))
        (expect (unperformed-effects (TRow (list "mut") (Some (TRigid "e"))) (list "e" "mut"))
                (Nil))
        (expect (unperformed-message "double" (list "mut"))
                "double declares the effect mut but never performs it")
        (expect (unperformed-message "f" (list "snail.core.io:console" "e"))
                "f declares the effects console e but never performs them"))))
   (else)))

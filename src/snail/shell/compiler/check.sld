;; Hindley-Milner checking with effect rows and typeclass evidence. Each
;; expression is rebuilt with its type; each variable records the type
;; arguments and the evidence of its instantiation, so later passes never
;; repeat inference or instance selection.
(define-library (snail shell compiler check)
  (export
   Typed
   Typed-program
   Typed-items
   definition-scheme
   Typed-schemes
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
    (: resumed (-> Checker Checker Checker))
    (define (resumed outer inner)
      (Checker (Checker-program outer)
               (Checker-locals outer)
               (Checker-givens outer)
               (Checker-copy outer)
               (Checker-confining outer)
               (Checker-signed outer)
               (Checker-counter inner)
               (Checker-solution inner)
               (Checker-schemes inner)
               (Checker-pending inner)
               (Checker-pending-count inner)
               (Checker-open inner)
               (Checker-discharged inner)
               (Checker-confined inner)
               (Checker-performed inner)))

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
    (: identity-key (-> I64 String))
    (define (identity-key id)
      (i64->string id))

    (: solved-type (-> Solution I64 (Option Type)))
    (define (solved-type solution id)
      (table-ref (Solution-types solution) (identity-key id)))

    (: solved-evidence (-> Solution I64 (Option Evidence)))
    (define (solved-evidence solution id)
      (table-ref (Solution-evidence solution) (identity-key id)))

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

    (: definition-scheme (-> Typed String Scheme))
    (define (definition-scheme typed name)
      (match (table-ref (Typed-schemes typed) name)
        ((Some scheme) scheme)
        ((None) (panic (string-append "internal error: no scheme for " name)))))

    (: program-of (-> Checker Program))
    (define (program-of ck)
      (Checker-program ck))

    (: solution (-> Checker Solution))
    (define (solution ck)
      (Checker-solution ck))

    ;; A linear query reads a type's structure, so it needs the solution
    ;; applied first; a metavariable on its own is not known to be linear.
    (: linear? (-> Checker Type Bool))
    (define (linear? ck type)
      (linear-type? (program-of ck) (Checker-copy ck) (resolve-type (solution ck) type)))

    (: bind-solved (-> Checker Type Type Checker))
    (define (bind-solved ck meta type)
      (Checker-solution-set ck
                            (Solution (table-set (Solution-types (solution ck))
                                                 (identity-key (TVar-id meta))
                                                 type)
                                      (Solution-evidence (solution ck)))))

    (: fresh-identity (-> Checker (Pair I64 Checker)))
    (define (fresh-identity ck)
      (let ((id (+ (Checker-counter ck) 1)))
        (Pair id (Checker-counter-set ck id))))

    ;; ---- Metavariables and unification ----

    (: fresh-meta (-> Checker (Pair Type Checker)))
    (define (fresh-meta ck)
      (learning ck ((id (fresh-identity)))
                (Pair (TVar id) ck)))

    (: meta? (-> Type Bool))
    (define (meta? type)
      (match type
        ((TVar _) #t)
        (_ #f)))

    (: same-meta? (-> Type Type Bool))
    (define (same-meta? a b)
      (match a
        ((TVar id) (match b ((TVar other) (= id other)) (_ #f)))
        (_ #f)))

    ;; The type a metavariable stands for, following a chain of bindings.
    ;; `bind?` always binds a pruned type, so a chain is short.
    (: prune (-> Solution Type Type))
    (define (prune solution type)
      (match type
        ((TVar id)
         (match (solved-type solution id)
           ((Some bound) (prune solution bound))
           ((None) type)))
        (_ type)))

    (: unify (-> Checker Type Type Loc Checker ! compile))
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
    (: unify? (-> Checker Type Type (Pair Bool Checker)))
    (define (unify? ck a b)
      (let ((a (prune (solution ck) a)) (b (prune (solution ck) b)))
        (cond ((same-meta? a b) (Pair #t ck))
              ((meta? a) (bind? ck a b))
              ((meta? b) (bind? ck b a))
              (else (unify-structure? ck a b)))))

    (: unify-all? (-> Checker (List Type) (List Type) (Pair Bool Checker)))
    (define (unify-all? ck as bs)
      (if (= (length as) (length bs))
          (fold-left (lambda (done pair)
                       (if (Pair-first done)
                           (unify? (Pair-second done) (Pair-first pair) (Pair-second pair))
                           done))
                     (Pair #t ck) (zip as bs))
          (Pair #f ck)))

    (: unify-structure? (-> Checker Type Type (Pair Bool Checker)))
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
    (: unify-function? (-> Checker (List Type) Type Type (List Type) Type Type (Pair Bool Checker)))
    (define (unify-function? ck params result row others other-result other-row)
      (learning ck ((parameters (unify-all? params others)))
                (if (not parameters)
                    (Pair #f ck)
                    (learning ck ((results (unify? result other-result)))
                              (if (not results) (Pair #f ck) (unify-rows? ck row other-row))))))

    (: bind? (-> Checker Type Type (Pair Bool Checker)))
    (define (bind? ck meta type)
      (if (occurs? (solution ck) meta type)
          (Pair #f ck)
          (Pair #t (bind-solved ck meta type))))

    (: occurs? (-> Solution Type Type Bool))
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
    (: flatten-row (-> Solution Type (Pair (List String) (Option Type))))
    (define (flatten-row solution row)
      (let ((row (prune solution row)))
        (match row
          ((TRow labels (None)) (Pair labels (None)))
          ((TRow labels (Some tail))
           (let ((rest (flatten-row solution tail)))
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
    (: unify-rows? (-> Checker Type Type (Pair Bool Checker)))
    (define (unify-rows? ck a b)
      (let* ((left (flatten-row (solution ck) a)) (right (flatten-row (solution ck) b))
             (only-left (label-difference (Pair-first left) (Pair-first right)))
             (only-right (label-difference (Pair-first right) (Pair-first left)))
             (left-tail (Pair-second left)) (right-tail (Pair-second right)))
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

    (: tail-type (-> (Option Type) Type))
    (define (tail-type tail)
      (match tail
        ((Some type) type)
        ((None) (panic "internal error: closed row"))))

    ;; Calls require inclusion, not row equality: e fits console + e for every
    ;; substitution of e. A shared tail proves inclusion when its known labels
    ;; fit. Otherwise inference opens closed latent rows before unification.
    ;; In a confining body, `mut` is discharged before either check.
    (: perform (-> Checker Type Type Loc Checker ! compile))
    (define (perform ck latent row loc)
      (let ((flat (flatten-row (solution ck) latent)))
        (learning ck ((labels (performed-labels row (Pair-first flat)))
                      (then
                       (record-performed row (append labels (tail-variable (Pair-second flat))))))
                  (let ((context (flatten-row (solution ck) row)))
                    (if (and (same-tail? (Pair-second flat) (Pair-second context))
                             (null? (label-difference labels (Pair-first context))))
                        ck
                        (learning ck ((tail (row-tail (Pair-second flat)))
                                      (included (unify? (TRow labels (Some tail)) row)))
                                  (if included
                                      ck
                                      (compile-error loc
                                                     (string-append
                                                      "this performs effects its context does not allow:"
                                                      (labels->string
                                                       (append labels
                                                               (tail-variable
                                                                (Pair-second flat)))))))))))))

    ;; In a confining body `mut` is discharged before the row is compared.
    (: performed-labels (-> Checker Type (List String) (Pair (List String) Checker)))
    (define (performed-labels ck row labels)
      (if (confining-row? ck row) (discharge-mut ck labels) (Pair labels ck)))

    ;; A latent row's own tail, or a fresh one when it is closed.
    (: row-tail (-> Checker (Option Type) (Pair Type Checker)))
    (define (row-tail ck tail)
      (match tail
        ((Some tail) (Pair tail ck))
        ((None) (fresh-meta ck))))

    (: discharge-mut (-> Checker (List String) (Pair (List String) Checker)))
    (define (discharge-mut ck labels)
      (Pair (filter (lambda (label) (not (string=? label "mut"))) labels)
            (if (member? "mut" labels) (Checker-discharged-set ck #t) ck)))

    (: confining-row? (-> Checker Type Bool))
    (define (confining-row? ck row)
      (row-variable? (Checker-confining ck) row))

    ;; Whether `row` is the row variable that `variable` names, if any.
    (: row-variable? (-> (Option I64) Type Bool))
    (define (row-variable? variable row)
      (match (Pair variable row)
        ((Pair (Some number) (TVar id)) (= number id))
        (_ #f)))

    ;; A call in the signed body performs its labels, and its tail when that
    ;; is a quantified variable. A metavariable tail performs nothing of its
    ;; own: inclusion binds it to whatever the row has left over.
    (: record-performed (-> Checker Type (List String) Checker))
    (define (record-performed ck row effects)
      (if (row-variable? (Checker-signed ck) row)
          (Checker-performed-set ck (label-union (Checker-performed ck) effects))
          ck))

    (: tail-variable (-> (Option Type) (List String)))
    (define (tail-variable tail)
      (match tail
        ((Some (TRigid name)) (list name))
        (_ (Nil))))

    ;; The effects a declared row names that no call performed: its labels
    ;; and its tail variable, less those `performed` records.
    (: unperformed-effects (-> Type (List String) (List String)))
    (define (unperformed-effects declared performed)
      (let ((flat (flatten-row empty-solution declared)))
        (label-difference (append (Pair-first flat) (tail-variable (Pair-second flat))) performed)))

    (: total? (-> Solution Type Bool))
    (define (total? solution row)
      (null? (Pair-first (flatten-row solution row))))

    ;; ---- Instantiation ----

    (: want (-> Checker Wanted Checker))
    (define (want ck wanted)
      (Checker-pending-count-set (Checker-pending-set ck (Cons wanted (Checker-pending ck)))
                                 (+ (Checker-pending-count ck) 1)))

    (: want-class (-> Checker Constraint Loc (Pair Evidence Checker)))
    (define (want-class ck constraint loc)
      (learning ck ((hole (fresh-identity))
                    (then
                     (want (WantClass constraint hole (Checker-givens ck) (Checker-copy ck) loc))))
                (Pair (EvHole hole) ck)))

    ;; A use of a variable: its type, the types its quantified variables
    ;; took, and the evidence for its constraints.
    (struct Instantiated
      ((type Type)
       (types (List Type))
       (evidence (List Evidence))))

    ;; Fresh metavariables for the quantified variables, a hole for each
    ;; constraint, and a fresh tail on a closed outermost row.
    (: instantiate (-> Checker Scheme Loc (Pair Instantiated Checker)))
    (define (instantiate ck scheme loc)
      (learning ck ((metas (fresh-bindings (Scheme-vars scheme)))
                    (type (open-row (substitute metas (Scheme-type scheme))))
                    (evidence (each (lambda (ck constraint)
                                      (want-class ck (substitute-constraint metas constraint) loc))
                                    (Scheme-constraints scheme)))
                    (then (want-each (copy-requirements ck scheme metas loc))))
                (Pair (Instantiated type (map Pair-second metas) evidence) ck)))

    ;; The types a use binds to the variables its scheme declares ω must be
    ;; ω where it is: concrete types without a linear part, or variables the
    ;; enclosing definition declares ω in turn. The other variables may
    ;; take linear types.
    (: copy-requirements (-> Checker Scheme Substitution Loc (List Wanted)))
    (define (copy-requirements ck scheme metas loc)
      (map (lambda (meta) (WantCopy (Pair-second meta) (Checker-copy ck) loc))
           (filter (lambda (meta) (member? (Pair-first meta) (Scheme-copy scheme))) metas)))

    ;; A fresh metavariable per quantified variable, in order.
    (: fresh-bindings (-> Checker (List String) (Pair Substitution Checker)))
    (define (fresh-bindings ck vars)
      (each ck
            (lambda (ck var) (learning ck ((meta (fresh-meta))) (Pair (Pair var meta) ck)))
            vars))

    (: want-each (-> Checker (List Wanted) Checker))
    (define (want-each ck wanted)
      (fold-left want ck wanted))

    ;; `step` over each item in order, threading the checker and collecting
    ;; the values, so a sequence of learning steps is itself one step.
    (: each
       (All (A B e) (requires (Copy B))
            (-> Checker (-> Checker A (Pair B Checker) ! e) (List A) (Pair (List B) Checker) ! e)))
    (define (each ck step items)
      (let ((done (fold-left (lambda (done item)
                               (match (step (Pair-second done) item)
                                 ((Pair value ck) (Pair (Cons value (Pair-first done)) ck))))
                             (Pair (Nil) ck) items)))
        (Pair (reverse (Pair-first done)) (Pair-second done))))

    (: open-row (-> Checker Type (Pair Type Checker)))
    (define (open-row ck type)
      (match (prune (solution ck) type)
        ((TFun params result (TRow labels (None)))
         (learning ck ((tail (fresh-meta)))
                   (Pair (TFun params result (TRow labels (Some tail))) ck)))
        (_ (Pair type ck))))

    (: global-scheme (-> Checker String (Option Scheme)))
    (define (global-scheme ck name)
      (match (table-ref (Checker-schemes ck) name)
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
      (fold-left (lambda (ck pair) (bind-local ck (Pair-first pair) (Pair-second pair)))
                 ck
                 (zip names types)))

    (: set-scheme (-> Checker String Scheme Checker))
    (define (set-scheme ck name scheme)
      (Checker-schemes-set ck (table-set (Checker-schemes ck) name scheme)))

    (: variable-type (-> Checker String Loc (Pair Instantiated Checker) ! compile))
    (define (variable-type ck name loc)
      (match (table-ref (Checker-locals ck) name)
        ((Some local) (Pair (Instantiated local (Nil) (Nil)) ck))
        ((None)
         (match (global-scheme ck name)
           ((Some scheme) (instantiate ck scheme loc))
           ((None) (compile-error loc (string-append "internal error: no type for " name)))))))

    ;; ---- Expressions ----

    (: literal-type (-> Checker Datum Loc (Pair Type Checker)))
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
    (: infer (-> Checker Expr Type (Pair Expr Checker) ! compile))
    (define (infer ck expr row)
      (let ((loc (Expr-loc expr)))
        (match (Expr-term expr)
          ((Lit value)
           (learning ck ((type (literal-type value loc)))
                     (Pair (Expr (Lit value) type loc) ck)))
          ((Var name _ _)
           (learning ck ((use (variable-type name loc)))
                     (Pair (Expr (Var name (Instantiated-types use) (Instantiated-evidence use))
                                 (Instantiated-type use)
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
                         (test (fit (TCon "Bool" (Nil)) test row (Expr-loc test)))
                         (then (unify (Expr-type consequent)
                                      (Expr-type alternative)
                                      (Expr-loc alternative))))
                     (Pair (Expr (If test consequent alternative) (Expr-type consequent) loc) ck)))
          ((Let name value body) (infer-let ck name value body row loc))
          ((Seq first rest)
           (learning ck ((first (infer first row))
                         (rest (infer rest row)))
                     (Pair (Expr (Seq first rest) (Expr-type rest) loc) ck)))
          ((Match scrutinee clauses) (infer-match ck scrutinee clauses row loc))
          ((Ann inner type)
           (learning ck ((inner (infer inner row)))
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
                         (inner (fit (TCon "Any" (Nil)) inner row (Expr-loc inner))))
                     (Pair (Expr (TryConvert inner target) (cast-result-type target) loc) ck)))
          ;; Whether an Any holds a value of the target type.
          ((TypeTest inner target)
           (learning ck ((inner (infer inner row))
                         (inner (fit (TCon "Any" (Nil)) inner row (Expr-loc inner))))
                     (Pair (Expr (TypeTest inner target) (TCon "Bool" (Nil)) loc) ck))))))

    (: infer-lambda (-> Checker (List String) Expr Bool Loc (Pair Expr Checker) ! compile))
    (define (infer-lambda ck params body captures? loc)
      (learning ck ((types (each (lambda (ck param) (fresh-meta ck)) params)))
                (infer-lambda-at ck params body captures? types loc)))

    ;; A lambda whose parameter types are known before its body is seen.
    (: infer-lambda-at
       (-> Checker (List String) Expr Bool (List Type) Loc (Pair Expr Checker) ! compile))
    (define (infer-lambda-at ck params body captures? types loc)
      (learning ck ((body-row (fresh-meta))
                    (body (scoped (bind-locals ck params types) body body-row))
                    (then (cleanup-lambda params types body body-row)))
                (Pair
                 (Expr (Lambda params body captures?) (TFun types (Expr-type body) body-row) loc)
                 ck)))

    ;; A sub-check under `inner`'s scope, resumed in this checker's. `inner`
    ;; is built from this one, so everything it learns flows back; only its
    ;; scope is discarded.
    (: within
       (All (A e) (-> Checker Checker (-> Checker (Pair A Checker) ! e) (Pair A Checker) ! e)))
    (define (within ck inner check)
      (match (check inner)
        ((Pair value done) (Pair value (resumed ck done)))))

    ;; Checks an expression against a known type: a lambda's parameters and
    ;; body row come from the type; anything else is inferred. A body whose
    ;; row forbids `mut` may still mutate storage it allocates; the function
    ;; is confined once its types are final.
    (: check-value (-> Checker Expr Type Type (Pair Expr Checker) ! compile))
    (define (check-value ck expr type row)
      (match (Pair (Expr-term expr) (prune (solution ck) type))
        ((Pair (Lambda params body captures?) (TFun param-types result body-row))
         (if (= (length params) (length param-types))
             (check-lambda ck expr params body captures? type param-types result body-row)
             (infer ck expr row)))
        ;; A function at an Fn is checked at its arrow, then given the Fn.
        ((Pair _ (TCon "Fn" (Cons arrow (Nil))))
         (learning ck ((value (check-value expr arrow row)))
                   (fit ck type value row (Expr-loc value))))
        (_ (infer ck expr row))))

    ;; A lambda checked against its type. The body's row is a variable bound
    ;; to the type's row, so `perform` can recognize it: calls in this body,
    ;; but not in lambdas inside it, record in `performed` what they
    ;; perform. A body whose row forbids `mut` is checked as confining; if a
    ;; call in it did mutate, the function goes to `confined` and the flag
    ;; is cleared for the next one.
    (: check-lambda
       (-> Checker
           Expr
           (List String)
           Expr
           Bool
           Type
           (List Type)
           Type
           Type
           (Pair Expr Checker)
           ! compile))
    (define (check-lambda ck expr params body captures? type param-types result body-row)
      (learning ck ((row (fresh-meta))
                    (then (unify row body-row (Expr-loc expr)))
                    (body (within (signed-body (bind-locals ck params param-types) row)
                                  (lambda (inner)
                                    (match (if (forbids-mut? (solution inner) body-row)
                                               (check-confining-body inner body row)
                                               (infer inner body row))
                                      ((Pair body inner)
                                       (match (fit inner result body row (Expr-loc body))
                                         ((Pair body inner)
                                          (Pair body
                                                (cleanup-lambda inner
                                                                params
                                                                param-types
                                                                body
                                                                row))))))))))
                (let ((value (Expr (Lambda params body captures?) type (Expr-loc expr))))
                  (Pair value (if (Checker-discharged ck)
                                  (Checker-confined-set (Checker-discharged-set ck #f)
                                                        (Cons value (Checker-confined ck)))
                                  ck)))))

    ;; The scope of a body checked against its signature, whose row
    ;; variable is `row`: nothing is performed in it yet.
    (: signed-body (-> Checker Type Checker))
    (define (signed-body ck row)
      (Checker-performed-set (Checker-signed-set ck (Some (meta-number row))) (Nil)))

    ;; `perform` recognizes the body's row variable and lets calls in this
    ;; body, but not in lambdas inside it, mutate. `confining` is scope, so
    ;; the caller gets its own back.
    (: check-confining-body (-> Checker Expr Type (Pair Expr Checker) ! compile))
    (define (check-confining-body ck body row)
      (within ck (Checker-confining-set ck (Some (meta-number row)))
              (lambda (inner) (infer inner body row))))

    (: meta-number (-> Type I64))
    (define (meta-number meta)
      (match meta
        ((TVar id) id)
        (_ -1)))

    ;; A row forbids `mut` unless it lists it or is open to more labels.
    (: forbids-mut? (-> Solution Type Bool))
    (define (forbids-mut? solution row)
      (let ((flat (flatten-row solution row)))
        (not (or (member? "mut" (Pair-first flat)) (meta-tail? (Pair-second flat))))))

    (: infer-app (-> Checker Expr (List Expr) Type Loc (Pair Expr Checker) ! compile))
    (define (infer-app ck callee args row loc)
      (let ((before (Checker-pending-count ck)))
        (learning ck ((callee (infer callee row))
                      (args (each (lambda (ck arg) (infer ck arg row)) args))
                      (result (fresh-meta))
                      (latent (fresh-meta))
                      (args (unify-call (Expr-type callee) args result latent row loc))
                      (then (improve-fields before))
                      (then (perform latent row loc))
                      (then (solve-found-rows before row)))
                  (Pair (Expr (App callee args) result loc) ck))))

    ;; Arguments are compared one by one, so a mismatch names its argument,
    ;; and each meets its parameter's type (`fit`), which may give it the
    ;; type Fn.
    (: unify-call
       (-> Checker Type (List Expr) Type Type Type Loc (Pair (List Expr) Checker) ! compile))
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
                                          (Pair-first pair)
                                          (Pair-second pair)
                                          context
                                          (Expr-loc (Pair-second pair))))
                                   (zip params args)))
                       (then (unify callee-result result loc))
                       (then (unify row latent loc)))
                   (Pair args ck)))
        ((TVar _) (Pair args (unify ck callee-type (TFun (map Expr-type args) result latent) loc)))
        ;; Calling a `FnOnce` calls the procedure it holds; ownership consumes
        ;; it. Calling an `Fn` calls the code it is.
        ((TCon "FnOnce" (Cons procedure (Nil)))
         (unify-call ck procedure args result latent context loc))
        ((TCon "Fn" (Cons procedure (Nil)))
         (unify-call ck procedure args result latent context loc))
        (other (compile-error loc (string-append "not a function: " (type->string other))))))

    ;; Concrete arguments constrain shared type variables before an Any
    ;; can instantiate one. This changes inference order, never evaluation
    ;; order: `(f boxed 1)` and `(f 1 boxed)` both select f at I64 when its
    ;; two parameters share a type. With only Any arguments it selects Any.
    (: fit-known-arguments (-> Checker (List Type) (List Expr) Type Checker ! compile))
    (define (fit-known-arguments ck params args row)
      (fold-left (lambda (ck pair)
                   (let ((arg (Pair-second pair)))
                     (if (any-type? (prune (solution ck) (Expr-type arg)))
                         ck
                         (Pair-second (fit ck (Pair-first pair) arg row (Expr-loc arg))))))
                 ck (zip params args)))

    ;; A value meets the type it is checked at: a parameter's, an
    ;; annotation's or a signature's. At an Fn, a `fn` or the name of a
    ;; top-level function is given that type, since neither has an
    ;; environment: `check-closed` proves it of a `fn`, and the expander
    ;; records which globals are functions. No other value has type Fn
    ;; unless it already does. Any crosses this boundary through an explicit
    ;; Convert in the checked IR. Variables still unify normally; a rigid
    ;; variable is not a runtime type to test. The final conversion and
    ;; ownership checks enforce the same restrictions as explicit casts.
    (: fit (-> Checker Type Expr Type Loc (Pair Expr Checker) ! compile))
    (define (fit ck expected expr row loc)
      (match (Pair (prune (solution ck) expected) (prune (solution ck) (Expr-type expr)))
        ((Pair (TCon "Any" (Nil)) (TCon "Any" (Nil))) (Pair expr ck))
        ((Pair (TCon "Any" (Nil)) (TVar _))
         (fit-any-literal ck expected expr (Expr-type expr) row loc))
        ((Pair (TVar _) (TCon "Any" (Nil)))
         (fit-any-literal ck expected expr expected row loc))
        ((Pair (TVar _) _) (Pair expr (unify ck expected (Expr-type expr) loc)))
        ((Pair _ (TVar _)) (Pair expr (unify ck expected (Expr-type expr) loc)))
        ((Pair (TCon "Any" (Nil)) _)
         (convert-value ck expr expected row loc))
        ((Pair _ (TCon "Any" (Nil)))
         (convert-value ck expr expected row loc))
        ((Pair (TCon "Fn" (Cons arrow (Nil))) (TFun _ _ _))
         (unless (environment-free? ck expr)
           (compile-error loc
                          (string-append "only a fn or a top-level function has type "
                                         (type->string (resolve-type (solution ck) expected))
                                         "; a lambda, or a local bound to one, may capture")))
         (Pair (Expr (Expr-term expr) expected (Expr-loc expr))
               (unify ck arrow (Expr-type expr) loc)))
        ((Pair (TFun _ _ _) (TCon "Fn" _))
         (compile-error loc
                        "an Fn is not a closure, and does not become one; wrap it in a lambda, as (lambda (x) (f x))"))
        (_ (Pair expr (unify ck expected (Expr-type expr) loc)))))

    ;; A numeric literal's variable is already constrained to a number.
    ;; Keep that constraint across an Any boundary: ordinary literal
    ;; defaulting (or a later use) chooses its concrete type, not Any.
    (: fit-any-literal (-> Checker Type Expr Type Type Loc (Pair Expr Checker) ! compile))
    (define (fit-any-literal ck expected expr type row loc)
      (if (any? (lambda (want)
                  (match want
                    ((WantLiteral _ literal _)
                     (same-meta? (prune (solution ck) type) (prune (solution ck) literal)))
                    (_ #f)))
                (Checker-pending ck))
          (convert-value ck expr expected row loc)
          (Pair expr (unify ck expected (Expr-type expr) loc))))

    ;; Only an established Any boundary reaches here. An unconstrained
    ;; variable unified in fit; a literal's variable is known to be numeric,
    ;; so extracting it from Any is fallible before its width is chosen.
    (: convert-value (-> Checker Expr Type Type Loc (Pair Expr Checker) ! compile))
    (define (convert-value ck value target row loc)
      ;; Reject known ineligible endpoints before a later host-row error
      ;; can hide the boundary. Final validation repeats this with solved
      ;; types; zonk here only closes unknowns for this negative check.
      (for-each (lambda (type)
                  (refuse-hidden-effects "type-convert" type loc)
                  (refuse-function-reference "type-convert" type loc))
                (list (zonk (solution ck) (Expr-type value)) (zonk (solution ck) target)))
      (let ((ck (if (and (any-type? (prune (solution ck) (Expr-type value)))
                         (not (any-type? (prune (solution ck) target))))
                    (require-conversion ck target row loc)
                    ck)))
        (Pair (Expr (Convert value target) target loc) ck)))

    (: require-conversion (-> Checker Type Type Loc Checker ! compile))
    (define (require-conversion ck target row loc)
      (let ((flat (flatten-row (solution ck) row)))
        (unless (or (member? dyn-cast-label (Pair-first flat)) (meta-tail? (Pair-second flat)))
          (compile-error loc
                         (string-append "conversion from Any to "
                                        (type->string (resolve-type (solution ck) target))
                                        " requires dyn-cast; handle or declare dyn-cast, or use try-convert")))
        (perform ck (TRow (list dyn-cast-label) (None)) row loc)))

    (: environment-free? (-> Checker Expr Bool))
    (define (environment-free? ck expr)
      (match (Expr-term expr)
        ((Lambda _ _ captures?) (not captures?))
        ((Var name _ _)
         (match (program-value (program-of ck) name)
           ((Some (Defined _ _ function?)) function?)
           (_ #f)))
        (_ #f)))

    ;; A function's own name is visible in its body, with a monomorphic type.
    (: infer-let (-> Checker String Expr Expr Type Loc (Pair Expr Checker) ! compile))
    (define (infer-let ck name value body row loc)
      (learning ck ((type (fresh-meta))
                    (value (infer-let-value name type value row))
                    (then (unify type (Expr-type value) (Expr-loc value)))
                    (body (scoped (bind-local ck name type) body row)))
                (Pair (Expr (Let name value body) (Expr-type body) loc) ck)))

    ;; A `let`'s own name is visible in its value only when the value is a
    ;; lambda, so a recursive local function can call itself.
    (: infer-let-value (-> Checker String Type Expr Type (Pair Expr Checker) ! compile))
    (define (infer-let-value ck name type value row)
      (if (lambda-expr? value)
          (scoped ck (bind-local ck name type) value row)
          (infer ck value row)))

    ;; `expr` inferred under `inner`'s scope, resumed in this checker's.
    (: scoped (-> Checker Checker Expr Type (Pair Expr Checker) ! compile))
    (define (scoped ck inner expr row)
      (within ck inner (lambda (scope) (infer scope expr row))))

    (: infer-match (-> Checker Expr (List Clause) Type Loc (Pair Expr Checker) ! compile))
    (define (infer-match ck scrutinee clauses row loc)
      (learning ck ((scrutinee (infer scrutinee row))
                    (result (fresh-meta))
                    (clauses (each (lambda (ck clause)
                                     (infer-clause ck clause (Expr-type scrutinee) result row))
                                   clauses)))
                (if (null? clauses)
                    (check-empty-match ck (Expr-type scrutinee) loc)
                    (check-coverage ck (map Clause-pattern clauses) loc))
                (Pair (Expr (Match scrutinee clauses) result loc) ck)))

    ;; A match with no clauses is exhaustive only on a type with no cases,
    ;; which has no value to reach it with.
    (: check-empty-match (-> Checker Type Loc Unit ! compile))
    (define (check-empty-match ck type loc)
      (unless (match (resolve-type (solution ck) type)
                ((TCon name _)
                 (match (table-ref (Program-types (program-of ck)) name)
                   ((Some data) (and (DataType-enum? data) (null? (DataType-cases data))))
                   ((None) #f)))
                (_ #f))
        (compile-error loc
                       "a match needs at least one clause, unless its value's type has no cases")))

    ;; One clause: its pattern binds for its body alone, and every body has
    ;; the match's result type.
    (: infer-clause (-> Checker Clause Type Type Type (Pair Clause Checker) ! compile))
    (define (infer-clause ck clause scrutinee-type result row)
      (let ((body-loc (Expr-loc (Clause-body clause))))
        (learning ck ((checked (check-pattern (Clause-pattern clause) scrutinee-type body-loc))
                      (body (scoped (Checked-scope checked) (Clause-body clause) row))
                      (then (unify result (Expr-type body) body-loc)))
                  (Pair (Clause (Checked-pattern checked) body) ck))))

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
       (-> Checker String (List (Pair String Expr)) Expr Type Loc (Pair Expr Checker) ! compile))
    (define (infer-handle ck effect implementations body row loc)
      (let* ((info (program-effect (program-of ck) effect)) (operations (Effect-operations info)))
        (unless (and (= (length operations) (length implementations))
                     (every? (lambda (operation)
                               (any? (lambda (entry) (string=? (Pair-first entry) operation))
                                     implementations))
                             operations))
          (compile-error loc "a handler implements each operation of its effect exactly once"))
        (learning ck ((result (fresh-meta))
                      (rest (fresh-meta))
                      (implementations
                       (each (lambda (ck entry)
                               (infer-implementation ck
                                                     entry
                                                     (Answer (Effect-control info) result)
                                                     row
                                                     loc))
                             implementations))
                      (body (infer body (TRow (list effect) (Some rest))))
                      (body (fit result body (TRow (list effect) (Some rest)) (Expr-loc body)))
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
       (-> Checker (Pair String Expr) Answer Type Loc (Pair (Pair String Expr) Checker) ! compile))
    (define (infer-implementation ck entry answer row loc)
      (match (program-value (program-of ck) (Pair-first entry))
        ((Some (Operation effect scheme))
         (learning ck ((use (instantiate scheme loc)))
                   (match (Instantiated-type use)
                     ((TFun params result _)
                      (learning ck ((rest (fresh-meta)))
                                (let ((expected
                                       (implementation-type (Pair-first entry) answer params result
                                                            (latent-row
                                                             (operation-latent effect scheme)
                                                             rest)
                                                            row)))
                                  (learning ck ((value
                                                 (infer-implementation-value (Pair-second entry)
                                                                             expected
                                                                             row))
                                                (then (unify expected
                                                             (Expr-type value)
                                                             (Expr-loc value)))
                                                (then (perform rest row (Expr-loc value))))
                                            (Pair (Pair (Pair-first entry) value) ck)))))
                     (_ (panic "internal error: an operation is a function")))))
        (_ (panic "internal error: unknown operation"))))

    ;; The row an implementation may perform: the latent labels, open to
    ;; `rest`, or `rest` alone.
    (: latent-row (-> (List String) Type Type))
    (define (latent-row labels rest)
      (if (null? labels) rest (TRow labels (Some rest))))

    ;; An implementation that is a lambda takes its parameter types from the
    ;; operation, so its body knows `resume` is one-shot when it calls it.
    (: infer-implementation-value (-> Checker Expr Type Type (Pair Expr Checker) ! compile))
    (define (infer-implementation-value ck value expected row)
      (match (Pair (Expr-term value) expected)
        ((Pair (Lambda params body captures?) (TFun types result _))
         (if (= (length params) (length types))
             (learning ck ((value (infer-lambda-at params body captures? types (Expr-loc value))))
                       (fit-lambda-result ck value result))
             (infer ck value row)))
        (_ (infer ck value row))))

    ;; An implementation is checked at its operation's result without
    ;; changing the inferred row or adapting an already existing function.
    (: fit-lambda-result (-> Checker Expr Type (Pair Expr Checker) ! compile))
    (define (fit-lambda-result ck value result)
      (match (Pair (Expr-term value) (Expr-type value))
        ((Pair (Lambda params body captures?) (TFun types _ row))
         (learning ck ((body (fit result body row (Expr-loc body))))
                   (Pair
                    (Expr (Lambda params body captures?) (TFun types result row) (Expr-loc value))
                    ck)))
        (_ (panic "internal error: fitting the result of a non-lambda"))))

    ;; An implementation returns the operation's answer to its caller. A
    ;; control operation's implementation returns the handler's result, and
    ;; is also handed `resume`, which it calls or drops exactly once, unless the
    ;; operation answers Never, when nothing could resume it. `resume`
    ;; performs `context`, the row of the code around the handle.
    (: implementation-type (-> String Answer (List Type) Type Type Type Type))
    (define (implementation-type operation answer params result latent context)
      (cond ((not (member? operation (Answer-control answer))) (TFun params result latent))
            ((never-type? result) (TFun params (Answer-result answer) latent))
            (else (TFun (append params
                                (list (TCon "FnOnce"
                                            (list (TFun (list result)
                                                        (Answer-result answer)
                                                        context)))))
                        (Answer-result answer)
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

    (: check-pattern (-> Checker Pattern Type Loc (Pair Checked Checker) ! compile))
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
                      (match (Instantiated-type use)
                        ((TFun fields result _)
                         (unless (= (length fields) (length args))
                           (compile-error loc
                                          (string-append (short-name constructor)
                                                         " has "
                                                         (i64->string (length fields))
                                                         " fields")))
                         (check-mutable-positions case args loc)
                         (learning ck ((then (unify type result loc))
                                       (checked (check-fields constructor type args fields loc)))
                                   (Pair checked ck)))
                        (_ (panic "internal error: a constructor is a function")))))
           (_
            (compile-error loc (string-append "not a constructor: " (short-name constructor))))))))

    ;; A mutable field is read through its accessor, which performs `mut`,
    ;; so a pattern can only skip it.
    (: check-mutable-positions (-> Case (List Pattern) Loc Unit ! compile))
    (define (check-mutable-positions case args loc)
      (for-each (lambda (pair)
                  (match (Pair (Field-mutable? (Pair-first pair)) (Pair-second pair))
                    ((Pair #f _) (unit))
                    ((Pair #t (PWild _)) (unit))
                    ((Pair #t _)
                     (compile-error loc
                                    (string-append "a pattern cannot read the mutable field "
                                                   (Field-name (Pair-first pair))
                                                   "; write _ there and read it with "
                                                   (short-name (Case-name case))
                                                   "-"
                                                   (Field-name (Pair-first pair)))))))
                (zip (Case-fields case) args)))

    ;; A constructor pattern's fields, checked in order into one scope:
    ;; names are unique, so the fields' locals simply join.
    (: check-fields
       (-> Checker String Type (List Pattern) (List Type) Loc (Pair Checked Checker) ! compile))
    (define (check-fields ck constructor type args fields loc)
      (learning ck ((done (each (lambda (ck pair)
                                  (check-pattern ck (Pair-first pair) (Pair-second pair) loc))
                                (zip args fields))))
                (Pair (Checked (PCon constructor (map Checked-pattern done) type)
                               (fold-left
                                (lambda (scope field) (merged-locals scope (Checked-scope field)))
                                ck
                                done))
                      ck)))

    ;; Every local a field pattern bound, added to the scope so far.
    (: merged-locals (-> Checker Checker Checker))
    (define (merged-locals scope field)
      (Checker-locals-set scope (table-union (Checker-locals scope) (Checker-locals field))))

    ;; ---- Coverage ----

    ;; Maranget's usefulness test. A clause is redundant if it is not useful
    ;; after the clauses before it; a match is exhaustive if a wildcard is not
    ;; useful after all of them.
    (: check-coverage (-> Checker (List Pattern) Loc Unit ! compile))
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
                   ((Some other)
                    (if (head=? other head) (list (append (pattern-args first) rest)) (Nil)))))
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
               (any? (lambda (head)
                       (useful? ck
                                (specialize rows head)
                                (append (wildcards (head-arity head)) rest)))
                     all))
              ((None) (useful? ck (default-rows rows) rest))))))))

    ;; All heads of the matched type, if `seen` includes every one of them.
    (: complete-signature (-> Checker (List Head) (Option (List Head))))
    (define (complete-signature ck seen)
      (let ((all (match seen
                   ((Cons (HLit (DBool _)) _) (list (HLit (DBool #t)) (HLit (DBool #f))))
                   ((Cons (HCon constructor _) _) (constructor-heads ck constructor))
                   (_ (Nil)))))
        (if (and (not (null? all))
                 (every? (lambda (head) (any? (lambda (other) (head=? head other)) seen)) all))
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
    ;; every class constraint is solved with the givens it arose under.
    ;; Solving binds no metavariables, so waiting until now loses nothing,
    ;; except for a class whose row is found from its types, as a drop's, a
    ;; clone's or a `(Store e S)`'s is, which charges its row: most are
    ;; solved at their call (`solve-found-rows`), and one left until now is
    ;; of a type that a later use decided.
    (: solve-pending (-> Checker Checker ! compile))
    (define (solve-pending ck)
      (let ((pending (reverse (Checker-pending ck))))
        (learning ck ((then (improve-fields 0))
                      (then (default-literals pending #t))
                      (then (default-literals pending #f)))
                  (for-each (lambda (want)
                              (match want
                                ((WantLiteral value type loc) (check-literal ck value type loc))
                                ((WantCopy type copy loc) (check-copy ck type copy loc))
                                (_ (unit))))
                            pending)
                  (fold-left (lambda (ck want)
                               (match want
                                 ((WantClass constraint hole givens copy loc)
                                  (solve-class ck constraint hole givens copy loc))
                                 (_ ck)))
                             ck pending))))

    (: default-literals (-> Checker (List Wanted) Bool Checker ! compile))
    (define (default-literals ck pending float?)
      (fold-left (lambda (ck want) (default-literal ck want float?)) ck pending))

    (: default-literal (-> Checker Wanted Bool Checker ! compile))
    (define (default-literal ck want float?)
      (match want
        ((WantLiteral value type loc)
         (if (and (float-literal? value float?) (meta? (prune (solution ck) type)))
             (unify ck (TCon (if float? "F64" "I64") (Nil)) type loc)
             ck))
        (_ ck)))

    (: float-literal? (-> Datum Bool Bool))
    (define (float-literal? value float?)
      (match value
        ((DFloat _) float?)
        (_ (not float?))))

    (: check-literal (-> Checker Datum Type Loc Unit ! compile))
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

    (: solve-class
       (-> Checker Constraint I64 (List Constraint) (List String) Loc Checker ! compile))
    (define (solve-class ck constraint hole givens copy loc)
      (cond ((row-class? ck (Constraint-class constraint))
             (solve-found ck constraint hole givens copy (None) loc))
            ((string=? (Constraint-class constraint) unboxed-class)
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

    (: solve-unboxed (-> Checker Constraint I64 (List Constraint) Loc Checker ! compile))
    (define (solve-unboxed ck constraint hole givens loc)
      (match (Constraint-types constraint)
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

    (: unboxed? (-> Program Type Bool))
    (define (unboxed? program type)
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
                            "Array" "Vector" "Ref" "FnOnce" "Fn"))
             (let ((data (program-type program name)))
               (or (DataType-enum? data)
                   (match (DataType-cases data)
                     ((Cons case _)
                      (match (Case-fields case)
                        ((Cons field (Nil))
                         (unboxed? program
                                   (substitute (zip (DataType-params data) args)
                                               (Field-type field))))
                        (_ #f)))
                     ((Nil) #f))))))
        (_ #f)))

    ;; An unsolved field constraint whose record type is known names the
    ;; field the type lacks; any other unsolved constraint is ambiguous.
    (: unsolved-constraint (-> Checker Constraint (List Constraint) String))
    (define (unsolved-constraint ck constraint givens)
      (let ((class (Constraint-class constraint)))
        (match (Pair (field-class? class) (Constraint-types constraint))
          ((Pair #t (Cons record _))
           (let ((record (resolve-type (solution ck) record)))
             (if (or (has-meta? (solution ck) record)
                     (match (field-type-of ck class record givens)
                       ((Some _) #t)
                       ((None) #f)))
                 (ambiguous-constraint ck constraint)
                 (string-append (type->string record)
                                " has no field "
                                (substring class 2 (string-length class))))))
          (_ (ambiguous-constraint ck constraint)))))

    ;; A class whose methods perform one of its parameters as a row, as
    ;; `(Drop e T)` and `(Store e S)` do. Its rows are found from its other
    ;; arguments, its types, rather than matched: what the instance those
    ;; select performs is charged to the constraint's rows.
    (: row-class? (-> Checker String Bool))
    (define (row-class? ck class)
      (not (null? (Class-rows (program-class (program-of ck) class)))))

    ;; A row class's constraint, solved in the row of the call it was raised
    ;; in when `context` gives one.
    (: solve-found
       (-> Checker
           Constraint
           I64
           (List Constraint)
           (List String)
           (Option Type)
           Loc
           Checker
           ! compile))
    (define (solve-found ck constraint hole givens copy context loc)
      (match (found-evidence ck constraint givens copy context loc)
        ((Pair evidence ck) (with-evidence ck hole evidence))))

    (: found-evidence
       (-> Checker
           Constraint
           (List Constraint)
           (List String)
           (Option Type)
           Loc
           (Pair Evidence Checker)
           ! compile))
    (define (found-evidence ck constraint givens copy context loc)
      (if (lifecycle-class? (Constraint-class constraint))
          (lifecycle-evidence ck constraint givens copy context loc)
          (determined-evidence ck constraint givens copy context loc)))

    ;; A row class other than Drop and Clone is chosen as any class is, by
    ;; its types alone: the requirement given for them, or the one instance
    ;; whose head matches them. What that performs at each row parameter is
    ;; charged to the constraint's row there.
    (: determined-evidence
       (-> Checker
           Constraint
           (List Constraint)
           (List String)
           (Option Type)
           Loc
           (Pair Evidence Checker)
           ! compile))
    (define (determined-evidence ck constraint givens copy context loc)
      (let* ((class (program-class (program-of ck) (Constraint-class constraint)))
             (types (map (lambda (type) (resolve-type (solution ck) type))
                         (Constraint-types constraint))))
        (when (any? (lambda (type) (has-meta? (solution ck) type)) (type-arguments class types))
          (compile-error loc (ambiguous-constraint ck constraint)))
        (match (determined-source ck class types givens copy loc)
          ((Pair (Pair evidence performed) ck)
           (Pair evidence
                 (fold-left (lambda (ck charged)
                              (charge ck (Pair-first charged) (Pair-second charged) context loc))
                            ck
                            (zip performed (row-arguments class types))))))))

    ;; The evidence for a row class's types, and the row it performs at each
    ;; row parameter: a requirement given for them performs its own rows.
    (: determined-source
       (-> Checker
           Class
           (List Type)
           (List Constraint)
           (List String)
           Loc
           (Pair (Pair Evidence (List Type)) Checker)
           ! compile))
    (define (determined-source ck class types givens copy loc)
      (match (list-index (lambda (given) (given-for? class types given)) givens)
        ((Some index)
         (Pair
          (Pair (EvParam index) (row-arguments class (Constraint-types (list-ref givens index))))
          ck))
        ((None) (determined-instance ck class types givens copy loc))))

    (: given-for? (-> Class (List Type) Constraint Bool))
    (define (given-for? class types given)
      (and (string=? (Class-name class) (Constraint-class given))
           (types=? (type-arguments class types) (type-arguments class (Constraint-types given)))))

    ;; The instance whose head matches the types. Its requirements are
    ;; solved with each variable its rows end with standing for a fresh row,
    ;; which they charge; its rows, ending with those, are what it performs.
    (: determined-instance
       (-> Checker
           Class
           (List Type)
           (List Constraint)
           (List String)
           Loc
           (Pair (Pair Evidence (List Type)) Checker)
           ! compile))
    (define (determined-instance ck class types givens copy loc)
      (match (matching-instance ck class types loc)
        ((Pair instance bindings)
         (let ((heads (row-arguments class (Instance-types instance))))
           (learning ck ((tails (fresh-bindings (concatenate (map row-variable heads))))
                         (evidence (instance-application instance bindings tails givens copy loc)))
                     (Pair (Pair evidence (map (lambda (row) (substitute tails row)) heads))
                           ck))))))

    (: with-evidence (-> Checker I64 Evidence Checker))
    (define (with-evidence ck hole evidence)
      (Checker-solution-set ck (Solution (Solution-types (solution ck))
                                         (table-set (Solution-evidence (solution ck))
                                                    (identity-key hole)
                                                    evidence))))

    (: ambiguous-constraint (-> Checker Constraint String))
    (define (ambiguous-constraint ck constraint)
      (string-append "ambiguous constraint "
                     (constraint->string (Constraint-class constraint)
                                         (map (lambda (type) (resolve-type (solution ck) type))
                                              (Constraint-types constraint)))
                     "; add a signature or an annotation"))

    ;; A lifecycle class's row, as `(Drop e T)`'s, is found from T, not
    ;; matched: dropping or cloning a T runs what the type says
    ;; (`lifecycle-rows`), and each row that performs is performed in `e`.
    ;; Mono finds what runs again from the ground type, so the evidence only
    ;; records the plan charged. `context` is the row of the call the
    ;; constraint was raised in, when it is solved there.
    (: lifecycle-evidence
       (-> Checker
           Constraint
           (List Constraint)
           (List String)
           (Option Type)
           Loc
           (Pair Evidence Checker)
           ! compile))
    (define (lifecycle-evidence ck constraint givens copy context loc)
      (match (Constraint-types constraint)
        ((Cons row (Cons type (Nil)))
         (let ((type (resolve-type (solution ck) type))
               (class (Constraint-class constraint))
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
    (: charge (-> Checker Type Type (Option Type) Loc Checker ! compile))
    (define (charge ck performed row context loc)
      (let ((ck (perform ck performed row loc)))
        (match context
          ((Some context)
           (if (same-tail? (Pair-second (flatten-row (solution ck) row))
                           (Pair-second (flatten-row (solution ck) context)))
               (record-performed ck
                                 context
                                 (let ((flat (flatten-row (solution ck) performed)))
                                   (append (Pair-first flat) (tail-variable (Pair-second flat)))))
               ck))
          ((None) ck))))

    ;; A row is charged where it is written: once a call is checked, each
    ;; constraint of a row class raised in it whose types are known by now
    ;; is solved in the call's scope, so a signed body is seen to perform
    ;; what its drops, clones and methods do. One whose types a later use
    ;; decides waits for `solve-pending`.
    (: solve-found-rows (-> Checker I64 Type Checker ! compile))
    (define (solve-found-rows ck before context)
      (let* ((count (- (Checker-pending-count ck) before))
             (recent (take (Checker-pending ck) count))
             (older (list-drop (Checker-pending ck) count)))
        (if (any? (lambda (want) (known-row? ck want)) recent)
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
       (-> (Pair (List Wanted) Checker) Wanted Type (Pair (List Wanted) Checker) ! compile))
    (define (solve-known-row progress want context)
      (match progress
        ((Pair kept ck)
         (match want
           ((WantClass constraint hole givens copy loc)
            (if (known-row? ck want)
                (Pair kept (solve-found ck constraint hole givens copy (Some context) loc))
                (Pair (Cons want kept) ck)))
           (_ (Pair (Cons want kept) ck))))))

    (: known-row? (-> Checker Wanted Bool))
    (define (known-row? ck want)
      (match want
        ((WantClass constraint _ _ _ _)
         (let ((class (Constraint-class constraint)))
           (and (row-class? ck class)
                (not (any? (lambda (type) (has-meta? (solution ck) type))
                           (type-arguments (program-class (program-of ck) class)
                                           (Constraint-types constraint)))))))
        (_ #f)))

    ;; A field constraint `(::f R T)` decides T from R: the one instance
    ;; whose record type matches R gives the field's type, or a given
    ;; constraint on the same R does. It runs where a call is checked, once
    ;; the arguments have given R, over the constraints raised since
    ;; `before`, and again over every constraint before solving, for an R a
    ;; later use decided. Nothing else solving does binds a metavariable.
    (: improve-fields (-> Checker I64 Checker ! compile))
    (define (improve-fields ck before)
      (fold-left improve-field
                 ck
                 (take (Checker-pending ck) (- (Checker-pending-count ck) before))))

    (: improve-field (-> Checker Wanted Checker ! compile))
    (define (improve-field ck want)
      (match want
        ((WantClass (Constraint class (Cons record (Cons field (Nil)))) _ givens _ loc)
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
    (: field-type-of (-> Checker String Type (List Constraint) (Option Type)))
    (define (field-type-of ck class record givens)
      (match record
        ((TCon _ _)
         (one (concatenate (map (lambda (instance) (instance-field-type instance record))
                                (class-instances (program-of ck) class)))))
        (_ (one (concatenate (map (lambda (given) (given-field-type ck class given record))
                                  givens))))))

    (: one (-> (List Type) (Option Type)))
    (define (one types)
      (match types
        ((Cons type (Nil)) (Some type))
        (_ (None))))

    (: instance-field-type (-> Instance Type (List Type)))
    (define (instance-field-type instance record)
      (match (Instance-types instance)
        ((Cons head (Cons type (Nil)))
         (match (match-type (Instance-vars instance) head record (Nil))
           ((Some bindings) (list (substitute bindings type)))
           ((None) (Nil))))
        (_ (Nil))))

    (: given-field-type (-> Checker String Constraint Type (List Type)))
    (define (given-field-type ck class given record)
      (match (Constraint-types given)
        ((Cons head (Cons type (Nil)))
         (if (and (string=? class (Constraint-class given))
                  (types=? (list (resolve-type (solution ck) head)) (list record)))
             (list type)
             (Nil)))
        (_ (Nil))))

    ;; Evidence from the enclosing definition's requirements, or from the
    ;; unique instance whose head matches. None while the types are ambiguous.
    (: find-evidence
       (-> Checker
           Constraint
           (List Constraint)
           (List String)
           Loc
           (Option (Pair Evidence Checker))
           ! compile))
    (define (find-evidence ck constraint givens copy loc)
      (let ((types
             (map (lambda (type) (resolve-type (solution ck) type)) (Constraint-types constraint))))
        (if (any? (lambda (type) (has-meta? (solution ck) type)) types)
            (None)
            (match (given-evidence (Constraint-class constraint) types givens)
              ((Some evidence) (Some (Pair evidence ck)))
              ((None)
               (Some
                (instance-evidence ck (Constraint-class constraint) types givens copy loc)))))))

    (: given-evidence (-> String (List Type) (List Constraint) (Option Evidence)))
    (define (given-evidence class types givens)
      (match (list-index (lambda (given)
                           (and (string=? class (Constraint-class given))
                                (types=? types (Constraint-types given))))
                         givens)
        ((Some index) (Some (EvParam index)))
        ((None) (None))))

    (: instance-evidence
       (-> Checker
           String
           (List Type)
           (List Constraint)
           (List String)
           Loc
           (Pair Evidence Checker)
           ! compile))
    (define (instance-evidence ck class types givens copy loc)
      (match (matching-instance ck (program-class (program-of ck) class) types loc)
        ((Pair instance bindings)
         (instance-application ck instance bindings (Nil) givens copy loc))))

    ;; The instance whose head matches a constraint's types, and what that
    ;; binds its variables to. Rows take no part: they are found from the
    ;; instance chosen, so no two instances of a class have the same types.
    (: matching-instance (-> Checker Class (List Type) Loc (Pair Instance Substitution) ! compile))
    (define (matching-instance ck class types loc)
      (let loop ((instances (class-instances (program-of ck) (Class-name class))))
        (match instances
          ((Nil)
           (compile-error loc
                          (match (Pair (field-class? (Class-name class)) types)
                            ((Pair #t (Cons record _))
                             (string-append (type->string record)
                                            " has no field "
                                            (substring (Class-name class)
                                                       2
                                                       (string-length (Class-name class)))))
                            (_ (string-append "no instance for "
                                              (constraint->string (Class-name class) types))))))
          ((Cons instance rest)
           (match (match-types (Instance-vars instance)
                               (type-arguments class (Instance-types instance))
                               (type-arguments class types)
                               (Nil))
             ((Some bindings) (Pair instance bindings))
             ((None) (loop rest)))))))

    ;; An instance applied where its head matched with `bindings`: a
    ;; variable it requires Copy must be given an unrestricted type, and
    ;; each of its requirements is satisfied there in turn, with `rows`
    ;; giving the variables a row class's instance ends its rows with.
    (: instance-application
       (-> Checker
           Instance
           Substitution
           Substitution
           (List Constraint)
           (List String)
           Loc
           (Pair Evidence Checker)
           ! compile))
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
                      (Instance-requires instance))
           ((Pair subs ck)
            (Pair (EvInstance (Instance-name instance)
                              (applied-types instance (append rows bindings))
                              subs)
                  ck))))))

    ;; The types the head's match gave the instance's variables, in order.
    (: applied-types (-> Instance Substitution (List Type)))
    (define (applied-types instance bindings)
      (map (lambda (var)
             (match (assoc-ref bindings var)
               ((Some type) type)
               ((None) (TCon "Unit" (Nil)))))
           (Instance-vars instance)))

    ;; A requirement of a row class, as `(Drop e A)` or `(Store e S)`, is
    ;; solved as its use is: what the type it gives `A` performs is charged
    ;; to its row `e`. Any other is found as a constraint is.
    (: requirement-evidence
       (-> Checker
           Constraint
           (List Constraint)
           (List String)
           Loc
           (Pair Evidence Checker)
           ! compile))
    (define (requirement-evidence ck requirement givens copy loc)
      (if (row-class? ck (Constraint-class requirement))
          (found-evidence ck requirement givens copy (None) loc)
          (match (find-evidence ck requirement givens copy loc)
            ((Some found) found)
            ((None) (compile-error loc (ambiguous-requirement requirement))))))

    (: ambiguous-requirement (-> Constraint String))
    (define (ambiguous-requirement requirement)
      (string-append "ambiguous requirement "
                     (constraint->string (Constraint-class requirement)
                                         (Constraint-types requirement))))

    ;; One-way matching of an instance head; only its own variables bind.
    (: match-types (-> (List String) (List Type) (List Type) Substitution (Option Substitution)))
    (define (match-types vars patterns types bindings)
      (if (= (length patterns) (length types))
          (fold-left (lambda (result pair)
                       (match result
                         ((Some bindings)
                          (match-type vars (Pair-first pair) (Pair-second pair) bindings))
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
           ((TCon other others)
            (if (string=? name other) (match-types vars args others bindings) (None)))
           (_ (None))))
        ((TFun params result _)
         (match type
           ((TFun others other-result _)
            (match-types vars (Cons result params) (Cons other-result others) bindings))
           (_ (None))))
        (_ (None))))

    (: constraint->string (-> String (List Type) String))
    (define (constraint->string class types)
      (if (field-class? class)
          (string-append "(" class " " (string-join (map type->string types) " ") ")")
          (type->string (TCon class types))))

    (: has-meta? (-> Solution Type Bool))
    (define (has-meta? solution type)
      (match (prune solution type)
        ((TVar _) #t)
        ((TCon _ args) (any? (lambda (arg) (has-meta? solution arg)) args))
        ((TFun params result _)
         (or (any? (lambda (param) (has-meta? solution param)) params) (has-meta? solution result)))
        (_ #f)))

    ;; ---- Zonking ----

    ;; Replaces solved metavariables and keeps unsolved ones.
    (: resolve-type (-> Solution Type Type))
    (define (resolve-type solution type)
      (let ((type (prune solution type)))
        (match type
          ((TCon name args) (TCon name (map (lambda (arg) (resolve-type solution arg)) args)))
          ((TFun params result row)
           (TFun (map (lambda (param) (resolve-type solution param)) params)
                 (resolve-type solution result) (resolve-type solution row)))
          ((TRow _ _)
           (let ((flat (flatten-row solution type))) (TRow (Pair-first flat) (Pair-second flat))))
          (_ type))))

    ;; Replaces solved metavariables. An unsolved type defaults to Unit and an
    ;; unsolved row tail closes; nothing observable depends on either.
    (: zonk (-> Solution Type Type))
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

    (: zonk-row (-> Solution Type Type))
    (define (zonk-row solution row)
      (let ((flat (flatten-row solution row)))
        (TRow (Pair-first flat) (if (meta-tail? (Pair-second flat)) (None) (Pair-second flat)))))

    (: zonk-evidence (-> Solution Evidence Evidence))
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

    (: zonk-expr (-> Solution Expr Expr))
    (define (zonk-expr solution expr)
      (Expr (match (Expr-term expr)
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
                      (map (lambda (clause) (Clause (zonk-pattern solution (Clause-pattern clause))
                                                    (zonk-expr solution (Clause-body clause))))
                           clauses)))
              ((Ann inner type) (Ann (zonk-expr solution inner) (zonk solution type)))
              ((Convert inner target) (Convert (zonk-expr solution inner) (zonk solution target)))
              ((TryConvert inner target)
               (TryConvert (zonk-expr solution inner) (zonk solution target)))
              ((TypeTest inner target) (TypeTest (zonk-expr solution inner) (zonk solution target)))
              ((Handle effect implementations body)
               (Handle effect
                       (map (lambda (entry)
                              (Pair (Pair-first entry) (zonk-expr solution (Pair-second entry))))
                            implementations)
                       (zonk-expr solution body))))
            (zonk solution (Expr-type expr)) (Expr-loc expr)))

    (: zonk-pattern (-> Solution Pattern Pattern))
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
    (: check-confined (-> Typed Expr Unit ! compile))
    (define (check-confined typed function)
      (match (Pair (Expr-term function) (Expr-type function))
        ((Pair (Lambda params _ _) (TFun param-types result _))
         (let ((program (Typed-program typed)))
           (for-each (lambda (pair)
                       (when (holds-storage? program (Pair-second pair))
                         (confinement-error function
                                            (string-append "its parameter "
                                                           (local-name (Pair-first pair))
                                                           ", a "
                                                           (type->string (Pair-second pair)) ","))))
                     (zip params param-types))
           (when (holds-storage? program result)
             (confinement-error function
                                (string-append "its result, a " (type->string result) ",")))
           (for-each (lambda (read) (check-outside-read typed read)) (outside-reads function))))
        (_ (unit))))

    (: confinement-error (-> Expr String Unit ! compile))
    (define (confinement-error function culprit)
      (compile-error (Expr-loc function)
                     (string-append
                      "this function's type does not allow mut, so it may mutate only storage it allocates, but "
                      culprit " could hold storage from outside")))

    ;; A local of an enclosing definition is judged by its type; a global by
    ;; its declared or inferred type, since instantiating a row variable can
    ;; only bring in effects the function itself performs.
    (: check-outside-read (-> Typed Expr Unit ! compile))
    (define (check-outside-read typed read)
      (match (Expr-term read)
        ((Var name _ _)
         (when (reaches-storage? typed name (Expr-type read))
           (compile-error (Expr-loc read)
                          (string-append
                           "this function's type does not allow mut, so it may mutate only storage it allocates, but "
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
    (: primitive-alias? (-> Typed String Bool))
    (define (primitive-alias? typed name)
      (let ((program (Typed-program typed)))
        (any? (lambda (item)
                (match item
                  ((Define defined value)
                   (and (string=? defined name)
                        (match (Expr-term value)
                          ((Var target _ _)
                           (match (program-value program target)
                             ((Some (Primitive _)) #t)
                             (_ #f)))
                          (_ #f))))
                  (_ #f)))
              (program-items program))))

    (: global-type (-> Typed String Value Type))
    (define (global-type typed name value)
      (match (table-ref (Typed-schemes typed) name)
        ((Some scheme) (Scheme-type scheme))
        ((None)
         (match (value-scheme value)
           ((Some scheme) (Scheme-type scheme))
           ((None) (panic (string-append "internal error: no type for " name)))))))

    ;; Whether a value of the type can hold or reach mutable storage: an
    ;; `Array`, an `Any` that may hide one, data with a mutable field, a
    ;; `Ref` among them, or with a field of such a type, or a function that
    ;; may perform `mut`. Code cannot use a value of a type variable as
    ;; storage, so type variables hold none.
    (: holds-storage? (-> Program Type Bool))
    (define (holds-storage? program type)
      (holds-storage-within? program type (Nil)))

    (: holds-storage-within? (-> Program Type (List String) Bool))
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
    (: row-mutates? (-> Type Bool))
    (define (row-mutates? row)
      (match row
        ((TRow labels _) (or (member? "mut" labels) (member? "host" labels)))
        (_ #f)))

    ;; Builtin types other than `Array` and `Any` have no fields.
    (: fields-hold-storage? (-> Program String (List String) Bool))
    (define (fields-hold-storage? program name visiting)
      (and (not (any? (lambda (entry) (string=? (Pair-first entry) name)) builtin-types))
           (any? (lambda (case)
                   (any?
                    (lambda (field)
                      (or (Field-mutable? field)
                          (holds-storage-within? program (Field-type field) visiting)))
                    (Case-fields case)))
                 (DataType-cases (program-type program name)))))

    ;; The variable reads in `expr` of names it does not bind. Names are
    ;; unique, so a name bound anywhere inside is bound at all its reads.
    ;; Keep occurrences: handler captures need each read's method evidence.
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
        (_ (concatenate (map variable-reads (expr-children expr))))))

    (: binders (-> Expr (List String)))
    (define (binders expr)
      (append (match (Expr-term expr)
                ((Lambda params _ _) params)
                ((Let name _ _) (list name))
                ((Match _ clauses)
                 (concatenate
                  (map (lambda (clause) (pattern-variables (Clause-pattern clause))) clauses)))
                (_ (Nil)))
              (concatenate (map binders (expr-children expr)))))

    (: pattern-variables (-> Pattern (List String)))
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
    (: check-places-item (-> Program Item Unit ! compile))
    (define (check-places-item program item)
      (match item
        ((Define _ value) (check-places program value))
        ((Do value) (check-places program value))
        (_ (unit))))

    (: check-places (-> Program Expr Unit ! compile))
    (define (check-places program expr)
      (match (Expr-term expr)
        ((App callee (Cons place (Cons _ (Nil))))
         (match (Expr-term callee)
           ((Var name _ _)
            (when (or (string=? name "prim:set!") (string=? name "prim:replace!"))
              (check-place-links program place)))
           (_ (unit))))
        (_ (unit)))
      (for-each (lambda (child) (check-places program child)) (expr-children expr)))

    ;; Links are followed inward to the first mutable field, whose record is
    ;; an ordinary expression.
    (: check-place-links (-> Program Expr Unit ! compile))
    (define (check-place-links program place)
      (match (place-link program place)
        ((Ok (Pair field inner))
         (unless (Field-mutable? field) (check-place-links program inner)))
        ((Err problem) (compile-error (Expr-loc place) problem))))

    (: place-link (-> Program Expr (Result (Pair Field Expr) String)))
    (define (place-link program expr)
      (match (Expr-term expr)
        ((Ann inner _) (place-link program inner))
        ((App callee (Cons record (Nil)))
         (match (Expr-term callee)
           ((Var name _ evidence)
            (match (link-field program name evidence)
              ((Ok field) (Ok (Pair field record)))
              ((Err problem) (Err problem))))
           (_ (Err not-a-place))))
        (_ (Err not-a-place))))

    (: not-a-place String)
    (define not-a-place
      "a place is a cell's content, (ref-get cell), or a chain of struct fields read from one")

    (: link-field (-> Program String (List Evidence) (Result Field String)))
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

    (: struct-field (-> Program Case I64 (Result Field String)))
    (define (struct-field program case index)
      (if (DataType-enum? (program-type program (Case-type case)))
          (Err "cannot write through an enum's case; replace the whole enum")
          (Ok (list-ref (Case-fields case) index))))

    ;; ---- Closed functions ----

    ;; A closure that may not capture reads no local of the code around it:
    ;; only its parameters, the locals it binds, globals, and, when a `let`
    ;; binds it, its own name, which the backend reads from the closure
    ;; itself. Names are unique, so a read of a name it does not bind is a
    ;; read from outside, and one the program does not know is a local.
    (: check-closed-item (-> Program Item Unit ! compile))
    (define (check-closed-item program item)
      (match item
        ((Define _ value) (check-closed program (Nil) value))
        ((Do value) (check-closed program (Nil) value))
        (_ (unit))))

    ;; `own` is the name a `let` binds the closure to, if it does.
    (: check-closed (-> Program (List String) Expr Unit ! compile))
    (define (check-closed program own expr)
      (match (Expr-term expr)
        ((Lambda _ _ captures?)
         (unless captures?
           (match (filter (lambda (read) (captured-read? program own read)) (outside-reads expr))
             ((Cons read _)
              (compile-error (Expr-loc read)
                             (string-append "a fn has no environment, so it cannot read the local "
                                            (local-name (var-name read))
                                            "; use lambda")))
             ((Nil) (unit)))))
        (_ (unit)))
      (match (Expr-term expr)
        ((Let name value body)
         (check-closed program (list name) value)
         (check-closed program (Nil) body))
        (_ (for-each (lambda (child) (check-closed program (Nil) child)) (expr-children expr)))))

    (: captured-read? (-> Program (List String) Expr Bool))
    (define (captured-read? program own read)
      (let ((name (var-name read)))
        (and (not (member? name own))
             (match (program-value program name)
               ((Some _) #f)
               ((None) #t)))))

    (: var-name (-> Expr String))
    (define (var-name read)
      (match (Expr-term read)
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
    (: check-conversions (-> Item Unit ! compile))
    (define (check-conversions item)
      (match item
        ((Define _ value) (check-expression-conversions value))
        ((Do value) (check-expression-conversions value))
        (_ (unit))))

    (: check-expression-conversions (-> Expr Unit ! compile))
    (define (check-expression-conversions expr)
      (match (Expr-term expr)
        ((Convert inner target)
         (refuse-hidden-effects "type-convert" (Expr-type inner) (Expr-loc expr))
         (refuse-hidden-effects "type-convert" target (Expr-loc expr))
         (refuse-function-reference "type-convert" (Expr-type inner) (Expr-loc expr))
         (refuse-function-reference "type-convert" target (Expr-loc expr))
         (check-through-any (Expr-type inner) target (Expr-loc expr)))
        ((TryConvert inner target)
         (refuse-hidden-effects "try-convert" target (Expr-loc expr))
         (refuse-function-reference "try-convert" target (Expr-loc expr))
         (check-through-any (Expr-type inner) target (Expr-loc expr)))
        ((TypeTest _ target)
         (refuse-hidden-effects "type-test" target (Expr-loc expr))
         (refuse-function-reference "type-test" target (Expr-loc expr)))
        (_ (unit)))
      (for-each check-expression-conversions (expr-children expr)))

    ;; A conversion changes nothing, or boxes into Any, or checks a value out
    ;; of it: there is no other representation change for it to make.
    (: check-through-any (-> Type Type Loc Unit ! compile))
    (define (check-through-any source target loc)
      (unless (or (string=? (type-key source) (type-key target))
                  (any-type? source)
                  (any-type? target))
        (compile-error loc
                       (string-append "type-convert converts to or from Any, not from "
                                      (type->string source)
                                      " to "
                                      (type->string target)))))

    ;; An Any holds a reference to a GC object, and an Fn's code reference
    ;; is not one, so neither side of a conversion is an Fn. Data holding
    ;; one is an object, and crosses.
    (: refuse-function-reference (-> String Type Loc Unit ! compile))
    (define (refuse-function-reference form type loc)
      (match type
        ((TCon "Fn" _)
         (compile-error loc
                        (string-append form
                                       " cannot take "
                                       (type->string type)
                                       ": an Any holds no function reference; wrap it in a lambda")))
        (_ (unit))))

    (: refuse-hidden-effects (-> String Type Loc Unit ! compile))
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
    (: cleanup-scope (-> Checker (List (Pair String Type)) Expr Bool (List (Pair String Type))))
    (define (cleanup-scope ck scope expr taken?)
      (let ((names (consumed-references (program-of ck) expr)))
        (filter (lambda (entry)
                  (if taken? (member? (Pair-first entry) names)
                      (not (member? (Pair-first entry) names)))) scope)))

    (: cleanup-row (-> Checker Expr Type))
    (define (cleanup-row ck callee)
      (match (Expr-term callee)
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
                                                        (Expr-type callee)))))
           (_ (cleanup-arrow-row ck (cleanup-global-type ck name types (Expr-type callee))))))
        (_ (cleanup-arrow-row ck (Expr-type callee)))))

    (: cleanup-global-type (-> Checker String (List Type) Type Type))
    (define (cleanup-global-type ck name types fallback)
      (match (global-scheme ck name)
        ((Some scheme) (substitute (zip (Scheme-vars scheme) types) (Scheme-type scheme)))
        ((None) fallback)))

    ;; A method use's row is opened to its context during checking. Its
    ;; selected instance's head supplies the declared rows instead. Every
    ;; implementation is checked against this contract, so there is no need
    ;; to look up its separate definition to recover the same information.
    (: cleanup-method-type (-> Checker String String (List Type) (List Evidence) Type Type))
    (define (cleanup-method-type ck class name types evidence fallback)
      (match evidence
        ((Cons first _)
         (match (cleanup-evidence ck first)
           ((EvInstance id arguments _)
            (match (find (lambda (instance) (string=? (Instance-name instance) id))
                         (class-instances (program-of ck) class))
              ((Some instance)
               (cleanup-global-type ck name (cleanup-method-arguments instance arguments types)
                                    fallback))
              ((None) fallback)))
           (_ (cleanup-global-type ck name types fallback))))
        (_ (cleanup-global-type ck name types fallback))))

    ;; Class parameters come first; method-local type arguments follow them.
    ;; Substitute the complete instance head, including its row variables.
    (: cleanup-method-arguments (-> Instance (List Type) (List Type) (List Type)))
    (define (cleanup-method-arguments instance arguments types)
      (let ((bindings (zip (Instance-vars instance) arguments)))
        (append (map (lambda (type) (substitute bindings type)) (Instance-types instance))
                (list-drop types (length (Instance-types instance))))))

    (: cleanup-evidence (-> Checker Evidence Evidence))
    (define (cleanup-evidence ck evidence)
      (match evidence
        ((EvHole id)
         (match (solved-evidence (solution ck) id)
           ((Some value) (cleanup-evidence ck value))
           ((None) evidence)))
        (_ evidence)))

    (: cleanup-arrow-row (-> Checker Type Type))
    (define (cleanup-arrow-row ck type)
      (match (resolve-type (solution ck) type)
        ((TFun _ _ row) row)
        ((TCon "FnOnce" (Cons inner (Nil))) (cleanup-arrow-row ck inner))
        ((TCon "Fn" (Cons inner (Nil))) (cleanup-arrow-row ck inner))
        (_ empty-row)))

    (: cleanup-control (-> Checker Type (List String)))
    (define (cleanup-control ck row)
      (let ((flat (flatten-row (solution ck) row)))
        (append (filter (lambda (label)
                          (match (table-ref (Program-effects (program-of ck)) label)
                            ((Some effect) (not (null? (Effect-control effect))))
                            ((None) #f))) (Pair-first flat))
                (match (Pair-second flat) ((None) (Nil)) (_ (list "?control"))))))

    ;; Which yields escape an expression, without entering lambdas. Declared
    ;; global rows avoid mistaking a pure call's opened use row for an effect.
    (: cleanup-yields (-> Checker Expr (List String)))
    (define (cleanup-yields ck expr)
      (match (Expr-term expr)
        ((Lambda _ _ _) (Nil))
        ((Convert inner target)
         (label-union (cleanup-yields ck inner)
                      (if (and (any-type? (resolve-type (solution ck) (Expr-type inner)))
                               (not (any-type? (resolve-type (solution ck) target))))
                          (list dyn-cast-label) (Nil))))
        ((App callee args)
         (label-union (cleanup-control ck (cleanup-row ck callee))
                      (cleanup-yields-all ck (Cons callee args))))
        ((Handle effect implementations body)
         (label-union (label-difference (cleanup-yields ck body) (list effect))
                      (fold-left (lambda (effects entry)
                                   (let ((value (Pair-second entry)))
                                     (label-union effects
                                                  (match (Expr-term value)
                                                    ((Lambda _ body _) (cleanup-yields ck body))
                                                    (_ (cleanup-control ck
                                                                        (cleanup-row ck value)))))))
                                 (Nil) implementations)))
        (_ (cleanup-yields-all ck (expr-children expr)))))

    (: cleanup-yields-all (-> Checker (List Expr) (List String)))
    (define (cleanup-yields-all ck exprs)
      (fold-left (lambda (effects expr) (label-union effects (cleanup-yields ck expr)))
                 (Nil)
                 exprs))

    (: charge-cleanup
       (-> Checker (List (Pair String Type)) (List String) Type Loc Checker ! compile))
    (define (charge-cleanup ck scope handled row loc)
      (fold-left (lambda (ck entry)
                   (let ((type (resolve-type (solution ck) (Pair-second entry))))
                     (if (or (has-meta? (solution ck) type) (not (linear? ck type))) ck
                         (match (lifecycle-rows (program-of ck) drop-class
                                                (Checker-copy ck) (Checker-givens ck) type)
                           ((Ok rows)
                            (fold-left (lambda (ck drop-row)
                                         (let ((flat (flatten-row (solution ck) drop-row)))
                                           (perform ck
                                                    (TRow
                                                     (label-difference (Pair-first flat) handled)
                                                     (Pair-second flat)) row loc))) ck rows))
                           ((Err _) ck))))) ck scope))

    ;; Earlier operands remain owned while later operands run. They are
    ;; represented as temporary owners here; ANF gives them real names later.
    (: cleanup-operands
       (-> Checker (List (Pair String Type)) (List String) (List Expr) Type Checker ! compile))
    (define (cleanup-operands ck scope handled exprs row)
      (match exprs
        ((Cons value rest)
         (let ((ck (infer-cleanup ck scope handled value row)))
           (cleanup-operands ck
                             (Cons (Pair "cleanup:operand" (Expr-type value))
                                   (cleanup-scope ck scope value #f))
                             handled rest row)))
        ((Nil) ck)))

    (: cleanup-pattern (-> Pattern (List (Pair String Type))))
    (define (cleanup-pattern pattern)
      (match pattern
        ((PVar name type) (list (Pair name type)))
        ((PCon _ args _) (concatenate (map cleanup-pattern args)))
        (_ (Nil))))

    (: infer-cleanup
       (-> Checker (List (Pair String Type)) (List String) Expr Type Checker ! compile))
    (define (infer-cleanup ck scope handled expr row)
      (match (Expr-term expr)
        ((Lambda _ _ _) ck)
        ((Let name value body)
         (let ((ck (infer-cleanup ck scope handled value row)))
           (infer-cleanup ck (Cons (Pair name (Expr-type value)) (cleanup-scope ck scope value #f))
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
                        (infer-cleanup ck (append (cleanup-pattern (Clause-pattern clause)) after)
                                       handled (Clause-body clause) row)) ck clauses)))
        ((Handle effect implementations body)
         (let* ((ck (cleanup-operands ck scope handled (map Pair-second implementations) row))
                (ck (infer-cleanup ck
                                   (cleanup-scope ck scope body #t)
                                   (Cons effect handled)
                                   body
                                   row)))
           (if (null? (cleanup-yields ck expr)) ck
               (charge-cleanup ck (cleanup-scope ck scope expr #f) handled row (Expr-loc expr)))))
        ((App callee args)
         (let ((ck (cleanup-operands ck scope handled (Cons callee args) row)))
           (if (null? (cleanup-control ck (cleanup-row ck callee))) ck
               (charge-cleanup ck (cleanup-scope ck scope expr #f) handled row (Expr-loc expr)))))
        ((Convert inner _)
         (let ((ck (infer-cleanup ck scope handled inner row)))
           (if (null? (cleanup-yields ck expr)) ck
               (charge-cleanup ck (cleanup-scope ck scope inner #f) handled row (Expr-loc expr)))))
        (_ (fold-left (lambda (ck child) (infer-cleanup ck scope handled child row))
                      ck (expr-children expr)))))

    (: cleanup-lambda (-> Checker (List String) (List Type) Expr Type Checker ! compile))
    (define (cleanup-lambda ck params types body row)
      (if (null? (cleanup-yields ck body)) ck
          (let ((captured (concatenate
                           (map (lambda (name)
                                  (match (table-ref (Checker-locals ck) name)
                                    ((Some type)
                                     (if (member? name params) (Nil) (list (Pair name type))))
                                    ((None) (Nil))))
                                (expr-references body)))))
            (infer-cleanup ck (append (zip params types) captured) (Nil) body row))))

    ;; ---- Definitions ----

    ;; An unannotated group of mutually recursive definitions is inferred
    ;; together. A group of functions is generalized; any other group stays
    ;; monomorphic, so later uses can still decide its types.
    (: check-group (-> Checker (List Item) (Pair (List Item) Checker) ! compile))
    (define (check-group ck definitions)
      (let ((before (Checker-pending-count ck)))
        (learning ck ((then (provisional-schemes definitions))
                      (results (each infer-definition definitions))
                      (then (host-effects results))
                      (then (generalize-group definitions before)))
                  (Pair (map (lambda (pair)
                               (Define (Define-name (Pair-first pair))
                                 (Pair-first (Pair-second pair))))
                             (zip definitions results))
                        (Checker-open-set ck
                                          (append (map Define-name definitions)
                                                  (Checker-open ck)))))))

    ;; Each definition in the group starts with a monomorphic metavariable, so
    ;; the group's members can refer to one another while it is inferred.
    (: provisional-schemes (-> Checker (List Item) Checker))
    (define (provisional-schemes ck definitions)
      (fold-left (lambda (ck definition)
                   (learning ck ((meta (fresh-meta)))
                             (set-scheme ck (Define-name definition) (mono-scheme meta))))
                 ck definitions))

    (: host-effects (-> Checker (List (Pair Expr Type)) Checker ! compile))
    (define (host-effects ck results)
      (fold-left (lambda (ck result)
                   (check-host-effects ck (Pair-second result) (Expr-loc (Pair-first result))))
                 ck results))

    ;; A group of functions is generalized over the constraints it raised;
    ;; any other group stays monomorphic, so later uses can still decide it.
    (: generalize-group (-> Checker (List Item) I64 Checker))
    (define (generalize-group ck definitions before)
      (if (every? (lambda (definition) (lambda-expr? (Define-value definition))) definitions)
          (generalize ck
                      definitions
                      (take (Checker-pending ck) (- (Checker-pending-count ck) before)))
          ck))

    ;; The checked value and the effect row of its initializer.
    (: infer-definition (-> Checker Item (Pair (Pair Expr Type) Checker) ! compile))
    (define (infer-definition ck definition)
      (learning ck ((row (fresh-meta))
                    (value (infer (Define-value definition) row))
                    (then (infer-cleanup (Nil) (Nil) value row))
                    (then (unify (scheme-type ck (Define-name definition))
                                 (Expr-type value)
                                 (Expr-loc value))))
                (Pair (Pair value row) ck)))

    (: scheme-type (-> Checker String Type))
    (define (scheme-type ck name)
      (match (table-ref (Checker-schemes ck) name)
        ((Some scheme) (Scheme-type scheme))
        ((None) (panic (string-append "internal error: no scheme for " name)))))

    ;; A metavariable becomes a quantified variable (`t1`, `t2`, ...) unless
    ;; something that outlives the group still mentions it: another
    ;; definition's type, or a constraint of this group.
    (: generalize (-> Checker (List Item) (List Wanted) Checker))
    (define (generalize ck definitions wanted)
      (let* ((fixed (map meta-id
                         (append (concatenate (map (lambda (name)
                                                     (free-metas (solution ck)
                                                                 (scheme-type ck name)))
                                                   (Checker-open ck)))
                                 (concatenate
                                  (map (lambda (want) (wanted-metas (solution ck) want)) wanted)))))
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
                                 (bind-solved ck (Pair-first pair) (TRigid (Pair-second pair))))
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

    (: meta-id (-> Type I64))
    (define (meta-id meta)
      (match meta
        ((TVar id) id)
        (_ -1)))

    ;; A type bound to a Copy variable. A variable of the enclosing
    ;; definition that it does not declare ω is linear, so the definition
    ;; must declare it; a concrete linear type cannot be bound at all.
    (: check-copy (-> Checker Type (List String) Loc Unit ! compile))
    (define (check-copy ck type copy loc)
      (match (copy-refusal (program-of ck)
                           copy
                           (resolve-type (solution ck) type)
                           "a type variable requires an unrestricted type")
        ((Some refusal) (compile-error loc refusal))
        ((None) (unit))))

    (: wanted-metas (-> Solution Wanted (List Type)))
    (define (wanted-metas solution want)
      (match want
        ((WantClass constraint _ _ _ _)
         (concatenate
          (map (lambda (type) (free-metas solution type)) (Constraint-types constraint))))
        ((WantLiteral _ type _) (free-metas solution type))
        ((WantCopy _ _ _) (Nil))))

    (: free-metas (-> Solution Type (List Type)))
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
    (: check-annotated (-> Checker Item Scheme (Pair Item Checker) ! compile))
    (define (check-annotated ck definition scheme)
      (within ck
              (Checker-copy-set (Checker-givens-set ck
                                                    (if (null? (Scheme-vars scheme))
                                                        (Nil)
                                                        (Scheme-constraints scheme)))
                                (Scheme-copy scheme))
              (lambda (inner) (check-annotated-value inner definition scheme))))

    (: check-annotated-value (-> Checker Item Scheme (Pair Item Checker) ! compile))
    (define (check-annotated-value ck definition scheme)
      ;; Monomorphic roots run without evidence parameters. Their closed
      ;; requirements must be proved, not assumed by their initializer.
      (learning ck ((then (want-closed-requirements scheme (Expr-loc (Define-value definition))))
                    (row (fresh-meta))
                    (value (check-value (Define-value definition) (Scheme-type scheme) row))
                    (value (fit (Scheme-type scheme) value row (Expr-loc value)))
                    (then (infer-cleanup (Nil) (Nil) value row))
                    (then (check-host-effects row (Expr-loc value))))
                (when (and (not (null? (Scheme-vars scheme))) (not (total? (solution ck) row)))
                  (compile-error (Expr-loc value)
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
    (: check-performed (-> Checker Item Scheme Unit ! compile))
    (define (check-performed ck definition scheme)
      (match (Pair (signature-loc (program-of ck) (Define-name definition))
                   (fn-arrow (Scheme-type scheme)))
        ((Pair (Some loc) (TFun _ _ row))
         (match (if (lambda-expr? (Define-value definition))
                    (unperformed-effects row (Checker-performed ck))
                    (Nil))
           ((Nil) (unit))
           (effects (let ((label (definition-label (program-of ck) (Define-name definition))))
                      (compile-error loc (unperformed-message label effects))))))
        (_ (unit))))

    ;; How an error names a definition: a default by its operation, since
    ;; its global's name is generated.
    (: definition-label (-> Program String String))
    (define (definition-label program name)
      (match (find (lambda (default) (string=? (Pair-second default) name))
                   (concatenate (map Effect-defaults (table-values (Program-effects program)))))
        ((Some default) (string-append "the default of " (short-name (Pair-first default))))
        ((None) (short-name name))))

    (: unperformed-message (-> String (List String) String))
    (define (unperformed-message label effects)
      (let ((one (= (length effects) 1)))
        (string-append label
                       " declares the effect"
                       (if one "" "s")
                       (labels->string effects)
                       " but never performs " (if one "it" "them"))))

    (: want-closed-requirements (-> Checker Scheme Loc Checker))
    (define (want-closed-requirements ck scheme loc)
      (if (null? (Scheme-vars scheme))
          (fold-left (lambda (ck constraint) (Pair-second (want-class ck constraint loc)))
                     ck
                     (Scheme-constraints scheme))
          ck))

    (: check-statement (-> Checker Expr (Pair Item Checker) ! compile))
    (define (check-statement ck expr)
      (learning ck ((row (fresh-meta))
                    (value (infer expr row))
                    (then (infer-cleanup (Nil) (Nil) value row))
                    (then (check-host-effects row (Expr-loc value))))
                (Pair (Do value) ck)))

    ;; The host may retain unrestricted values, holding managed references
    ;; opaquely. Linear ownership cannot cross this unrestricted boundary.
    ;; The trusted host respects Snail-Core types and implements the declared effects.
    ;; What is exposed is a definition's code: a foreign function, a
    ;; constructor or an operation has none.
    (: check-exposed (-> Checker String Bool Loc Checker ! compile))
    (define (check-exposed ck name dynamic loc)
      (match (program-value (program-of ck) name)
        ((Some (Defined _ _ _)) (unit))
        (_ (compile-error loc "an exposed function must be defined")))
      (match (global-scheme ck name)
        ((Some (Scheme (Nil) (Nil) _ (TFun params result row)))
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
    (: check-dynamic (-> Checker (List Type) Type Loc Unit ! compile))
    (define (check-dynamic ck types row loc)
      (unless (every?
               (lambda (type) (first-order-type? (program-of ck) (resolve-type (solution ck) type)))
               types)
        (compile-error loc
                       "a dynamic export takes and returns only data, with no function or Any inside"))
      (unless (null? (Pair-first (flatten-row (solution ck) row)))
        (compile-error loc
                       "a dynamic export cannot perform effects: the program that loads it could not check them")))

    ;; Effects performed at program start need defaults for every
    ;; operation; the builtin effects are the host's own.
    (: check-host-effects (-> Checker Type Loc Checker ! compile))
    (define (check-host-effects ck row loc)
      (for-each (lambda (label)
                  (unless (or (member? label (list "mut" "host"))
                              (let ((effect (program-effect (program-of ck) label)))
                                (= (length (Effect-defaults effect))
                                   (length (Effect-operations effect)))))
                    (compile-error loc
                                   (string-append "the effect "
                                                  (short-name label)
                                                  " has no host implementation here"))))
                (Pair-first (flatten-row (solution ck) row)))
      ck)

    ;; ---- Programs ----

    ;; A program is checked a library at a time, in program order, so each
    ;; library's types are settled within it, as they must be when libraries
    ;; are compiled apart: an unannotated value takes its type from its own
    ;; library, never from a library that imports it.
    (: check-program (-> Program Typed ! compile))
    (define (check-program program)
      (let loop ((libraries (library-items program (program-items program)))
                 (items (Nil))
                 (schemes empty-table))
        (match libraries
          ((Cons library rest)
           (let ((typed (check-library program schemes (Pair-second library))))
             (loop rest (append items (Typed-items typed)) (Typed-schemes typed))))
          ((Nil) (Typed program items schemes)))))

    ;; One library's items, checked after the libraries before it: `schemes`
    ;; holds their definitions' schemes, and the result holds those and the
    ;; new ones. Unannotated definitions are checked first, in dependency
    ;; order; then annotated definitions and statements, which only need
    ;; schemes. Then every constraint is solved and every type zonked.
    (: check-library (-> Program (Table Scheme) (List Item) Typed ! compile))
    (define (check-library program schemes items)
      (let ((ck (Checker program
                         empty-table
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
                    (for-each check-conversions (Typed-items result))
                    (let ((result
                           (Typed-items-set result (lower-conversions (Typed-items result)))))
                      (check-final result
                                   (map (lambda (function) (zonk-expr (solution ck) function))
                                        (Checker-confined ck)))
                      result)))))

    ;; The checks of a library whose types are final. Each item's, and each
    ;; confining function's, are its own, so the library fails with what
    ;; every one found, in source order.
    (: check-final (-> Typed (List Expr) Unit ! compile))
    (define (check-final typed confined)
      (let ((program (Typed-program typed)) (schemes (Typed-schemes typed)))
        (check-owned-fields program)
        (fail-if-found
         (in-source-order
          (append (failures-of (lambda (item) (check-final-item program schemes item))
                               (Typed-items typed))
                  (failures-of (lambda (function) (check-confined typed function)) confined))))))

    (: check-final-item (-> Program (Table Scheme) Item Unit ! compile))
    (define (check-final-item program schemes item)
      (check-closed-item program item)
      (check-places-item program item)
      (check-item-ownership program schemes item))

    (: check-exposures (-> Checker (List Item) Checker ! compile))
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
    (: check-items (-> Checker (List Item) (Pair (List Item) Checker) ! compile))
    (define (check-items ck items)
      (let* ((groups (each-recovered (Recovered ck (Nil) (Nil) (Nil))
                                     group-references
                                     (lambda (group) (map Define-name group))
                                     check-group
                                     (unannotated-groups ck items)))
             (results (fold-left
                       (lambda (results result) (table-set results (Define-name result) result))
                       empty-table (concatenate (Recovered-values groups))))
             (checked (each-recovered (Recovered (Recovered-checker groups)
                                                 (Nil)
                                                 (Recovered-found groups)
                                                 (Recovered-failed groups))
                                      item-references
                                      (lambda (item) (Nil))
                                      (lambda (ck item) (check-item ck results item))
                                      items)))
        (fail-if-found (in-source-order (Recovered-found checked)))
        (Pair (Recovered-values checked) (Recovered-checker checked))))

    (: group-references (-> (List Item) (List String)))
    (define (group-references definitions)
      (concatenate (map (lambda (definition) (expr-references (Define-value definition)))
                        definitions)))

    ;; A definition refers to itself too, so one whose group failed is
    ;; not checked again.
    (: item-references (-> Item (List String)))
    (define (item-references item)
      (match item
        ((Define name value) (Cons name (expr-references value)))
        ((Do value) (expr-references value))
        ((Expose name _ _ _) (list name))))

    (: unannotated-groups (-> Checker (List Item) (List (List Item))))
    (define (unannotated-groups ck items)
      (definition-groups
        (filter (lambda (item)
                  (match item
                    ((Define name _)
                     (match (annotated-scheme (program-of ck) name) ((None) #t) ((Some _) #f)))
                    (_ #f)))
                items)))

    (: check-item (-> Checker (Table Item) Item (Pair Item Checker) ! compile))
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

    (: zonk-item (-> Solution Item Item))
    (define (zonk-item solution item)
      (match item
        ((Define name value) (Define name (zonk-expr solution value)))
        ((Do value) (Do (zonk-expr solution value)))
        (_ item)))

    ;; Inferred schemes with their remaining metavariables defaulted, and the
    ;; signatures of annotated definitions.
    (: final-schemes (-> Checker (List Item) (Table Scheme)))
    (define (final-schemes ck items)
      (let ((defaulted (fold-left (lambda (ck name)
                                    (match (table-ref (Checker-schemes ck) name)
                                      ((Some scheme)
                                       (set-scheme ck
                                                   name
                                                   (Scheme (Scheme-vars scheme)
                                                           (Scheme-constraints scheme)
                                                           (Scheme-copy scheme)
                                                           (zonk (solution ck)
                                                                 (Scheme-type scheme)))))
                                      ((None) ck)))
                                  ck (Checker-open ck))))
        (Checker-schemes
         (fold-left (lambda (ck item)
                      (match item
                        ((Define name _)
                         (match (annotated-scheme (program-of ck) name)
                           ((Some scheme) (set-scheme ck name scheme))
                           ((None) ck)))
                        (_ ck)))
                    defaulted items))))

    (: annotated-scheme (-> Program String (Option Scheme)))
    (define (annotated-scheme program name)
      (match (program-value program name)
        ((Some (Defined scheme _ _)) scheme)
        (_ (None))))

    ;; Where a definition's own signature was written, if it has one.
    (: signature-loc (-> Program String (Option Loc)))
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
            (-> (Recovered B)
                (-> A (List String))
                (-> A (List String))
                (-> Checker A (Pair B Checker) ! compile)
                (List A)
                (Recovered B) ! compile)))
    (define (each-recovered start references names step items)
      (let ((done (fold-left (lambda (done item) (recover done references names step item))
                             start
                             items)))
        (Recovered-values-set done (reverse (Recovered-values done)))))

    (: recover
       (All (A B) (requires (Copy A) (Copy B))
            (-> (Recovered B)
                (-> A (List String))
                (-> A (List String))
                (-> Checker A (Pair B Checker) ! compile)
                A
                (Recovered B) ! compile)))
    (define (recover done references names step item)
      (let ((failed (Recovered-failed done)))
        (if (any? (lambda (name) (member? name failed)) (references item))
            (Recovered-failed-set done (append (names item) failed))
            (match (recovering (lambda () (step (Recovered-checker done) item)))
              ((Ok (Pair value ck))
               (Recovered ck (Cons value (Recovered-values done)) (Recovered-found done) failed))
              ((Err found)
               (Recovered-failed-set
                (Recovered-found-set done (append (Recovered-found done) (diagnostics->list found)))
                (append (names item) failed)))))))

    ;; ---- Dependency order ----

    ;; The definitions in groups that refer to one another, each group after
    ;; the groups it refers to. Definitions are numbered in program order.
    (: definition-groups (-> (List Item) (List (List Item))))
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
    (: definition-edges (-> (Table I64) Item (List I64)))
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

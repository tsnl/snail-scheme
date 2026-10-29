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
   (snail shell compiler ownership))
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
    ;; type variables declared ω there, which decide what a drop releases;
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
                                                      (labels->string labels))))))))))

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
                         (then (unify (TCon "Bool" (Nil)) (Expr-type test) (Expr-loc test)))
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
           (learning ck ((inner (infer inner row))
                         (then (unify type (Expr-type inner) loc)))
                     (Pair inner ck)))
          ((Handle effect implementations body)
           (infer-handle ck effect implementations body row loc))
          ;; The direction is decided once types are ground: to Any, from
          ;; Any, or nothing when the types already agree.
          ((Convert inner target)
           (learning ck ((inner (infer inner row)))
                     (Pair (Expr (Convert inner target) target loc) ck)))
          ;; Whether an Any holds a value of the target type.
          ((TypeTest inner target)
           (learning ck ((inner (infer inner row))
                         (then (unify (TCon "Any" (Nil)) (Expr-type inner) (Expr-loc inner))))
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
                    (body (scoped (bind-locals ck params types) body body-row)))
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
      (match (Expr-term expr)
        ((Lambda params body captures?)
         (match (prune (solution ck) type)
           ((TFun param-types result body-row)
            (if (= (length params) (length param-types))
                (check-lambda ck expr params body captures? type param-types result body-row)
                (infer ck expr row)))
           (_ (infer ck expr row))))
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
                                    (if (forbids-mut? (solution inner) body-row)
                                        (check-confining-body inner body row)
                                        (infer inner body row)))))
                    (then (unify result (Expr-type body) (Expr-loc body))))
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
                      (then (unify-call (Expr-type callee) args result latent loc))
                      (then (perform latent row loc))
                      (then (solve-drops before row)))
                  (Pair (Expr (App callee args) result loc) ck))))

    ;; Arguments are compared one by one, so a mismatch names its argument.
    (: unify-call (-> Checker Type (List Expr) Type Type Loc Checker ! compile))
    (define (unify-call ck callee-type args result latent loc)
      (match (prune (solution ck) callee-type)
        ((TFun params callee-result row)
         (unless (= (length params) (length args))
           (compile-error loc
                          (string-append "expected "
                                         (i64->string (length params))
                                         " arguments, found "
                                         (i64->string (length args)))))
         (learning ck ((then (unify-arguments params args))
                       (then (unify callee-result result loc)))
                   (unify ck row latent loc)))
        ((TVar _) (unify ck callee-type (TFun (map Expr-type args) result latent) loc))
        ;; Calling a `FnOnce` calls the procedure it holds; ownership consumes it.
        ((TCon "FnOnce" (Cons procedure (Nil))) (unify-call ck procedure args result latent loc))
        (other (compile-error loc (string-append "not a function: " (type->string other))))))

    (: unify-arguments (-> Checker (List Type) (List Expr) Checker ! compile))
    (define (unify-arguments ck params args)
      (fold-left (lambda (ck pair)
                   (unify ck
                          (Pair-first pair)
                          (Expr-type (Pair-second pair))
                          (Expr-loc (Pair-second pair))))
                 ck (zip params args)))

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
                      (then (unify result (Expr-type body) (Expr-loc body)))
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
        ((Pair (Lambda params body captures?) (TFun types _ _))
         (if (= (length params) (length types))
             (infer-lambda-at ck params body captures? types (Expr-loc value))
             (infer ck value row)))
        (_ (infer ck value row))))

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
    ;; except a drop's, which charges its row: most are solved at their call
    ;; (`solve-drops`), and one left until now is a drop of a type that a
    ;; later use decided.
    (: solve-pending (-> Checker Checker ! compile))
    (define (solve-pending ck)
      (let ((pending (reverse (Checker-pending ck))))
        (learning ck ((then (default-literals pending #t))
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
      (if (string=? (Constraint-class constraint) drop-class)
          (solve-drop ck constraint hole givens copy (None) loc)
          (match (find-evidence ck constraint givens loc)
            ((Some evidence) (with-evidence ck hole evidence))
            ((None) (compile-error loc (ambiguous-constraint ck constraint))))))

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

    ;; `(Drop e T)`'s row is found from T, not matched: dropping a T runs
    ;; what releases one (`drop-rows`), and each row that performs is
    ;; performed in `e`. Mono finds the release again from the ground
    ;; type, so the evidence only says so. `context` is the row of the call
    ;; the drop was raised in, when it is solved there.
    (: solve-drop
       (-> Checker
           Constraint
           I64
           (List Constraint)
           (List String)
           (Option Type)
           Loc
           Checker
           ! compile))
    (define (solve-drop ck constraint hole givens copy context loc)
      (match (Constraint-types constraint)
        ((Cons row (Cons type (Nil)))
         (let ((type (resolve-type (solution ck) type)))
           (when (has-meta? (solution ck) type)
             (compile-error loc (ambiguous-constraint ck constraint)))
           (match (drop-rows (program-of ck) copy givens type)
             ((Ok rows)
              (with-evidence
               (fold-left (lambda (ck performed) (charge-drop ck performed row context loc))
                          ck
                          rows)
               hole
               (EvDerived)))
             ((Err message) (compile-error loc message)))))
        (_ (panic "internal error: Drop has a row and a type"))))

    ;; A drop performs `performed` in its own row. When that row has joined
    ;; the call's context, as it has when the drop is called there or
    ;; handed to a callee that calls it, the context performs it too, which
    ;; a signed body counts (`record-performed`); a drop only stored, as in
    ;; a struct, charges nothing here.
    (: charge-drop (-> Checker Type Type (Option Type) Loc Checker ! compile))
    (define (charge-drop ck performed row context loc)
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

    ;; A drop is charged where it is written: once a call is checked, each
    ;; Drop constraint raised in it whose type is known by now is solved in
    ;; the call's scope, so a signed body is seen to perform what its drops
    ;; do. One whose type a later use decides waits for `solve-pending`.
    (: solve-drops (-> Checker I64 Type Checker ! compile))
    (define (solve-drops ck before context)
      (let* ((count (- (Checker-pending-count ck) before))
             (recent (take (Checker-pending ck) count))
             (older (list-drop (Checker-pending ck) count)))
        (if (any? (lambda (want) (known-drop? ck want)) recent)
            (match (fold-left (lambda (progress want) (solve-known-drop progress want context))
                              (Pair (Nil) ck)
                              (reverse recent))
              ((Pair kept ck)
               (Checker-pending-count-set (Checker-pending-set ck (append kept older))
                                          (+ before (length kept)))))
            ck)))

    ;; One wanted constraint, oldest first: solved when it is a drop of a
    ;; known type, and otherwise kept, newest first, as `pending` keeps them.
    (: solve-known-drop
       (-> (Pair (List Wanted) Checker) Wanted Type (Pair (List Wanted) Checker) ! compile))
    (define (solve-known-drop progress want context)
      (match progress
        ((Pair kept ck)
         (match want
           ((WantClass constraint hole givens copy loc)
            (if (known-drop? ck want)
                (Pair kept (solve-drop ck constraint hole givens copy (Some context) loc))
                (Pair (Cons want kept) ck)))
           (_ (Pair (Cons want kept) ck))))))

    (: known-drop? (-> Checker Wanted Bool))
    (define (known-drop? ck want)
      (match want
        ((WantClass constraint _ _ _ _)
         (and (string=? (Constraint-class constraint) drop-class)
              (match (Constraint-types constraint)
                ((Cons _ (Cons type (Nil))) (not (has-meta? (solution ck) type)))
                (_ #f))))
        (_ #f)))

    ;; Evidence from the enclosing definition's requirements, or from the
    ;; unique instance whose head matches. None while the types are ambiguous.
    (: find-evidence (-> Checker Constraint (List Constraint) Loc (Option Evidence) ! compile))
    (define (find-evidence ck constraint givens loc)
      (let ((types
             (map (lambda (type) (resolve-type (solution ck) type)) (Constraint-types constraint))))
        (if (any? (lambda (type) (has-meta? (solution ck) type)) types)
            (None)
            (match (given-evidence (Constraint-class constraint) types givens)
              ((Some evidence) (Some evidence))
              ((None)
               (Some (instance-evidence ck (Constraint-class constraint) types givens loc)))))))

    (: given-evidence (-> String (List Type) (List Constraint) (Option Evidence)))
    (define (given-evidence class types givens)
      (match (list-index (lambda (given)
                           (and (string=? class (Constraint-class given))
                                (types=? types (Constraint-types given))))
                         givens)
        ((Some index) (Some (EvParam index)))
        ((None) (None))))

    (: instance-evidence (-> Checker String (List Type) (List Constraint) Loc Evidence ! compile))
    (define (instance-evidence ck class types givens loc)
      (let loop ((instances (class-instances (program-of ck) class)))
        (match instances
          ((Nil)
           (compile-error loc (string-append "no instance for " (constraint->string class types))))
          ((Cons instance rest)
           (match (match-types (Instance-vars instance) (Instance-types instance) types (Nil))
             ((Some bindings)
              (EvInstance (Instance-name instance)
                          (map (lambda (var)
                                 (match (assoc-ref bindings var)
                                   ((Some type) type)
                                   ((None) (TCon "Unit" (Nil)))))
                               (Instance-vars instance))
                          (map (lambda (requirement)
                                 (requirement-evidence ck
                                                       (substitute-constraint bindings requirement)
                                                       givens
                                                       loc))
                               (Instance-requires instance))))
             ((None) (loop rest)))))))

    (: requirement-evidence (-> Checker Constraint (List Constraint) Loc Evidence ! compile))
    (define (requirement-evidence ck requirement givens loc)
      (match (find-evidence ck requirement givens loc)
        ((Some evidence) evidence)
        ((None)
         (compile-error loc (string-append "ambiguous requirement "
                                           (constraint->string (Constraint-class requirement)
                                                               (Constraint-types requirement)))))))

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
      (type->string (TCon class types)))

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
        (_ (concatenate (map variable-reads (subexpressions expr))))))

    (: binders (-> Expr (List String)))
    (define (binders expr)
      (append (match (Expr-term expr)
                ((Lambda params _ _) params)
                ((Let name _ _) (list name))
                ((Match _ clauses)
                 (concatenate
                  (map (lambda (clause) (pattern-variables (Clause-pattern clause))) clauses)))
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
        ((Lambda _ body _) (list body))
        ((App callee args) (Cons callee args))
        ((If test then otherwise) (list test then otherwise))
        ((Let _ value body) (list value body))
        ((Seq first rest) (list first rest))
        ((Match scrutinee clauses) (Cons scrutinee (map Clause-body clauses)))
        ((Ann inner _) (list inner))
        ((Convert inner _) (list inner))
        ((TypeTest inner _) (list inner))
        ((Handle _ implementations body) (append (map Pair-second implementations) (list body)))))

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
        (_ (for-each (lambda (child) (check-closed program (Nil) child)) (subexpressions expr)))))

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
         (check-through-any (Expr-type inner) target (Expr-loc expr)))
        ((TypeTest _ target) (refuse-hidden-effects "type-test" target (Expr-loc expr)))
        (_ (unit)))
      (for-each check-expression-conversions (subexpressions expr)))

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
      (let ((type (resolve-type (solution ck) type)) (program (program-of ck)))
        (when (linear-type? program copy type)
          (compile-error loc
                         (match (missing-copy program copy type)
                           ((Nil)
                            (string-append "a type variable requires an unrestricted type, and "
                                           (type->string type)
                                           " is linear"))
                           (names
                            (string-append "this use needs "
                                           (copy-declaration names)
                                           ", which the definition must require")))))))

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
                    (then (unify (Scheme-type scheme) (Expr-type value) (Expr-loc value)))
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
    ;; neither is held to it.
    (: check-performed (-> Checker Item Scheme Unit ! compile))
    (define (check-performed ck definition scheme)
      (match (Pair (signature-loc (program-of ck) (Define-name definition)) (Scheme-type scheme))
        ((Pair (Some loc) (TFun _ _ row))
         (match (if (lambda-expr? (Define-value definition))
                    (unperformed-effects row (Checker-performed ck))
                    (Nil))
           ((Nil) (unit))
           (effects (compile-error loc (unperformed-message (Define-name definition) effects)))))
        (_ (unit))))

    (: unperformed-message (-> String (List String) String))
    (define (unperformed-message name effects)
      (let ((one (= (length effects) 1)))
        (string-append (short-name name)
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
        ((Some (Defined _ _)) (unit))
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
        (learning ck ((inferred (check-inferred items))
                      (typed (each (lambda (ck item) (check-item ck inferred item)) items))
                      (then (solve-pending))
                      (then (check-exposures items)))
                  (let ((result
                         (Typed program (map (lambda (item) (zonk-item (solution ck) item)) typed)
                                (final-schemes ck items))))
                    (for-each check-conversions (Typed-items result))
                    (for-each (lambda (item) (check-closed-item program item)) (Typed-items result))
                    (check-owned-types program (Typed-schemes result) (Typed-items result))
                    (check-ownership program (Typed-schemes result) (Typed-items result))
                    (for-each
                     (lambda (function) (check-confined result (zonk-expr (solution ck) function)))
                     (Checker-confined ck))
                    result))))

    (: check-exposures (-> Checker (List Item) Checker ! compile))
    (define (check-exposures ck items)
      (fold-left (lambda (ck item)
                   (match item
                     ((Expose name _ dynamic loc) (check-exposed ck name dynamic loc))
                     (_ ck)))
                 ck items))

    ;; Checks the definitions without signatures, a group at a time in
    ;; dependency order, and returns them by name.
    (: check-inferred (-> Checker (List Item) (Pair (Table Item) Checker) ! compile))
    (define (check-inferred ck items)
      (learning ck ((groups (each check-group (unannotated-groups ck items))))
                (Pair (fold-left
                       (lambda (results result) (table-set results (Define-name result) result))
                       empty-table (concatenate groups))
                      ck)))

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
        ((Some (Defined scheme _)) scheme)
        (_ (None))))

    ;; Where a definition's own signature was written, if it has one.
    (: signature-loc (-> Program String (Option Loc)))
    (define (signature-loc program name)
      (match (program-value program name)
        ((Some (Defined _ loc)) loc)
        (_ (None))))

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
        (expect (unperformed-message "main:double" (list "mut"))
                "double declares the effect mut but never performs it")
        (expect (unperformed-message "main:f" (list "snail.core.io:console" "e"))
                "f declares the effects console e but never performs them"))))
   (else)))

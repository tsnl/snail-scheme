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
   (snail shell compiler ownership))
  (begin

    ;; ---- Checker state ----

    ;; Scope holds the names and class requirements visible at this point.
    ;; Learning holds the substitutions and obligations accumulated so far.
    ;; A signed body's row identity records which declared effects it uses;
    ;; nested lambdas restore the enclosing body's record on return.
    (struct Checker
      ((program Program)
       (locals (Table Type))
       (givens (List Constraint))
       (copy (List String))
       (instances (List String))
       (resolving (List Constraint))
       (signed (Option I64))
       (counter I64)
       (solution Solution)
       (schemes (Table Scheme))
       (pending (List Wanted))
       (pending-count I64)
       (open (List String))
       (performed (List Type))))

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

    (define (resumed (outer Checker) (inner Checker)) (→ Checker)
      (Checker (● outer program)
               (● outer locals)
               (● outer givens)
               (● outer copy)
               (● outer instances)
               (● outer resolving)
               (● outer signed)
               (● inner counter)
               (● inner solution)
               (● inner schemes)
               (● inner pending)
               (● inner pending-count)
               (● inner open)
               (● inner performed)))

    ;; What checking has learned: each metavariable's identity to the type it
    ;; stands for, and each evidence hole's to its evidence. A `Type` and an
    ;; `Expr` are plain data, so reading one means reading it through a
    ;; solution. `check-library` allocates one, refines it, and zonks it away
    ;; before returning, so neither it nor a metavariable outlives the call.
    (struct Solution
      ((types (Table Type))
       (evidence (Table Evidence))
       (projections (Table Expr))))

    (define empty-solution (→ Solution) (Solution empty-table empty-table empty-table))

    ;; Identities are dense small integers from one counter, so a key is just
    ;; its decimal text.

    (define (identity-key (id I64)) (→ String)
      (i64->string id))

    (define (solved-type (solution Solution) (id I64)) (→ (Option Type))
      (table-ref (● solution types) (identity-key id)))

    (define (solved-evidence (solution Solution) (id I64)) (→ (Option Evidence))
      (table-ref (● solution evidence) (identity-key id)))

    ;; A class constraint keeps the givens in scope where it arose, and the
    ;; type variables declared ω there, which decide what a drop releases
    ;; and a clone shares;
    ;; a Copy requirement keeps those variables too.
    ;; A selection waiting for its receiver's nominal type. The result and
    ;; surrounding row participate in inference; Copy determines whether a
    ;; field can be read without moving it out of its aggregate.
    (struct Projection
      ((record Expr)
       (label String)
       (result Type)
       (row Type)
       (hole I64)
       (copy (List String))
       (loc Loc)))

    (enum Wanted
      (WantPerformed ((name String) (declared Type) (performed (List Type)) (loc Loc)))
      (WantInclusion ((latent Type) (context Type) (loc Loc)))
      (WantEscape
       ((scope (List (Pair String Type)))
        (expression Expr)
        (row Type)
        (handled (List String))
        (givens (List Constraint))
        (copy (List String))))
      (WantField ((projection Projection)))
      (WantClass
       ((constraint Constraint)
        (hole I64)
        (givens (List Constraint))
        (copy (List String))
        (instances (List String))
        (loc Loc)))
      (WantCleanup
       ((type Type)
        (row Type)
        (handled (List String))
        (givens (List Constraint))
        (copy (List String))
        (shared-only? Bool)
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

    (define (definition-scheme (typed Typed) (name String)) (→ Scheme)
      (match (table-ref (● typed schemes) name)
        ((Some scheme) scheme)
        ((None) (panic (string-append "internal error: no scheme for " name)))))

    (define (program-of (ck Checker)) (→ Program)
      (● ck program))

    (define (solution (ck Checker)) (→ Solution)
      (● ck solution))

    ;; A linear query reads a type's structure, so it needs the solution
    ;; applied first; a metavariable on its own is not known to be linear.

    (define (linear? (ck Checker) (type Type)) (→ Bool)
      (linear-type? (program-of ck) (● ck copy) (resolve-type (solution ck) type)))

    (define (bind-solved (ck Checker) (meta Type) (type Type)) (→ Checker)
      (match meta
        ((TVar id) (Checker-solution-set ck
                                         (Solution-types-set (solution ck)
                                                             (table-set (● (solution ck) types)
                                                                        (identity-key id)
                                                                        type))))
        (_ (panic "internal error: expected TVar"))))

    (define (fresh-identity (ck Checker)) (→ (Pair I64 Checker))
      (let ((id (+ (● ck counter) 1)))
        (Pair id (Checker-counter-set ck id))))

    ;; ---- Metavariables and unification ----

    (define (fresh-meta (ck Checker)) (→ (Pair Type Checker))
      (learning ck ((id (fresh-identity)))
                (Pair (TVar id) ck)))

    (define (meta? (type Type)) (→ Bool)
      (match type
        ((TVar _) #t)
        (_ #f)))

    (define (same-meta? (a Type) (b Type)) (→ Bool)
      (match a
        ((TVar id) (match b ((TVar other) (= id other)) (_ #f)))
        (_ #f)))

    ;; The type a metavariable stands for, following a chain of bindings.
    ;; `bind?` always binds a pruned type, so a chain is short.

    (define (prune (solution Solution) (type Type)) (→ Type)
      (match type
        ((TVar id)
         (match (solved-type solution id)
           ((Some bound) (prune solution bound))
           ((None) type)))
        (_ type)))

    (define (unify (ck Checker) (expected Type) (actual Type) (loc Loc)) (→ Checker) (! compile)
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

    (define (unify? (ck Checker) (a Type) (b Type)) (→ (Pair Bool Checker))
      (let ((a (prune (solution ck) a)) (b (prune (solution ck) b)))
        (cond ((same-meta? a b) (Pair #t ck))
              ((meta? a) (bind? ck a b))
              ((meta? b) (bind? ck b a))
              (else (unify-structure? ck a b)))))

    (define (unify-all? (ck Checker) (as (List Type)) (bs (List Type))) (→ (Pair Bool Checker))
      (if (= (length as) (length bs))
          (fold-left (lambda (done pair)
                       (if (● done first)
                           (unify? (● done second) (● pair first) (● pair second))
                           done))
                     (Pair #t ck) (zip as bs))
          (Pair #f ck)))

    (define (unify-structure? (ck Checker) (a Type) (b Type)) (→ (Pair Bool Checker))
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

    (define (unify-function? (ck Checker)
                             (params (List Type))
                             (result Type)
                             (row Type)
                             (others (List Type))
                             (other-result Type)
                             (other-row Type))
      (→ (Pair Bool Checker))
      (learning ck ((parameters (unify-all? params others)))
                (if (not parameters)
                    (Pair #f ck)
                    (learning ck ((results (unify? result other-result)))
                              (if (not results) (Pair #f ck) (unify-rows? ck row other-row))))))

    (define (bind? (ck Checker) (meta Type) (type Type)) (→ (Pair Bool Checker))
      (if (occurs? (solution ck) meta type)
          (Pair #f ck)
          (Pair #t (bind-solved ck meta type))))

    (define (occurs? (solution Solution) (meta Type) (type Type)) (→ Bool)
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

    (define (flatten-row (solution Solution) (row Type)) (→ (Pair (List String) (Option Type)))
      (let ((row (prune solution row)))
        (match row
          ((TRow labels (None)) (Pair labels (None)))
          ((TRow labels (Some tail))
           (let ((rest (flatten-row solution tail)))
             (Pair (label-union labels (● rest first)) (● rest second))))
          (_ (Pair (Nil) (Some row))))))

    (define (meta-tail? (tail (Option Type))) (→ Bool)
      (match tail
        ((Some type) (meta? type))
        ((None) #f)))

    (define (same-tail? (a (Option Type)) (b (Option Type))) (→ Bool)
      (match a
        ((None) (match b ((None) #t) ((Some _) #f)))
        ((Some (TRigid name)) (match b ((Some (TRigid other)) (string=? name other)) (_ #f)))
        ((Some x) (match b ((Some y) (same-meta? x y)) ((None) #f)))))

    ;; Rows unify as sets: shared labels match, and each open tail absorbs the
    ;; labels only the other side has.

    (define (unify-rows? (ck Checker) (a Type) (b Type)) (→ (Pair Bool Checker))
      (let* ((left (flatten-row (solution ck) a)) (right (flatten-row (solution ck) b))
             (only-left (label-difference (● left first) (● right first)))
             (only-right (label-difference (● right first) (● left first)))
             (left-tail (● left second)) (right-tail (● right second)))
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

    (define (tail-type (tail (Option Type))) (→ Type)
      (match tail
        ((Some type) type)
        ((None) (panic "internal error: closed row"))))

    ;; Calls require inclusion, while stored function types remain invariant.
    ;; Unknown latent effects stay as obligations until class resolution has
    ;; supplied their lower bounds. Neither pure nor the whole caller row is
    ;; a valid early guess for an unresolved callback or destructor.
    (define (perform (ck Checker) (latent Type) (row Type) (loc Loc)) (→ Checker) (! compile)
      (let ((ck (record-performed ck row latent)))
        (learning ck ((included (propagate-inclusion latent row loc)))
                  (if included ck (want ck (WantInclusion latent row loc))))))

    (define (propagate-inclusion (ck Checker) (latent Type) (row Type) (loc Loc))
      (→ (Pair Bool Checker)) (! compile)
      (let* ((source (flatten-row (solution ck) latent))
             (target (flatten-row (solution ck) row))
             (missing (label-difference (● source first) (● target first))))
        (if (null? missing)
            (if (and (meta-tail? (● target second))
                     (match (● source second) ((Some (TRigid _)) #t) (_ #f)))
                (learning ck ((then (unify (tail-type (● target second))
                                           (tail-type (● source second)) loc)))
                          (Pair #t ck))
                (if (and (match (● source second) ((Some (TRigid _)) #t) (_ #f))
                         (not (same-tail? (● source second) (● target second))))
                    (effect-refusal ck latent loc)
                    (Pair (or (match (● source second) ((None) #t) (_ #f))
                              (same-tail? (● source second) (● target second))) ck)))
            (if (meta-tail? (● target second))
                (learning ck ((tail (fresh-meta))
                              (then (unify (tail-type (● target second))
                                           (TRow missing (Some tail)) loc)))
                          (propagate-inclusion ck latent row loc))
                (effect-refusal ck latent loc)))))

    (define (effect-refusal (ck Checker) (latent Type) (loc Loc)) (→ T) (! compile) (∀ (T))
      (let ((flat (flatten-row (solution ck) latent)))
        (compile-error loc
                       (string-append "this performs effects its context does not allow:"
                                      (labels->string (append (● flat first)
                                                              (tail-variable (● flat second))))))))

    ;; Propagation can expose a label through several calls. Each growth
    ;; allocates a fresh tail, so the counter also detects a fixed point.
    (define (propagate-inclusions (ck Checker)) (→ Checker) (! compile)
      (let* ((before (● ck counter))
             (ck (fold-left propagate-wanted-inclusion ck (reverse (● ck pending)))))
        (if (= before (● ck counter)) ck (propagate-inclusions ck))))

    (define (solve-inclusions (ck Checker)) (→ Checker) (! compile)
      (let ((ck (propagate-inclusions ck)))
        (fold-left finish-wanted-inclusion ck (reverse (● ck pending)))))

    (define (propagate-wanted-inclusion (ck Checker) (want Wanted)) (→ Checker) (! compile)
      (match want
        ((WantInclusion latent row loc) (● (propagate-inclusion ck latent row loc) second))
        (_ ck)))

    ;; Residual tails share one row variable. This conservative completion
    ;; avoids adding bounded-row schemes; a closed allowance closes a still
    ;; unconstrained source tail only after all class and cleanup obligations.
    (define (finish-wanted-inclusion (ck Checker) (want Wanted)) (→ Checker) (! compile)
      (match want
        ((WantInclusion latent row loc)
         (learning ck ((included (propagate-inclusion latent row loc)))
                   (if included ck
                       (let ((source (flatten-row (solution ck) latent))
                             (target (flatten-row (solution ck) row)))
                         (learning ck ((agreed (unify? (tail-type (● source second))
                                                       (match (● target second)
                                                         ((Some tail) tail) ((None) empty-row)))))
                                   (if agreed ck (effect-refusal ck latent loc)))))))
        (_ ck)))

    ;; Whether `row` is the row variable that `variable` names, if any.

    (define (row-variable? (variable (Option I64)) (row Type)) (→ Bool)
      (match (Pair variable row)
        ((Pair (Some number) (TVar id)) (= number id))
        (_ #f)))

    ;; Preserve the row itself: generic evidence and cleanup may determine
    ;; its effects later. The final check reads it through the solved types.
    (define (record-performed (ck Checker) (row Type) (effects Type)) (→ Checker)
      (if (row-variable? (● ck signed) row)
          (Checker-performed-set ck (Cons effects (● ck performed))) ck))

    (define (tail-variable (tail (Option Type))) (→ (List String))
      (match tail
        ((Some (TRigid name)) (list name))
        (_ (Nil))))

    ;; The effects a declared row names that no call performed: its labels
    ;; and its tail variable, less those `performed` records.

    (define (unperformed-effects (declared Type) (performed (List String))) (→ (List String))
      (let ((flat (flatten-row empty-solution declared)))
        (label-difference (append (● flat first) (tail-variable (● flat second))) performed)))

    (define (total? (solution Solution) (row Type)) (→ Bool)
      (null? (● (flatten-row solution row) first)))

    ;; ---- Instantiation ----

    (define (want (ck Checker) (wanted Wanted)) (→ Checker)
      (Checker-pending-count-set (Checker-pending-set ck (Cons wanted (● ck pending)))
                                 (+ (● ck pending-count) 1)))

    (define (want-class (ck Checker) (constraint Constraint) (loc Loc)) (→ (Pair Evidence Checker))
      (learning ck ((hole (fresh-identity))
                    (then
                     (want (WantClass constraint
                                      hole
                                      (● ck givens)
                                      (● ck copy)
                                      (● ck instances)
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

    (define (instantiate (ck Checker) (scheme Scheme) (loc Loc)) (→ (Pair Instantiated Checker))
      (learning ck ((metas (fresh-bindings (● scheme vars)))
                    (type (open-row (substitute metas (● scheme type))))
                    (evidence (each (lambda (ck constraint)
                                      (want-class ck (substitute-constraint metas constraint) loc))
                                    (● scheme constraints)))
                    (then (want-each (copy-requirements ck scheme metas loc))))
                (Pair (Instantiated type (map (lambda (record) (● record second)) metas) evidence)
                      ck)))

    ;; The types a use binds to the variables its scheme declares ω must be
    ;; ω where it is: concrete types without a linear part, or variables the
    ;; enclosing definition declares ω in turn. The other variables may
    ;; take linear types.

    (define (copy-requirements (ck Checker) (scheme Scheme) (metas Substitution) (loc Loc))
      (→ (List Wanted))
      (map (lambda (meta) (WantCopy (● meta second) (● ck copy) loc))
           (filter (lambda (meta) (member? (● meta first) (● scheme copy))) metas)))

    ;; A fresh metavariable per quantified variable, in order.

    (define (fresh-bindings (ck Checker) (vars (List String))) (→ (Pair Substitution Checker))
      (each ck
            (lambda (ck var) (learning ck ((meta (fresh-meta))) (Pair (Pair var meta) ck)))
            vars))

    (define (want-each (ck Checker) (wanted (List Wanted))) (→ Checker)
      (fold-left want ck wanted))

    ;; `step` over each item in order, threading the checker and collecting
    ;; the values, so a sequence of learning steps is itself one step.

    (define (each (ck Checker) (step (Fn Checker A → (Pair B Checker) ! e)) (items (List A)))
      (→ (Pair (List B) Checker))
      (! e)
      (∀ (A B e))
      (⊨ (Copy B) (Drop e B))
      (let ((done (fold-left (lambda (done item)
                               (match (step (● done second) item)
                                 ((Pair value ck) (Pair (Cons value (● done first)) ck))))
                             (Pair (Nil) ck) items)))
        (Pair (reverse (● done first)) (● done second))))

    (define (open-row (ck Checker) (type Type)) (→ (Pair Type Checker))
      (match (prune (solution ck) type)
        ((TFun params result (TRow labels (None)))
         (learning ck ((tail (fresh-meta)))
                   (Pair (TFun params result (TRow labels (Some tail))) ck)))
        ((TCon name (Cons arrow captures))
         (Pair type ck))
        (_ (Pair type ck))))

    (define (global-scheme (ck Checker) (name String)) (→ (Option Scheme))
      (match (table-ref (● ck schemes) name)
        ((Some scheme) (Some scheme))
        ((None)
         (match (program-value (program-of ck) name)
           ((Some value)
            (match (value-scheme value)
              ((Some scheme) (Some scheme))
              ((None) (None))))
           ((None) (None))))))

    ;; Names are unique, so a local's type is in scope exactly where its
    ;; binding form passes the extended checker.

    (define (bind-local (ck Checker) (name String) (type Type)) (→ Checker)
      (Checker-locals-set ck (table-set (● ck locals) name type)))

    (define (bind-locals (ck Checker) (names (List String)) (types (List Type))) (→ Checker)
      (fold-left (lambda (ck pair) (bind-local ck (● pair first) (● pair second)))
                 ck
                 (zip names types)))

    (define (set-scheme (ck Checker) (name String) (scheme Scheme)) (→ Checker)
      (Checker-schemes-set ck (table-set (● ck schemes) name scheme)))

    (define (variable-type (ck Checker) (name String) (loc Loc))
      (→ (Pair Instantiated Checker))
      (! compile)
      (match (table-ref (● ck locals) name)
        ((Some local) (Pair (Instantiated local (Nil) (Nil)) ck))
        ((None)
         (match (global-scheme ck name)
           ((Some scheme) (instantiate ck scheme loc))
           ((None) (compile-error loc (string-append "internal error: no type for " name)))))))

    ;; ---- Expressions ----

    (define (literal-type (ck Checker) (value Datum) (loc Loc)) (→ (Pair Type Checker))
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

    (define (infer (ck Checker) (expr Expr) (row Type)) (→ (Pair Expr Checker)) (! compile)
      (let ((loc (● expr loc)))
        (match (● expr term)
          ((Lit value)
           (learning ck ((type (literal-type value loc)))
                     (Pair (Expr (Lit value) type loc) ck)))
          ((Var name _ _)
           (learning ck ((use (variable-type name loc)))
                     (Pair (Expr (Var name (● use types) (● use evidence))
                                 (● use type)
                                 loc)
                           ck)))
          ((Lambda params body captures?) (infer-lambda ck params body captures? loc))
          ((App callee args) (infer-app ck callee args row loc))
          ((FieldRead record label _) (infer-field-read ck record label row loc))
          ;; `then` is `learning`'s own keyword, so the branches are named
          ;; for what they are rather than by their field names.
          ((If test consequent alternative)
           (learning ck ((test (infer test row))
                         (consequent (infer consequent row))
                         (alternative (infer alternative row))
                         (test (fit (TCon "Bool" (Nil)) test row (● test loc)))
                         (then (unify (● consequent type)
                                      (● alternative type)
                                      (● alternative loc))))
                     (Pair (Expr (If test consequent alternative) (● consequent type) loc) ck)))
          ((Let name value body) (infer-let ck name value body row loc))
          ((Seq first rest)
           (learning ck ((first (infer first row))
                         (rest (infer rest row)))
                     (Pair (Expr (Seq first rest) (● rest type) loc) ck)))
          ((Match scrutinee clauses) (infer-match ck scrutinee clauses row loc))
          ((ScopedInstances sets body)
           (scoped ck (instance-scope ck sets loc) body row))
          ((Ann inner type)
           (learning ck ((inner (check-value inner type row)))
                     (fit ck type inner row loc)))
          ((Handle effect implementations body)
           (infer-handle ck effect implementations body row loc))
          ((BoxAny inner)
           (learning ck ((inner (infer inner row)))
                     (Pair (Expr (BoxAny inner) (TCon "Any" (Nil)) loc) ck)))
          ((Downcast inner target)
           (learning ck ((inner (check-result inner (TCon "Any" (Nil)) row)))
                     (Pair (Expr (Downcast inner target)
                                 (TCon "snail.core.base:Option" (list target)) loc) ck)))
          )))

    (define (instance-scope (ck Checker) (sets (List String)) (loc Loc)) (→ Checker) (! compile)
      (let ((sets (delete-duplicates string=? (append sets (● ck instances)))))
        (check-active-instances (program-of ck) sets loc)
        (Checker-instances-set ck sets)))

    (define (infer-lambda (ck Checker)
                          (params (List String))
                          (body Expr)
                          (captures? Bool)
                          (loc Loc))
      (→ (Pair Expr Checker)) (! compile)
      (learning ck ((types (each (lambda (ck param) (fresh-meta ck)) params)))
                (infer-lambda-at ck params body captures? types loc)))

    ;; A lambda whose parameter types are known before its body is seen.

    (define (infer-lambda-at (ck Checker)
                             (params (List String))
                             (body Expr)
                             (captures? Bool)
                             (types (List Type))
                             (loc Loc))
      (→ (Pair Expr Checker))
      (! compile)
      (learning ck ((body-row (fresh-meta))
                    (body (scoped (bind-locals ck params types) body body-row))
                    (then (cleanup-lambda params types body body-row)))
                (Pair
                 (Expr (Lambda params body captures?) (TFun types (● body type) body-row) loc)
                 ck)))

    ;; A sub-check under `inner`'s scope, resumed in this checker's. `inner`
    ;; is built from this one, so everything it learns flows back; only its
    ;; scope is discarded.

    (define (within (ck Checker) (inner Checker) (check (Fn Checker → (Pair A Checker) ! e)))
      (→ (Pair A Checker))
      (! e)
      (∀ (A e))
      (match (check inner)
        ((Pair value done) (Pair value (resumed ck done)))))

    ;; Checks an expression against a known type: a lambda's parameters and
    ;; body row come from the type; anything else is inferred.

    (define (check-value (ck Checker) (expr Expr) (type Type) (row Type))
      (→ (Pair Expr Checker))
      (! compile)
      (match (Pair (● expr term) (prune (solution ck) type))
        ((Pair (ScopedInstances sets body) _)
         (within ck (instance-scope ck sets (● expr loc))
                 (lambda (inner) (check-value inner body type row))))
        ((Pair (App callee args) _)
         (infer-app-at ck callee args row (● expr loc) (Some type)))
        ((Pair (If test consequent alternative) _)
         (learning ck ((test (check-result test (TCon "Bool" (Nil)) row))
                       (consequent (check-result consequent type row))
                       (alternative (check-result alternative type row)))
                   (Pair (Expr (If test consequent alternative) type (● expr loc)) ck)))
        ((Pair (Let name value body) _)
         (learning ck ((local (local-placeholder name value))
                       (value (infer-let-value name local value row))
                       (then (unify local (● value type) (● value loc)))
                       (body (within (bind-local ck name local)
                                     (lambda (inner) (check-result inner body type row)))))
                   (Pair (Expr (Let name value body) type (● expr loc)) ck)))
        ((Pair (Seq first rest) _)
         (learning ck ((first (infer first row)) (rest (check-result rest type row)))
                   (Pair (Expr (Seq first rest) type (● expr loc)) ck)))
        ((Pair (Match scrutinee clauses) _)
         (infer-match-at ck scrutinee clauses type row (● expr loc)))
        ((Pair (Lambda params body captures?) (TFun param-types result body-row))
         (if (= (length params) (length param-types))
             (check-lambda ck expr params body captures? type param-types result body-row)
             (infer ck expr row)))
        ;; A function at a fn is checked at its signature, then given the fn.
        ((Pair _ (TCon "fn" (Cons arrow (Nil))))
         (learning ck ((value (check-value expr arrow row)))
                   (fit ck type value row (● value loc))))
        ((Pair (Lambda params body captures?)
               (TCon "FnOnce" (Cons (TFun types result effects) (Nil))))
         (check-lambda ck expr params body captures? type types result effects))
        (_ (infer ck expr row))))

    ;; Infer with the expected type, then unify the resulting type.

    (define (check-result (ck Checker) (expr Expr) (type Type) (row Type))
      (→ (Pair Expr Checker))
      (! compile)
      (learning ck ((expr (check-value expr type row)))
                (fit ck type expr row (● expr loc))))

    ;; A lambda checked against its type. The body's row is a variable bound
    ;; to the type's row, so `perform` can recognize it: calls in this body,
    ;; but not in lambdas inside it, record in `performed` what they
    ;; perform. Writes always charge mut, including writes to fresh objects.

    (define (check-lambda (ck Checker) (expr Expr) (params (List String))
                          (body Expr) (captures? Bool) (type Type) (param-types (List Type))
                          (result Type) (body-row Type))
      (→ (Pair Expr Checker)) (! compile)
      (let ((outer ck))
        (learning ck ((row (fresh-meta))
                      (then (unify row body-row (● expr loc)))
                      (body
                       (within (signed-body (bind-locals ck params param-types) row)
                               (lambda (inner)
                                 (learning inner ((body (check-result body result row))
                                                  (then
                                                   (cleanup-lambda params param-types body row)))
                                           (Pair body inner))))))
                  (Pair (Expr (Lambda params body captures?) type (● expr loc))
                        (finish-lambda-scope outer ck)))))

    ;; A nested function's effects do not replace what its enclosing body
    ;; already performed.

    (define (finish-lambda-scope (outer Checker) (done Checker)) (→ Checker)
      (match (● outer signed)
        ((Some _) (Checker-performed-set done (● outer performed)))
        ((None) done)))

    ;; The scope of a body checked against its signature, whose row
    ;; variable is `row`: nothing is performed in it yet.

    (define (signed-body (ck Checker) (row Type)) (→ Checker)
      (Checker-performed-set (Checker-signed-set ck (Some (meta-number row))) (Nil)))

    (define (meta-number (meta Type)) (→ I64)
      (match meta
        ((TVar id) id)
        (_ -1)))

    (define (infer-app (ck Checker) (callee Expr) (args (List Expr)) (row Type) (loc Loc))
      (→ (Pair Expr Checker))
      (! compile)
      (infer-app-at ck callee args row loc (None)))

    (define (infer-app-at (ck Checker)
                          (callee Expr)
                          (args (List Expr))
                          (row Type)
                          (loc Loc)
                          (expected (Option Type)))
      (→ (Pair Expr Checker))
      (! compile)
      (let ((before (● ck pending-count)))
        (learning ck ((callee (infer callee row))
                      (then (result-context callee expected loc))
                      (args (infer-arguments callee args row))
                      (result (fresh-meta))
                      (latent (fresh-meta))
                      (args (unify-call (● callee type) args result latent row loc))
                      (then (improve-types before))
                      (then (solve-found-rows before row))
                      (then (perform latent row loc)))
                  (Pair (Expr (App callee args) result loc) ck))))

    ;; Matching result constructors carry an explicit storage boundary
    ;; inward. This also reaches callbacks of producers such as map.

    (define (result-context (ck Checker) (callee Expr) (expected (Option Type)) (loc Loc))
      (→ Checker)
      (! compile)
      (match (Pair (callable-arrow (prune (solution ck) (● callee type))) expected)
        ((Pair (Some (TFun _ (TCon result args) _)) (Some type))
         (match (prune (solution ck) type)
           ((TCon target _) (if (string=? target result)
                                (unify ck type (TCon result args) loc) ck))
           (_ ck)))
        (_ ck)))

    (define (infer-arguments (ck Checker) (callee Expr) (args (List Expr)) (row Type))
      (→ (Pair (List Expr) Checker))
      (! compile)
      (match (callable-arrow (prune (solution ck) (● callee type)))
        ((Some (TFun params _ _))
         (if (= (length params) (length args))
             (each ck (lambda (ck pair)
                        (if (projection-call? ck callee)
                            (check-value ck (● pair second) (● pair first) row)
                            (check-result ck (● pair second) (● pair first) row)))
                   (zip params args))
             (each ck (lambda (ck arg) (infer ck arg row)) args)))
        (_ (each ck (lambda (ck arg) (infer ck arg row)) args))))

    ;; Projections first inspect their receiver to select its field type.
    ;; Other parameters constrain later arguments.

    (define (projection-call? (ck Checker) (callee Expr)) (→ Bool)
      (match (● callee term)
        ((Var name _ _)
         (match (program-value (program-of ck) name)
           ((Some (Accessor _ _ _)) #t)
           (_ #f)))
        (_ #f)))

    ;; A literal once body consumes its captures. Giving that lambda the
    ;; actual FnOnce identity removes a special ownership-checking mode.

    ;; Arguments are compared one by one, so a mismatch names its argument,
    ;; and each meets its parameter's type (`fit`), which may give it the
    ;; type Fn.

    (define (unify-call (ck Checker)
                        (callee-type Type)
                        (args (List Expr))
                        (result Type)
                        (latent Type)
                        (context Type)
                        (loc Loc))
      (→ (Pair (List Expr) Checker))
      (! compile)
      (match (prune (solution ck) callee-type)
        ((TFun params callee-result row)
         (unless (= (length params) (length args))
           (compile-error loc
                          (string-append "expected "
                                         (i64->string (length params))
                                         " arguments, found "
                                         (i64->string (length args)))))
         (learning ck ((args (each (lambda (ck pair)
                                     (fit ck
                                          (● pair first)
                                          (● pair second)
                                          context
                                          (● (● pair second) loc)))
                                   (zip params args)))
                       (then (unify callee-result result loc))
                       (then (unify row latent loc)))
                   (Pair args ck)))
        ((TVar _)
         (Pair args
               (unify ck
                      callee-type
                      (TFun (map (lambda (record) (● record type)) args) result latent)
                      loc)))
        ;; Calling a `FnOnce` calls the procedure it holds; ownership consumes
        ;; it. Calling an `Fn` calls the code it is.
        ((TCon "FnOnce" (Cons procedure (Nil)))
         (unify-call ck procedure args result latent context loc))
        ((TCon "fn" (Cons procedure (Nil)))
         (unify-call ck procedure args result latent context loc))
        (other (compile-error loc (string-append "not a function: " (type->string other))))))

    ;; Checking a value never changes its representation. Any is boxed and
    ;; extracted explicitly; all ordinary type boundaries unify.

    (define (fit (ck Checker) (expected Type) (expr Expr) (row Type) (loc Loc))
      (→ (Pair Expr Checker))
      (! compile)
      (match (Pair (prune (solution ck) expected) (prune (solution ck) (● expr type)))
        ((Pair (TCon "fn" (Cons arrow (Nil))) (TFun _ _ _))
         (unless (environment-free? ck expr)
           (compile-error loc
                          (string-append "only a fn or a top-level function has type "
                                         (type->string (resolve-type (solution ck) expected))
                                         "; a lambda, or a local bound to one, may capture")))
         (Pair (Expr (● expr term) expected (● expr loc))
               (unify ck arrow (● expr type) loc)))
        ((Pair (TFun _ _ _) (TCon "fn" _))
         (compile-error loc
                        "an Fn is not a closure, and does not become one; wrap it in a lambda, as (lambda (x) (f x))"))
        (_ (Pair expr (unify ck expected (● expr type) loc)))))

    (define (fit-code-pointer (ck Checker) (expected Type) (arrow Type) (expr Expr) (loc Loc))
      (→ (Pair Expr Checker))
      (! compile)
      (if (match (prune (solution ck) (● expr type)) ((TCon "fn" _) #t) (_ #f))
          (Pair expr (unify ck expected (● expr type) loc))
          (begin
            (unless (environment-free? ck expr)
              (compile-error loc
                             (string-append "only a fn or a top-level function has type "
                                            (type->string
                                             (resolve-type (solution ck) expected))
                                            "; a lambda, or a local bound to one, may capture")))
            (Pair (Expr (● expr term) expected (● expr loc))
                  (unify ck arrow (fn-arrow (● expr type)) loc)))))

    (define (environment-free? (ck Checker) (expr Expr)) (→ Bool)
      (match (● expr term)
        ((Lambda _ _ captures?) (not captures?))
        ((Var name _ _)
         (match (program-value (program-of ck) name)
           ((Some (Defined _ _ function?)) function?)
           (_ #f)))
        (_ #f)))

    ;; A function's own name is visible in its body, with a monomorphic type.

    (define (infer-let (ck Checker) (name String) (value Expr) (body Expr) (row Type) (loc Loc))
      (→ (Pair Expr Checker))
      (! compile)
      (learning ck ((type (local-placeholder name value))
                    (value (infer-let-value name type value row))
                    (then (unify type (● value type) (● value loc)))
                    (body (scoped (bind-local ck name type) body row)))
                (Pair (Expr (Let name value body) (● body type) loc) ck)))

    ;; Reserve a lambda's identity before checking recursive references.
    ;; Captures are resolved in the outer scope, never including itself.

    (define (local-placeholder (ck Checker) (name String) (value Expr)) (→ (Pair Type Checker))
      (match (● value term)
        ((Ann inner type)
         (if (local-function? inner) (Pair type ck) (fresh-meta ck)))
        ((Lambda params _ _)
         (learning ck ((types (each (lambda (ck param) (fresh-meta ck)) params))
                       (result (fresh-meta)) (row (fresh-meta)))
                   (Pair (TFun types result row) ck)))
        (_ (fresh-meta ck))))

    ;; A `let`'s own name is visible in its value only when the value is a
    ;; lambda, so a recursive local function can call itself.

    (define (infer-let-value (ck Checker) (name String) (type Type) (value Expr) (row Type))
      (→ (Pair Expr Checker)) (! compile)
      (if (local-function? value)
          (within ck (bind-local ck name type) (lambda (inner) (check-value inner value type row)))
          (infer ck value row)))

    ;; Typed define headers wrap the lambda in an annotation. They retain
    ;; the same recursive scope as an unannotated local function.
    (define (local-function? (value Expr)) (→ Bool)
      (match (● value term)
        ((Ann inner _) (local-function? inner))
        (_ (lambda-expr? value))))

    ;; A recursive local function reserves its argument and result types
    ;; before checking the body, so recursive calls constrain that signature.

    (define (infer-local-lambda (ck Checker) (value Expr) (type Type))
      (→ (Pair Expr Checker))
      (! compile)
      (match (Pair (● value term) (fn-arrow type))
        ((Pair (Lambda params body captures?) (TFun types _ _))
         (learning ck ((value (infer-lambda-at params body captures? types (● value loc)))
                       (then (unify (fn-arrow type) (● value type) (● value loc))))
                   (Pair (Expr (● value term) type (● value loc)) ck)))
        (_ (panic "internal error: a local lambda has a reserved signature"))))

    ;; `expr` inferred under `inner`'s scope, resumed in this checker's.

    (define (scoped (ck Checker) (inner Checker) (expr Expr) (row Type))
      (→ (Pair Expr Checker))
      (! compile)
      (within ck inner (lambda (scope) (infer scope expr row))))

    (define (infer-match (ck Checker) (scrutinee Expr) (clauses (List Clause)) (row Type) (loc Loc))
      (→ (Pair Expr Checker))
      (! compile)
      (learning ck ((result (fresh-meta)))
                (infer-match-at ck scrutinee clauses result row loc)))

    (define (infer-match-at (ck Checker)
                            (scrutinee Expr)
                            (clauses (List Clause))
                            (result Type)
                            (row Type)
                            (loc Loc))
      (→ (Pair Expr Checker))
      (! compile)
      (learning ck ((scrutinee (infer scrutinee row))
                    (clauses (each (lambda (ck clause)
                                     (infer-clause ck clause (● scrutinee type) result row))
                                   clauses)))
                (if (null? clauses)
                    (check-empty-match ck (● scrutinee type) loc)
                    (check-coverage ck (map (lambda (record) (● record pattern)) clauses) loc))
                (Pair (Expr (Match scrutinee clauses) result loc) ck)))

    ;; A match with no clauses is exhaustive only on a type with no cases,
    ;; which has no value to reach it with.

    (define (check-empty-match (ck Checker) (type Type) (loc Loc)) (→ Unit) (! compile)
      (unless (match (resolve-type (solution ck) type)
                ((TCon name _)
                 (match (table-ref (● (program-of ck) types) name)
                   ((Some data) (and (● data enum?) (null? (● data cases))))
                   ((None) #f)))
                (_ #f))
        (compile-error loc
                       "a match needs at least one clause, unless its value's type has no cases")))

    ;; One clause: its pattern binds for its body alone, and every body has
    ;; the match's result type.

    (define (infer-clause (ck Checker)
                          (clause Clause)
                          (scrutinee-type Type)
                          (result Type)
                          (row Type))
      (→ (Pair Clause Checker))
      (! compile)
      (let ((body-loc (● (● clause body) loc)))
        (learning ck ((checked (check-pattern (● clause pattern) scrutinee-type body-loc))
                      (body (within (● checked scope)
                                    (lambda (inner)
                                      (check-result inner (● clause body) result row)))))
                  (Pair (Clause (● checked pattern) body) ck))))

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

    (define (infer-handle (ck Checker)
                          (effect String)
                          (implementations (List (Pair String Expr)))
                          (body Expr)
                          (row Type)
                          (loc Loc))
      (→ (Pair Expr Checker))
      (! compile)
      (let* ((info (program-effect (program-of ck) effect)) (operations (● info operations)))
        (unless (and (= (length operations) (length implementations))
                     (every? (lambda (operation)
                               (any? (lambda (entry) (string=? (● entry first) operation))
                                     implementations))
                             operations))
          (compile-error loc "a handler implements each operation of its effect exactly once"))
        (learning ck ((result (fresh-meta))
                      (rest (fresh-meta))
                      (implementations
                       (each (lambda (ck entry)
                               (infer-implementation ck
                                                     entry
                                                     (Answer (● info control) result)
                                                     row
                                                     loc))
                             implementations))
                      (body (infer body (TRow (list effect) (Some rest))))
                      (body (fit result body (TRow (list effect) (Some rest)) (● body loc)))
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

    (define (infer-implementation (ck Checker)
                                  (entry (Pair String Expr))
                                  (answer Answer)
                                  (row Type)
                                  (loc Loc))
      (→ (Pair (Pair String Expr) Checker))
      (! compile)
      (match (program-value (program-of ck) (● entry first))
        ((Some (Operation effect scheme))
         (learning ck ((use (instantiate scheme loc)))
                   (match (● use type)
                     ((TFun params result _)
                      (learning ck ((rest (fresh-meta)))
                                (let ((expected
                                       (implementation-type (● entry first) answer params result
                                                            (latent-row
                                                             (operation-latent effect scheme)
                                                             rest)
                                                            row)))
                                  (learning ck ((value
                                                 (infer-implementation-value (● entry second)
                                                                             expected
                                                                             row))
                                                (value (fit expected value row (● value loc)))
                                                (then (perform rest row (● value loc))))
                                            (Pair (Pair (● entry first) value) ck)))))
                     (_ (panic "internal error: an operation is a function")))))
        (_ (panic "internal error: unknown operation"))))

    ;; The row an implementation may perform: the latent labels, open to
    ;; `rest`, or `rest` alone.

    (define (latent-row (labels (List String)) (rest Type)) (→ Type)
      (if (null? labels) rest (TRow labels (Some rest))))

    ;; An implementation that is a lambda takes its parameter types from the
    ;; operation, so its body knows `resume` is one-shot when it calls it.

    (define (infer-implementation-value (ck Checker) (value Expr) (expected Type) (row Type))
      (→ (Pair Expr Checker))
      (! compile)
      (match (Pair (● value term) expected)
        ((Pair (Lambda params body captures?) (TFun types result _))
         (if (= (length params) (length types))
             (learning ck ((value (infer-lambda-at params body captures? types (● value loc))))
                       (fit-lambda-result ck value result))
             (infer ck value row)))
        (_ (infer ck value row))))

    ;; An implementation is checked at its operation's result without
    ;; changing the inferred row or adapting an already existing function.

    (define (fit-lambda-result (ck Checker) (value Expr) (result Type))
      (→ (Pair Expr Checker))
      (! compile)
      (match (Pair (● value term) (● value type))
        ((Pair (Lambda params body captures?) (TFun types _ row))
         (learning ck ((body (fit result body row (● body loc))))
                   (Pair
                    (Expr (Lambda params body captures?) (TFun types result row) (● value loc))
                    ck)))
        (_ (panic "internal error: fitting the result of a non-lambda"))))

    ;; An implementation returns the operation's answer to its caller. A
    ;; control operation's implementation returns the handler's result, and
    ;; is also handed `resume`, which it calls or drops exactly once, unless the
    ;; operation answers Never, when nothing could resume it. `resume`
    ;; performs `context`, the row of the code around the handle.

    (define (implementation-type (operation String)
                                 (answer Answer)
                                 (params (List Type))
                                 (result Type)
                                 (latent Type)
                                 (context Type))
      (→ Type)
      (cond ((not (member? operation (● answer control))) (TFun params result latent))
            ((never-type? result) (TFun params (● answer result) latent))
            (else (TFun (append params
                                (list (TCon "FnOnce"
                                            (list (TFun (list result)
                                                        (● answer result)
                                                        context)))))
                        (● answer result)
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

    (define (check-pattern (ck Checker) (pattern Pattern) (type Type) (loc Loc))
      (→ (Pair Checked Checker))
      (! compile)
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
                      (match (● use type)
                        ((TFun fields result _)
                         (unless (= (length fields) (length args))
                           (compile-error loc
                                          (string-append (short-name constructor)
                                                         " has "
                                                         (i64->string (length fields))
                                                         " fields")))
                         (let ((owned (prune (solution ck) type)))
                           (learning ck ((then (unify owned result loc))
                                         (checked (check-fields constructor
                                                                owned
                                                                args
                                                                fields
                                                                loc)))
                                     (Pair checked ck))))
                        (_ (panic "internal error: a constructor is a function")))))
           (_
            (compile-error loc (string-append "not a constructor: " (short-name constructor))))))))

    ;; A constructor pattern's fields, checked in order into one scope:
    ;; names are unique, so the fields' locals simply join.

    (define (check-fields (ck Checker)
                          (constructor String)
                          (type Type)
                          (args (List Pattern))
                          (fields (List Type))
                          (loc Loc))
      (→ (Pair Checked Checker))
      (! compile)
      (learning ck ((done (each (lambda (ck pair)
                                  (check-pattern ck (● pair first) (● pair second) loc))
                                (zip args fields))))
                (Pair
                 (Checked (PCon constructor (map (lambda (record) (● record pattern)) done) type)
                          (fold-left
                           (lambda (scope field) (merged-locals scope (● field scope)))
                           ck
                           done))
                 ck)))

    ;; Every local a field pattern bound, added to the scope so far.

    (define (merged-locals (scope Checker) (field Checker)) (→ Checker)
      (Checker-locals-set scope (table-union (● scope locals) (● field locals))))

    ;; ---- Coverage ----

    ;; Maranget's usefulness test. A clause is redundant if it is not useful
    ;; after the clauses before it; a match is exhaustive if a wildcard is not
    ;; useful after all of them.

    (define (check-coverage (ck Checker) (patterns (List Pattern)) (loc Loc)) (→ Unit) (! compile)
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

    (define (head-of (pattern Pattern)) (→ (Option Head))
      (match pattern
        ((PCon constructor args _) (Some (HCon constructor (length args))))
        ((PLit value _) (Some (HLit value)))
        (_ (None))))

    (define (head=? (a Head) (b Head)) (→ Bool)
      (match a
        ((HCon name _) (match b ((HCon other _) (string=? name other)) (_ #f)))
        ((HLit value) (match b ((HLit other) (datum=? value other)) (_ #f)))))

    (define (head-arity (head Head)) (→ I64)
      (match head
        ((HCon _ arity) arity)
        ((HLit _) 0)))

    (define (pattern-args (pattern Pattern)) (→ (List Pattern))
      (match pattern
        ((PCon _ args _) args)
        (_ (Nil))))

    (define (wildcards (count I64)) (→ (List Pattern))
      (map (lambda (index) (PWild unchecked)) (iota count)))

    (define (specialize (rows (List (List Pattern))) (head Head)) (→ (List (List Pattern)))
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

    (define (default-rows (rows (List (List Pattern)))) (→ (List (List Pattern)))
      (concatenate
       (map (lambda (row)
              (match row
                ((Cons first rest) (match (head-of first) ((None) (list rest)) ((Some _) (Nil))))
                ((Nil) (Nil))))
            rows)))

    (define (row-heads (rows (List (List Pattern)))) (→ (List Head))
      (concatenate
       (map (lambda (row)
              (match row
                ((Cons first _) (match (head-of first) ((Some head) (list head)) ((None) (Nil))))
                ((Nil) (Nil))))
            rows)))

    (define (useful? (ck Checker) (rows (List (List Pattern))) (vector (List Pattern))) (→ Bool)
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

    (define (complete-signature (ck Checker) (seen (List Head))) (→ (Option (List Head)))
      (let ((all (match seen
                   ((Cons (HLit (DBool _)) _) (list (HLit (DBool #t)) (HLit (DBool #f))))
                   ((Cons (HCon constructor _) _) (constructor-heads ck constructor))
                   (_ (Nil)))))
        (if (and (not (null? all))
                 (every? (lambda (head) (any? (lambda (other) (head=? head other)) seen)) all))
            (Some all)
            (None))))

    (define (constructor-heads (ck Checker) (constructor String)) (→ (List Head))
      (match (program-value (program-of ck) constructor)
        ((Some (Constructor case _))
         (map (lambda (case) (HCon (● case name) (length (● case fields))))
              (● (program-type (program-of ck) (● case type)) cases)))
        (_ (Nil))))

    ;; ---- Nominal field selections ----

    (define (infer-field-read (ck Checker) (record Expr) (label String) (row Type) (loc Loc))
      (→ (Pair Expr Checker)) (! compile)
      (let ((before (● ck pending-count)))
        (learning ck ((record (infer record row))
                      (result (fresh-meta))
                      (hole (fresh-identity))
                      (then
                       (want (WantField (Projection record label result row hole (● ck copy) loc))))
                      (then (improve-types before)))
                  (Pair (Expr (FieldRead record label (Some hole)) result loc) ck))))

    (define (projection-solved? (ck Checker) (projection Projection)) (→ Bool)
      (table-contains? (● (solution ck) projections) (identity-key (● projection hole))))

    (define (improve-projection (ck Checker) (projection Projection)) (→ Checker) (! compile)
      (if (projection-solved? ck projection) ck
          (match (resolve-projection ck (● projection record) (● projection label)
                                     (● projection copy) (● projection loc))
            ((None) ck)
            ((Some (Pair value effects))
             (learning ck ((then (unify (● projection result) (● value type) (● projection loc)))
                           (then (perform effects (● projection row) (● projection loc))))
                       (Checker-solution-set ck
                                             (Solution-projections-set (solution ck)
                                                                       (table-set (● (solution ck)
                                                                                     projections)
                                                                                  (identity-key
                                                                                   (● projection
                                                                                      hole))
                                                                                  value))))))))

    (define (check-projection (ck Checker) (projection Projection)) (→ Unit) (! compile)
      (unless (projection-solved? ck projection)
        (compile-error (● projection loc)
                       (string-append "field " (● projection label)
                                      " requires a known struct type; annotate the receiver"))))

    ;; Each label selects one stored field of the current nominal object.
    (define (resolve-projection (ck Checker) (record Expr) (label String)
                                (copy (List String)) (loc Loc))
      (→ (Option (Pair Expr Type))) (! compile)
      (let* ((type (resolve-type (solution ck) (● record type)))
             (owner type))
        (match owner
          ((TVar _) (None))
          ((TCon _ _) (projection-slot ck record owner label copy loc))
          (_ (compile-error loc (string-append "field " label
                                               " requires a known struct type, found "
                                               (type->string owner)))))))

    (define (projection-slot (ck Checker) (record Expr) (owner Type) (label String)
                             (copy (List String)) (loc Loc))
      (→ (Option (Pair Expr Type))) (! compile)
      (match owner
        ((TCon "Rc" (Cons value (Nil))) (projection-slot ck record value label copy loc))
        ((TCon name args)
         (match (table-ref (● (program-of ck) types) name)
           ((Some data)
            (when (● data enum?)
              (compile-error loc "field selection requires a struct; match an enum's cases"))
            (let ((case (list-ref (● data cases) 0)))
              (match (list-index (lambda (field) (string=? label (● field name))) (● case fields))
                ((Some index) (projection-value ck record data case index args copy loc))
                ((None)
                 (compile-error loc (string-append (type->string owner) " has no field " label))))))
           ((None)
            (compile-error loc (string-append (type->string owner) " has no field " label)))))
        (_ (panic "internal error: a slot has a nominal owner"))))

    (define (projection-value (ck Checker) (record Expr) (data DataType) (case Case)
                              (index I64) (args (List Type)) (copy (List String)) (loc Loc))
      (→ (Option (Pair Expr Type))) 
      (let* ((field (list-ref (● case fields) index))
             (result (substitute (zip (● data params) args) (● field type)))
             (callee (Expr (Var (field-operation-name case index "get") args (Nil))
                           (TFun (list (● record type)) result empty-row) loc)))
        (Some (Pair (Expr (App callee (list record)) result loc) empty-row))))

    ;; ---- Solving ----

    ;; Runs once, after every item is checked: literals whose type nothing
    ;; determined default to F64 or I64, every literal is range-checked, and
    ;; every class constraint is solved with the givens it arose under.
    ;; Field types and associated outputs are improved before and after
    ;; literal defaulting. A row class also charges the effects its inputs
    ;; determine: most are solved at their call (`solve-found-rows`), while
    ;; constraints whose inputs a later use decides wait until here.

    (define (solve-pending (ck Checker)) (→ Checker) (! compile)
      (let ((pending (reverse (● ck pending))))
        (learning ck ((then (improve-types 0))
                      (then (default-literals pending #t))
                      (then (default-literals pending #f))
                      (then (improve-types 0)))
                  (for-each (lambda (want)
                              (match want
                                ((WantField projection) (check-projection ck projection))
                                ((WantLiteral value type loc) (check-literal ck value type loc))
                                ((WantCopy type copy loc) (check-copy ck type copy loc))
                                (_ (unit))))
                            pending)
                  (let* ((ck (propagate-inclusions (fold-left solve-pending-class ck pending)))
                         (ck (propagate-inclusions (fold-left solve-pending-cleanup ck pending)))
                         (ck (fold-left solve-pending-escape ck pending)))
                    (let ((ck (solve-inclusions ck)))
                      (for-each (lambda (want) (check-performed ck want)) pending)
                      ck)))))

    ;; Class resolution can still add effects to a procedure's inferred row.
    ;; Finish those obligations before filtering control effects out of its
    ;; destruction row; filtering an unresolved tail would retain them later.
    (define (solve-pending-class (ck Checker) (want Wanted)) (→ Checker) (! compile)
      (match want
        ((WantClass constraint hole givens copy sets loc)
         (resumed ck (solve-class (Checker-instances-set ck sets)
                                  constraint hole givens copy loc)))
        (_ ck)))

    (define (solve-pending-cleanup (ck Checker) (want Wanted)) (→ Checker) (! compile)
      (match want
        ((WantCleanup type row handled givens copy shared-only? loc)
         (resumed ck (charge-disposal (Checker-copy-set (Checker-givens-set ck givens) copy)
                                      type handled row loc shared-only? #f)))
        (_ ck)))

    (define (solve-pending-escape (ck Checker) (want Wanted)) (→ Checker) (! compile)
      (match want
        ((WantEscape scope expr row handled givens copy)
         (if (null? (label-difference (cleanup-yields ck expr) (list "?meta-control"))) ck
             (resumed ck (charge-exceptional
                          (Checker-copy-set (Checker-givens-set ck givens) copy)
                          (map (lambda (owner)
                                 (Pair (● owner first) (zonk (solution ck) (● owner second))))
                               scope)
                          handled row (● expr loc)))))
        (_ ck)))

    (define (default-literals (ck Checker) (pending (List Wanted)) (float? Bool))
      (→ Checker)
      (! compile)
      (fold-left (lambda (ck want) (default-literal ck want float?)) ck pending))

    (define (default-literal (ck Checker) (want Wanted) (float? Bool)) (→ Checker) (! compile)
      (match want
        ((WantLiteral value type loc)
         (if (and (float-literal? value float?) (meta? (prune (solution ck) type)))
             (unify ck (TCon (if float? "F64" "I64") (Nil)) type loc)
             ck))
        (_ ck)))

    (define (float-literal? (value Datum) (float? Bool)) (→ Bool)
      (match value
        ((DFloat _) float?)
        (_ (not float?))))

    (define (check-literal (ck Checker) (value Datum) (type Type) (loc Loc)) (→ Unit) (! compile)
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

    (define (literal-fits? (value Datum) (type String)) (→ Bool)
      (match value
        ((DInt n)
         (case type
           (("U8") (and (<= 0 n) (<= n 255)))
           (("I32") (and (<= -2147483648 n) (<= n 2147483647)))
           (("I64" "F32" "F64") #t)
           (else #f)))
        ((DFloat _) (or (string=? type "F32") (string=? type "F64")))
        (_ #f)))

    (define (solve-class (ck Checker)
                         (constraint Constraint)
                         (hole I64)
                         (givens (List Constraint))
                         (copy (List String))
                         (loc Loc))
      (→ Checker)
      (! compile)
      (cond ((determined-class? ck (● constraint class))
             (solve-found ck constraint hole givens copy (None) loc))
            (else
             (match (find-evidence ck constraint givens copy loc)
               ((Some (Pair evidence ck)) (with-evidence ck hole evidence))
               ((None) (compile-error loc (ambiguous-constraint ck constraint)))))))

    ;; Rows and associated outputs are determined arguments. The remaining
    ;; input arguments select evidence; that evidence establishes outputs
    ;; by equality and supplies the rows its methods perform.

    (define (determined-class? (ck Checker) (class String)) (→ Bool)
      (let ((class (program-class (program-of ck) class)))
        (not (null? (append (● class rows) (● class outputs))))))

    ;; A row class's constraint, solved in the row of the call it was raised
    ;; in when `context` gives one.

    (define (solve-found (ck Checker)
                         (constraint Constraint)
                         (hole I64)
                         (givens (List Constraint))
                         (copy (List String))
                         (context (Option Type))
                         (loc Loc))
      (→ Checker)
      (! compile)
      (match (found-evidence ck constraint givens copy context loc)
        ((Pair evidence ck) (with-evidence ck hole evidence))))

    (define (found-evidence (ck Checker)
                            (constraint Constraint)
                            (givens (List Constraint))
                            (copy (List String))
                            (context (Option Type))
                            (loc Loc))
      (→ (Pair Evidence Checker))
      (! compile)
      (if (lifecycle-class? (● constraint class))
          (lifecycle-evidence ck constraint givens copy context loc)
          (determined-evidence ck constraint givens copy context loc)))

    ;; A row class other than Drop and Clone is chosen as any class is, by
    ;; its types alone: the requirement given for them, or the one instance
    ;; whose head matches them. What that performs at each row parameter is
    ;; charged to the constraint's row there.

    (define (determined-evidence (ck Checker)
                                 (constraint Constraint)
                                 (givens (List Constraint))
                                 (copy (List String))
                                 (context (Option Type))
                                 (loc Loc))
      (→ (Pair Evidence Checker))
      (! compile)
      (let* ((class (program-class (program-of ck) (● constraint class)))
             (types (map (lambda (type) (resolve-type (solution ck) type))
                         (● constraint types))))
        (when (any? (lambda (type) (has-meta? (solution ck) type)) (type-arguments class types))
          (compile-error loc (ambiguous-constraint ck constraint)))
        (match (determined-source ck class types givens copy loc)
          ((Pair (Pair evidence performed) ck)
           (Pair evidence
                 (fold-left (lambda (ck charged)
                              (charge ck (● charged first) (● charged second) context loc))
                            ck
                            (zip performed (row-arguments class types))))))))

    ;; The evidence for a row class's types, and the row it performs at each
    ;; row parameter: a requirement given for them performs its own rows.

    (define (determined-source (ck Checker)
                               (class Class)
                               (types (List Type))
                               (givens (List Constraint))
                               (copy (List String))
                               (loc Loc))
      (→ (Pair (Pair Evidence (List Type)) Checker))
      (! compile)
      (match (list-index (lambda (given) (given-for? class types given)) givens)
        ((Some index)
         (let ((given (● (list-ref givens index) types)))
           (Pair (Pair (EvParam index) (row-arguments class given))
                 (unify-outputs ck class given types loc))))
        ((None) (determined-instance ck class types givens copy loc))))

    (define (given-for? (class Class) (types (List Type)) (given Constraint)) (→ Bool)
      (and (string=? (● class name) (● given class))
           (types=? (type-arguments class types) (type-arguments class (● given types)))))

    ;; Inputs bind the instance's selecting variables. The remaining row
    ;; and output variables start fresh, and ordered prerequisites establish
    ;; them before the selected head constrains the caller's output slots.

    (define (determined-instance (ck Checker)
                                 (class Class)
                                 (types (List Type))
                                 (givens (List Constraint))
                                 (copy (List String))
                                 (loc Loc))
      (→ (Pair (Pair Evidence (List Type)) Checker))
      (! compile)
      (match (matching-instance ck class types loc)
        ((Pair instance bindings)
         (let ((outer ck) (ck (enter-instance ck class types loc)))
           (learning ck ((determined (fresh-bindings
                                      (filter (lambda (var) (not (assoc-contains? bindings var)))
                                              (● instance vars))))
                         (evidence
                          (instance-application instance bindings determined givens copy loc)))
                     (let ((head (map (lambda (type) (substitute (append determined bindings) type))
                                      (● instance types))))
                       (Pair (Pair evidence (row-arguments class head))
                             (resumed outer (unify-outputs ck class head types loc)))))))))

    (define (enter-instance (ck Checker) (class Class) (types (List Type)) (loc Loc))
      (→ Checker)
      (! compile)
      (when (or (>= (length (● ck resolving)) 128)
                (any? (lambda (goal) (given-for? class types goal)) (● ck resolving)))
        (compile-error loc "instance requirements do not terminate"))
      (Checker-resolving-set ck
                             (Cons (Constraint (● class name) types) (● ck resolving))))

    (define (assoc-contains? (bindings Substitution) (name String)) (→ Bool)
      (match (assoc-ref bindings name)
        ((Some _) #t)
        ((None) #f)))

    (define (unify-outputs (ck Checker)
                           (class Class)
                           (established (List Type))
                           (wanted (List Type))
                           (loc Loc))
      (→ Checker)
      (! compile)
      (fold-left (lambda (ck pair) (unify ck (● pair first) (● pair second) loc))
                 ck (zip (output-arguments class established) (output-arguments class wanted))))

    (define (with-evidence (ck Checker) (hole I64) (evidence Evidence)) (→ Checker)
      (Checker-solution-set ck
                            (Solution-evidence-set (solution ck)
                                                   (table-set (● (solution ck) evidence)
                                                              (identity-key hole)
                                                              evidence))))

    (define (ambiguous-constraint (ck Checker) (constraint Constraint)) (→ String)
      (string-append "ambiguous constraint "
                     (constraint->string (● constraint class)
                                         (map (lambda (type) (resolve-type (solution ck) type))
                                              (● constraint types)))
                     "; add a signature or an annotation"))

    ;; A lifecycle class's row, as `(Drop e T)`'s, is found from T, not
    ;; matched: dropping or cloning a T runs what the type says
    ;; (`lifecycle-rows`), and each row that performs is performed in `e`.
    ;; Mono finds what runs again from the ground type, so the evidence only
    ;; records the plan charged. `context` is the row of the call the
    ;; constraint was raised in, when it is solved there.

    (define (lifecycle-evidence (ck Checker)
                                (constraint Constraint)
                                (givens (List Constraint))
                                (copy (List String))
                                (context (Option Type))
                                (loc Loc))
      (→ (Pair Evidence Checker))
      (! compile)
      (match (● constraint types)
        ((Cons row (Cons type (Nil)))
         (let ((type (resolve-type (solution ck) type))
               (class (● constraint class))
               (program (program-of ck)))
           (unless (lifecycle-input-known? ck class type)
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

    (define (charge (ck Checker) (performed Type) (row Type) (context (Option Type)) (loc Loc))
      (→ Checker)
      (! compile)
      (let ((ck (perform ck performed row loc)))
        (match context
          ((Some context)
           (if (same-tail? (● (flatten-row (solution ck) row) second)
                           (● (flatten-row (solution ck) context) second))
               (record-performed ck context performed)
               ck))
          ((None) ck))))

    ;; A row is charged where it is written: once a call is checked, each
    ;; constraint of a row class raised in it whose types are known by now
    ;; is solved in the call's scope, so a signed body is seen to perform
    ;; what its drops, clones and methods do. One whose types a later use
    ;; decides waits for `solve-pending`.

    (define (solve-found-rows (ck Checker) (before I64) (context Type)) (→ Checker) (! compile)
      (let* ((count (- (● ck pending-count) before))
             (recent (take (● ck pending) count))
             (older (list-drop (● ck pending) count)))
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

    (define (solve-known-row (progress (Pair (List Wanted) Checker)) (want Wanted) (context Type))
      (→ (Pair (List Wanted) Checker)) (! compile)
      (match progress
        ((Pair kept ck)
         (if (not (known-class-inputs? ck want)) (Pair (Cons want kept) ck)
             (let ((before (● ck pending-count)))
               (let ((done
                      (match want
                        ((WantClass constraint hole givens copy sets loc)
                         (resumed ck (solve-found (Checker-instances-set ck sets)
                                                  constraint hole givens copy (Some context) loc)))
                        ((WantCleanup type row handled givens copy shared-only? loc)
                         (resumed ck (charge-disposal
                                      (Checker-copy-set (Checker-givens-set ck givens) copy)
                                      type handled row loc shared-only? #f)))
                        (_ ck))))
                 (Pair (append (take (● done pending) (- (● done pending-count) before)) kept)
                       done)))))))

    (define (known-class-inputs? (ck Checker) (want Wanted)) (→ Bool)
      (match want
        ((WantClass constraint _ _ _ _ _)
         (let ((class (● constraint class)))
           (and (determined-class? ck class)
                (every? (lambda (type) (lifecycle-input-known? ck class type))
                        (type-arguments (program-class (program-of ck) class)
                                        (● constraint types))))))
        ((WantCleanup type _ _ _ _ _ _) (disposal-known? (resolve-type (solution ck) type)))
        (_ #f)))

    ;; Callable destruction depends on its effect row, never its arguments
    ;; or result. A handler's answer may still be unknown when it drops its
    ;; resumption; waiting for that answer would close the call row too soon.
    (define (lifecycle-input-known? (ck Checker) (class String) (type Type)) (→ Bool)
      (let ((type (resolve-type (solution ck) type)))
        (if (string=? class drop-class)
            (match (fn-arrow type)
              ((TFun _ _ row) (not (has-meta? (solution ck) row)))
              (_ (not (has-meta? (solution ck) type))))
            (not (has-meta? (solution ck) type)))))

    ;; Field selections and associated outputs improve together: each
    ;; established output can determine another selection's receiver.

    (define (improve-types (ck Checker) (before I64)) (→ Checker) (! compile)
      (let* ((count (- (● ck pending-count) before))
             (recent (take (● ck pending) count))
             (deferred (filter (lambda (want)
                                 (match want
                                   ((WantField projection) (not (projection-solved? ck projection)))
                                   (_ #f)))
                               (list-drop (● ck pending) count)))
             (wanted (reverse (append recent deferred))))
        (let loop ((ck ck))
          (let ((next (fold-left improve-output ck wanted)))
            (if (types=? (improvement-types ck wanted) (improvement-types next wanted))
                next (loop next))))))

    (define (improvement-types (ck Checker) (wanted (List Wanted))) (→ (List Type))
      (concatenate (map (lambda (want)
                          (match want
                            ((WantField projection)
                             (map (lambda (type) (resolve-type (solution ck) type))
                                  (list (● projection record type) (● projection result)
                                        (● projection row))))
                            ((WantClass constraint _ _ _ _ _)
                             (map (lambda (type) (resolve-type (solution ck) type))
                                  (● constraint types)))
                            (_ (Nil)))) wanted)))

    (define (improve-output (ck Checker) (want Wanted)) (→ Checker) (! compile)
      (match want
        ((WantField projection) (improve-projection ck projection))
        ((WantClass constraint _ givens copy sets loc)
         (let ((class (program-class (program-of ck) (● constraint class))))
           (if (and (not (null? (● class outputs))) (known-class-inputs? ck want))
               (resumed ck (● (determined-source (Checker-instances-set ck sets) class
                                                 (map
                                                  (lambda (type) (resolve-type (solution ck) type))
                                                  (● constraint types)) givens copy loc) second))
               ck)))
        (_ ck)))

    ;; Evidence from the enclosing definition's requirements, or from the
    ;; unique instance whose head matches. None while the types are ambiguous.

    (define (find-evidence (ck Checker) (constraint Constraint) (givens (List Constraint))
                           (copy (List String)) (loc Loc))
      (→ (Option (Pair Evidence Checker))) (! compile)
      (let ((types (map (lambda (type) (resolve-type (solution ck) type)) (● constraint types))))
        (if (any? (lambda (type) (has-meta? (solution ck) type)) types) (None)
            (match (given-evidence (● constraint class) types givens)
              ((Some evidence) (Some (Pair evidence ck)))
              ((None) (Some (instance-evidence ck (● constraint class) types givens copy loc)))))))

    (define (given-evidence (class String) (types (List Type)) (givens (List Constraint)))
      (→ (Option Evidence))
      (match (list-index (lambda (given)
                           (and (string=? class (● given class))
                                (types=? types (● given types))))
                         givens)
        ((Some index) (Some (EvParam index)))
        ((None) (None))))

    (define (instance-evidence (ck Checker)
                               (class String)
                               (types (List Type))
                               (givens (List Constraint))
                               (copy (List String))
                               (loc Loc))
      (→ (Pair Evidence Checker))
      (! compile)
      (match (matching-instance ck (program-class (program-of ck) class) types loc)
        ((Pair instance bindings)
         (instance-application ck instance bindings (Nil) givens copy loc))))

    ;; The instance whose head matches a constraint's types, and what that
    ;; binds its variables to. Rows take no part: they are found from the
    ;; instance chosen, so no two instances of a class have the same types.

    (define (matching-instance (ck Checker) (class Class) (types (List Type)) (loc Loc))
      (→ (Pair Instance Substitution))
      (! compile)
      (let loop ((instances
                  (visible-instances (program-of ck) (● class name) (● ck instances))))
        (match instances
          ((Nil)
           (compile-error loc
                          (string-append "no instance for "
                                         (constraint->string (● class name) types))))
          ((Cons instance rest)
           (match (match-types (● instance vars)
                               (type-arguments class (● instance types))
                               (type-arguments class types)
                               (Nil))
             ((Some bindings) (Pair instance bindings))
             ((None) (loop rest)))))))

    ;; An instance applied where its head matched with `bindings`: a
    ;; variable it requires Copy must be given an unrestricted type, and
    ;; each of its requirements is satisfied there in turn, with `rows`
    ;; giving the variables a row class's instance ends its rows with.

    (define (instance-application (ck Checker)
                                  (instance Instance)
                                  (bindings Substitution)
                                  (rows Substitution)
                                  (givens (List Constraint))
                                  (copy (List String))
                                  (loc Loc))
      (→ (Pair Evidence Checker))
      (! compile)
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
                      (● instance requires))
           ((Pair subs ck)
            (Pair (EvInstance (● instance name)
                              (applied-types instance (append rows bindings))
                              subs)
                  ck))))))

    ;; The types the head's match gave the instance's variables, in order.

    (define (applied-types (instance Instance) (bindings Substitution)) (→ (List Type))
      (map (lambda (var)
             (match (assoc-ref bindings var)
               ((Some type) type)
               ((None) (TCon "Unit" (Nil)))))
           (● instance vars)))

    ;; A requirement of a row class, as `(Drop e A)` or `(Store e S)`, is
    ;; solved as its use is: what the type it gives `A` performs is charged
    ;; to its row `e`. Any other is found as a constraint is.

    (define (requirement-evidence (ck Checker)
                                  (requirement Constraint)
                                  (givens (List Constraint))
                                  (copy (List String))
                                  (loc Loc))
      (→ (Pair Evidence Checker))
      (! compile)
      (if (determined-class? ck (● requirement class))
          (found-evidence ck requirement givens copy (None) loc)
          (match (find-evidence ck requirement givens copy loc)
            ((Some found) found)
            ((None) (compile-error loc (ambiguous-requirement requirement))))))

    (define (ambiguous-requirement (requirement Constraint)) (→ String)
      (string-append "ambiguous requirement "
                     (constraint->string (● requirement class)
                                         (● requirement types))))

    (define (constraint->string (class String) (types (List Type))) (→ String)
      (type->string (TCon class types)))

    (define (has-meta? (solution Solution) (type Type)) (→ Bool)
      (match (prune solution type)
        ((TVar _) #t)
        ((TCon _ args) (any? (lambda (arg) (has-meta? solution arg)) args))
        ((TFun params result _)
         (or (any? (lambda (param) (has-meta? solution param)) params) (has-meta? solution result)))
        (_ #f)))

    ;; ---- Zonking ----

    ;; Replaces solved metavariables and keeps unsolved ones.

    (define (resolve-type (solution Solution) (type Type)) (→ Type)
      (let ((type (prune solution type)))
        (match type
          ((TCon name args) (TCon name (map (lambda (arg) (resolve-type solution arg)) args)))
          ((TFun params result row)
           (TFun (map (lambda (param) (resolve-type solution param)) params)
                 (resolve-type solution result) (resolve-type solution row)))
          ((TRow _ _)
           (let ((flat (flatten-row solution type))) (TRow (● flat first) (● flat second))))
          (_ type))))

    ;; Replaces solved metavariables. An unsolved type defaults to Unit and an
    ;; unsolved row tail closes; nothing observable depends on either.

    (define (zonk (solution Solution) (type Type)) (→ Type)
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

    (define (zonk-row (solution Solution) (row Type)) (→ Type)
      (let ((flat (flatten-row solution row)))
        (TRow (● flat first) (if (meta-tail? (● flat second)) (None) (● flat second)))))

    (define (zonk-evidence (solution Solution) (evidence Evidence)) (→ Evidence)
      (match evidence
        ((EvHole hole)
         (match (solved-evidence solution hole)
           ((Some solved) (zonk-evidence solution solved))
           ((None) (panic "internal error: unsolved evidence"))))
        ((EvInstance instance types subs)
         (EvInstance instance (map (lambda (type) (zonk solution type)) types)
                     (map (lambda (sub) (zonk-evidence solution sub)) subs)))
        (_ evidence)))

    (define (zonk-expr (solution Solution) (expr Expr)) (→ Expr)
      (Expr (match (● expr term)
              ((Lit value) (Lit value))
              ((Var name types evidence)
               (Var name
                    (map (lambda (type) (zonk solution type)) types)
                    (map (lambda (e) (zonk-evidence solution e)) evidence)))
              ((Lambda params body captures?) (Lambda params (zonk-expr solution body) captures?))
              ((App callee args)
               (App (zonk-expr solution callee) (map (lambda (arg) (zonk-expr solution arg)) args)))
              ((FieldRead _ _ (Some hole))
               (match (table-ref (● solution projections) (identity-key hole))
                 ((Some value) (● (zonk-expr solution value) term))
                 ((None) (panic "internal error: unsolved field selection"))))
              ((FieldRead _ _ (None)) (panic "internal error: unchecked field selection"))
              ((If test then otherwise)
               (If (zonk-expr solution test)
                   (zonk-expr solution then)
                   (zonk-expr solution otherwise)))
              ((Let name value body)
               (Let name (zonk-expr solution value) (zonk-expr solution body)))
              ((Seq first rest) (Seq (zonk-expr solution first) (zonk-expr solution rest)))
              ((Match scrutinee clauses)
               (Match (zonk-expr solution scrutinee)
                      (map (lambda (clause) (Clause (zonk-pattern solution (● clause pattern))
                                                    (zonk-expr solution (● clause body))))
                           clauses)))
              ((ScopedInstances _ _) (panic "internal error: instance scope survived checking"))
              ((Ann inner type) (Ann (zonk-expr solution inner) (zonk solution type)))
              ((BoxAny inner) (BoxAny (zonk-expr solution inner)))
              ((Downcast inner target) (Downcast (zonk-expr solution inner) (zonk solution target)))
              ((Handle effect implementations body)
               (Handle effect
                       (map (lambda (entry)
                              (Pair (● entry first) (zonk-expr solution (● entry second))))
                            implementations)
                       (zonk-expr solution body))))
            (zonk solution (● expr type)) (● expr loc)))

    (define (zonk-pattern (solution Solution) (pattern Pattern)) (→ Pattern)
      (match pattern
        ((PWild type) (PWild (zonk solution type)))
        ((PVar name type) (PVar name (zonk solution type)))
        ((PLit value type) (PLit value (zonk solution type)))
        ((PCon constructor args type)
         (PCon constructor
               (map (lambda (arg) (zonk-pattern solution arg)) args)
               (zonk solution type)))))

    ;; ---- Free variables ----

    ;; The variable reads in `expr` of names it does not bind. Names are
    ;; unique, so a name bound anywhere inside is bound at all its reads.
    ;; Keep occurrences: handler captures need each read's method evidence.

    (define (outside-reads (expr Expr)) (→ (List Expr))
      (let ((bound (binders expr)))
        (filter (lambda (read)
                  (match (● read term)
                    ((Var name _ _) (not (member? name bound)))
                    (_ #f)))
                (variable-reads expr))))

    (define (variable-reads (expr Expr)) (→ (List Expr))
      (match (● expr term)
        ((Var _ _ _) (list expr))
        (_ (concatenate (map variable-reads (expr-children expr))))))

    (define (binders (expr Expr)) (→ (List String))
      (append (match (● expr term)
                ((Lambda params _ _) params)
                ((Let name _ _) (list name))
                ((Match _ clauses)
                 (concatenate
                  (map (lambda (clause) (pattern-variables (● clause pattern))) clauses)))
                (_ (Nil)))
              (concatenate (map binders (expr-children expr)))))

    (define (pattern-variables (pattern Pattern)) (→ (List String))
      (match pattern
        ((PVar name _) (list name))
        ((PCon _ args _) (concatenate (map pattern-variables args)))
        (_ (Nil))))

    ;; ---- Places ----

    ;; A written place selects a struct field. Enum fields are destructured
    ;; by match; mutable payloads can themselves be structs.
    (define (check-places-item (program Program) (item Item)) (→ Unit) (! compile)
      (match item
        ((Define _ value) (check-places program value))
        (_ (unit))))

    (define (check-places (program Program) (expr Expr)) (→ Unit) (! compile)
      (match (● expr term)
        ((App callee (Cons place (Cons _ (Nil))))
         (match (● callee term)
           ((Var name _ _)
            (when (or (string=? name "prim:set!") (string=? name "prim:replace!"))
              (check-place-links program place)))
           (_ (unit))))
        (_ (unit)))
      (for-each (lambda (child) (check-places program child)) (expr-children expr)))

    ;; A place resolves to its declared field and ordinary receiver expression.

    (define (check-place-links (program Program) (place Expr)) (→ Unit) (! compile)
      (match (place-link program place)
        ((Ok _) (unit))
        ((Err problem) (compile-error (● place loc) problem))))

    (define (place-link (program Program) (expr Expr)) (→ (Result (Pair Field Expr) String))
      (match (● expr term)
        ((Ann inner _) (place-link program inner))
        ((App callee (Cons record (Nil)))
         (match (● callee term)
           ((Var name _ evidence)
            (match (link-field program name)
              ((Ok field) (Ok (Pair field record)))
              ((Err problem) (Err problem))))
           (_ (Err not-a-place))))
        (_ (Err not-a-place))))

    (define not-a-place (→ String)
      "a place must select a field")

    (define (link-field (program Program) (name String))
      (→ (Result Field String))
      (match (program-value program name)
        ((Some (Accessor case index _)) (Ok (list-ref (● case fields) index)))
        (_ (Err not-a-place))))

    ;; ---- Closed functions ----

    ;; A closure that may not capture reads no local of the code around it:
    ;; only its parameters, the locals it binds, globals, and, when a `let`
    ;; binds it, its own name, which the backend reads from the closure
    ;; itself. Names are unique, so a read of a name it does not bind is a
    ;; read from outside, and one the program does not know is a local.

    (define (check-closed-item (program Program) (item Item)) (→ Unit) (! compile)
      (match item
        ((Define _ value) (check-closed program (Nil) value))
        (_ (unit))))

    ;; `own` is the name a `let` binds the closure to, if it does.

    (define (check-closed (program Program) (own (List String)) (expr Expr)) (→ Unit) (! compile)
      (match (● expr term)
        ((Lambda _ _ captures?)
         (unless captures?
           (match (filter (lambda (read) (captured-read? program own read)) (outside-reads expr))
             ((Cons read _)
              (compile-error (● read loc)
                             (string-append "a fn has no environment, so it cannot read the local "
                                            (local-name (var-name read))
                                            "; use lambda")))
             ((Nil) (unit)))))
        (_ (unit)))
      (match (● expr term)
        ((Let name value body)
         (check-closed program (list name) value)
         (check-closed program (Nil) body))
        (_ (for-each (lambda (child) (check-closed program (Nil) child)) (expr-children expr)))))

    (define (captured-read? (program Program) (own (List String)) (read Expr)) (→ Bool)
      (let ((name (var-name read)))
        (and (not (member? name own))
             (match (program-value program name)
               ((Some _) #f)
               ((None) #t)))))

    (define (var-name (read Expr)) (→ String)
      (match (● read term)
        ((Var name _ _) name)
        (_ (panic "internal error: a read is a variable"))))

    ;; ---- Explicit Any ----

    ;; An Any's TypeId keys its type without rows, so converting a function
    ;; that performs effects would let a caller forget them: a call through
    ;; the converted function would be charged nothing, and never tested for
    ;; a yield. Once a library's types are final, and before specialization
    ;; erases ordinary effects, each conversion refuses such a type, so an
    ;; Any never holds a function with effects and the rows a TypeId leaves
    ;; out are empty.

    (define (check-boxing (program Program) (item Item)) (→ Unit) (! compile)
      (match item
        ((Define _ value) (check-expression-boxing program value))
        (_ (unit))))

    (define (check-expression-boxing (program Program) (expr Expr)) (→ Unit) (! compile)
      (match (● expr term)
        ((BoxAny inner) (check-boxed-type program "Any" (● inner type) (● expr loc)))
        ((Downcast _ target) (check-boxed-type program "downcast" target (● expr loc)))
        (_ (unit)))
      (for-each (lambda (child) (check-expression-boxing program child)) (expr-children expr)))

    (define (check-boxed-type (program Program) (form String) (type Type) (loc Loc))
      (→ Unit) (! compile)
      (refuse-hidden-effects form type loc)
      (refuse-hidden-disposal program type loc)
      (refuse-function-reference form type loc))

    (define (refuse-hidden-disposal (program Program) (type Type) (loc Loc)) (→ Unit) (! compile)
      (match (lifecycle-rows program drop-class (Nil) (Nil) type)
        ((Ok rows)
         (unless (every? (lambda (row)
                           (let ((flat (flatten-row empty-solution row)))
                             (and (null? (● flat first))
                                  (match (● flat second) ((None) #t) (_ #f))))) rows)
           (compile-error loc "Any cannot hide disposal effects; keep this value's static type")))
        ((Err _)
         (compile-error loc "Any requires a value whose disposal is known to be effect-free"))))

    ;; An Any holds a reference to a GC object, and a fn's code reference
    ;; is not one, so neither side of a conversion is an Fn. Data holding
    ;; one is an object, and crosses.

    (define (refuse-function-reference (form String) (type Type) (loc Loc)) (→ Unit) (! compile)
      (match type
        ((TCon "fn" _)
         (compile-error loc
                        (string-append form
                                       " cannot take "
                                       (type->string type)
                                       ": an Any holds no function reference; wrap it in a lambda")))
        (_ (unit))))

    (define (refuse-hidden-effects (form String) (type Type) (loc Loc)) (→ Unit) (! compile)
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

    (define (cleanup-scope (ck Checker) (scope (List (Pair String Type))) (expr Expr) (taken? Bool))
      (→ (List (Pair String Type)))
      (let ((names (consumed-references (program-of ck) expr)))
        (filter (lambda (entry)
                  (let ((moved?
                         (and (linear? ck (● entry second)) (member? (● entry first) names))))
                    (if taken? (member? (● entry first) names) (not moved?)))) scope)))

    (define (cleanup-row (ck Checker) (callee Expr)) (→ Type)
      (match (● callee term)

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
                                                        (● callee type)))))
           (_ (cleanup-arrow-row ck (cleanup-global-type ck name types (● callee type))))))
        (_ (cleanup-arrow-row ck (● callee type)))))

    (define (cleanup-global-type (ck Checker) (name String) (types (List Type)) (fallback Type))
      (→ Type)
      (match (global-scheme ck name)
        ((Some scheme) (substitute (zip (● scheme vars) types) (● scheme type)))
        ((None) fallback)))

    ;; A method use's row is opened to its context during checking. Its
    ;; selected instance's head supplies the declared rows instead. Every
    ;; implementation is checked against this contract, so there is no need
    ;; to look up its separate definition to recover the same information.

    (define (cleanup-method-type (ck Checker)
                                 (class String)
                                 (name String)
                                 (types (List Type))
                                 (evidence (List Evidence))
                                 (fallback Type))
      (→ Type)
      (cleanup-global-type ck name
                           (selected-method-arguments
                            (program-of ck) class types
                            (map (lambda (value) (cleanup-evidence ck value)) evidence))
                           fallback))

    (define (cleanup-evidence (ck Checker) (evidence Evidence)) (→ Evidence)
      (match evidence
        ((EvHole id)
         (match (solved-evidence (solution ck) id)
           ((Some value) (cleanup-evidence ck value))
           ((None) evidence)))
        (_ evidence)))

    (define (cleanup-arrow-row (ck Checker) (type Type)) (→ Type)
      (match (fn-arrow (resolve-type (solution ck) type))
        ((TFun _ _ row) row)
        (_ empty-row)))

    (define (cleanup-control (ck Checker) (row Type)) (→ (List String))
      (let ((flat (flatten-row (solution ck) row)))
        (append (filter (lambda (label)
                          (match (table-ref (● (program-of ck) effects) label)
                            ((Some effect) (not (null? (● effect control))))
                            ((None) #f))) (● flat first))
                (match (● flat second)
                  ((None) (Nil))
                  ((Some (TVar _)) (list "?meta-control"))
                  (_ (list "?control"))))))

    ;; Which yields escape an expression, without entering lambdas. Declared
    ;; global rows avoid mistaking a pure call's opened use row for an effect.

    (define (cleanup-yields (ck Checker) (expr Expr)) (→ (List String))
      (match (● expr term)
        ((Lambda _ _ _) (Nil))

        ((App callee args)
         (label-union (cleanup-control ck (cleanup-row ck callee))
                      (cleanup-yields-all ck (Cons callee args))))
        ((Handle effect implementations body)
         (label-union (label-difference (cleanup-yields ck body) (list effect))
                      (fold-left (lambda (effects entry)
                                   (let ((value (● entry second)))
                                     (label-union effects
                                                  (match (● value term)
                                                    ((Lambda _ body _) (cleanup-yields ck body))
                                                    (_ (cleanup-control ck
                                                                        (cleanup-row ck value)))))))
                                 (Nil) implementations)))
        (_ (cleanup-yields-all ck (expr-children expr)))))

    (define (cleanup-yields-all (ck Checker) (exprs (List Expr))) (→ (List String))
      (fold-left (lambda (effects expr) (label-union effects (cleanup-yields ck expr)))
                 (Nil)
                 exprs))

    (define (charge-cleanup (ck Checker) (scope (List (Pair String Type)))
                            (handled (List String)) (row Type) (loc Loc))
      (→ Checker) (! compile)
      (fold-left (lambda (ck entry)
                   (charge-disposal ck (● entry second) handled row loc #f #t)) ck scope))

    ;; A procedure's row bounds destruction of its counted captures as well
    ;; as invocation. Its argument and result types do not affect that bound.
    (define (disposal-known? (type Type)) (→ Bool)
      (match type
        ((TVar _) #f)
        ((TFun _ _ row) (not (meta-tail? (● (flatten-row empty-solution row) second))))
        ((TCon _ args) (every? disposal-known? args))
        (_ #t)))

    ;; Unconstrained effect tails close at the final checking boundary.
    ;; Procedure arguments and results do not determine capture destruction.
    (define (final-disposal-type (type Type)) (→ Type)
      (match type
        ((TFun params result row) (TFun params result (zonk-row empty-solution row)))
        ((TCon name args) (TCon name (map final-disposal-type args)))
        (_ type)))

    (define (charge-disposal (ck Checker) (type Type) (handled (List String)) (row Type)
                             (loc Loc) (shared-only? Bool) (defer? Bool))
      (→ Checker) (! compile)
      (let* ((type (resolve-type (solution ck) type))
             (type (if defer? type (final-disposal-type type))))
        (cond ((not (disposal-known? type))
               (if defer?
                   (want ck
                         (WantCleanup type row handled (● ck givens) (● ck copy) shared-only? loc))
                   (compile-error loc
                                  "the disposal effects of this value are ambiguous; add a type annotation")))
              ((and shared-only? (linear? ck type)) ck)
              (else
               (match (lifecycle-rows (program-of ck) drop-class (● ck copy) (● ck givens) type)
                 ((Err problem) (compile-error loc problem))
                 ((Ok rows)
                  (fold-left (lambda (ck drop-row)
                               (let ((flat (flatten-row (solution ck) drop-row)))
                                 (perform ck (TRow (label-difference (● flat first) handled)
                                                   (● flat second)) row loc))) ck rows)))))))

    ;; A local's owner is released at its lexical exit. A direct outgoing
    ;; reference, immutable capture, or private result field keeps it alive.
    (define (charge-exit (ck Checker) (owners (List (Pair String Type))) (body Expr)
                         (handled (List String)) (row Type) (tail? Bool))
      (→ Checker) (! compile)
      (let ((survivors (surviving-references (program-of ck) body tail?)))
        (fold-left (lambda (ck owner)
                     (if (member? (● owner first) survivors) ck
                         (charge-disposal ck (● owner second) handled row (● body loc) #t #t)))
                   ck owners)))

    ;; Temporary observation/discard cannot finalize a local whose own
    ;; lexical reference remains live. A fresh closure's captures also have
    ;; their original owners here. Unknown call results carry only a type.
    (define (charge-temporary (ck Checker) (scope (List (Pair String Type))) (value Expr)
                              (handled (List String)) (row Type))
      (→ Checker) (! compile)
      (match (● value term)
        ;; The resolved fatal primitive produces no result owner. Its
        ;; operands were already visited by infer-cleanup; retain their effects.
        ((App (Expr (Var "prim:panic" _ _) _ _) _) ck)
        ((Var name _ _)
         (if (or (any? (lambda (entry) (string=? name (● entry first))) scope)
                 (match (program-value (program-of ck) name) ((Some _) #t) (_ #f))) ck
                 (charge-disposal ck (● value type) handled row (● value loc) #t #t)))
        ((Lambda _ _ _) ck)
        ((Ann inner _) (charge-temporary ck scope inner handled row))
        (_ (charge-disposal ck (● value type) handled row (● value loc) #t #t))))

    (define (cleanup-operation (ck Checker) (callee Expr)) (→ (Option Value))
      (match (● callee term)
        ((Var name _ _) (program-value (program-of ck) name))
        ((Ann inner _) (cleanup-operation ck inner))
        (_ (None))))

    ;; A replacement discards the old field; a swap returns it. The receiver
    ;; itself remains held across evaluation of the incoming expression.
    (define (cleanup-write (ck Checker) (callee Expr) (args (List Expr))
                           (handled (List String)) (row Type) (loc Loc))
      (→ Checker) (! compile)
      (match (Pair (● callee term) args)
        ((Pair (Var "prim:set!" _ _) (Cons place _))
         (charge-disposal ck (● place type) handled row loc #t #t))
        ((Pair (Var "prim:vector-copy!" _ _) (Cons destination _))
         (charge-disposal ck (● destination type) handled row loc #t #t))
        (_ (match (cleanup-operation ck callee)
             ((Some (Setter _ _ _))
              (charge-disposal ck (● (list-ref args 1) type) handled row loc #t #t))
             (_ (match (Pair (● callee term) args)
                  ((Pair (Var "prim:vector-set!" _ _) (Cons _ (Cons _ (Cons value _))))
                   (charge-disposal ck (● value type) handled row loc #t #t))
                  (_ ck)))))))

    (define (cleanup-observation (ck Checker) (scope (List (Pair String Type)))
                                 (callee Expr)
                                 (args (List Expr))
                                 (handled (List String))
                                 (row Type))
      (→ Checker) (! compile)
      (let ((operation (cleanup-operation ck callee)))
        (fold-left (lambda (ck entry)
                     (if (observes-argument? operation callee (● entry first))
                         (charge-temporary ck scope (● entry second) handled row) ck))
                   ck (zip (iota (length args)) args))))

    (define (charge-exceptional (ck Checker) (scope (List (Pair String Type)))
                                (handled (List String)) (row Type) (loc Loc))
      (→ Checker) (! compile)
      (fold-left (lambda (ck owner)
                   (let ((type (resolve-type (solution ck) (● owner second))))
                     (match (lifecycle-rows (program-of ck)
                                            drop-class
                                            (● ck copy)
                                            (● ck givens)
                                            type)
                       ((Ok _) (charge-disposal ck type handled row loc #f #t))
                       ((Err _) ck)))) ck scope))

    ;; A latent metavariable may later prove pure. Keep cancellation's
    ;; cleanup obligation until the call's actual control effects are known.
    (define (charge-escape (ck Checker) (scope (List (Pair String Type)))
                           (handled (List String)) (expr Expr) (row Type))
      (→ Checker) (! compile)
      (let ((effects (cleanup-yields ck expr)))
        (cond ((not (null? (label-difference effects (list "?meta-control"))))
               (charge-exceptional ck scope handled row (● expr loc)))
              ((member? "?meta-control" effects)
               (want ck (WantEscape scope expr row handled (● ck givens) (● ck copy))))
              (else ck))))

    ;; Earlier operands remain owned while later operands run. They are
    ;; represented as temporary owners here; ANF gives them real names later.

    (define (cleanup-operands (ck Checker)
                              (scope (List (Pair String Type)))
                              (handled (List String))
                              (exprs (List Expr))
                              (row Type))
      (→ Checker)
      (! compile)
      (match exprs
        ((Cons value rest)
         (let ((ck (infer-cleanup ck scope handled value row)))
           (cleanup-operands ck
                             (Cons (Pair "cleanup:operand" (● value type))
                                   (cleanup-scope ck scope value #f))
                             handled rest row)))
        ((Nil) ck)))

    (define (cleanup-pattern (pattern Pattern)) (→ (List (Pair String Type)))
      (match pattern
        ((PVar name type) (list (Pair name type)))
        ((PCon _ args _) (concatenate (map cleanup-pattern args)))
        (_ (Nil))))

    (define (infer-cleanup (ck Checker) (scope (List (Pair String Type)))
                           (handled (List String)) (expr Expr) (row Type))
      (→ Checker) (! compile)
      (infer-cleanup-at ck scope handled expr row #f))

    (define (infer-cleanup-at (ck Checker) (scope (List (Pair String Type)))
                              (handled (List String)) (expr Expr) (row Type) (tail? Bool))
      (→ Checker) (! compile)
      (match (● expr term)
        ((Lambda _ _ _) ck)
        ((Let name value body)
         (let* ((ck (infer-cleanup ck scope handled value row))
                (owner (Pair name (● value type)))
                (ck (infer-cleanup-at ck (Cons owner (cleanup-scope ck scope value #f))
                                      handled body row tail?)))
           (charge-exit ck (list owner) body handled row tail?)))
        ((Seq first rest)
         (let* ((ck (infer-cleanup ck scope handled first row))
                (ck (charge-temporary ck scope first handled row)))
           (infer-cleanup-at ck (cleanup-scope ck scope first #f) handled rest row tail?)))
        ((If test then otherwise)
         (let* ((ck (infer-cleanup ck scope handled test row))
                (after (cleanup-scope ck scope test #f)))
           (infer-cleanup-at (infer-cleanup-at ck after handled then row tail?)
                             after handled otherwise row tail?)))
        ((Match value clauses)
         (let* ((ck (infer-cleanup ck scope handled value row))
                (ck (charge-temporary ck scope value handled row))
                (after (cleanup-scope ck scope value #f)))
           (fold-left (lambda (ck clause)
                        (let* ((owners (cleanup-pattern (● clause pattern)))
                               (body (● clause body))
                               (ck
                                (infer-cleanup-at ck (append owners after) handled body row tail?)))
                          (charge-exit ck owners body handled row tail?))) ck clauses)))
        ((Handle effect implementations body)
         (let* ((values (map (lambda (entry) (● entry second)) implementations))
                (ck (cleanup-operands ck scope handled values row))
                (ck
                 (infer-cleanup ck (cleanup-scope ck scope body #t) (Cons effect handled) body row))
                (ck (fold-left (lambda (ck value) (charge-temporary ck scope value handled row))
                               ck
                               values)))
           (charge-escape ck (cleanup-scope ck scope expr #f) handled expr row)))
        ((App callee args)
         (let* ((ck (cleanup-operands ck scope handled (Cons callee args) row))
                (ck (cleanup-observation ck scope callee args handled row))
                (ck (cleanup-write ck callee args handled row (● expr loc))))
           (charge-escape ck (cleanup-scope ck scope expr #f) handled expr row)))

        (_ (fold-left (lambda (ck child) (infer-cleanup ck scope handled child row))
                      ck (expr-children expr)))))

    (define (cleanup-lambda (ck Checker) (params (List String)) (types (List Type))
                            (body Expr) (row Type))
      (→ Checker) (! compile)
      (let* ((captured
              (concatenate
               (map (lambda (name)
                      (match (table-ref (● ck locals) name)
                        ((Some type) (if (member? name params) (Nil) (list (Pair name type))))
                        ((None) (Nil)))) (expr-references body))))
             (owners (zip params types))
             (ck (charge-cleanup ck captured (Nil) row (● body loc)))
             (ck (infer-cleanup-at ck (append owners captured) (Nil) body row #t)))
        (charge-exit ck owners body (Nil) row #t)))

    ;; ---- Definitions ----

    ;; An unannotated group of mutually recursive definitions is inferred
    ;; together. A group of functions is generalized; any other group stays
    ;; monomorphic, so later uses can still decide its types.

    (define (check-group (ck Checker) (definitions (List Item)) (exposed (List String)))
      (→ (Pair (List Item) Checker))
      (! compile)
      (let ((before (● ck pending-count)))
        (learning ck ((then (provisional-schemes definitions))
                      (results (each infer-definition definitions))
                      (then (host-effects results))
                      (then (generalize-group definitions before exposed)))
                  (Pair (map (lambda (pair)
                               (Define (match (● pair first)
                                         ((Define definition-name _)
                                          definition-name)
                                         (_ (panic "internal error: expected Define")))
                                 (● (● pair second) first)))
                             (zip definitions results))
                        (Checker-open-set ck
                                          (append (map (lambda (definition)
                                                         (match definition
                                                           ((Define definition-name
                                                              _)
                                                            definition-name)
                                                           (_ (panic
                                                               "internal error: expected Define"))))
                                                       definitions)
                                                  (● ck open)))))))

    ;; Each definition in the group starts with a monomorphic metavariable, so
    ;; the group's members can refer to one another while it is inferred.

    (define (provisional-schemes (ck Checker) (definitions (List Item))) (→ Checker)
      (fold-left (lambda (ck definition)
                   (match definition
                     ((Define definition-name definition-value)
                      (learning ck ((type (local-placeholder definition-name
                                                             definition-value)))
                                (set-scheme ck definition-name (mono-scheme type))))
                     (_ (panic "internal error: expected Define"))))
                 ck definitions))

    (define (host-effects (ck Checker) (results (List (Pair Expr Type)))) (→ Checker) (! compile)
      (fold-left (lambda (ck result)
                   (unless (total? (solution ck) (● result second))
                     (compile-error (● (● result first) loc)
                                    "a top-level value must be effect-free; put runtime work in a function"))
                   (check-host-effects ck (● result second) (● (● result first) loc)))
                 ck results))

    ;; A group of functions is generalized over the constraints it raised;
    ;; any other group stays monomorphic, so later uses can still decide it.

    (define (generalize-group (ck Checker)
                              (definitions (List Item))
                              (before I64)
                              (exposed (List String)))
      (→ Checker)
      (if (every? (lambda (definition) (match definition
                                         ((Define _ definition-value)
                                          (lambda-expr? definition-value))
                                         (_ (panic "internal error: expected Define"))))
                  definitions)
          (generalize ck
                      definitions
                      (take (● ck pending) (- (● ck pending-count) before))
                      exposed)
          ck))

    ;; The checked value and the effect row of its initializer.

    (define (infer-definition (ck Checker) (definition Item))
      (→ (Pair (Pair Expr Type) Checker))
      (! compile)
      (match definition
        ((Define definition-name definition-value)
         (learning ck ((row (fresh-meta))
                       (value (infer-definition-value
                               definition-value
                               (scheme-type ck
                                            definition-name)
                               row))
                       (then (infer-cleanup (Nil)
                                            (Nil)
                                            value
                                            row))
                       (then (unify (scheme-type ck
                                                 definition-name)
                                    (● value type)
                                    (● value loc))))
                   (unless (total? (solution ck) row)
                     (compile-error (● value loc)
                                    "a top-level value must be effect-free; put runtime work in a function"))
                   (Pair (Pair value row) ck)))
        (_ (panic "internal error: expected Define"))))

    (define (infer-definition-value (ck Checker) (value Expr) (type Type) (row Type))
      (→ (Pair Expr Checker))
      (! compile)
      (if (lambda-expr? value)
          (infer-local-lambda ck value type)
          (infer ck value row)))

    (define (scheme-type (ck Checker) (name String)) (→ Type)
      (match (table-ref (● ck schemes) name)
        ((Some scheme) (● scheme type))
        ((None) (panic (string-append "internal error: no scheme for " name)))))

    ;; A metavariable becomes a quantified variable (`t1`, `t2`, ...) unless
    ;; something that outlives the group still mentions it: another
    ;; definition's type, or a constraint of this group.

    (define (generalize (ck Checker)
                        (definitions (List Item))
                        (wanted (List Wanted))
                        (exposed (List String)))
      (→ Checker)
      (let* ((fixed (map meta-id
                         (append (concatenate (map (lambda (name)
                                                     (free-metas (solution ck)
                                                                 (scheme-type ck name)))
                                                   (● ck open)))
                                 (append (concatenate
                                          (map (lambda (want) (wanted-metas (solution ck) want))
                                               wanted))
                                         (exposed-row-metas ck definitions exposed)))))
             (metas (filter (lambda (meta) (not (member? (meta-id meta) fixed)))
                            (delete-duplicates same-meta?
                                               (concatenate (map (lambda (d)
                                                                   (match d
                                                                     ((Define definition-name
                                                                        _)
                                                                      (free-metas (solution ck)
                                                                                  (scheme-type ck
                                                                                               definition-name)))
                                                                     (_
                                                                      (panic
                                                                       "internal error: expected Define"))))
                                                                 definitions)))))
             (names (map (lambda (index) (string-append "t" (i64->string (+ index 1))))
                         (iota (length metas))))
             ;; Generalization binds a metavariable to a quantified name, like
             ;; any other solution; nothing distinguishes the two afterwards.
             (bound (fold-left (lambda (ck pair)
                                 (bind-solved ck (● pair first) (TRigid (● pair second))))
                               ck (zip metas names))))
        (fold-left (lambda (ck definition)
                     (match definition
                       ((Define definition-name _)
                        (let ((name definition-name))
                          (set-scheme ck
                                      name
                                      (Scheme names
                                              (Nil)
                                              (Nil)
                                              (resolve-type
                                               (solution
                                                ck)
                                               (scheme-type
                                                ck
                                                name))))))
                       (_ (panic "internal error: expected Define"))))
                   bound definitions)))

    ;; A foreign caller supplies no row argument. Keep an inferred export's
    ;; row open for instance solving instead of quantifying that row. Its
    ;; ordinary type variables still generalize and are refused by expose.

    (define (exposed-row-metas (ck Checker) (definitions (List Item)) (exposed (List String)))
      (→ (List Type))
      (concatenate
       (map (lambda (definition)
              (match definition
                ((Define definition-name _)
                 (if (member? definition-name exposed)
                     (match (fn-arrow
                             (resolve-type (solution ck)
                                           (scheme-type ck
                                                        definition-name)))
                       ((TFun _ _ row)
                        (free-metas (solution ck) row))
                       (_ (Nil)))
                     (Nil)))
                (_ (panic "internal error: expected Define")))) definitions)))

    (define (meta-id (meta Type)) (→ I64)
      (match meta
        ((TVar id) id)
        (_ -1)))

    ;; A type bound to a Copy variable. A variable of the enclosing
    ;; definition that it does not declare ω is linear, so the definition
    ;; must declare it; a concrete linear type cannot be bound at all.

    (define (check-copy (ck Checker) (type Type) (copy (List String)) (loc Loc))
      (→ Unit)
      (! compile)
      (match (copy-refusal (program-of ck)
                           copy
                           (resolve-type (solution ck) type)
                           "a type variable requires an unrestricted type")
        ((Some refusal) (compile-error loc refusal))
        ((None) (unit))))

    (define (wanted-metas (solution Solution) (want Wanted)) (→ (List Type))
      (match want
        ((WantPerformed _ _ rows _)
         (concatenate (map (lambda (row) (free-metas solution row)) rows)))
        ((WantInclusion latent row _)
         (append (free-metas solution latent) (free-metas solution row)))
        ((WantEscape scope expr row _ _ _)
         (append (free-metas solution row)
                 (concatenate (map (lambda (owner) (free-metas solution (● owner second))) scope))))
        ((WantField projection)
         (concatenate (map (lambda (type) (free-metas solution type))
                           (list (● projection record type) (● projection result)
                                 (● projection row)))))
        ((WantClass constraint _ _ _ _ _)
         (concatenate
          (map (lambda (type) (free-metas solution type)) (● constraint types))))
        ((WantCleanup type row _ _ _ _ _)
         (append (free-metas solution type) (free-metas solution row)))
        ((WantLiteral _ type _) (free-metas solution type))
        ((WantCopy _ _ _) (Nil))))

    (define (free-metas (solution Solution) (type Type)) (→ (List Type))
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

    (define (check-annotated (ck Checker) (definition Item) (scheme Scheme))
      (→ (Pair Item Checker))
      (! compile)
      (match definition
        ((Define _ definition-value)
         (check-associated-givens (program-of ck) (● scheme constraints)
                                  (● definition-value loc))
         (within ck
                 (Checker-copy-set (Checker-givens-set ck
                                                       (if (null? (● scheme vars))
                                                           (Nil)
                                                           (● scheme constraints)))
                                   (● scheme copy))
                 (lambda (inner) (check-annotated-value inner definition scheme))))
        (_ (panic "internal error: expected Define"))))

    ;; A projection has one witness. Distinct rows or output equalities
    ;; cannot disambiguate two requirements with the same selecting inputs.

    (define (check-associated-givens (program Program) (givens (List Constraint)) (loc Loc))
      (→ Unit)
      (! compile)
      (match givens
        ((Nil) (unit))
        ((Cons given rest)
         (let ((class (program-class program (● given class))))
           (when (and (not (null? (● class outputs)))
                      (any? (lambda (other) (given-for? class (● given types) other))
                            rest))
             (compile-error loc "associated projection matches multiple requirements"))
           (check-associated-givens program rest loc)))))

    (define (check-annotated-value (ck Checker) (definition Item) (scheme Scheme))
      (→ (Pair Item Checker))
      (! compile)
      ;; Monomorphic roots run without evidence parameters. Their closed
      ;; requirements must be proved, not assumed by their initializer.
      (match definition
        ((Define definition-name definition-value)
         (learning ck ((then (want-closed-requirements scheme (● definition-value loc)))
                       (row (fresh-meta))
                       (value (check-value definition-value (● scheme type) row))
                       (value (fit (● scheme type) value row (● value loc)))
                       (then (infer-cleanup (Nil) (Nil) value row))
                       (then (check-host-effects row (● value loc))))
                   (unless (total? (solution ck) row)
                     (compile-error (● value loc)
                                    "a top-level value must be effect-free; put runtime work in a function"))
                   (Pair (Define definition-name value)
                         (want-performed ck definition scheme))))
        (_ (panic "internal error: expected Define"))))

    ;; A signature's row says what calling the function may do, so it may
    ;; not name an effect the body never performs. A lambda was checked by
    ;; `check-lambda`, so `performed` holds what its body performed. An
    ;; instance method has its class's row, which this instance may need
    ;; less of, and a value other than a lambda has no body of its own, so
    ;; neither is held to it. A default is: its `default` entry is its
    ;; signature (expand.sld's `snail-defaults`).

    (define (want-performed (ck Checker) (definition Item) (scheme Scheme)) (→ Checker)
      (match definition
        ((Define definition-name definition-value)
         (match (Pair (signature-loc (program-of ck) definition-name)
                      (fn-arrow (● scheme type)))
           ((Pair (Some loc) (TFun _ _ row))
            (if (lambda-expr? definition-value)
                (want ck (WantPerformed definition-name row (● ck performed) loc)) ck))
           (_ ck)))
        (_ (panic "internal error: expected Define"))))

    (define (check-performed (ck Checker) (want Wanted)) (→ Unit) (! compile)
      (match want
        ((WantPerformed name declared performed loc)
         (match (unperformed-effects declared
                                     (concatenate (map (lambda (row)
                                                         (let ((flat
                                                                (flatten-row (solution ck) row)))
                                                           (append (● flat first)
                                                                   (tail-variable
                                                                    (● flat second)))))
                                                       performed)))
           ((Nil) (unit))
           (effects (compile-error loc
                                   (unperformed-message (definition-label (program-of ck) name)
                                                        effects)))))
        (_ (unit))))

    ;; How an error names a definition: a default by its operation, since
    ;; its global's name is generated.

    (define (definition-label (program Program) (name String)) (→ String)
      (match (find (lambda (default) (string=? (● default second) name))
                   (concatenate
                    (map (lambda (record) (● record defaults)) (table-values (● program effects)))))
        ((Some default) (string-append "the default of " (short-name (● default first))))
        ((None) (short-name name))))

    (define (unperformed-message (label String) (effects (List String))) (→ String)
      (let ((one (= (length effects) 1)))
        (string-append label
                       " declares the effect"
                       (if one "" "s")
                       (labels->string effects)
                       " but never performs " (if one "it" "them"))))

    (define (want-closed-requirements (ck Checker) (scheme Scheme) (loc Loc)) (→ Checker)
      (if (null? (● scheme vars))
          (fold-left (lambda (ck constraint) (● (want-class ck constraint loc) second))
                     ck
                     (● scheme constraints))
          ck))

    ;; A program's body runs as its first task when it links the scheduler,
    ;; under the handler of every effect declared `around-main`, so the
    ;; body may perform those besides what the host implements.

    (define (check-entry (ck Checker) (name String) (loc Loc)) (→ Checker) (! compile)
      (match (global-scheme ck name)
        ((Some (Scheme (Nil) (Nil) _ type))
         (match (resolve-type (solution ck) type)
           ((TFun (Nil) (TCon "Unit" (Nil)) row) (check-body-effects ck row loc))
           (_
            (compile-error loc "main must be a function taking no arguments and returning Unit"))))
        (_ (compile-error loc
                          "main must be a monomorphic function taking no arguments and returning Unit"))))

    (define (check-body-effects (ck Checker) (row Type) (loc Loc)) (→ Checker) (! compile)
      (check-effects-with ck row loc (lambda (effect) (● effect around-main))))

    ;; The host may retain unrestricted values, holding managed references
    ;; opaquely. Linear ownership cannot cross this unrestricted boundary.
    ;; The trusted host respects Snail Scheme types and implements the declared effects.
    ;; What is exposed is a definition's code: a foreign function, a
    ;; constructor or an operation has none.

    (define (check-exposed (ck Checker) (name String) (dynamic Bool) (loc Loc))
      (→ Checker)
      (! compile)
      (match (program-value (program-of ck) name)
        ((Some (Defined _ _ _)) (unit))
        (_ (compile-error loc "an exposed function must be defined")))
      (match (global-scheme ck name)
        ((Some (Scheme (Nil) (Nil) _ type))
         (check-exposed-type ck (resolve-type (solution ck) type) dynamic loc))
        (_ (compile-error loc "an exposed function must be a monomorphic function"))))

    ;; Inferred values may still name their solved metavariable here. Host
    ;; exports obey the same boundary whether their type was written or inferred.

    (define (check-exposed-type (ck Checker) (type Type) (dynamic Bool) (loc Loc))
      (→ Checker)
      (! compile)
      (unit)
      (match (fn-arrow type)
        ((TFun params result row)
         (when (any? (lambda (type) (linear? ck type)) (Cons result params))
           (compile-error loc "an exposed function cannot take or return a linear value"))
         (when dynamic (check-dynamic ck (Cons result params) row loc))
         (check-result-disposal ck result loc)
         (check-host-effects ck row loc))
        (_ (compile-error loc "an exposed function must be a monomorphic function"))))

    ;; The host eventually releases each returned owner under empty evidence.
    ;; Its cleanup must be supported there even when the caller first closes
    ;; the object: a convention does not change the result's static type.
    (define (check-result-disposal (ck Checker) (type Type) (loc Loc)) (→ Unit) (! compile)
      (match (lifecycle-rows (program-of ck) drop-class (Nil) (Nil) type)
        ((Err problem) (compile-error loc problem))
        ((Ok rows)
         (for-each (lambda (row)
                     (unless (match (● (flatten-row (solution ck) row) second)
                               ((None) #t) (_ #f))
                       (compile-error loc "an exposed result must have known disposal effects"))
                     (check-host-effects ck row loc)
                     (unit)) rows))))

    ;; A program that loads a dynamic export trusts nothing of it but its
    ;; signature, which names each type by its TypeId, so every parameter
    ;; and the result must be data that a TypeId describes. Effects are
    ;; erased before the backend writes the signature, so a program that
    ;; loads the function could not check them: a dynamic export is pure.

    (define (check-dynamic (ck Checker) (types (List Type)) (row Type) (loc Loc))
      (→ Unit)
      (! compile)
      (unless (every?
               (lambda (type) (first-order-type? (program-of ck) (resolve-type (solution ck) type)))
               types)
        (compile-error loc
                       "a dynamic export takes and returns only data, with no function or Any inside"))
      (unless (null? (● (flatten-row (solution ck) row) first))
        (compile-error loc
                       "a dynamic export cannot perform effects: the program that loads it could not check them")))

    ;; Effects performed at program start need defaults for every
    ;; operation; the builtin effects are the host's own.

    (define (check-host-effects (ck Checker) (row Type) (loc Loc)) (→ Checker) (! compile)
      (check-effects-with ck row loc (lambda (effect) #f)))

    ;; The effects of `row` must each be the host's: builtin, with a default
    ;; for every operation, or `allowed` otherwise.

    (define (check-effects-with (ck Checker)
                                (row Type)
                                (loc Loc)
                                (allowed (Fn Effect → Bool)))
      (→ Checker)
      (! compile)
      (for-each (lambda (label)
                  (unless (or (member? label (list "mut" "host"))
                              (let ((effect (program-effect (program-of ck) label)))
                                (or (allowed effect)
                                    (= (length (● effect defaults))
                                       (length (● effect operations))))))
                    (compile-error loc
                                   (string-append "the effect "
                                                  (short-name label)
                                                  " has no host implementation here"))))
                (● (flatten-row (solution ck) row) first))
      ck)

    ;; ---- Programs ----

    ;; A program is checked a library at a time, in program order, so each
    ;; library's types are settled within it, as they must be when libraries
    ;; are compiled apart: an unannotated value takes its type from its own
    ;; library, never from a library that imports it.

    (define (check-program (program Program)) (→ Typed) (! compile)
      (let loop ((libraries (library-items program (program-items program)))
                 (items (Nil))
                 (schemes empty-table))
        (match libraries
          ((Cons library rest)
           (let ((typed (check-library program schemes (● library second))))
             (loop rest (append items (● typed items)) (● typed schemes))))
          ((Nil) (Typed program items schemes)))))

    ;; One library's items, checked after the libraries before it: `schemes`
    ;; holds their definitions' schemes, and the result holds those and the
    ;; new ones. Unannotated definitions are checked first, in dependency
    ;; order; then annotated definitions and statements, which only need
    ;; schemes. Then every constraint is solved and every type zonked.

    (define (check-library (program Program) (schemes (Table Scheme)) (items (List Item)))
      (→ Typed)
      (! compile)
      (let ((ck (Checker program
                         empty-table
                         (Nil)
                         (Nil)
                         (Nil)
                         (Nil)
                         (None)
                         0
                         empty-solution
                         schemes
                         (Nil)
                         0
                         (Nil)
                         (Nil))))
        (learning ck ((typed (check-items items))
                      (then (solve-pending))
                      (then (check-exposures items)))
                  (let ((result
                         (Typed program
                                (map (lambda (item) (zonk-item (solution ck) item)) typed)
                                (final-schemes ck items))))
                    (for-each (lambda (item) (check-boxing program item)) (● result items))
                    (check-final result)
                    result))))

    ;; Check each item at its final types and report failures in source order.

    (define (check-final (typed Typed)) (→ Unit) (! compile)
      (let ((program (● typed program)) (schemes (● typed schemes)))
        (check-owned-fields program)
        (fail-if-found
         (in-source-order
          (failures-of (lambda (item) (check-final-item program schemes item))
                       (● typed items))))))

    (define (check-final-item (program Program) (schemes (Table Scheme)) (item Item))
      (→ Unit)
      (! compile)
      (check-closed-item program item)
      (check-places-item program item)
      (check-item-ownership program schemes item))

    (define (check-exposures (ck Checker) (items (List Item))) (→ Checker) (! compile)
      (fold-left (lambda (ck item)
                   (match item
                     ((Expose name _ dynamic loc) (check-exposed ck name dynamic loc))
                     ((Entry name loc) (check-entry ck name loc))
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

    (define (check-items (ck Checker) (items (List Item)))
      (→ (Pair (List Item) Checker))
      (! compile)
      (let* ((exposed (concatenate (map (lambda (item)
                                          (match item
                                            ((Expose name _ _ _) (list name))
                                            ((Entry name _) (list name))
                                            (_ (Nil))))
                                        items)))
             (groups (each-recovered (Recovered ck (Nil) (Nil) (Nil))
                                     group-references
                                     (lambda (group)
                                       (map (lambda (definition)
                                              (match definition
                                                ((Define definition-name _)
                                                 definition-name)
                                                (_ (panic "internal error: expected Define"))))
                                            group))
                                     (lambda (ck group) (check-group ck group exposed))
                                     (unannotated-groups ck items)))
             (results (fold-left
                       (lambda (results result) (match result
                                                  ((Define definition-name _)
                                                   (table-set results definition-name result))
                                                  (_ (panic "internal error: expected Define"))))
                       empty-table (concatenate (● groups values))))
             (checked (each-recovered (Recovered (● groups checker)
                                                 (Nil)
                                                 (● groups found)
                                                 (● groups failed))
                                      item-references
                                      (lambda (item) (Nil))
                                      (lambda (ck item) (check-item ck results item))
                                      items)))
        (fail-if-found (in-source-order (● checked found)))
        (Pair (● checked values) (● checked checker))))

    (define (group-references (definitions (List Item))) (→ (List String))
      (concatenate (map (lambda (definition) (match definition
                                               ((Define _ definition-value)
                                                (expr-references definition-value))
                                               (_ (panic "internal error: expected Define"))))
                        definitions)))

    ;; A definition refers to itself too, so one whose group failed is
    ;; not checked again.

    (define (item-references (item Item)) (→ (List String))
      (match item
        ((Define name value) (Cons name (expr-references value)))
        ((Expose name _ _ _) (list name))
        ((Entry name _) (list name))))

    (define (unannotated-groups (ck Checker) (items (List Item))) (→ (List (List Item)))
      (definition-groups
        (filter (lambda (item)
                  (match item
                    ((Define name _)
                     (match (annotated-scheme (program-of ck) name) ((None) #t) ((Some _) #f)))
                    (_ #f)))
                items)))

    (define (check-item (ck Checker) (results (Table Item)) (item Item))
      (→ (Pair Item Checker))
      (! compile)
      (match item
        ((Define name _)
         (match (table-ref results name)
           ((Some result) (Pair result ck))
           ((None)
            (match (annotated-scheme (program-of ck) name)
              ((Some scheme) (check-annotated ck item scheme))
              ((None) (panic "internal error: unchecked definition"))))))
        (_ (Pair item ck))))

    (define (zonk-item (solution Solution) (item Item)) (→ Item)
      (match item
        ((Define name value) (Define name (zonk-expr solution value)))
        (_ item)))

    ;; Inferred schemes with their remaining metavariables defaulted, and the
    ;; signatures of annotated definitions.

    (define (final-schemes (ck Checker) (items (List Item))) (→ (Table Scheme))
      (let ((defaulted (fold-left (lambda (ck name)
                                    (match (table-ref (● ck schemes) name)
                                      ((Some scheme)
                                       (set-scheme ck
                                                   name
                                                   (Scheme (● scheme vars)
                                                           (● scheme constraints)
                                                           (● scheme copy)
                                                           (zonk (solution ck)
                                                                 (● scheme type)))))
                                      ((None) ck)))
                                  ck (● ck open))))
        (● (fold-left (lambda (ck item)
                        (match item
                          ((Define name _)
                           (match (annotated-scheme (program-of ck) name)
                             ((Some scheme) (set-scheme ck name scheme))
                             ((None) ck)))
                          (_ ck)))
                      defaulted items) schemes)))

    (define (annotated-scheme (program Program) (name String)) (→ (Option Scheme))
      (match (program-value program name)
        ((Some (Defined (Some scheme) _ _)) (Some scheme))
        (_ (None))))

    ;; Where a definition's own signature was written, if it has one.

    (define (signature-loc (program Program) (name String)) (→ (Option Loc))
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

    (define (each-recovered (start (Recovered B))
                            (references (Fn A → (List String)))
                            (names (Fn A → (List String)))
                            (step (Fn Checker A → (Pair B Checker) ! compile))
                            (items (List A)))
      (→ (Recovered B))
      (! compile e)
      (∀ (A B e))
      (⊨ (Copy A) (Copy B) (Drop e B) (Drop e A))
      (let ((done (fold-left (lambda (done item) (recover done references names step item))
                             start
                             items)))
        (Recovered-values-set done (reverse (● done values)))))

    (define (recover (done (Recovered B))
                     (references (Fn A → (List String)))
                     (names (Fn A → (List String)))
                     (step (Fn Checker A → (Pair B Checker) ! compile))
                     (item A))
      (→ (Recovered B))
      (! compile e)
      (∀ (A B e))
      (⊨ (Copy A) (Copy B) (Drop e B) (Drop e A))
      (let ((failed (● done failed)))
        (if (any? (lambda (name) (member? name failed)) (references item))
            (Recovered-failed-set done (append (names item) failed))
            (match (recovering (lambda () (step (● done checker) item)))
              ((Ok (Pair value ck))
               (Recovered ck (Cons value (● done values)) (● done found) failed))
              ((Err found)
               (Recovered-failed-set
                (Recovered-found-set done (append (● done found) (diagnostics->list found)))
                (append (names item) failed)))))))

    ;; ---- Dependency order ----

    ;; The definitions in groups that refer to one another, each group after
    ;; the groups it refers to. Definitions are numbered in program order.

    (define (definition-groups (definitions (List Item))) (→ (List (List Item)))
      (let* ((nodes (list->vector definitions))
             (numbers (fold-left (lambda (table index)
                                   (table-set table
                                              (match (vector-ref nodes index)
                                                ((Define definition-name _)
                                                 definition-name)
                                                (_ (panic "internal error: expected Define")))
                                              index))
                                 empty-table (iota (vector-length nodes)))))
        (map (lambda (component) (map (lambda (index) (vector-ref nodes index)) component))
             (strong-components
              (vector-map (lambda (definition) (definition-edges numbers definition)) nodes)))))

    ;; The numbers of the definitions `definition` refers to, in order of
    ;; first reference.

    (define (definition-edges (numbers (Table I64)) (definition Item)) (→ (List I64))
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
      (define test-check
        (lambda () (expect (unperformed-effects (TRow (list "mut" "snail.core.io:console") (None))
                                                (list "snail.core.io:console"))
                           (list "mut"))
                (expect (unperformed-effects (TRow (list "mut") (Some (TRigid "e"))) (list "mut"))
                        (list "e"))
                (expect
                 (unperformed-effects (TRow (list "mut") (Some (TRigid "e"))) (list "e" "mut"))
                 (Nil))
                (expect (unperformed-message "double" (list "mut"))
                        "double declares the effect mut but never performs it")
                (expect (unperformed-message "f" (list "snail.core.io:console" "e"))
                        "f declares the effects console e but never performs them")))))
   (else)))

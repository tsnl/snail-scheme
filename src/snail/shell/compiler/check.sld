;; Hindley-Milner checking with effect rows and typeclass evidence. Each
;; expression is rebuilt with its type; each variable records the type
;; arguments and the evidence of its instantiation, so later passes never
;; repeat inference or instance selection.
(define-library (snail shell compiler check)
  (export
   Typed
   definition-scheme
   check-program)
  (import
   (snail core base)
   (snail core table)
   (snail shell compiler read)
   (snail shell compiler core))
  (begin

    ;; ---- Checker state ----

    ;; Scope holds the names and class requirements visible at this point.
    ;; Learning holds the substitutions and obligations accumulated so far.
    ;; A signed body's row identity records which declared effects it uses;
    ;; nested lambdas restore the enclosing body's record on return.
    ;; `waiting` holds the field selections whose receiver's type is not
    ;; yet known, newest first.
    (record Checker
      ((program Program)
       (locals (Table Type))
       (givens (List Constraint))
       (resolving (List Constraint))
       (signed (Option I64))
       (counter I64)
       (solution Solution)
       (schemes (Table Scheme))
       (wanted (List Wanted))
       (waiting (List Projection))
       (open (List String))
       (performed (List Type))))

    ;; A sub-check that ran under its own scope, resumed in the caller's:
    ;; everything it learned stays, every scoped field is the caller's again.
    ;; One place names which fields are which, so a sub-check cannot leak the
    ;; scope it ran under.

    (define (resumed (outer Checker) (inner Checker)) (→ Checker)
      (new Checker (program (● outer program))
           (locals (● outer locals))
           (givens (● outer givens))
           (resolving (● outer resolving))
           (signed (● outer signed))
           (counter (● inner counter))
           (solution (● inner solution))
           (schemes (● inner schemes))
           (wanted (● inner wanted))
           (waiting (● inner waiting))
           (open (● inner open))
           (performed (● inner performed))))

    ;; What checking has learned: each metavariable's identity to the type it
    ;; stands for, each evidence hole's to its evidence, and each field
    ;; selection's to the field it selects. A `Type` and an
    ;; `Expr` are plain data, so reading one means reading it through a
    ;; solution. `check-library` allocates one, refines it, and zonks it away
    ;; before returning, so neither it nor a metavariable outlives the call.
    (record Solution
      ((types (Table Type))
       (evidence (Table Evidence))
       (projections (Table Slot))))

    ;; The field a selection resolved to: one of a record case's fields,
    ;; with the record type's arguments, and the field's type under them.

    (record Slot
      ((case Case)
       (index I64)
       (args (List Type))
       (type Type)))

    (define empty-solution
      (→ Solution)
      (new Solution (types (empty-table)) (evidence (empty-table)) (projections (empty-table))))

    ;; Identities are dense small integers from one counter, so a key is just
    ;; its decimal text.

    (define (identity-key (id I64)) (→ String)
      (i64->string id))

    (define (solved-type (solution Solution) (id I64)) (→ (Option Type))
      (table-ref (● solution types) (identity-key id)))

    (define (solved-evidence (solution Solution) (id I64)) (→ (Option Evidence))
      (table-ref (● solution evidence) (identity-key id)))

    ;; A field selection waits for its receiver's nominal type; its result
    ;; participates in inference.
    (record Projection
      ((record Expr)
       (label String)
       (result Type)
       (hole I64)
       (loc Loc)))

    ;; An obligation. A class constraint keeps the givens in scope where it
    ;; arose.
    (enum Wanted
      (WantPerformed ((name String) (declared Type) (performed (List Type)) (loc Loc)))
      (WantInclusion ((latent Type) (context Type) (loc Loc)))
      (WantClass ((constraint Constraint)
                  (hole I64)
                  (givens (List Constraint))
                  (loc Loc)))
      (WantLiteral
       ((value Datum)
        (type Type)
        (loc Loc))))

    ;; The checker's output: typed items in program order and every
    ;; definition's scheme.
    (record Typed
      ((program Program)
       (items (List Item))
       (schemes (Table Scheme))))

    (define (definition-scheme (typed Typed) (name String)) (→ Scheme)
      (match (table-ref (● typed schemes) name)
        ((Some scheme) scheme)
        ((None) (panic (string-append "internal error: no scheme for " name)))))

    (define (solution (ck Checker)) (→ Solution)
      (● ck solution))

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
        (new Pair (first id) (second (Checker-counter-set ck id)))))

    ;; ---- Metavariables and unification ----

    (define (fresh-meta (ck Checker)) (→ (Pair Type Checker))
      (threading ck ((id (fresh-identity)))
                 (new Pair (first (TVar id)) (second ck))))

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

    (define (unify (ck Checker) (expected Type) (actual Type) (loc Loc)) (→ Checker)
      (threading ck ((agreed (unify? expected actual)))
                 (if agreed ck (type-mismatch ck expected actual loc))))

    (define (type-mismatch (ck Checker) (expected Type) (actual Type) (loc Loc))
      (→ T) (∀ (T))
      (compile-error loc
                     (string-append "type mismatch: expected "
                                    (type->string (resolve-type (solution ck) expected))
                                    ", found "
                                    (type->string (resolve-type (solution ck) actual)))))

    ;; Unification both answers and learns, so it hands back both. A failed
    ;; attempt may still have bound metavariables along the way; the caller
    ;; reports the mismatch and goes no further, so nothing reads them.

    (define (unify? (ck Checker) (a Type) (b Type)) (→ (Pair Bool Checker))
      (let ((a (prune (solution ck) a)) (b (prune (solution ck) b)))
        (cond ((same-meta? a b) (new Pair (first #t) (second ck)))
              ((meta? a) (bind? ck a b))
              ((meta? b) (bind? ck b a))
              (else (unify-structure? ck a b)))))

    (define (unify-all? (ck Checker) (as (List Type)) (bs (List Type))) (→ (Pair Bool Checker))
      (if (= (length as) (length bs))
          (fold-left (lambda (done pair)
                       (if (● done first)
                           (unify? (● done second) (● pair first) (● pair second))
                           done))
                     (new Pair (first #t) (second ck)) (zip as bs))
          (new Pair (first #f) (second ck))))

    (define (unify-structure? (ck Checker) (a Type) (b Type)) (→ (Pair Bool Checker))
      (match a
        ((TCon name args)
         (match b
           ((TCon other others)
            (if (string=? name other)
                (unify-all? ck args others)
                (new Pair (first #f) (second ck))))
           (_ (new Pair (first #f) (second ck)))))
        ((TFun params result row)
         (match b
           ((TFun others other-result other-row)
            (unify-function? ck params result row others other-result other-row))
           (_ (new Pair (first #f) (second ck)))))
        ((TRow _ _) (unify-rows? ck a b))
        ((TRigid name)
         (match b
           ((TRigid other) (new Pair (first (string=? name other)) (second ck)))
           (_ (new Pair (first #f) (second ck)))))
        (_ (new Pair (first #f) (second ck)))))

    ;; Parameters, result and row in turn, stopping at the first disagreement.

    (define (unify-function? (ck Checker)
                             (params (List Type))
                             (result Type)
                             (row Type)
                             (others (List Type))
                             (other-result Type)
                             (other-row Type))
      (→ (Pair Bool Checker))
      (threading ck ((parameters (unify-all? params others)))
                 (if (not parameters)
                     (new Pair (first #f) (second ck))
                     (threading ck ((results (unify? result other-result)))
                                (if (not results)
                                    (new Pair (first #f) (second ck))
                                    (unify-rows? ck row other-row))))))

    (define (bind? (ck Checker) (meta Type) (type Type)) (→ (Pair Bool Checker))
      (if (occurs? (solution ck) meta type)
          (new Pair (first #f) (second ck))
          (new Pair (first #t) (second (bind-solved ck meta type)))))

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
          ((TRow labels (None)) (new Pair (first labels) (second (None))))
          ((TRow labels (Some tail))
           (let ((rest (flatten-row solution tail)))
             (new Pair (first (label-union labels (● rest first))) (second (● rest second)))))
          (_ (new Pair (first (Nil)) (second (Some row)))))))

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
         ((same-tail? left-tail right-tail)
          (new Pair (first (and (null? only-left) (null? only-right))) (second ck)))
         ((and (meta-tail? left-tail) (meta-tail? right-tail))
          (threading ck ((meta (fresh-meta))
                         (bound-left (bind? (tail-type left-tail) (TRow only-right (Some meta)))))
                     (if (not bound-left)
                         (new Pair (first #f) (second ck))
                         (bind? ck (tail-type right-tail) (TRow only-left (Some meta))))))
         ((meta-tail? left-tail)
          (if (null? only-left)
              (bind? ck (tail-type left-tail) (TRow only-right right-tail))
              (new Pair (first #f) (second ck))))
         ((meta-tail? right-tail)
          (if (null? only-right)
              (bind? ck (tail-type right-tail) (TRow only-left left-tail))
              (new Pair (first #f) (second ck))))
         (else (new Pair (first #f) (second ck))))))

    (define (tail-type (tail (Option Type))) (→ Type)
      (match tail
        ((Some type) type)
        ((None) (panic "internal error: closed row"))))

    ;; Calls require inclusion, and so does a function value where it fits
    ;; a wider type ("Subsumption"); a stored type itself never widens.
    ;; Unknown latent effects stay as obligations until class resolution has
    ;; supplied their lower bounds. Neither pure nor the whole caller row is
    ;; a valid early guess for an unresolved callback or destructor.
    (define (perform (ck Checker) (latent Type) (row Type) (loc Loc)) (→ Checker)
      (let ((ck (record-performed ck row latent)))
        (threading ck ((included (propagate-inclusion latent row loc)))
                   (if included ck (want ck (WantInclusion latent row loc))))))

    (define (propagate-inclusion (ck Checker) (latent Type) (row Type) (loc Loc))
      (→ (Pair Bool Checker))
      (let* ((source (flatten-row (solution ck) latent))
             (target (flatten-row (solution ck) row))
             (missing (label-difference (● source first) (● target first))))
        (if (null? missing)
            (if (and (meta-tail? (● target second))
                     (match (● source second) ((Some (TRigid _)) #t) (_ #f)))
                (threading ck ((then (unify (tail-type (● target second))
                                            (tail-type (● source second)) loc)))
                           (new Pair (first #t) (second ck)))
                (if (and (match (● source second) ((Some (TRigid _)) #t) (_ #f))
                         (not (same-tail? (● source second) (● target second))))
                    (effect-refusal ck latent loc)
                    (new Pair (first (or (match (● source second) ((None) #t) (_ #f))
                                         (same-tail? (● source second) (● target second))))
                         (second ck))))
            (if (meta-tail? (● target second))
                (threading ck ((tail (fresh-meta))
                               (then (unify (tail-type (● target second))
                                            (TRow missing (Some tail)) loc)))
                           (propagate-inclusion ck latent row loc))
                (effect-refusal ck latent loc)))))

    (define (effect-refusal (ck Checker) (latent Type) (loc Loc)) (→ T) (∀ (T))
      (let ((flat (flatten-row (solution ck) latent)))
        (compile-error loc
                       (string-append "this performs effects its context does not allow:"
                                      (labels->string (append (● flat first)
                                                              (tail-variable (● flat second))))))))

    ;; Propagation can expose a label through several calls. Each growth
    ;; allocates a fresh tail, so the counter also detects a fixed point.
    (define (propagate-inclusions (ck Checker)) (→ Checker)
      (let* ((before (● ck counter))
             (ck (fold-left propagate-wanted-inclusion ck (reverse (● ck wanted)))))
        (if (= before (● ck counter)) ck (propagate-inclusions ck))))

    (define (solve-inclusions (ck Checker)) (→ Checker)
      (let ((ck (propagate-inclusions ck)))
        (fold-left finish-wanted-inclusion ck (reverse (● ck wanted)))))

    (define (propagate-wanted-inclusion (ck Checker) (want Wanted)) (→ Checker)
      (match want
        ((WantInclusion latent row loc) (● (propagate-inclusion ck latent row loc) second))
        (_ ck)))

    ;; Residual tails share one row variable. This conservative completion
    ;; avoids adding bounded-row schemes; a closed allowance closes a still
    ;; unconstrained source tail only after all class obligations.
    (define (finish-wanted-inclusion (ck Checker) (want Wanted)) (→ Checker)
      (match want
        ((WantInclusion latent row loc)
         (threading ck ((included (propagate-inclusion latent row loc)))
                    (if included ck
                        (let ((source (flatten-row (solution ck) latent))
                              (target (flatten-row (solution ck) row)))
                          (threading ck ((agreed (unify? (tail-type (● source second))
                                                         (match (● target second)
                                                           ((Some tail) tail)
                                                           ((None) empty-row)))))
                                     (if agreed ck (effect-refusal ck latent loc)))))))
        (_ ck)))

    ;; Whether `row` is the row variable that `variable` names, if any.

    (define (row-variable? (variable (Option I64)) (row Type)) (→ Bool)
      (match (new Pair (first variable) (second row))
        ((Pair (Some number) (TVar id)) (= number id))
        (_ #f)))

    ;; Preserve the row itself: generic evidence may determine its effects
    ;; later. The final check reads it through the solved types.
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

    ;; ---- Subsumption ----

    ;; A value fits a type that allows at least the effects its own type
    ;; does: a function that performs fewer effects runs wherever more are
    ;; allowed. Only rows may differ, so no value's representation changes
    ;; and fitting converts nothing. A function's result and row may widen
    ;; and its parameters narrow. An enum's arguments may widen, since its
    ;; fields are never written. A record's must be equal: what one reads
    ;; through a widened record, another could have written through a
    ;; narrower one. A type or row not yet solved is unified, as before.

    (define (subsume? (ck Checker) (expected Type) (actual Type) (loc Loc))
      (→ (Pair Bool Checker))
      (match (new Pair (first (prune (solution ck) expected)) (second (prune (solution ck) actual)))
        ((Pair (TFun params result row) (TFun others other-result other-row))
         (subsume-function? ck params result row others other-result other-row loc))
        ((Pair (TCon name args) (TCon other others))
         (cond ((not (and (string=? name other) (= (length args) (length others))))
                (new Pair (first #f) (second ck)))
               ((null? args) (new Pair (first #t) (second ck)))
               ((covariant-enum? (● ck program) name (Nil)) (all-subsumed? ck args others loc))
               (else (unify-all? ck args others))))
        ((Pair expected actual) (unify? ck expected actual))))

    ;; The expected function's arguments flow into the value's parameters,
    ;; and the value's result out to the expected one.

    (define (subsume-function? (ck Checker) (params (List Type)) (result Type) (row Type)
                               (others (List Type)) (other-result Type) (other-row Type)
                               (loc Loc))
      (→ (Pair Bool Checker))
      (if (not (= (length params) (length others)))
          (new Pair (first #f) (second ck))
          (threading ck ((parameters (all-subsumed? others params loc)))
                     (if (not parameters)
                         (new Pair (first #f) (second ck))
                         (threading ck ((results (subsume? result other-result loc)))
                                    (if (not results)
                                        (new Pair (first #f) (second ck))
                                        (includes-row? ck row other-row loc)))))))

    (define (all-subsumed? (ck Checker) (expected (List Type)) (actual (List Type)) (loc Loc))
      (→ (Pair Bool Checker))
      (fold-left (lambda (done pair)
                   (if (● done first)
                       (subsume? (● done second) (● pair first) (● pair second) loc)
                       done))
                 (new Pair (first #t) (second ck)) (zip expected actual)))

    ;; The expected row includes the value's when it names the value's
    ;; labels and its tail covers the value's tail. A value whose row is
    ;; still open is unified, as before. An expected row still open grows
    ;; to name the value's labels and stays open, so the code it belongs
    ;; to may still perform more. Neither case waits: the inclusion holds
    ;; or fails here.

    (define (includes-row? (ck Checker) (expected Type) (actual Type) (loc Loc))
      (→ (Pair Bool Checker))
      (cond ((or (meta? (prune (solution ck) expected))
                 (meta-tail? (● (flatten-row (solution ck) actual) second)))
             (unify? ck expected actual))
            ((excluded? (solution ck) expected actual) (new Pair (first #f) (second ck)))
            (else (propagate-inclusion ck actual expected loc))))

    ;; Whether no solution of the expected row's tail could include the
    ;; value's row: a label it lacks, or a rigid tail it does not share.

    (define (excluded? (solution Solution) (expected Type) (actual Type)) (→ Bool)
      (let ((source (flatten-row solution actual)) (target (flatten-row solution expected)))
        (and (not (meta-tail? (● target second)))
             (or (not (null? (label-difference (● source first) (● target first))))
                 (match (● source second)
                   ((Some (TRigid _)) (not (same-tail? (● source second) (● target second))))
                   (_ #f))))))

    ;; An enum widens with its arguments when each of its parameters occurs
    ;; only where a wider type still fits: a function's result or row, or a
    ;; widening argument. The enums being examined are assumed to widen,
    ;; which holds when every one of them is shown to under the assumption.

    (define (covariant-enum? (program Program) (name String) (visiting (List String))) (→ Bool)
      (match (table-ref (● program types) name)
        ((Some data)
         (and (● data enum?)
              (every? (lambda (case)
                        (every? (lambda (field)
                                  (every? (lambda (param)
                                            (positive-only? program param (● field type) #t
                                                            (Cons name visiting)))
                                          (● data params)))
                                (● case fields)))
                      (● data cases))))
        ((None) #f)))

    ;; Whether every occurrence of `param` in `type` is positive, when
    ;; `type` itself is at a positive place if `positive`.

    (define (positive-only? (program Program) (param String) (type Type) (positive Bool)
                            (visiting (List String)))
      (→ Bool)
      (match type
        ((TRigid name) (or positive (not (string=? name param))))
        ((TFun params result row)
         (and (every? (lambda (type) (positive-only? program param type (not positive) visiting))
                      params)
              (positive-only? program param result positive visiting)
              (positive-only? program param row positive visiting)))
        ((TRow _ (Some tail)) (positive-only? program param tail positive visiting))
        ((TCon name args)
         (if (or (member? name visiting) (covariant-enum? program name visiting))
             (every? (lambda (type) (positive-only? program param type positive visiting)) args)
             (every? (lambda (type) (not (mentions? param type))) args)))
        (_ #t)))

    (define (mentions? (param String) (type Type)) (→ Bool)
      (match type
        ((TRigid name) (string=? name param))
        ((TFun params result row)
         (or (any? (lambda (type) (mentions? param type)) params)
             (mentions? param result)
             (mentions? param row)))
        ((TRow _ (Some tail)) (mentions? param tail))
        ((TCon _ args) (any? (lambda (type) (mentions? param type)) args))
        (_ #f)))

    ;; ---- Instantiation ----

    (define (want (ck Checker) (wanted Wanted)) (→ Checker)
      (Checker-wanted-set ck (Cons wanted (● ck wanted))))

    (define (want-class (ck Checker) (constraint Constraint) (loc Loc)) (→ (Pair Evidence Checker))
      (threading ck ((hole (fresh-identity))
                     (then
                      (want (WantClass constraint hole (● ck givens) loc))))
                 (new Pair (first (EvHole hole)) (second ck))))

    ;; A use of a variable: its type, the types its quantified variables
    ;; took, and the evidence for its constraints.
    (record Instantiated
      ((type Type)
       (types (List Type))
       (evidence (List Evidence))))

    ;; Fresh metavariables for the quantified variables, a hole for each
    ;; constraint, and a fresh tail on a closed outermost row.

    (define (instantiate (ck Checker) (scheme Scheme) (loc Loc)) (→ (Pair Instantiated Checker))
      (threading ck ((metas (fresh-bindings (● scheme vars)))
                     (type (open-row (substitute metas (● scheme type))))
                     (evidence (each (lambda (ck constraint)
                                       (want-class ck (substitute-constraint metas constraint) loc))
                                     (● scheme constraints))))
                 (new Pair
                   (first (new Instantiated
                            (type type)
                            (types (map (lambda (record) (● record second)) metas))
                            (evidence evidence)))
                   (second ck))))

    ;; A fresh metavariable per quantified variable, in order.

    (define (fresh-bindings (ck Checker) (vars (List String))) (→ (Pair Substitution Checker))
      (each ck
            (lambda (ck var)
              (threading ck ((meta (fresh-meta)))
                         (new Pair (first (new Pair (first var) (second meta))) (second ck))))
            vars))

    (define (open-row (ck Checker) (type Type)) (→ (Pair Type Checker))
      (match (prune (solution ck) type)
        ((TFun params result (TRow labels (None)))
         (threading ck ((tail (fresh-meta)))
                    (new Pair (first (TFun params result (TRow labels (Some tail)))) (second ck))))
        (_ (new Pair (first type) (second ck)))))

    (define (global-scheme (ck Checker) (name String)) (→ (Option Scheme))
      (match (table-ref (● ck schemes) name)
        ((Some scheme) (Some scheme))
        ((None)
         (match (program-value (● ck program) name)
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
      (match (table-ref (● ck locals) name)
        ((Some local)
         (new Pair
           (first (new Instantiated (type local) (types (Nil)) (evidence (Nil))))
           (second ck)))
        ((None)
         (match (global-scheme ck name)
           ((Some scheme) (instantiate ck scheme loc))
           ((None) (compile-error loc (string-append "internal error: no type for " name)))))))

    ;; ---- Expressions ----

    (define (literal-type (ck Checker) (value Datum) (loc Loc)) (→ (Pair Type Checker))
      (match value
        ((DBool _) (new Pair (first (TCon "Bool" (Nil))) (second ck)))
        ((DChar _) (new Pair (first (TCon "Char" (Nil))) (second ck)))
        ((DString _) (new Pair (first (TCon "String" (Nil))) (second ck)))
        ((DBytes _) (new Pair (first (TCon "Array" (list (TCon "U8" (Nil))))) (second ck)))
        ((DUnit) (new Pair (first (TCon "Unit" (Nil))) (second ck)))
        ((DConstants element _)
         (new Pair
           (first (TCon "ConstantArray" (list (TCon element (Nil)))))
           (second ck)))
        (_ (threading ck ((type (fresh-meta))
                          (then (want (WantLiteral value type loc))))
                      (new Pair (first type) (second ck))))))

    ;; `row` is the effect row of the enclosing function body.

    (define (infer (ck Checker) (expr Expr) (row Type)) (→ (Pair Expr Checker))
      (let ((loc (● expr loc)))
        (match (● expr term)
          ((Lit value)
           (threading ck ((type (literal-type value loc)))
                      (new Pair
                        (first (new Expr (term (Lit value)) (type type) (loc loc)))
                        (second ck))))
          ((Var name _ _)
           (threading ck ((use (variable-type name loc)))
                      (new Pair (first (new Expr (term (Var name (● use types) (● use evidence)))
                                            (type (● use type))
                                            (loc loc)))
                           (second ck))))
          ((Lambda params body) (infer-lambda ck params body loc))
          ((App callee args) (infer-app ck callee args row loc (None)))
          ((New callee fields) (infer-new ck callee fields row loc (None)))
          ((FieldRead record label _) (infer-field-read ck record label row loc))
          ((FieldWrite record label value _) (infer-field-write ck record label value row loc))
          ;; `then` is `threading`'s own keyword, so the branches are named
          ;; for what they are rather than by their field names.
          ((If test consequent alternative)
           (threading ck ((test (infer test row))
                          (consequent (infer consequent row))
                          (alternative (infer alternative row))
                          (then (fit (TCon "Bool" (Nil)) (● test type) (● test loc)))
                          (then (unify (● consequent type)
                                       (● alternative type)
                                       (● alternative loc))))
                      (new Pair
                        (first (new Expr
                                 (term (If test consequent alternative))
                                 (type (● consequent type))
                                 (loc loc)))
                        (second ck))))
          ((Let name value body) (infer-let ck name value body row loc))
          ((Seq first rest)
           (threading ck ((first (infer first row))
                          (rest (infer rest row)))
                      (new Pair
                        (first (new Expr (term (Seq first rest)) (type (● rest type)) (loc loc)))
                        (second ck))))
          ((Match scrutinee clauses) (infer-match ck scrutinee clauses row loc))
          ((Ann inner type)
           (threading ck ((inner (check-value inner type row))
                          (then (fit type (● inner type) loc)))
                      (new Pair (first inner) (second ck))))
          ((BoxAny inner)
           (threading ck ((inner (infer inner row)))
                      (new Pair
                        (first (new Expr (term (BoxAny inner)) (type (TCon "Any" (Nil))) (loc loc)))
                        (second ck))))
          ((Downcast inner target)
           (threading ck ((inner (check-result inner (TCon "Any" (Nil)) row)))
                      (new Pair (first (new Expr (term (Downcast inner target))
                                            (type (TCon "snail.core.base:Option" (list target)))
                                            (loc loc)))
                           (second ck)))))))

    (define (infer-lambda (ck Checker)
                          (params (List String))
                          (body Expr)
                          (loc Loc))
      (→ (Pair Expr Checker))
      (threading ck ((types (each (lambda (ck param) (fresh-meta ck)) params)))
                 (infer-lambda-at ck params body types loc)))

    ;; A lambda whose parameter types are known before its body is seen.

    (define (infer-lambda-at (ck Checker)
                             (params (List String))
                             (body Expr)
                             (types (List Type))
                             (loc Loc))
      (→ (Pair Expr Checker))
      (threading ck ((body-row (fresh-meta))
                     (body (within (lambda (inner)
                                     (infer (bind-locals inner params types) body body-row)))))
                 (new Pair
                   (first (new Expr
                            (term (Lambda params body))
                            (type (TFun types (● body type) body-row))
                            (loc loc)))
                   (second ck))))

    ;; A sub-check that may change the scope, resumed in this checker's:
    ;; everything it learns flows back, and only its scope is discarded.

    (define (within (ck Checker) (check (Fn Checker → (Pair A Checker) ! e)))
      (→ (Pair A Checker))
      (! e)
      (∀ (A e))
      (match (check ck)
        ((Pair value done) (new Pair (first value) (second (resumed ck done))))))

    ;; Checks an expression against a known type: a lambda's parameters and
    ;; body row come from the type; anything else is inferred.

    (define (check-value (ck Checker) (expr Expr) (type Type) (row Type))
      (→ (Pair Expr Checker))
      (match (new Pair (first (● expr term)) (second (prune (solution ck) type)))
        ((Pair (New callee fields) _)
         (infer-new ck callee fields row (● expr loc) (Some type)))
        ((Pair (App callee args) _)
         (infer-app ck callee args row (● expr loc) (Some type)))
        ((Pair (If test consequent alternative) _)
         (threading ck ((test (check-result test (TCon "Bool" (Nil)) row))
                        (consequent (check-result consequent type row))
                        (alternative (check-result alternative type row)))
                    (new Pair
                      (first (new Expr
                               (term (If test consequent alternative))
                               (type type)
                               (loc (● expr loc))))
                      (second ck))))
        ((Pair (Let name value body) _)
         (threading ck ((local (local-placeholder value))
                        (value (infer-let-value name local value row))
                        (then (unify local (● value type) (● value loc)))
                        (body (within (lambda (inner)
                                        (check-result (bind-local inner name local)
                                                      body
                                                      type
                                                      row)))))
                    (new Pair
                      (first (new Expr (term (Let name value body)) (type type) (loc (● expr loc))))
                      (second ck))))
        ((Pair (Seq first rest) _)
         (threading ck ((first (infer first row)) (rest (check-result rest type row)))
                    (new Pair
                      (first (new Expr (term (Seq first rest)) (type type) (loc (● expr loc))))
                      (second ck))))
        ((Pair (Match scrutinee clauses) _)
         (infer-match-at ck scrutinee clauses type row (● expr loc)))
        ((Pair (Lambda params body) (TFun param-types result body-row))
         (if (= (length params) (length param-types))
             (check-lambda ck expr params body type param-types result body-row)
             (infer ck expr row)))
        (_ (infer ck expr row))))

    ;; Infer with the expected type, which the resulting type then meets.

    (define (check-result (ck Checker) (expr Expr) (type Type) (row Type))
      (→ (Pair Expr Checker))
      (threading ck ((expr (check-value expr type row))
                     (then (fit type (● expr type) (● expr loc))))
                 (new Pair (first expr) (second ck))))

    ;; A lambda checked against its type. The body's row is a variable bound
    ;; to the type's row, so `perform` can recognize it: calls in this body,
    ;; but not in lambdas inside it, record in `performed` what they
    ;; perform. Writes always charge mut, including writes to fresh objects.

    (define (check-lambda (ck Checker) (expr Expr) (params (List String))
                          (body Expr) (type Type) (param-types (List Type))
                          (result Type) (body-row Type))
      (→ (Pair Expr Checker))
      (let ((outer ck))
        (threading ck ((row (fresh-meta))
                       (then (unify row body-row (● expr loc)))
                       (body
                        (within (lambda (inner)
                                  (check-result
                                   (signed-body (bind-locals inner params param-types) row)
                                   body
                                   result
                                   row)))))
                   (new Pair
                     (first (new Expr (term (Lambda params body)) (type type) (loc (● expr loc))))
                     (second (finish-lambda-scope outer ck))))))

    ;; A nested function's effects do not replace what its enclosing body
    ;; already performed.

    (define (finish-lambda-scope (outer Checker) (done Checker)) (→ Checker)
      (match (● outer signed)
        ((Some _) (Checker-performed-set done (● outer performed)))
        ((None) done)))

    ;; The scope of a body checked against its signature, whose row
    ;; variable is `row`: nothing is performed in it yet.

    (define (signed-body (ck Checker) (row Type)) (→ Checker)
      (Checker-performed-set (Checker-signed-set ck (Some (meta-id row))) (Nil)))

    (define (infer-app (ck Checker)
                       (callee Expr)
                       (args (List Expr))
                       (row Type)
                       (loc Loc)
                       (expected (Option Type)))
      (→ (Pair Expr Checker))
      (threading ck ((callee (infer callee row))
                     (then (result-context callee expected loc))
                     (args (infer-arguments callee args row))
                     (result (fresh-meta))
                     (latent (fresh-meta))
                     (then (unify-call (● callee type) args result latent loc))
                     (then (improve-types))
                     (then (perform latent row loc)))
                 (new Pair
                   (first (new Expr (term (App callee args)) (type result) (loc loc)))
                   (second ck))))

    ;; Check each initializer with its declared field type, including the
    ;; expected record's generic arguments. Only evaluation order is novel;
    ;; the checked result uses the existing constructor.
    (define (infer-new (ck Checker) (callee Expr) (fields (List Initializer))
                       (row Type) (loc Loc) (expected (Option Type)))
      (→ (Pair Expr Checker))
      (threading ck ((callee (infer callee row)) (then (result-context callee expected loc)))
                 (match (● callee type)
                   ((TFun params result _)
                    (threading ck ((fields (each (lambda (ck field)
                                                   (check-initializer ck field params row))
                                                 fields))
                                   (then (improve-types)))
                               (new Pair (first (lower-new callee fields result loc)) (second ck))))
                   (_ (panic "internal error: record constructor is not a function")))))

    (define (check-initializer (ck Checker) (field Initializer) (params (List Type)) (row Type))
      (→ (Pair Initializer Checker))
      (threading ck ((value (check-result (● field value) (list-ref params (● field slot)) row)))
                 (new Pair
                   (first
                    (new Initializer (slot (● field slot)) (name (● field name)) (value value)))
                   (second ck))))

    ;; Ordinary calls already evaluate arguments once, from left to right.
    ;; Bind only when placement order differs from that evaluation order.
    (define (lower-new (callee Expr) (fields (List Initializer)) (type Type) (loc Loc)) (→ Expr)
      (if (every? (lambda (pair) (= (● pair first) (● (● pair second) slot)))
                  (zip (iota (length fields)) fields))
          (new Expr
            (term (App callee (map (lambda (field) (● field value)) fields)))
            (type type)
            (loc loc))
          (let* ((ordered (list-sort (lambda (a b) (< (● a slot) (● b slot))) fields))
                 (args (map (lambda (field) (new Expr (term (Var (● field name) (Nil) (Nil)))
                                                 (type (● (● field value) type))
                                                 (loc (● (● field value) loc))))
                            ordered)))
            (fold-right (lambda (field body)
                          (new Expr
                            (term (Let (● field name) (● field value) body))
                            (type type)
                            (loc loc)))
                        (new Expr (term (App callee args)) (type type) (loc loc)) fields))))

    ;; A call checked against the type its callee builds meets it before
    ;; its arguments are checked, so what is expected reaches them, and the
    ;; callbacks of producers such as map.

    (define (result-context (ck Checker) (callee Expr) (expected (Option Type)) (loc Loc))
      (→ Checker)
      (match (new Pair (first (prune (solution ck) (● callee type))) (second expected))
        ((Pair (TFun _ (TCon result args) _) (Some type))
         (match (prune (solution ck) type)
           ((TCon target _) (if (string=? target result)
                                (fit ck type (TCon result args) loc) ck))
           (_ ck)))
        (_ ck)))

    ;; A value of type `found` meets `expected` without changing its
    ;; representation. Any is boxed and extracted explicitly; every other
    ;; boundary subsumes, which differs from unifying only in rows
    ;; ("Subsumption").

    (define (fit (ck Checker) (expected Type) (found Type) (loc Loc)) (→ Checker)
      (threading ck ((fits (subsume? expected found loc)))
                 (if fits ck (type-mismatch ck expected found loc))))

    (define (infer-arguments (ck Checker) (callee Expr) (args (List Expr)) (row Type))
      (→ (Pair (List Expr) Checker))
      (match (prune (solution ck) (● callee type))
        ((TFun params _ _)
         (if (= (length params) (length args))
             (each ck (lambda (ck pair) (check-result ck (● pair second) (● pair first) row))
                   (zip params args))
             (each ck (lambda (ck arg) (infer ck arg row)) args)))
        (_ (each ck (lambda (ck arg) (infer ck arg row)) args))))

    ;; Arguments are compared one by one, so a mismatch names its argument,
    ;; and each meets its parameter's type (`fit`).

    (define (unify-call (ck Checker)
                        (callee-type Type)
                        (args (List Expr))
                        (result Type)
                        (latent Type)
                        (loc Loc))
      (→ Checker)
      (match (prune (solution ck) callee-type)
        ((TFun params callee-result row)
         (unless (= (length params) (length args))
           (compile-error loc
                          (string-append "expected "
                                         (i64->string (length params))
                                         " arguments, found "
                                         (i64->string (length args)))))
         (threading ck ((then (fit-arguments params args))
                        (then (unify callee-result result loc)))
                    (unify ck row latent loc)))
        ((TVar _)
         (unify ck callee-type (TFun (map (lambda (arg) (● arg type)) args) result latent) loc))
        (other (compile-error loc (string-append "not a function: " (type->string other))))))

    (define (fit-arguments (ck Checker) (params (List Type)) (args (List Expr)))
      (→ Checker)
      (fold-left (lambda (ck pair)
                   (fit ck (● pair first) (● (● pair second) type) (● (● pair second) loc)))
                 ck (zip params args)))

    ;; A function's own name is visible in its body, with a monomorphic type.

    (define (infer-let (ck Checker) (name String) (value Expr) (body Expr) (row Type) (loc Loc))
      (→ (Pair Expr Checker))
      (threading ck ((type (local-placeholder value))
                     (value (infer-let-value name type value row))
                     (then (unify type (● value type) (● value loc)))
                     (body (within (lambda (inner) (infer (bind-local inner name type) body row)))))
                 (new Pair
                   (first (new Expr (term (Let name value body)) (type (● body type)) (loc loc)))
                   (second ck))))

    ;; Reserve a lambda's identity before checking recursive references.
    ;; Captures are resolved in the outer scope, never including itself.

    (define (local-placeholder (ck Checker) (value Expr)) (→ (Pair Type Checker))
      (match (● value term)
        ((Ann inner type)
         (if (local-function? inner) (new Pair (first type) (second ck)) (fresh-meta ck)))
        ((Lambda params _)
         (threading ck ((types (each (lambda (ck param) (fresh-meta ck)) params))
                        (result (fresh-meta)) (row (fresh-meta)))
                    (new Pair (first (TFun types result row)) (second ck))))
        (_ (fresh-meta ck))))

    ;; A `let`'s own name is visible in its value only when the value is a
    ;; lambda, so a recursive local function can call itself.

    (define (infer-let-value (ck Checker) (name String) (type Type) (value Expr) (row Type))
      (→ (Pair Expr Checker))
      (if (local-function? value)
          (within ck (lambda (inner) (check-value (bind-local inner name type) value type row)))
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
      (match (new Pair (first (● value term)) (second type))
        ((Pair (Lambda params body) (TFun types _ _))
         (threading ck ((value (infer-lambda-at params body types (● value loc)))
                        (then (unify type (● value type) (● value loc))))
                    (new Pair
                      (first (new Expr (term (● value term)) (type type) (loc (● value loc))))
                      (second ck))))
        (_ (panic "internal error: a local lambda has a reserved signature"))))

    ;; `expr` inferred under `inner`'s scope, resumed in this checker's.

    (define (infer-match (ck Checker) (scrutinee Expr) (clauses (List Clause)) (row Type) (loc Loc))
      (→ (Pair Expr Checker))
      (threading ck ((result (fresh-meta)))
                 (infer-match-at ck scrutinee clauses result row loc)))

    (define (infer-match-at (ck Checker)
                            (scrutinee Expr)
                            (clauses (List Clause))
                            (result Type)
                            (row Type)
                            (loc Loc))
      (→ (Pair Expr Checker))
      (threading ck ((scrutinee (infer scrutinee row))
                     (clauses (each (lambda (ck clause)
                                      (infer-clause ck clause (● scrutinee type) result row))
                                    clauses)))
                 (if (null? clauses)
                     (check-empty-match ck (● scrutinee type) loc)
                     (check-coverage ck (map (lambda (record) (● record pattern)) clauses) loc))
                 (new Pair
                   (first (new Expr (term (Match scrutinee clauses)) (type result) (loc loc)))
                   (second ck))))

    ;; A match with no clauses is exhaustive only on a type with no cases,
    ;; which has no value to reach it with.

    (define (check-empty-match (ck Checker) (type Type) (loc Loc)) (→ Unit)
      (unless (match (resolve-type (solution ck) type)
                ((TCon name _)
                 (match (table-ref (● (● ck program) types) name)
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
      (let ((body-loc (● (● clause body) loc)))
        (within ck
                (lambda (ck)
                  (threading ck
                             ((pattern (check-pattern (● clause pattern) scrutinee-type body-loc))
                              (body (check-result (● clause body) result row)))
                             (new Pair
                               (first (new Clause (pattern pattern) (body body)))
                               (second ck)))))))

    ;; ---- Patterns ----

    ;; A pattern's typed form. The checker it hands back has learned the
    ;; pattern's types and binds its variables, for the clause body; names
    ;; are unique, so a constructor's fields bind into one scope in turn.

    (define (check-pattern (ck Checker) (pattern Pattern) (type Type) (loc Loc))
      (→ (Pair Pattern Checker))
      (match pattern
        ((PWild _) (new Pair (first (PWild type)) (second ck)))
        ((PVar name _) (new Pair (first (PVar name type)) (second (bind-local ck name type))))
        ((PLit value _)
         (threading ck ((literal (literal-type value loc))
                        (then (unify type literal loc)))
                    (new Pair (first (PLit value type)) (second ck))))
        ((PCon constructor args _)
         (match (program-value (● ck program) constructor)
           ((Some (Constructor _ scheme))
            (threading ck ((use (instantiate scheme loc)))
                       (match (● use type)
                         ((TFun fields result _)
                          (unless (= (length fields) (length args))
                            (compile-error loc
                                           (string-append (short-name constructor)
                                                          " has "
                                                          (i64->string (length fields))
                                                          " fields")))
                          (threading ck ((then (unify type result loc))
                                         (args (each (lambda (ck pair)
                                                       (check-pattern ck
                                                                      (● pair first)
                                                                      (● pair second)
                                                                      loc))
                                                     (zip args fields))))
                                     (new Pair (first (PCon constructor args type)) (second ck))))
                         (_ (panic "internal error: a constructor is a function")))))
           (_
            (compile-error loc (string-append "not a constructor: " (short-name constructor))))))))

    ;; ---- Coverage ----

    ;; Maranget's usefulness test. A clause is redundant if it is not useful
    ;; after the clauses before it; a match is exhaustive if a wildcard is not
    ;; useful after all of them.

    (define (check-coverage (ck Checker) (patterns (List Pattern)) (loc Loc)) (→ Unit)
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

    (define (specialize-rows (rows (List (List Pattern))) (head Head)) (→ (List (List Pattern)))
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

    (define (useful? (ck Checker) (rows (List (List Pattern))) (array (List Pattern))) (→ Bool)
      (match array
        ((Nil) (null? rows))
        ((Cons first rest)
         (match (head-of first)
           ((Some head) (useful? ck (specialize-rows rows head) (append (pattern-args first) rest)))
           ((None)
            (match (complete-signature ck (delete-duplicates head=? (row-heads rows)))
              ((Some all)
               (any? (lambda (head)
                       (useful? ck
                                (specialize-rows rows head)
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
      (match (program-value (● ck program) constructor)
        ((Some (Constructor case _))
         (map (lambda (case) (HCon (● case name) (length (● case fields))))
              (● (program-type (● ck program) (● case type)) cases)))
        (_ (Nil))))

    ;; ---- Nominal field selections ----

    (define (infer-field-read (ck Checker) (record Expr) (label String) (row Type) (loc Loc))
      (→ (Pair Expr Checker))
      (threading ck ((record (infer record row))
                     (projection (select-field record label loc)))
                 (new Pair
                   (first (new Expr
                            (term (FieldRead record label (Some (● projection hole))))
                            (type (● projection result))
                            (loc loc)))
                   (second ck))))

    ;; A write checks its value against the field's type, and performs
    ;; `mut`.

    (define (infer-field-write (ck Checker)
                               (record Expr)
                               (label String)
                               (value Expr)
                               (row Type)
                               (loc Loc))
      (→ (Pair Expr Checker))
      (threading ck ((record (infer record row))
                     (projection (select-field record label loc))
                     (value (check-result value (● projection result) row))
                     (then (perform (TRow (list "mut") (None)) row loc)))
                 (new Pair
                   (first (new Expr
                            (term (FieldWrite record label value (Some (● projection hole))))
                            (type (TCon "Unit" (Nil)))
                            (loc loc)))
                   (second ck))))

    (define (select-field (ck Checker) (record Expr) (label String) (loc Loc))
      (→ (Pair Projection Checker))
      (threading ck ((result (fresh-meta))
                     (hole (fresh-identity)))
                 (let ((projection (new Projection
                                     (record record)
                                     (label label)
                                     (result result)
                                     (hole hole)
                                     (loc loc))))
                   (new Pair
                     (first projection)
                     (second (improve-types (wait-for-field ck projection)))))))

    ;; Until its receiver's type is known, a selection keeps the types it
    ;; mentions from being generalized; once it reads its field, it is
    ;; ordinary inference and keeps nothing.

    (define (wait-for-field (ck Checker) (projection Projection)) (→ Checker)
      (Checker-waiting-set ck (Cons projection (● ck waiting))))

    ;; A selection whose receiver's type is now known reads its field;
    ;; one whose is not waits again.

    (define (improve-projection (ck Checker) (projection Projection)) (→ Checker)
      (match (resolve-projection ck (● projection record) (● projection label) (● projection loc))
        ((None) (wait-for-field ck projection))
        ((Some slot)
         (threading ck ((then (unify (● projection result) (● slot type) (● projection loc))))
                    (with-projection ck (● projection hole) slot)))))

    (define (with-projection (ck Checker) (hole I64) (slot Slot)) (→ Checker)
      (Checker-solution-set ck
                            (Solution-projections-set (solution ck)
                                                      (table-set (● (solution ck) projections)
                                                                 (identity-key hole)
                                                                 slot))))

    (define (unresolved-field (projection Projection)) (→ Unit)
      (compile-error (● projection loc)
                     (string-append "field " (● projection label)
                                    " requires a known record type; annotate the receiver")))

    ;; Each label selects one stored field of the current nominal object.
    (define (resolve-projection (ck Checker) (record Expr) (label String) (loc Loc))
      (→ (Option Slot))
      (let ((owner (resolve-type (solution ck) (● record type))))
        (match owner
          ((TVar _) (None))
          ((TCon _ _) (projection-slot ck owner label loc))
          (_ (compile-error loc (string-append "field " label
                                               " requires a known record type, found "
                                               (type->string owner)))))))

    (define (projection-slot (ck Checker) (owner Type) (label String) (loc Loc))
      (→ (Option Slot))
      (match owner
        ((TCon name args)
         (match (table-ref (● (● ck program) types) name)
           ((Some data)
            (when (● data enum?)
              (compile-error loc "field selection requires a record; match an enum's cases"))
            (let ((case (list-ref (● data cases) 0)))
              (match (list-index (lambda (field) (string=? label (● field name))) (● case fields))
                ((Some index)
                 (Some (new Slot
                         (case case)
                         (index index)
                         (args args)
                         (type (substitute (zip (● data params) args)
                                           (● (list-ref (● case fields) index) type))))))
                ((None)
                 (compile-error loc (string-append (type->string owner) " has no field " label))))))
           ((None)
            (compile-error loc (string-append (type->string owner) " has no field " label)))))
        (_ (panic "internal error: a slot has a nominal owner"))))

    ;; ---- Solving ----

    ;; Runs once, after every item is checked: literals whose type nothing
    ;; determined default to F64 or I64, every literal is range-checked, and
    ;; every class constraint is solved with the givens it arose under.
    ;; Field types are improved before and after literal defaulting.

    (define (solve-wanted (ck Checker)) (→ Checker)
      (let ((wanted (reverse (● ck wanted))))
        (threading ck ((then (improve-types))
                       (then (default-literals wanted #t))
                       (then (default-literals wanted #f))
                       (then (improve-types)))
                   (for-each unresolved-field (reverse (● ck waiting)))
                   (for-each (lambda (want)
                               (match want
                                 ((WantLiteral value type loc) (check-literal ck value type loc))
                                 (_ (unit))))
                             wanted)
                   (let ((ck (solve-inclusions
                              (propagate-inclusions (fold-left solve-wanted-class ck wanted)))))
                     (for-each (lambda (want) (check-performed ck want)) wanted)
                     ck))))

    ;; Class resolution can still add effects to a procedure's inferred row,
    ;; so inclusions are propagated again once every class is solved.
    (define (solve-wanted-class (ck Checker) (want Wanted)) (→ Checker)
      (match want
        ((WantClass constraint hole givens loc)
         (resumed ck (solve-class ck constraint hole givens loc)))
        (_ ck)))

    (define (default-literals (ck Checker) (wanted (List Wanted)) (float? Bool))
      (→ Checker)
      (fold-left (lambda (ck want) (default-literal ck want float?)) ck wanted))

    (define (default-literal (ck Checker) (want Wanted) (float? Bool)) (→ Checker)
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

    (define (check-literal (ck Checker) (value Datum) (type Type) (loc Loc)) (→ Unit)
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
                         (loc Loc))
      (→ Checker)
      (match (find-evidence ck constraint givens loc)
        ((Some (Pair evidence ck)) (with-evidence ck hole evidence))
        ((None) (compile-error loc (ambiguous-constraint ck constraint)))))

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

    ;; Field selections improve together: each result a selection
    ;; establishes can determine another selection's receiver, so the
    ;; waiting ones are retried, oldest first, until a round solves none.

    (define (improve-types (ck Checker)) (→ Checker)
      (let* ((waiting (● ck waiting))
             (ck (fold-left improve-projection (Checker-waiting-set ck (Nil)) (reverse waiting))))
        (if (= (length (● ck waiting)) (length waiting)) ck (improve-types ck))))

    ;; Evidence from the enclosing definition's requirements, or from the
    ;; unique instance whose head matches. None while the types are ambiguous.

    (define (find-evidence (ck Checker) (constraint Constraint) (givens (List Constraint))
                           (loc Loc))
      (→ (Option (Pair Evidence Checker)))
      (let ((types (map (lambda (type) (resolve-type (solution ck) type)) (● constraint types))))
        (if (any? (lambda (type) (has-meta? (solution ck) type)) types) (None)
            (match (given-evidence (● constraint class) types givens)
              ((Some evidence) (Some (new Pair (first evidence) (second ck))))
              ((None) (Some (instance-evidence ck (● constraint class) types givens loc)))))))

    (define (given-evidence (class String) (types (List Type)) (givens (List Constraint)))
      (→ (Option Evidence))
      (match (list-index (lambda (given)
                           (and (string=? class (● given class))
                                (types=? types (● given types))))
                         givens)
        ((Some index) (Some (EvParam index)))
        ((None) (None))))

    ;; An instance's requirements are solved where its head matched. A goal
    ;; met again while it is being solved, or a chain of 128, would not end.

    (define (instance-evidence (ck Checker)
                               (class String)
                               (types (List Type))
                               (givens (List Constraint))
                               (loc Loc))
      (→ (Pair Evidence Checker))
      (match (matching-instance ck class types loc)
        ((Pair instance bindings)
         (match (each (enter-instance ck (new Constraint (class class) (types types)) loc)
                      (lambda (ck requirement)
                        (requirement-evidence ck
                                              (substitute-constraint bindings requirement)
                                              givens
                                              loc))
                      (● instance requires))
           ((Pair subs inner)
            (new Pair
              (first (EvInstance (● instance name) (applied-types instance bindings) subs))
              (second (Checker-resolving-set inner (● ck resolving)))))))))

    (define (enter-instance (ck Checker) (goal Constraint) (loc Loc)) (→ Checker)
      (when (or (>= (length (● ck resolving)) 128)
                (any? (lambda (other)
                        (and (string=? (● goal class) (● other class))
                             (types=? (● goal types) (● other types))))
                      (● ck resolving)))
        (compile-error loc "instance requirements do not terminate"))
      (Checker-resolving-set ck (Cons goal (● ck resolving))))

    ;; The instance whose head matches a constraint's types, and what that
    ;; binds its variables to. No two instances of a class match the same
    ;; types.

    (define (matching-instance (ck Checker) (class String) (types (List Type)) (loc Loc))
      (→ (Pair Instance Substitution))
      (let loop ((instances (class-instances (● ck program) class)))
        (match instances
          ((Nil)
           (compile-error loc (string-append "no instance for " (constraint->string class types))))
          ((Cons instance rest)
           (match (match-types (● instance vars) (● instance types) types (Nil))
             ((Some bindings) (new Pair (first instance) (second bindings)))
             ((None) (loop rest)))))))

    ;; The types the head's match gave the instance's variables, in order.

    (define (applied-types (instance Instance) (bindings Substitution)) (→ (List Type))
      (map (lambda (var)
             (match (assoc-ref bindings var)
               ((Some type) type)
               ((None) (TCon "Unit" (Nil)))))
           (● instance vars)))

    (define (requirement-evidence (ck Checker)
                                  (requirement Constraint)
                                  (givens (List Constraint))
                                  (loc Loc))
      (→ (Pair Evidence Checker))
      (match (find-evidence ck requirement givens loc)
        ((Some found) found)
        ((None) (compile-error loc (ambiguous-requirement requirement)))))

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

    (define (selected-slot (solution Solution) (hole (Option I64))) (→ Slot)
      (match hole
        ((Some hole)
         (match (table-ref (● solution projections) (identity-key hole))
           ((Some slot) slot)
           ((None) (panic "internal error: unsolved field selection"))))
        ((None) (panic "internal error: unchecked field selection"))))

    ;; A selection reads its field with the field's accessor; a write, given
    ;; the value it writes, writes it with the field's writer.

    (define (field-call (solution Solution)
                        (slot Slot)
                        (record Expr)
                        (written (Option Expr))
                        (loc Loc))
      (→ Term)
      (let* ((record (zonk-expr solution record))
             (field (zonk solution (● slot type)))
             (args (map (lambda (type) (zonk solution type)) (● slot args)))
             (callee (lambda (name type)
                       (new Expr (term (Var (name (● slot case) (● slot index)) args (Nil)))
                            (type type)
                            (loc loc)))))
        (match written
          ((None) (App (callee accessor-name (TFun (list (● record type)) field empty-row))
                       (list record)))
          ((Some value)
           (App (callee writer-name
                        (TFun (list (● record type) field)
                              (TCon "Unit" (Nil))
                              (TRow (list "mut") (None))))
                (list record (zonk-expr solution value)))))))

    (define (zonk-expr (solution Solution) (expr Expr)) (→ Expr)
      (new Expr (term (match (● expr term)
                        ((Lit value) (Lit value))
                        ((Var name types evidence)
                         (Var name
                              (map (lambda (type) (zonk solution type)) types)
                              (map (lambda (e) (zonk-evidence solution e)) evidence)))
                        ((Lambda params body) (Lambda params (zonk-expr solution body)))
                        ((App callee args)
                         (App (zonk-expr solution callee)
                              (map (lambda (arg) (zonk-expr solution arg)) args)))
                        ((FieldRead record _ hole)
                         (field-call solution
                                     (selected-slot solution hole)
                                     record
                                     (None)
                                     (● expr loc)))
                        ((FieldWrite record _ value hole)
                         (field-call solution
                                     (selected-slot solution hole)
                                     record
                                     (Some value)
                                     (● expr loc)))
                        ((New _ _) (panic "internal error: unchecked construction"))
                        ((If test then otherwise)
                         (If (zonk-expr solution test)
                             (zonk-expr solution then)
                             (zonk-expr solution otherwise)))
                        ((Let name value body)
                         (Let name (zonk-expr solution value) (zonk-expr solution body)))
                        ((Seq first rest)
                         (Seq (zonk-expr solution first) (zonk-expr solution rest)))
                        ((Match scrutinee clauses)
                         (Match (zonk-expr solution scrutinee)
                                (map (lambda (clause)
                                       (new Clause
                                         (pattern (zonk-pattern solution (● clause pattern)))
                                         (body (zonk-expr solution (● clause body)))))
                                     clauses)))
                        ((Ann inner type) (Ann (zonk-expr solution inner) (zonk solution type)))
                        ((BoxAny inner) (BoxAny (zonk-expr solution inner)))
                        ((Downcast inner target)
                         (Downcast (zonk-expr solution inner) (zonk solution target)))))
           (type (zonk solution (● expr type))) (loc (● expr loc))))

    (define (zonk-pattern (solution Solution) (pattern Pattern)) (→ Pattern)
      (match pattern
        ((PWild type) (PWild (zonk solution type)))
        ((PVar name type) (PVar name (zonk solution type)))
        ((PLit value type) (PLit value (zonk solution type)))
        ((PCon constructor args type)
         (PCon constructor
               (map (lambda (arg) (zonk-pattern solution arg)) args)
               (zonk solution type)))))

    ;; ---- Checked operations ----

    ;; Validate operations at their final inferred types, before
    ;; specialization erases ordinary effects: the signature a cache is
    ;; built for, and what `Any` and `downcast` may take. Each item's first
    ;; failure is reported, in source order.

    (define (check-final (typed Typed)) (→ Unit)
      (fail-if-found
       (in-source-order
        (failures-of (lambda (item)
                       (match item
                         ((Define _ value) (check-operations value))
                         (_ (unit))))
                     (● typed items)))))

    (define (check-operations (expr Expr)) (→ Unit)
      (match (● expr term)
        ((Var name _ _)
         (when (member? name (list "prim:cache" "prim:lru-cache"))
           (check-cache-signature (● expr type) (● expr loc))))
        ((BoxAny inner) (refuse-hidden-effects "Any" (● inner type) (● expr loc)))
        ((Downcast _ target) (refuse-hidden-effects "downcast" target (● expr loc)))
        (_ (unit)))
      (for-each check-operations (expr-children expr)))

    ;; A cache is built for one signature, so an unknown F cannot be cached.
    ;; A generic factory states the function's shape in its header.
    (define (check-cache-signature (type Type) (loc Loc)) (→ Unit)
      (match type
        ((TFun _ (TFun _ _ _) _) (unit))
        (_ (compile-error loc "cache requires an ordinary Fn function with a known signature"))))

    ;; A box must not hide a callable's effects. Boxing and downcasting
    ;; themselves introduce no effects.

    (define (refuse-hidden-effects (form String) (type Type) (loc Loc)) (→ Unit)
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
    ;; together and generalized over the obligations it raised, which it
    ;; collects apart from the library's and then adds to them. Typed
    ;; function headers are checked directly.

    (define (check-group (ck Checker) (definitions (List Definition)) (exposed (List String)))
      (→ (Pair (List Definition) Checker))
      (let ((outer (● ck wanted)))
        (threading ck ((then (Checker-wanted-set (Nil)))
                       (then (provisional-schemes definitions))
                       (values (each infer-definition definitions))
                       (then (improve-types))
                       (then (generalize definitions (● ck wanted) exposed)))
                   (new Pair
                     (first
                      (map (lambda (pair) (Definition-value-set (● pair first) (● pair second)))
                           (zip definitions values)))
                     (second
                      (Checker-open-set (Checker-wanted-set ck (append (● ck wanted) outer))
                                        (append (definition-names definitions)
                                                (● ck open))))))))

    (define (definition-names (definitions (List Definition))) (→ (List String))
      (map (lambda (definition) (● definition name)) definitions))

    ;; Each definition in the group starts with a monomorphic metavariable, so
    ;; the group's members can refer to one another while it is inferred.

    (define (provisional-schemes (ck Checker) (definitions (List Definition))) (→ Checker)
      (fold-left (lambda (ck definition)
                   (threading ck ((type (local-placeholder (● definition value))))
                              (set-scheme ck (● definition name) (mono-scheme type))))
                 ck definitions))

    ;; An inferred function, checked against its recursive placeholder.

    (define (infer-definition (ck Checker) (definition Definition))
      (→ (Pair Expr Checker))
      (let ((value (● definition value)) (type (scheme-type ck (● definition name))))
        (if (lambda-expr? value)
            (infer-local-lambda ck value type)
            (check-result ck value type empty-row))))

    (define (scheme-type (ck Checker) (name String)) (→ Type)
      (match (table-ref (● ck schemes) name)
        ((Some scheme) (● scheme type))
        ((None) (panic (string-append "internal error: no scheme for " name)))))

    ;; A metavariable becomes a quantified variable (`t1`, `t2`, ...) unless
    ;; something that outlives the group still mentions it: another
    ;; definition's type, a constraint of this group, a field selection
    ;; still waiting for its receiver, or a top-level value.

    (define (generalize (ck Checker)
                        (definitions (List Definition))
                        (wanted (List Wanted))
                        (exposed (List String)))
      (→ Checker)
      (let* ((fixed (map meta-id
                         (concatenate
                          (list (scheme-metas ck (● ck open))
                                (concatenate (map (lambda (want) (wanted-metas (solution ck) want))
                                                  wanted))
                                (waiting-metas ck)
                                (value-metas ck definitions)
                                (exposed-row-metas ck definitions exposed)))))
             (metas (filter (lambda (meta) (not (member? (meta-id meta) fixed)))
                            (delete-duplicates same-meta?
                                               (scheme-metas ck (definition-names definitions)))))
             (names (map (lambda (index) (string-append "t" (i64->string (+ index 1))))
                         (iota (length metas))))
             ;; Generalization binds a metavariable to a quantified name, like
             ;; any other solution; nothing distinguishes the two afterwards.
             (bound (fold-left (lambda (ck pair)
                                 (bind-solved ck (● pair first) (TRigid (● pair second))))
                               ck (zip metas names))))
        (fold-left (lambda (ck name)
                     (set-scheme ck name (new Scheme
                                           (vars names)
                                           (constraints (Nil))
                                           (type
                                            (resolve-type (solution ck) (scheme-type ck name))))))
                   bound (definition-names definitions))))

    ;; A top-level value is kept in one slot, so it has one type: what its
    ;; initializer leaves open, as the element of an empty list, its uses
    ;; in its library decide together.

    (define (value-metas (ck Checker) (definitions (List Definition))) (→ (List Type))
      (scheme-metas ck (definition-names (filter (lambda (definition)
                                                   (match (value-loc (● definition value))
                                                     ((Some _) #t)
                                                     ((None) #f)))
                                                 definitions))))

    ;; The metavariables the current schemes of `names` mention.

    (define (scheme-metas (ck Checker) (names (List String))) (→ (List Type))
      (concatenate (map (lambda (name) (free-metas (solution ck) (scheme-type ck name))) names)))

    ;; Where a value's definition is, if `value` is one as the expander
    ;; writes it.

    (define (value-loc (value Expr)) (→ (Option Loc))
      (match value
        ((Expr (App (Expr (Var "prim:cached-thunk" _ _) _ _) _) _ loc) (Some loc))
        (_ (None))))

    ;; An importer's use never decides a type, so an inferred value's is
    ;; known once its library is solved. One that states its type has no
    ;; inferred scheme.

    (define (check-value-types (ck Checker) (items (List Item))) (→ Unit)
      (for-each (lambda (item)
                  (match item
                    ((Define name value)
                     (match (new Pair
                              (first (value-loc value))
                              (second (table-ref (● ck schemes) name)))
                       ((Pair (Some loc) (Some scheme))
                        (when (has-meta? (solution ck) (● scheme type))
                          (compile-error loc
                                         "nothing decides this value's type; state it with (→ Type)")))
                       (_ (unit))))
                    (_ (unit))))
                items))

    ;; A foreign caller supplies no row argument. Keep an inferred export's
    ;; row open for instance solving instead of quantifying that row. Its
    ;; ordinary type variables still generalize and are refused by expose.

    (define (exposed-row-metas (ck Checker) (definitions (List Definition)) (exposed (List String)))
      (→ (List Type))
      (concatenate (map (lambda (name)
                          (match (resolve-type (solution ck) (scheme-type ck name))
                            ((TFun _ _ row) (free-metas (solution ck) row))
                            (_ (Nil))))
                        (filter (lambda (name) (member? name exposed))
                                (definition-names definitions)))))

    (define (meta-id (meta Type)) (→ I64)
      (match meta
        ((TVar id) id)
        (_ -1)))

    (define (waiting-metas (ck Checker)) (→ (List Type))
      (concatenate (map (lambda (projection)
                          (append (free-metas (solution ck) (● projection record type))
                                  (free-metas (solution ck) (● projection result))))
                        (● ck waiting))))

    (define (wanted-metas (solution Solution) (want Wanted)) (→ (List Type))
      (match want
        ((WantPerformed _ _ rows _)
         (concatenate (map (lambda (row) (free-metas solution row)) rows)))
        ((WantInclusion latent row _)
         (append (free-metas solution latent) (free-metas solution row)))
        ((WantClass constraint _ _ _)
         (concatenate
          (map (lambda (type) (free-metas solution type)) (● constraint types))))
        ((WantLiteral _ type _) (free-metas solution type))))

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
    ;; where it occurs. The givens are scope: they hold while this
    ;; definition is checked and no longer.

    (define (check-annotated (ck Checker) (definition Definition) (scheme Scheme))
      (→ (Pair Item Checker))
      (within ck
              (lambda (ck)
                (let ((value (● definition value))
                      (ck (Checker-givens-set ck
                                              (if (null? (● scheme vars))
                                                  (Nil)
                                                  (● scheme constraints)))))
                  (threading ck ((then (want-closed-requirements scheme (● value loc)))
                                 (checked (check-result value (● scheme type) empty-row)))
                             (new Pair
                               (first (Define (● definition name) checked))
                               (second (want-performed ck definition scheme))))))))

    ;; A signature's row says what calling the function may do, so it may
    ;; not name an effect the body never performs. A lambda was checked by
    ;; `check-lambda`, so `performed` holds what its body performed. An
    ;; instance method has its class's row, which this instance may need
    ;; less of, and a value other than a lambda has no body of its own, so
    ;; neither is held to it.

    (define (want-performed (ck Checker) (definition Definition) (scheme Scheme)) (→ Checker)
      (match (new Pair
               (first (signature-loc (● ck program) (● definition name)))
               (second (● scheme type)))
        ((Pair (Some loc) (TFun _ _ row))
         (if (lambda-expr? (● definition value))
             (want ck (WantPerformed (● definition name) row (● ck performed) loc))
             ck))
        (_ ck)))

    (define (check-performed (ck Checker) (want Wanted)) (→ Unit)
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
                                   (unperformed-message (short-name name) effects)))))
        (_ (unit))))

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

    ;; What the host calls is `start`, which runs main as the first task of
    ;; the host's scheduler. Main's parameters are capabilities its target
    ;; provides, which `start` supplies; a main that is its own start has
    ;; no target to ask.

    (define (check-entry (ck Checker) (name String) (start String) (loc Loc)) (→ Unit)
      (match (global-scheme ck name)
        ((Some (Scheme (Nil) (Nil) type))
         (match (resolve-type (solution ck) type)
           ((TFun params (TCon "Unit" (Nil)) _)
            (when (and (string=? name start) (not (null? params)))
              (compile-error loc "main asks for capabilities, and this build has no target")))
           (_ (compile-error loc "main must be a function returning Unit"))))
        (_ (compile-error loc "main must be a monomorphic function returning Unit"))))

    ;; The host may retain values, holding managed references opaquely. The
    ;; trusted host respects `snail-scheme` types. What is exposed is a
    ;; definition's code: a foreign function or a constructor has none.

    (define (check-exposed (ck Checker) (name String) (loc Loc))
      (→ Unit)
      (match (program-value (● ck program) name)
        ((Some (Defined _ _)) (unit))
        (_ (compile-error loc "an exposed function must be defined")))
      (match (global-scheme ck name)
        ((Some (Scheme (Nil) (Nil) type))
         (match (resolve-type (solution ck) type)
           ((TFun _ _ _) (unit))
           (_ (compile-error loc "an exposed function must be a monomorphic function"))))
        (_ (compile-error loc "an exposed function must be a monomorphic function"))))

    ;; ---- Programs ----

    ;; A program is checked a library at a time, in program order, so each
    ;; library's types are settled within it, as they must be when libraries
    ;; are compiled apart: an unannotated value takes its type from its own
    ;; library, never from a library that imports it.

    (define (check-program (program Program)) (→ Typed)
      (let loop ((libraries (library-items program (program-items program)))
                 (items (Nil))
                 (schemes (empty-table)))
        (match libraries
          ((Cons library rest)
           (let ((typed (check-library program schemes (● library second))))
             (loop rest (append items (● typed items)) (● typed schemes))))
          ((Nil) (new Typed (program program) (items items) (schemes schemes))))))

    ;; One library's items, checked after the libraries before it: `schemes`
    ;; holds their definitions' schemes, and the result holds those and the
    ;; new ones. Unannotated definitions are checked first, in dependency
    ;; order; then annotated definitions and statements, which only need
    ;; schemes. Then every constraint is solved and every type zonked.

    (define (check-library (program Program) (schemes (Table Scheme)) (items (List Item)))
      (→ Typed)
      (let ((ck (new Checker (program program)
                     (locals (empty-table))
                     (givens (Nil))
                     (resolving (Nil))
                     (signed (None))
                     (counter 0)
                     (solution empty-solution)
                     (schemes schemes)
                     (wanted (Nil))
                     (waiting (Nil))
                     (open (Nil))
                     (performed (Nil)))))
        (threading ck ((typed (check-items items))
                       (then (solve-wanted)))
                   (check-value-types ck items)
                   (check-exposures ck items)
                   (let ((result
                          (new Typed (program program)
                               (items (map (lambda (item) (zonk-item (solution ck) item)) typed))
                               (schemes (final-schemes ck items)))))
                     (check-final result)
                     result))))

    (define (check-exposures (ck Checker) (items (List Item))) (→ Unit)
      (for-each (lambda (item)
                  (match item
                    ((Expose name _ loc) (check-exposed ck name loc))
                    ((Entry name start loc) (check-entry ck name start loc))
                    (_ (unit))))
                items))

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
      (let* ((exposed (concatenate (map (lambda (item)
                                          (match item
                                            ((Expose name _ _) (list name))
                                            ((Entry name start _) (list name start))
                                            (_ (Nil))))
                                        items)))
             (groups (each-recovered
                      (new Recovered (checker ck) (values (Nil)) (found (Nil)) (failed (Nil)))
                      group-references
                      definition-names
                      (lambda (ck group) (check-group ck group exposed))
                      (unannotated-groups ck items)))
             (results (fold-left (lambda (results definition)
                                   (table-set results (● definition name) (● definition value)))
                                 (empty-table) (concatenate (● groups values))))
             (checked (each-recovered (new Recovered (checker (● groups checker))
                                           (values (Nil))
                                           (found (● groups found))
                                           (failed (● groups failed)))
                                      item-references
                                      (lambda (item) (Nil))
                                      (lambda (ck item) (check-item ck results item))
                                      items)))
        (fail-if-found (in-source-order (● checked found)))
        (new Pair (first (● checked values)) (second (● checked checker)))))

    (define (group-references (definitions (List Definition))) (→ (List String))
      (concatenate (map (lambda (definition) (expr-references (● definition value))) definitions)))

    ;; A definition refers to itself too, so one whose group failed is
    ;; not checked again.

    (define (item-references (item Item)) (→ (List String))
      (match item
        ((Define name value) (Cons name (expr-references value)))
        ((Expose name _ _) (list name))
        ((Entry name start _) (list name start))))

    (define (unannotated-groups (ck Checker) (items (List Item))) (→ (List (List Definition)))
      (definition-groups
        (concatenate (map (lambda (item)
                            (match item
                              ((Define name value)
                               (match (annotated-scheme (● ck program) name)
                                 ((None) (list (new Definition (name name) (value value))))
                                 ((Some _) (Nil))))
                              (_ (Nil))))
                          items))))

    (define (check-item (ck Checker) (results (Table Expr)) (item Item))
      (→ (Pair Item Checker))
      (match item
        ((Define name value)
         (match (table-ref results name)
           ((Some checked) (new Pair (first (Define name checked)) (second ck)))
           ((None)
            (match (annotated-scheme (● ck program) name)
              ((Some scheme) (check-annotated ck (new Definition (name name) (value value)) scheme))
              ((None) (panic "internal error: unchecked definition"))))))
        (_ (new Pair (first item) (second ck)))))

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
                                                   (new Scheme (vars (● scheme vars))
                                                        (constraints (● scheme constraints))
                                                        (type (zonk (solution ck)
                                                                    (● scheme type))))))
                                      ((None) ck)))
                                  ck (● ck open))))
        (● (fold-left (lambda (ck item)
                        (match item
                          ((Define name _)
                           (match (annotated-scheme (● ck program) name)
                             ((Some scheme) (set-scheme ck name scheme))
                             ((None) ck)))
                          (_ ck)))
                      defaulted items) schemes)))

    (define (annotated-scheme (program Program) (name String)) (→ (Option Scheme))
      (match (program-value program name)
        ((Some (Defined (Some scheme) _)) (Some scheme))
        (_ (None))))

    ;; Where a definition's own signature was written, if it has one.

    (define (signature-loc (program Program) (name String)) (→ (Option Loc))
      (match (program-value program name)
        ((Some (Defined _ loc)) loc)
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
    (record (Recovered B)
      ((checker Checker)
       (values (List B))
       (found (List SourceDiagnostic))
       (failed (List String))))

    ;; `step` over each item, as `each` does, past the items that fail.
    ;; `references` and `names` say what an item refers to and defines.

    (define (each-recovered (start (Recovered B))
                            (references (Fn A → (List String)))
                            (names (Fn A → (List String)))
                            (step (Fn Checker A → (Pair B Checker)))
                            (items (List A)))
      (→ (Recovered B))
      (∀ (A B))
      (let ((done (fold-left (lambda (done item) (recover done references names step item))
                             start
                             items)))
        (Recovered-values-set done (reverse (● done values)))))

    (define (recover (done (Recovered B))
                     (references (Fn A → (List String)))
                     (names (Fn A → (List String)))
                     (step (Fn Checker A → (Pair B Checker)))
                     (item A))
      (→ (Recovered B))
      (∀ (A B))
      (let ((failed (● done failed)))
        (if (any? (lambda (name) (member? name failed)) (references item))
            (Recovered-failed-set done (append (names item) failed))
            (match (recovering (lambda () (step (● done checker) item)))
              ((Ok (Pair value ck))
               (new Recovered
                 (checker ck)
                 (values (Cons value (● done values)))
                 (found (● done found))
                 (failed failed)))
              ((Err found)
               (Recovered-failed-set
                (Recovered-found-set done (append (● done found) (diagnostics->list found)))
                (append (names item) failed)))))))

    ;; ---- Dependency order ----

    ;; The definitions in groups that refer to one another, each group after
    ;; the groups it refers to. Definitions are numbered in program order.

    (define (definition-groups (definitions (List Definition))) (→ (List (List Definition)))
      (let* ((nodes (list->array definitions))
             (numbers (fold-left (lambda (table index)
                                   (table-set table (● (array-ref nodes index) name) index))
                                 (empty-table) (iota (array-length nodes)))))
        (map (lambda (component) (map (lambda (index) (array-ref nodes index)) component))
             (strong-components
              (array-map (lambda (definition) (definition-edges numbers definition)) nodes)))))

    ;; The numbers of the definitions `definition` refers to, in order of
    ;; first reference.

    (define (definition-edges (numbers (Table I64)) (definition Definition)) (→ (List I64))
      (fold-right (lambda (name edges)
                    (match (table-ref numbers name)
                      ((Some index) (Cons index edges))
                      ((None) edges)))
                  (Nil) (expr-references (● definition value))))

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

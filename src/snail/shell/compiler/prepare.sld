;; Preparation closes specialization and produces fixed declarations and
;; normalized items.
;;
;; A suspension unwinds as a yield: `suspend` records it and returns, and
;; each call between it and its `with-prompt` returns after it, so nothing
;; may run after a call that may yield before the backend has tested for
;; the yield. No type says which calls those are, so the pass finds out
;; ("Suspensions"): what each definition's call may suspend to, and what a
;; call of any function value of each type may. A call that may yield
;; stays where it is when its value flows straight out of a function or a
;; let's value; anywhere else, a let names it, with the rest of the
;; expression as the let's body, and names first each operand that runs
;; before it, so those still run first. The backend tests for a yield after
;; each let whose value may yield. The prepared program uses this subset of
;; the checked expression language; emission has no specialization work.
(define-library (snail shell compiler prepare)
  (export
   Prepared
   prepare-program
   Suspensions
   yields
   holds-yield-point?
   may-resume?)
  (import
   (snail core base)
   (snail core table)
   (snail shell compiler read)
   (snail shell compiler core)
   (only (snail shell compiler check) Typed)
   (snail shell compiler specialize))
  (begin

    ;; ---- Prepared code ----

    ;; Fixed declarations and concrete function bodies consumed by emission,
    ;; with what each call may suspend to.
    (record Prepared
      ((declarations Declarations)
       (suspensions Suspensions)
       (definitions (List Definition))
       (entry (Option String))
       (exposed (List Item))))

    ;; The whole reachable graph is specialized before any body is read, so
    ;; the suspensions are those of a closed graph. Lowering then rewrites
    ;; each body on its own. The program's entry and exposures name copies.

    (define (prepare-program (typed Typed)) (→ Prepared)
      (let* ((items (● typed items))
             (specialized (specialize typed items))
             (definitions (● specialized definitions))
             (suspensions (program-suspensions (● specialized declarations) definitions)))
        (for-each (lambda (definition) (check-cache-keys (● definition value))) definitions)
        (new Prepared
          (declarations (● specialized declarations))
          (suspensions suspensions)
          (definitions (map (lambda (definition) (control-definition suspensions definition))
                            definitions))
          (entry (match (find (lambda (item) (match item ((Entry _ _ _) #t) (_ #f))) items)
                   ((Some (Entry _ start _)) (Some start))
                   (_ (None))))
          (exposed (filter (lambda (item) (match item ((Expose _ _ _) #t) (_ #f))) items)))))

    ;; ---- Labels ----

    ;; What a suspension goes to, as the analysis can name it. A prompt read
    ;; from a top-level value is named by that value, which holds one prompt
    ;; for the whole run. Any other prompt is known by its type alone:
    ;; `?abort` when its answer is Never, so that nothing resumes it, and
    ;; `?resume` otherwise.

    (define (prompt-label (declarations Declarations) (prompt Expr)) (→ String)
      (match (● prompt term)
        ((Ann inner _) (prompt-label declarations inner))
        ((App (Expr (Var name _ _) _ _) (Nil))
         (if (table-contains? (● declarations types) name)
             name
             (unnamed-prompt (● prompt type))))
        (_ (unnamed-prompt (● prompt type)))))

    (define (unnamed-prompt (type Type)) (→ String)
      (if (never-answered? type) "?abort" "?resume"))

    (define (named-prompt? (label String)) (→ Bool)
      (not (or (string=? label "?abort") (string=? label "?resume"))))

    (define (never-answered? (prompt Type)) (→ Bool)
      (match prompt
        ((TCon "Prompt" (Cons _ (Cons answer (Nil)))) (never-type? answer))
        (_ #f)))

    ;; Whether something may resume a suspension to `label`.

    (define (resumed? (declarations Declarations) (label String)) (→ Bool)
      (cond ((string=? label "?abort") #f)
            ((string=? label "?resume") #t)
            (else (match (table-ref (● declarations types) label)
                    ((Some (TFun _ prompt _)) (not (never-answered? prompt)))
                    (_ #t)))))

    ;; ---- Flows ----

    ;; What running some code may suspend to, before the program's
    ;; suspensions are known: labels it names itself, the suspensions of a
    ;; definition it calls, those of any function value of a type it
    ;; applies, and what a `with-prompt` leaves of its body's.
    (enum Flow
      (To
       ((labels (List String))))
      (Calling
       ((name String)))
      (Applying
       ((key String)))
      (Either
       ((flows (List Flow))))
      (Caught
       ((flow Flow)
        (label String))))

    (define nowhere (→ Flow) (To (Nil)))

    (define (nowhere? (flow Flow)) (→ Bool)
      (match flow
        ((To (Nil)) #t)
        (_ #f)))

    (define (either (flows (List Flow))) (→ Flow)
      (match (filter (lambda (flow) (not (nowhere? flow))) flows)
        ((Nil) nowhere)
        ((Cons flow (Nil)) flow)
        (several (Either several))))

    ;; What evaluating `expr` may suspend to. Making a closure suspends
    ;; nothing; its body does when it is called.

    (define (flow (declarations Declarations) (expr Expr)) (→ Flow)
      (match (● expr term)
        ((Lambda _ _) nowhere)
        ((App callee args)
         (either (Cons (application-flow declarations callee args)
                       (map (lambda (part) (flow declarations part)) (Cons callee args)))))
        (_ (either (map (lambda (child) (flow declarations child)) (expr-children expr))))))

    ;; What the call itself may suspend to, its operands aside. `suspend`
    ;; goes to its prompt. These primitives run a procedure they are given;
    ;; no other primitive calls anything.

    (define (application-flow (declarations Declarations) (callee Expr) (args (List Expr)))
      (→ Flow)
      (match (● callee term)
        ((Ann inner _) (application-flow declarations inner args))
        ((Var "prim:suspend" _ _) (To (list (prompt-label declarations (list-ref args 0)))))
        ((Var "prim:with-prompt" _ _) (delimited-flow declarations args))
        ((Var "prim:unsafe-total" _ _) (procedure-flow declarations (list-ref args 0)))
        ((Var "prim:array-generate" _ _) (procedure-flow declarations (list-ref args 1)))
        ((Var "prim:string-generate" _ _) (procedure-flow declarations (list-ref args 1)))
        ((Var name _ _)
         (match (program-value (● declarations program) name)
           ((Some (Primitive _)) nowhere)
           (_ (procedure-flow declarations callee))))
        (_ (procedure-flow declarations callee))))

    ;; A `with-prompt` catches what its body suspends to its prompt, which
    ;; the analysis knows when the prompt has a name, and runs its handler
    ;; itself, once the body has unwound to it.

    (define (delimited-flow (declarations Declarations) (args (List Expr))) (→ Flow)
      (let ((label (prompt-label declarations (list-ref args 0)))
            (body (procedure-flow declarations (list-ref args 1))))
        (either (list (if (named-prompt? label) (Caught body label) body)
                      (procedure-flow declarations (list-ref args 2))))))

    ;; What calling a procedure may suspend to: what a lambda's body may, a
    ;; definition's own suspensions, and otherwise those of any function
    ;; value of its type.

    (define (procedure-flow (declarations Declarations) (procedure Expr)) (→ Flow)
      (match (● procedure term)
        ((Lambda _ body) (flow declarations body))
        ((Ann inner _) (procedure-flow declarations inner))
        ((Var name _ _) (named-flow declarations name (● procedure type)))
        (_ (Applying (type-key (● procedure type))))))

    (define (named-flow (declarations Declarations) (name String) (type Type)) (→ Flow)
      (if (table-contains? (● declarations types) name)
          (Calling name)
          (match (program-value (● declarations program) name)
            ((Some (Primitive _)) (primitive-flow name type))
            ((Some _) nowhere)
            ((None) (Applying (type-key type))))))

    ;; A primitive used as a value is called who knows where. `suspend` goes
    ;; to a prompt of its type; any other may call the procedures it is
    ;; given.

    (define (primitive-flow (name String) (type Type)) (→ Flow)
      (match type
        ((TFun params _ _)
         (if (string=? name "prim:suspend")
             (To (list (unnamed-prompt (list-ref params 0))))
             (either (map (lambda (param) (Applying (type-key param)))
                          (filter function-type? params)))))
        (_ nowhere)))

    (define (function-type? (type Type)) (→ Bool)
      (match type
        ((TFun _ _ _) #t)
        (_ #f)))

    ;; ---- Suspensions ----

    ;; What a call may suspend to: each definition's, under `call NAME`, and
    ;; that of a function value of each type, under `apply KEY`, whichever
    ;; closure it is. `quiet` says the program never suspends at all, so no
    ;; question reads a body.
    (record Suspensions
      ((declarations Declarations)
       (reached (Table (List String)))
       (quiet Bool)))

    (define (call-key (name String)) (→ String)
      (string-append "call " name))

    (define (apply-key (key String)) (→ String)
      (string-append "apply " key))

    ;; One contribution to a key's suspensions.
    (record Equation
      ((target String)
       (flow Flow)))

    (define (program-suspensions (declarations Declarations) (definitions (List Definition)))
      (→ Suspensions)
      (let ((reached (solve (concatenate (map (lambda (definition)
                                                (definition-equations declarations definition))
                                              definitions)))))
        (new Suspensions
          (declarations declarations)
          (reached reached)
          (quiet (every? null? (table-values reached))))))

    ;; A definition's call suspends what its body does. A top-level value's
    ;; is its initializer's, which runs on the first read.

    (define (definition-equations (declarations Declarations) (definition Definition))
      (→ (List Equation))
      (let ((body (definition-body (● definition value))))
        (Cons (new Equation (target (call-key (● definition name))) (flow (flow declarations body)))
              (value-equations declarations body))))

    (define (definition-body (value Expr)) (→ Expr)
      (match (● value term)
        ((Lambda _ body) body)
        ((Ann inner _) (definition-body inner))
        ((App (Expr (Var "prim:cached-thunk" _ _) _ _) (Cons thunk (Nil))) (definition-body thunk))
        (_ (panic "internal error: a definition is a function"))))

    ;; The function values `expr` makes, each a contribution to its type's
    ;; suspensions: a lambda's body, a definition or primitive read as a
    ;; value, and the `resume` a `with-prompt` hands its handler.

    (define (value-equations (declarations Declarations) (expr Expr)) (→ (List Equation))
      (let ((inside (lambda (parts)
                      (concatenate (map (lambda (part) (value-equations declarations part))
                                        parts)))))
        (match (● expr term)
          ((Lambda _ body)
           (Cons (applied (● expr type) (flow declarations body)) (inside (list body))))
          ((Var name _ _) (read-equations declarations name (● expr type)))
          ((App callee args)
           (append (resume-equations declarations expr callee args)
                   (inside (if (names-callee? callee) args (Cons callee args)))))
          (_ (inside (expr-children expr))))))

    (define (applied (type Type) (flow Flow)) (→ Equation)
      (new Equation (target (apply-key (type-key type))) (flow flow)))

    (define (names-callee? (callee Expr)) (→ Bool)
      (match (● callee term)
        ((Var _ _ _) #t)
        ((Ann inner _) (names-callee? inner))
        (_ #f)))

    ;; A local is a value some other expression made, so reading one adds
    ;; nothing.

    (define (read-equations (declarations Declarations) (name String) (type Type))
      (→ (List Equation))
      (match (named-flow declarations name type)
        ((Applying _) (Nil))
        (found (if (and (function-type? type) (not (nowhere? found)))
                   (list (applied type found))
                   (Nil)))))

    ;; `resume` runs the rest of the body under its `with-prompt` again, so
    ;; calling it suspends what the `with-prompt` itself may.

    (define (resume-equations (declarations Declarations)
                              (expr Expr)
                              (callee Expr)
                              (args (List Expr)))
      (→ (List Equation))
      (match (● callee term)
        ((Ann inner _) (resume-equations declarations expr inner args))
        ((Var "prim:with-prompt" _ _)
         (match (● (list-ref args 0) type)
           ((TCon "Prompt" (Cons _ (Cons answer (Nil))))
            (list (applied (TFun (list answer) (● expr type) empty-row)
                           (delimited-flow declarations args))))
           (_ (panic "internal error: a prompt has the Prompt type"))))
        (_ (Nil))))

    ;; ---- Solving ----

    ;; The least suspensions that satisfy every equation. An equation is
    ;; taken up again only when a key its flow reads has grown, and a key
    ;; grows at most once for each label.

    (define (solve (equations (List Equation))) (→ (Table (List String)))
      (let ((indexed (list->array equations)))
        (settle indexed
                (dependents equations)
                (empty-table)
                (iota (array-length indexed)))))

    (define (settle (equations (Array Equation))
                    (readers (Table (List I64)))
                    (reached (Table (List String)))
                    (pending (List I64)))
      (→ (Table (List String)))
      (match pending
        ((Nil) reached)
        ((Cons index rest)
         (let* ((equation (array-ref equations index))
                (target (● equation target))
                (before (reached-at reached target))
                (after (label-union before (flow-labels reached (● equation flow)))))
           (if (= (length after) (length before))
               (settle equations readers (keep reached target before) rest)
               (settle equations
                       readers
                       (table-set reached target after)
                       (append (readers-of readers target) rest)))))))

    ;; Every target has an entry, so `quiet` reads them all.

    (define (keep (reached (Table (List String))) (target String) (labels (List String)))
      (→ (Table (List String)))
      (if (table-contains? reached target) reached (table-set reached target labels)))

    (define (reached-at (reached (Table (List String))) (key String)) (→ (List String))
      (match (table-ref reached key)
        ((Some labels) labels)
        ((None) (Nil))))

    (define (readers-of (readers (Table (List I64))) (key String)) (→ (List I64))
      (match (table-ref readers key)
        ((Some indices) indices)
        ((None) (Nil))))

    ;; The equations whose flows read each key, by their indices.

    (define (dependents (equations (List Equation))) (→ (Table (List I64)))
      (fold-left (lambda (readers entry)
                   (fold-left (lambda (readers key)
                                (table-set readers key
                                           (Cons (● entry first) (readers-of readers key))))
                              readers
                              (flow-keys (● (● entry second) flow))))
                 (empty-table)
                 (zip (iota (length equations)) equations)))

    (define (flow-keys (flow Flow)) (→ (List String))
      (match flow
        ((To _) (Nil))
        ((Calling name) (list (call-key name)))
        ((Applying key) (list (apply-key key)))
        ((Either flows) (concatenate (map flow-keys flows)))
        ((Caught inner _) (flow-keys inner))))

    (define (flow-labels (reached (Table (List String))) (flow Flow)) (→ (List String))
      (match flow
        ((To labels) labels)
        ((Calling name) (reached-at reached (call-key name)))
        ((Applying key) (reached-at reached (apply-key key)))
        ((Either flows)
         (fold-left (lambda (labels part) (label-union labels (flow-labels reached part)))
                    (Nil)
                    flows))
        ((Caught inner label) (label-difference (flow-labels reached inner) (list label)))))

    ;; ---- Yields ----

    ;; What evaluating `expr` may yield to.

    (define (yields (suspensions Suspensions) (expr Expr)) (→ (List String))
      (if (● suspensions quiet)
          (Nil)
          (flow-labels (● suspensions reached) (flow (● suspensions declarations) expr))))

    ;; Whether something may resume a yield to one of `labels`. One nothing
    ;; resumes saves no frame.

    (define (may-resume? (suspensions Suspensions) (labels (List String))) (→ Bool)
      (any? (lambda (label) (resumed? (● suspensions declarations) label)) labels))

    ;; Whether no call anywhere in `expr`, lambda bodies included, may yield.

    (define (yield-free? (suspensions Suspensions) (expr Expr)) (→ Bool)
      (or (● suspensions quiet)
          (and (match (● expr term)
                 ((App callee args)
                  (null? (flow-labels (● suspensions reached)
                                      (application-flow (● suspensions declarations)
                                                        callee
                                                        args))))
                 (_ #t))
               (every? (lambda (child) (yield-free? suspensions child)) (expr-children expr)))))

    ;; Whether a let inside `expr`, outside its lambdas, has a value that
    ;; may yield. The backend tests for a yield after such a let and leaves
    ;; while one is set, so a value that holds one is a block it can leave.

    (define (holds-yield-point? (suspensions Suspensions) (expr Expr)) (→ Bool)
      (match (● expr term)
        ((Lambda _ _) #f)
        ((Let _ value body)
         (or (not (null? (yields suspensions value))) (holds-yield-point? suspensions body)))
        (_ (any? (lambda (child) (holds-yield-point? suspensions child)) (expr-children expr)))))

    ;; ---- Cache keys ----

    ;; A cache's keys are hashed and compared, which a raw Funcref does not
    ;; support.

    (define (check-cache-keys (expr Expr)) (→ Unit)
      (match (● expr term)
        ((Var name _ _)
         (when (member? name (list "prim:cache" "prim:lru-cache"))
           (match (● expr type)
             ((TFun _ (TFun params _ _) _)
              (for-each (lambda (type) (check-cache-key type (● expr loc))) params))
             (_ (panic "internal error: checking refuses a cache of an unknown signature")))))
        (_ (unit)))
      (for-each check-cache-keys (expr-children expr)))

    (define (check-cache-key (type Type) (loc Loc)) (→ Unit)
      (match type
        ((TCon "Funcref" _) (compile-error loc "cache keys cannot be raw Funcref values"))
        (_ (unit))))

    ;; ---- A-normal form ----

    ;; Source locals end in `.digits` and globals contain a colon, so these
    ;; names are the pass's own.

    (define (temporary-name (count I64)) (→ String)
      (string-append "%control." (i64->string count) "%"))

    (define (temporary (name String) (value Expr)) (→ Expr)
      (new Expr (term (Var name (Nil) (Nil))) (type (● value type)) (loc (● value loc))))

    (define (bind (name String) (value Expr) (body Expr)) (→ Expr)
      (new Expr (term (Let name value body)) (type (● body type)) (loc (● value loc))))

    ;; `expr` with each call that may yield, and each operand that runs
    ;; before one, named by a let, except where its value flows out of
    ;; `expr`: through a branch, a let's body, the rest of a sequence, a
    ;; clause body or an annotation. A let's value and a lambda's body are
    ;; each a place values flow out of as well.

    (define (normal (count I64) (suspensions Suspensions) (expr Expr)) (→ (Pair Expr I64))
      (let ((rebuild
             (lambda (term) (new Expr (term term) (type (● expr type)) (loc (● expr loc))))))
        (match (● expr term)
          ((Lambda params body)
           (threading count ((body (normal suspensions body)))
                      (new Pair (first (rebuild (Lambda params body))) (second count))))
          ((App callee args) (normal-call count suspensions expr callee args))
          ((If test consequent alternative)
           (threading count ((test (normal suspensions test))
                             (consequent (normal suspensions consequent))
                             (alternative (normal suspensions alternative)))
                      (named count
                             suspensions
                             test
                             (lambda (test) (rebuild (If test consequent alternative))))))
          ((Let name value body)
           (threading count ((value (normal suspensions value))
                             (body (normal suspensions body)))
                      (new Pair (first (rebuild (Let name value body))) (second count))))
          ((Seq first rest)
           (threading count ((first (normal suspensions first))
                             (rest (normal suspensions rest)))
                      (sequence count suspensions expr first rest)))
          ((Match scrutinee clauses)
           (threading count ((scrutinee (normal suspensions scrutinee))
                             (clauses (normal-clauses suspensions clauses)))
                      (named count
                             suspensions
                             scrutinee
                             (lambda (scrutinee) (rebuild (Match scrutinee clauses))))))
          ((FieldRead _ _ _) (panic "internal error: field selection survived checking"))
          ((FieldWrite _ _ _ _) (panic "internal error: field selection survived checking"))
          ((New _ _) (panic "internal error: named construction survived checking"))
          ((Ann inner type)
           (threading count ((inner (normal suspensions inner)))
                      (new Pair (first (rebuild (Ann inner type))) (second count))))
          ((BoxAny inner)
           (threading count ((inner (normal suspensions inner)))
                      (named count suspensions inner (lambda (inner) (rebuild (BoxAny inner))))))
          ((Downcast inner target)
           (threading count ((inner (normal suspensions inner)))
                      (named count
                             suspensions
                             inner
                             (lambda (inner) (rebuild (Downcast inner target))))))
          (_ (new Pair (first expr) (second count))))))

    (define (normal-all (count I64) (suspensions Suspensions) (exprs (List Expr)))
      (→ (Pair (List Expr) I64))
      (match exprs
        ((Cons expr rest)
         (threading count ((expr (normal suspensions expr))
                           (rest (normal-all suspensions rest)))
                    (new Pair (first (Cons expr rest)) (second count))))
        ((Nil) (new Pair (first (Nil)) (second count)))))

    (define (normal-clauses (count I64) (suspensions Suspensions) (clauses (List Clause)))
      (→ (Pair (List Clause) I64))
      (match clauses
        ((Cons clause rest)
         (threading count ((body (normal suspensions (● clause body)))
                           (rest (normal-clauses suspensions rest)))
                    (new Pair
                      (first (Cons (new Clause (pattern (● clause pattern)) (body body)) rest))
                      (second count))))
        ((Nil) (new Pair (first (Nil)) (second count)))))

    ;; `make` applied to `operand`, or, when the operand may yield, to a
    ;; temporary that a let binds to it first.

    (define (named (count I64) (suspensions Suspensions) (operand Expr) (make (Fn Expr → Expr)))
      (→ (Pair Expr I64))
      (if (null? (yields suspensions operand))
          (new Pair (first (make operand)) (second count))
          (let ((name (temporary-name count)))
            (new Pair
              (first (bind name operand (make (temporary name operand))))
              (second (+ count 1))))))

    ;; A sequence whose first part may yield binds it, so the let tests it.

    (define (sequence (count I64) (suspensions Suspensions) (expr Expr) (first Expr) (rest Expr))
      (→ (Pair Expr I64))
      (if (null? (yields suspensions first))
          (new Pair
            (first (new Expr (term (Seq first rest)) (type (● expr type)) (loc (● expr loc))))
            (second count))
          (new Pair (first (bind (temporary-name count) first rest)) (second (+ count 1)))))

    (define (normal-call (count I64) (suspensions Suspensions) (expr Expr) (callee Expr) (args (List Expr)))
      (→ (Pair Expr I64))
      (threading count ((operands (normal-all suspensions (Cons callee args)))
                        (bound (bind-operands suspensions operands)))
                 (match (● bound operands)
                   ((Cons callee args)
                    (new Pair (first (wrap-lets bound (applied expr callee args))) (second count)))
                   ((Nil) (panic "internal error: a call without a callee")))))

    (define (applied (expr Expr) (callee Expr) (args (List Expr))) (→ Expr)
      (new Expr (term (App callee args)) (type (● expr type)) (loc (● expr loc))))

    ;; ---- Operands ----

    ;; Operands in evaluation order, after the lets that must run before
    ;; them. Each operand before the last that may yield is named, so it
    ;; still runs before that one, unless evaluating it has no effect; the
    ;; last that may yield is named, so the let tests it.
    (record Bound
      ((lets (List (Pair String Expr)))
       (operands (List Expr))))

    (define (wrap-lets (bound Bound) (body Expr)) (→ Expr)
      (fold-right (lambda (entry body) (bind (● entry first) (● entry second) body))
                  body
                  (● bound lets)))

    (define (bind-operands (count I64) (suspensions Suspensions) (operands (List Expr)))
      (→ (Pair Bound I64))
      (let ((final (fold-left (lambda (final entry)
                                (if (null? (yields suspensions (● entry second)))
                                    final
                                    (● entry first)))
                              -1 (zip (iota (length operands)) operands))))
        (bind-from count final 0 operands)))

    (define (bind-from (count I64) (final I64) (index I64) (operands (List Expr)))
      (→ (Pair Bound I64))
      (match operands
        ((Cons operand rest)
         (if (and (<= index final) (or (= index final) (not (inert? operand))))
             (let ((name (temporary-name count)) (next (+ count 1)))
               (threading next ((bound (bind-from final (+ index 1) rest)))
                          (new Pair
                            (first (new Bound
                                     (lets
                                      (Cons (new Pair (first name) (second operand))
                                            (● bound lets)))
                                     (operands (Cons (temporary name operand) (● bound operands)))))
                            (second next))))
             (threading count ((bound (bind-from final (+ index 1) rest)))
                        (new Pair
                          (first (new Bound
                                   (lets (● bound lets))
                                   (operands (Cons operand (● bound operands)))))
                          (second count)))))
        ((Nil) (new Pair (first (new Bound (lets (Nil)) (operands (Nil)))) (second count)))))

    (define (inert? (expr Expr)) (→ Bool)
      (match (● expr term)
        ((Lit _) #t)
        ((Var _ _ _) #t)
        ((Lambda _ _) #t)
        (_ #f)))

    ;; ---- Lowering ----

    ;; Each function numbers its own temporaries from zero.

    (define (control-definition (suspensions Suspensions) (definition Definition)) (→ Definition)
      (Definition-value-set definition
        (● (control-expr 0 suspensions (● definition value)) first)))

    (define (control-expr (count I64) (suspensions Suspensions) (expr Expr)) (→ (Pair Expr I64))
      (if (yield-free? suspensions expr)
          (new Pair (first expr) (second count))
          (normal count suspensions expr)))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-prepare)
    (import
     (only (chezscheme) eq?)
     (snail stage0 testing))
    (begin
      (define test-prepare
        (lambda ()
          (define i64 (TCon "I64" (Nil)))

          (define bool (TCon "Bool" (Nil)))

          (define unit-type (TCon "Unit" (Nil)))

          (define never (TCon "snail.core.base:Never" (Nil)))

          (define loc (new Loc (file "control") (line 1) (column 1)))

          (define expr (lambda (term type) (new Expr (term term) (type type) (loc loc))))

          (define local (lambda (name type) (expr (Var name (Nil) (Nil)) type)))

          (define number (lambda (n) (expr (Lit (DInt n)) i64)))

          (define function-result (lambda (type) (match type ((TFun _ result _) result) (_ i64))))

          (define call
            (lambda (callee args) (expr (App callee args) (function-result (● callee type)))))

          (define thunk (lambda (body) (expr (Lambda (Nil) body) (TFun (Nil) (● body type) empty-row))))

          ;; `t:f` and `t:predicate` suspend, to a prompt something resumes;
          ;; `t:g` and `t:add` never do.
          (define f (local "t:f" (TFun (list i64) i64 empty-row)))

          (define g (local "t:g" (TFun (list i64) i64 empty-row)))

          (define predicate (local "t:predicate" (TFun (list) bool empty-row)))

          (define add (local "t:add" (TFun (list i64 i64) i64 empty-row)))

          ;; A prompt a top-level value holds, and reads of it.
          (define stopping-type (TCon "Prompt" (list i64 never)))

          (define pausing-type (TCon "Prompt" (list i64 unit-type)))

          (define stopping (call (local "t:stopping" (TFun (Nil) stopping-type empty-row)) (Nil)))

          (define pausing (call (local "t:pausing" (TFun (Nil) pausing-type empty-row)) (Nil)))

          (define suspend
            (lambda (prompt)
              (call (local "prim:suspend"
                           (TFun (list (● prompt type) i64)
                                 (match (● prompt type)
                                   ((TCon _ (Cons _ (Cons answer (Nil)))) answer))
                                 empty-row))
                    (list prompt (number 1)))))

          (define with-prompt
            (lambda (prompt body handler)
              (expr (App (local "prim:with-prompt" (TFun (Nil) i64 empty-row))
                         (list prompt body handler))
                    i64)))

          (define declarations
            (new Declarations
              (program (program-with-value
                        (program-with-value empty-program
                                            "prim:suspend"
                                            (Primitive (mono-scheme (TFun (Nil) i64 empty-row))))
                        "prim:with-prompt"
                        (Primitive (mono-scheme (TFun (Nil) i64 empty-row)))))
              (types (fold-left (lambda (types entry)
                                  (table-set types (● entry first) (● (● entry second) type)))
                                (table-set (table-set (empty-table)
                                                      "t:stopping"
                                                      (TFun (Nil) stopping-type empty-row))
                                           "t:pausing"
                                           (TFun (Nil) pausing-type empty-row))
                                (list (new Pair (first "t:f") (second f))
                                      (new Pair (first "t:g") (second g))
                                      (new Pair (first "t:predicate") (second predicate))
                                      (new Pair (first "t:add") (second add)))))))

          (define suspensions
            (new Suspensions
              (declarations declarations)
              (reached (table-set (table-set (empty-table) "call t:f" (list "?resume"))
                                  "call t:predicate"
                                  (list "?resume")))
              (quiet #f)))

          (define normalized (lambda (expr) (shape (● (normal 0 suspensions expr) first))))

          (define shape
            (lambda (expr) (match (● expr term)
                             ((Lit (DInt n)) (i64->string n))
                             ((Var name _ _) (short-name name))
                             ((Lambda params body) (string-append "(lambda " (shape body) ")"))
                             ((App callee args)
                              (string-append "("
                                             (string-join (map shape (Cons callee args)) " ")
                                             ")"))
                             ((If test then otherwise)
                              (string-append "(if "
                                             (shape test)
                                             " "
                                             (shape then)
                                             " "
                                             (shape otherwise)
                                             ")"))
                             ((Let name value body)
                              (string-append "(let " name " " (shape value) " " (shape body) ")"))
                             ((Seq first rest)
                              (string-append "(begin " (shape first) " " (shape rest) ")"))
                             (_ "?"))))

          ;; A call yields what its callee does, a closure nothing until it
          ;; is called, and a suspension to its prompt.
          (define test-yields
            (lambda () (expect (yields suspensions (call g (list (number 1)))) (Nil))
                    (expect
                     (yields suspensions (call add (list (number 1) (call f (list (number 2))))))
                     (list "?resume"))
                    (expect (yields suspensions (thunk (call f (list (number 1))))) (Nil))
                    (expect (yields suspensions (suspend stopping)) (list "t:stopping"))
                    (expect (yields suspensions (suspend (local "prompt.1" stopping-type)))
                            (list "?abort"))
                    (expect (yields suspensions (suspend (local "prompt.1" pausing-type)))
                            (list "?resume"))))

          ;; A `with-prompt` of a named prompt catches its body's suspensions
          ;; to it and nothing else, and adds what its handler suspends.
          (define test-delimited
            (lambda ()
              (let ((handler (expr (Lambda (list "value.1" "resume.1") (number 0))
                                   (TFun (list i64 (TFun (list never) i64 empty-row))
                                         i64
                                         empty-row))))
                (expect (yields suspensions (with-prompt stopping (thunk (suspend stopping)) handler))
                        (Nil))
                (expect (yields suspensions (with-prompt stopping (thunk (suspend pausing)) handler))
                        (list "t:pausing"))
                (expect
                 (yields suspensions
                         (with-prompt (local "prompt.1" stopping-type)
                                      (thunk (suspend (local "prompt.1" stopping-type)))
                                      handler))
                 (list "?abort"))
                (expect
                 (yields suspensions
                         (with-prompt stopping
                                      (thunk (number 1))
                                      (expr (Lambda (list "value.1" "resume.1") (suspend pausing))
                                            (● handler type))))
                 (list "t:pausing")))))

          ;; Only a suspension something may resume saves frames.
          (define test-resumed
            (lambda () (expect (may-resume? suspensions (list "t:stopping" "?abort")) #f)
                    (expect (may-resume? suspensions (list "t:stopping" "t:pausing")) #t)
                    (expect (may-resume? suspensions (list "?resume")) #t)))

          ;; Suspensions reach every caller, through recursion and through a
          ;; function value of the suspending lambda's type, and stop at the
          ;; `with-prompt` that catches them.
          (define test-solved
            (lambda ()
              (let* ((definition
                       (lambda (name params body)
                         (new Definition
                           (name name)
                           (value (expr (Lambda params body)
                                        (TFun (map (lambda (param) i64) params)
                                              (● body type)
                                              empty-row))))))
                     (callback (TFun (Nil) i64 empty-row))
                     (handler (expr (Lambda (list "value.1" "resume.1") (number 0))
                                    (TFun (list i64 (TFun (list unit-type) i64 empty-row))
                                          i64
                                          empty-row)))
                     (definitions
                       (list (definition "t:leaf" (Nil) (suspend pausing))
                             (definition "t:even" (Nil) (call (local "t:odd" callback) (Nil)))
                             (definition "t:odd"
                                         (Nil)
                                         (expr (Seq (call (local "t:leaf" callback) (Nil))
                                                    (call (local "t:even" callback) (Nil)))
                                               i64))
                             (definition "t:maker" (Nil) (thunk (suspend stopping)))
                             (definition "t:applies"
                                         (list "action.1")
                                         (call (local "action.1" callback) (Nil)))
                             (definition "t:caught"
                                         (Nil)
                                         (with-prompt pausing
                                                      (thunk (call (local "t:even" callback) (Nil)))
                                                      handler))
                             (definition "t:quiet" (Nil) (number 1))))
                     (types (fold-left (lambda (types definition)
                                         (table-set types
                                                    (● definition name)
                                                    (● (● definition value) type)))
                                       (● declarations types)
                                       definitions))
                     (solved (program-suspensions (Declarations-types-set declarations types)
                                                  definitions))
                     (reaches (lambda (key) (reached-at (● solved reached) key))))
                (expect (reaches "call t:leaf") (list "t:pausing"))
                (expect (reaches "call t:even") (list "t:pausing"))
                (expect (reaches "call t:odd") (list "t:pausing"))
                (expect (reaches "call t:maker") (Nil))
                (expect (reaches "call t:applies") (list "t:stopping"))
                (expect (reaches "call t:caught") (Nil))
                (expect (reaches "call t:quiet") (Nil))
                (expect (● solved quiet) #f))))

          (define test-operands
            (lambda ()
              (expect
               (normalized (call add (list (call g (list (number 1))) (call f (list (number 2))))))
               "(let %control.0% (g 1) (let %control.1% (f 2) (add %control.0% %control.1%)))")
              (expect (normalized (call add (list (number 1) (call f (list (number 2))))))
                      "(let %control.0% (f 2) (add 1 %control.0%))")
              (expect
               (normalized (call add (list (call f (list (number 1))) (call g (list (number 2))))))
               "(let %control.0% (f 1) (add %control.0% (g 2)))")
              (expect (normalized (call g (list (call f (list (call f (list (number 1))))))))
                      "(let %control.1% (let %control.0% (f 1) (f %control.0%)) (g %control.1%))")))

          (define test-flow
            (lambda () (expect (normalized (call f (list (call g (list (number 1)))))) "(f (g 1))")
                    (expect (normalized
                             (expr (If (call predicate (Nil)) (call f (list (number 1))) (number 2))
                                   i64))
                            "(let %control.0% (predicate) (if %control.0% (f 1) 2))")
                    (expect (normalized (expr (Seq (call f (list (number 1))) (number 2)) i64))
                            "(let %control.0% (f 1) 2)")
                    (expect
                     (normalized
                      (expr (Let "x.1" (call f (list (number 1))) (call g (list (local "x.1" i64))))
                            i64))
                     "(let x.1 (f 1) (g x.1))")
                    (expect
                     (normalized
                      (expr (Lambda (list "x.1") (call g (list (call f (list (number 1))))))
                            (● g type)))
                     "(lambda (let %control.0% (f 1) (g %control.0%)))")))

          (define test-unchanged
            (lambda ()
              (let ((pure (call add (list (call g (list (number 1))) (call g (list (number 2)))))))
                (expect (eq? (● (control-expr 0 suspensions pure) first) pure) #t))))

          (define test-holds
            (lambda ()
              (let ((inner
                     (expr (Let "x.1" (call f (list (number 1))) (call g (list (local "x.1" i64))))
                           i64)))
                (expect (holds-yield-point? suspensions inner) #t)
                (expect (holds-yield-point? suspensions
                                            (expr (If (local "c.1" bool) inner (number 2)) i64))
                        #t)
                (expect (holds-yield-point? suspensions (call f (list (number 1)))) #f)
                (expect (holds-yield-point? suspensions
                                            (expr (Lambda (list "y.1") inner) (● g type)))
                        #f))))

          (test-yields)
          (test-delimited)
          (test-resumed)
          (test-solved)
          (test-operands)
          (test-flow)
          (test-unchanged)
          (test-holds)))))
   (else)))

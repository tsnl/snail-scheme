;; Preparation closes specialization and cleanup requests, checks concrete
;; original bodies, and produces fixed declarations and normalized items.
;; Control lowering ensures nothing runs after a
;; call that may yield before the backend has tested for the yield. After
;; specialization a row keeps only control effects, so a call may yield
;; exactly when its callee's row names one: a global's as it is defined or
;; declared, a local's as its type says. Such a call stays where it is
;; when its value flows straight out of a function, a handle body or a
;; let's value; anywhere else, a let names it, with the rest of the
;; expression as the let's body, and names first each operand that runs
;; before it, so those still run first. The backend tests for a yield after
;; each let whose value may yield. The prepared program uses this subset of
;; the checked expression language; emission has no specialization work.
;;
;; The pass also refuses a control row wherever nothing could carry a
;; yield: in the callbacks that the WAT loops of vector-generate and
;; string-generate call, in an unsafe-total thunk, in a procedure closed
;; over its handlers, in dispatched work but to `tasks`, and in the
;; implementation of an operation declared without ctl.
(define-library (snail shell compiler prepare)
  (export
   Prepared
   prepare-program
   prepare-library
   Callees
   declaration-callees
   yields
   holds-yield-point?)
  (import
   (snail core base)
   (snail core table)
   (snail shell compiler read)
   (snail shell compiler core)
   (snail shell compiler capabilities)
   (only (snail shell compiler check) Typed)
   (only (snail shell compiler ownership) consumed-references)
   (snail shell compiler specialize)
   (snail shell compiler reference-counting))
  (begin

    ;; ---- Prepared code ----

    ;; Fixed declarations and concrete function bodies consumed by emission.
    ;; A value binding keeps function? false; its body is a zero-argument
    ;; initializer lowered by the same passes as an ordinary function.
    (struct Prepared
      ((declarations Declarations)
       (definitions (List Item))
       (entry (Option String))
       (exposed (List Item))
       (exported (List String))))

    (define (prepare-program (typed Typed)) (→ Prepared) (! compile)
      (prepare (prepare-specialization typed) (None) (● typed items)))

    (define (prepare-library (input Specialization) (owner String) (items (List Item)))
      (→ Prepared)
      (! compile)
      (prepare input (Some owner) items))

    (define (prepare (input Specialization) (owner (Option String)) (items (List Item)))
      (→ Prepared) (! compile)
      (match (start-specialization (new-state input owner) items)
        ((Pair exported state)
         (let* ((roots (filter (lambda (item) (match item ((Define _ _) #f) (_ #t))) items))
                (lowered (prepare-batches state roots (Nil))))
           (prepared (● lowered state) (● lowered items) exported)))))

    ;; Close each newly discovered graph before checking its original bodies.
    ;; Cleanup adds new definitions without changing an old body or contract,
    ;; so old checks remain valid. A new check may still inspect an old body
    ;; under a different context; only construction, never that answer, is cached.

    (define (prepare-batches (state State) (roots (List Item)) (done (List Item)))
      (→ Lowered) (! compile)
      (match (complete-specializations state)
        ((Pair definitions state)
         (let ((items (append roots definitions)))
           (if (null? items) (Lowered (reverse done) state)
               (let ((lowered (prepare-batch state items)))
                 (prepare-batches (● lowered state) (Nil)
                                  (append (reverse (● lowered items)) done))))))))

    (define (prepare-batch (state State) (items (List Item))) (→ Lowered) (! compile)
      (let ((callees (specialization-callees state)))
        (for-each (lambda (item) (check-item callees item)) items)
        (let* ((declarations (specialization-declarations state))
               (items
                (map
                 (lambda (item) (lower-reference-counting declarations (initializer-function item)))
                 items))
               (lowered (fold-left (lambda (lowered item) (lower-item lowered callees item))
                                   (Lowered (Nil) state) items)))
          (Lowered-items-set lowered (reverse (● lowered items))))))



    ;; Keep the original body in specialization's contextual analysis. A
    ;; computed procedure's initializer is pure; calling its result may yield.
    (define (initializer-function (item Item)) (→ Item)
      (match item
        ((Define name value)
         (if (lambda-expr? value) item
             (Define name (Expr (Lambda (Nil) value #f)
                                (TFun (Nil) (● value type) empty-row) (● value loc)))))
        (_ item)))

    (define (prepared (state State) (items (List Item)) (exported (List String))) (→ Prepared)
      (Prepared (specialization-declarations state)
                (filter (lambda (item) (match item ((Define _ _) #t) (_ #f))) items)
                (match (find (lambda (item) (match item ((Entry _ _) #t) (_ #f))) items)
                  ((Some (Entry name _)) (Some name))
                  (_ (None)))
                (filter (lambda (item) (match item ((Expose _ _ _ _) #t) (_ #f))) items)
                exported))

    ;; ---- Yields ----

    ;; Checks read the original concrete bodies of a closed graph. Emission
    ;; uses the same fixed call contracts with no original bodies attached.
    ;; Reading/resumption assumptions belong to each inspection, not a binding.
    (struct Callees
      ((declarations Declarations)
       (definitions (Table Expr))
       (resumes (List (Pair String String)))
       (reading (Option (List String)))))

    (define (specialization-callees (state State)) (→ Callees)
      (Callees (specialization-declarations state)
               (if (null? (● state control)) empty-table (specialization-definitions state))
               (Nil) (None)))

    (define (declaration-callees (declarations Declarations)) (→ Callees)
      (Callees declarations empty-table (Nil) (None)))

    (define (callees-program (callees Callees)) (→ Program)
      (● (● callees declarations) program))

    (define (callees-control (callees Callees)) (→ (List String))
      (● (● callees declarations) control))

    ;; The control effects a value of a procedure type may yield to when
    ;; called: those its row names. Calling a `FnOnce` calls the procedure it
    ;; holds, and calling a `fn` the code it is.

    (define (call-row (type Type)) (→ (List String))
      (match (fn-arrow type)
        ((TFun _ _ (TRow labels _)) labels)
        (_ (Nil))))

    ;; What calling `callee` may yield to. The checker opens the row of each
    ;; use of a global to its context's, so a global's own definition or
    ;; declaration says instead: a constructor, an accessor or a foreign
    ;; function yields nothing, an operation yields to the control effects
    ;; among its effect and its latent row, which its implementation may
    ;; yield to, and a primitive yields only through a row variable, as
    ;; call-once does through its procedure's. Closing a procedure over its
    ;; handlers charges its row without calling it, so it yields nothing.

    (define (callee-row (callees Callees) (callee Expr)) (→ (List String))
      (match (● callee term)
        ((Ann inner _) (callee-row callees inner))
        ((Var name _ _)
         (match (table-ref (● (● callees declarations) bindings) name)
           ((Some binding)
            (filter (lambda (label) (member? label (callees-control callees)))
                    (definition-row callees name binding)))
           ((None) (declared-row callees name (● callee type)))))
        (_ (call-row (● callee type)))))

    ;; A contextual check reads the cached source body. Generated glue,
    ;; imported definitions and recursive inspection use the declared row.

    (define (definition-row (callees Callees) (name String) (binding Binding)) (→ (List String))
      (let ((row (call-row (● binding type))))
        (match (● callees reading)
          ((Some reading)
           (if (or (● binding external?) (member? name reading))
               row
               (match (table-ref (● callees definitions) name)
                 ((Some (Expr (Lambda _ body _) _ _))
                  (yields (Callees-reading-set callees (Some (Cons name reading))) body))
                 (_ row))))
          ((None) row))))

    (define (declared-row (callees Callees) (name String) (type Type)) (→ (List String))
      (match (program-value (callees-program callees) name)
        ((Some (Operation effect scheme)) (operation-row callees effect scheme))
        ((Some (Primitive scheme))
         (if (or (closed-row? (● scheme type)) (member? name closing-primitives))
             (Nil)
             (call-row type)))
        ((Some (Foreign _ _)) (Nil))
        ((Some (Constructor _ _)) (Nil))
        ((Some (Accessor _ _ _)) (Nil))
        ((Some (Replacer _ _ _)) (Nil))
        ((Some (Setter _ _ _)) (Nil))
        ((Some (Swapper _ _ _)) (Nil))
        (_ (resume-row callees name type))))

    (define closing-primitives (list "prim:inherit-handlers" "prim:inherit-handlers-1"))

    ;; A `resume` of a handle of X runs the rest of its body under the same
    ;; handle again, which catches every yield to X there.

    (define (resume-row (callees Callees) (name String) (type Type)) (→ (List String))
      (match (assoc-ref (● callees resumes) name)
        ((Some effect) (label-difference (call-row type) (list effect)))
        ((None) (call-row type))))

    (define (operation-row (callees Callees) (effect String) (scheme Scheme)) (→ (List String))
      (filter (lambda (label) (member? label (callees-control callees)))
              (Cons effect (operation-latent effect scheme))))

    (define (closed-row? (type Type)) (→ Bool)
      (match (fn-arrow type)
        ((TFun _ _ (TRow _ (None))) #t)
        (_ #f)))

    ;; The control effects evaluating `expr` may yield to. Making a closure
    ;; yields nothing; its body yields when it is called. A handle catches
    ;; what its body yields to its own effect, and runs its control
    ;; implementations itself, once the body has unwound to it.

    (define (yields (callees Callees) (expr Expr)) (→ (List String))
      (let ((all (lambda (exprs)
                   (fold-left (lambda (labels expr) (label-union labels (yields callees expr)))
                              (Nil)
                              exprs))))
        (match (● expr term)
          ((Lambda _ _ _) (Nil))
          ((App callee args)
           (label-union (application-yields callees callee args) (all (Cons callee args))))
          ((Handle effect implementations body)
           (label-union (all (map (lambda (record) (● record second)) implementations))
                        (label-union (label-difference (yields callees body) (list effect))
                                     (control-implementation-yields callees
                                                                    effect
                                                                    implementations))))
          (_ (all (expr-children expr))))))

    ;; These primitives execute a supplied callback. Its body is stronger
    ;; evidence than a use row widened to the surrounding context. In
    ;; particular, copying primitive array elements cannot start yielding
    ;; merely because the caller also performs a control effect.
    (define (application-yields (callees Callees) (callee Expr) (args (List Expr)))
      (→ (List String))
      (match (● callee term)
        ((Ann inner _) (application-yields callees inner args))
        ((Var "prim:unsafe-total" _ _) (procedure-yields callees (list-ref args 0)))
        ((Var "prim:vector-generate" _ _) (procedure-yields callees (list-ref args 1)))
        ((Var "prim:string-generate" _ _) (procedure-yields callees (list-ref args 1)))
        (_ (callee-row callees callee))))

    (define (control-implementation-yields (callees Callees)
                                           (effect String)
                                           (implementations (List (Pair String Expr))))
      (→ (List String))
      (let ((control (● (program-effect (callees-program callees) effect) control)))
        (fold-left (lambda (labels entry)
                     (if (member? (● entry first) control)
                         (label-union labels (procedure-yields callees (● entry second)))
                         labels))
                   (Nil) implementations)))

    ;; What calling a procedure may yield to: what a lambda's body may, and
    ;; otherwise what calling the procedure may. `(once procedure)` holds
    ;; the procedure it is given.

    (define (procedure-yields (callees Callees) (procedure Expr)) (→ (List String))
      (match (● procedure term)
        ((Lambda _ body _) (yields callees body))
        ((Ann inner _) (procedure-yields callees inner))
        ((App (Expr (Var "prim:once" _ _) _ _) (Cons held (Nil))) (procedure-yields callees held))
        (_ (callee-row callees procedure))))

    ;; Whether no call anywhere in `expr`, lambda bodies included, may yield.

    (define (yield-free? (callees Callees) (expr Expr)) (→ Bool)
      (and (match (● expr term)
             ((App callee _) (null? (callee-row callees callee)))
             (_ #t))
           (every? (lambda (child) (yield-free? callees child)) (expr-children expr))))

    ;; Whether a let inside `expr`, outside its lambdas, has a value that
    ;; may yield. The backend tests for a yield after such a let and leaves
    ;; while one is set, so a value that holds one is a block it can leave.

    (define (holds-yield-point? (callees Callees) (expr Expr)) (→ Bool)
      (match (● expr term)
        ((Lambda _ _ _) (match (● expr type) ((TCon "FnOnce" _) #t) (_ #f)))
        ((Let _ value body)
         (or (not (null? (yields callees value))) (holds-yield-point? callees body)))
        (_ (any? (lambda (child) (holds-yield-point? callees child)) (expr-children expr)))))

    ;; ---- Restrictions ----

    ;; A function whose procedure argument runs where no yield test can
    ;; reach: the argument's position, what to call it in a diagnostic, and
    ;; the control effects it may yield to all the same.
    (struct Restriction
      ((position I64)
       (what String)
       (allowed (List String))))

    ;; The generate helpers loop in WAT; unsafe-total discards its thunk's
    ;; row, so nothing after it tests; and a procedure closed over its
    ;; handlers runs whenever it is called, when the handles it would yield
    ;; to may have returned. Dispatched work is closed over its handlers
    ;; too, and runs under its own handler of `tasks`. It is named at the
    ;; dispatch, which is where its work is written, rather than at the
    ;; closing inside (snail shell task).

    (define restrictions (→ (List (Pair String Restriction)))
      (list (Pair "prim:vector-generate" (Restriction 1 "a vector-generate callback" (Nil)))
            (Pair "prim:string-generate" (Restriction 1 "a string-generate callback" (Nil)))
            (Pair "prim:unsafe-total" (Restriction 0 "an unsafe-total thunk" (Nil)))
            (Pair "prim:inherit-handlers"
                  (Restriction 0 "a procedure given to inherit-handlers" (Nil)))
            (Pair "prim:inherit-handlers-1"
                  (Restriction 0 "a procedure given to inherit-handlers-1" (Nil)))
            (Pair "snail.shell.task:dispatch-local"
                  (Restriction 0 "work given to dispatch-local" (list "snail.shell.task:tasks")))
            (Pair "snail.shell.task:dispatch-task"
                  (Restriction 0 "work given to dispatch-task" (list "snail.shell.task:tasks")))
            (Pair "snail.shell.async:dispatch"
                  (Restriction 0 "work given to dispatch" (list "snail.shell.task:tasks")))))

    (define (restriction (callee Expr)) (→ (Option Restriction))
      (match (● callee term)
        ((Ann inner _) (restriction inner))
        ((Var name _ _) (assoc-ref restrictions (generic-name name)))
        (_ (None))))

    ;; Specialization names a concrete implementation by its definition and the types it is
    ;; at, `name<types>`; a restriction names the definition.

    (define (generic-name (name String)) (→ String)
      (let ((chars (string->vector name)))
        (let loop ((index 0))
          (cond ((= index (vector-length chars)) name)
                ((char=? (vector-ref chars index) #\<) (substring name 0 index))
                (else (loop (+ index 1)))))))

    ;; A restricted primitive called directly is judged by the procedure it
    ;; is given, and one used as a value by its type. An implementation of
    ;; an operation declared without ctl returns to its caller in the
    ;; handled body, which tests for a yield after the operation only when
    ;; the operation's type names a control effect: the implementation may
    ;; yield to those its latent row names, and to no other.

    (define (check-restrictions (callees Callees) (expr Expr)) (→ Unit) (! compile)
      (match (● expr term)
        ((App callee args)
         (match (restriction callee)
           ((Some (Restriction index what allowed))
            (refuse-labels
             (label-difference (procedure-yields (reading callees) (list-ref args index)) allowed)
             what
             (● expr loc)))
           ((None) (check-restrictions callees callee)))
         (for-each (lambda (arg) (check-restrictions callees arg)) args))
        ((Var _ _ _)
         (match (restriction expr)
           ((Some (Restriction index what allowed))
            (refuse-labels
             (label-difference (call-row (list-ref (function-params (● expr type)) index))
                               allowed)
             what
             (● expr loc)))
           ((None) (unit))))
        ((Handle effect implementations body)
         (check-implementations callees effect implementations)
         (check-restrictions callees body)
         (let ((inside (resuming callees effect implementations)))
           (for-each (lambda (entry) (check-restrictions inside (● entry second)))
                     implementations)))
        (_ (for-each (lambda (child) (check-restrictions callees child)) (expr-children expr)))))

    ;; A restriction check reads the bodies of the definitions it reaches.

    (define (reading (callees Callees)) (→ Callees)
      (match (● callees reading)
        ((Some _) callees)
        ((None) (Callees-reading-set callees (Some (Nil))))))

    ;; Inside its control implementations, a handle's `resume`s yield to its
    ;; effect only if an implementation does, so a scheduler can close a
    ;; resumption over its handlers when its continuation would yield to
    ;; the scheduler's own effect. Whether one does is asked assuming they
    ;; do not; if one does even so, the assumption is dropped.

    (define (resuming (callees Callees) (effect String) (implementations (List (Pair String Expr))))
      (→ Callees)
      (let ((assumed (Callees-resumes-set callees
                                          (append (resume-names callees effect implementations)
                                                  (● callees resumes)))))
        (if (member? effect (control-implementation-yields assumed effect implementations))
            callees
            assumed)))

    ;; Each control implementation written as a lambda takes its `resume`
    ;; last.

    (define (resume-names (callees Callees)
                          (effect String)
                          (implementations (List (Pair String Expr))))
      (→ (List (Pair String String)))
      (let ((control (● (program-effect (callees-program callees) effect) control)))
        (concatenate (map (lambda (entry)
                            (if (member? (● entry first) control)
                                (match (● (● entry second) term)
                                  ((Lambda params _ _)
                                   (match (last params)
                                     ((Some resume) (list (Pair resume effect)))
                                     ((None) (Nil))))
                                  (_ (Nil)))
                                (Nil)))
                          implementations))))

    (define (check-implementations (callees Callees)
                                   (effect String)
                                   (implementations (List (Pair String Expr))))
      (→ Unit)
      (! compile)
      (let ((control (● (program-effect (callees-program callees) effect) control)))
        (for-each (lambda (entry)
                    (unless (member? (● entry first) control)
                      (check-implementation callees (● entry first) (● entry second))))
                  implementations)))

    (define (check-implementation (callees Callees) (operation String) (implementation Expr))
      (→ Unit)
      (! compile)
      (match (program-value (callees-program callees) operation)
        ((Some (Operation effect scheme))
         (let ((labels (label-difference (procedure-yields callees implementation)
                                         (operation-latent effect scheme))))
           (unless (null? labels)
             (compile-error (● implementation loc)
                            (string-append "the implementation of " (short-name operation)
                                           " can yield only to the control effects its operation's type names; it may yield to"
                                           (labels->string labels))))))
        (_ (panic "internal error: not an operation"))))

    (define (refuse-labels (labels (List String)) (what String) (loc Loc)) (→ Unit) (! compile)
      (unless (null? labels)
        (compile-error loc
                       (string-append what
                                      " cannot reach a control operation; it may yield to"
                                      (labels->string labels)))))

    (define (function-params (type Type)) (→ (List Type))
      (match (fn-arrow type)
        ((TFun params _ _) params)
        (_ (panic "internal error: a primitive is a function"))))

    ;; ---- A-normal form ----

    ;; Temporaries are numbered, and the count is threaded through the pass
    ;; as `let*` would write it: each step takes the count as its first
    ;; argument and hands back its value and the next count.
    (define-syntax naming
      (syntax-rules ()
        ((_ count () body ...) (begin body ...))
        ((_ count ((name (f argument ...)) step ...) body ...)
         (match (f count argument ...)
           ((Pair name count) (naming count (step ...) body ...))))))

    ;; Source locals end in `.digits` and globals contain a colon, so these
    ;; names are the pass's own.

    (define (temporary-name (count I64)) (→ String)
      (string-append "%control." (i64->string count) "%"))

    (define (temporary (name String) (value Expr)) (→ Expr)
      (Expr (Var name (Nil) (Nil)) (● value type) (● value loc)))

    (define (bind (name String) (value Expr) (body Expr)) (→ Expr)
      (Expr (Let name value body) (● body type) (● value loc)))

    ;; `expr` with each call that may yield, and each operand that runs
    ;; before one, named by a let, except where its value flows out of
    ;; `expr`: through a branch, a let's body, the rest of a sequence, a
    ;; clause body or an annotation. A let's value, a handle's body and a
    ;; lambda's body are each a place values flow out of as well.

    (define (normal (count I64) (callees Callees) (expr Expr)) (→ (Pair Expr I64))
      (let ((rebuild (lambda (term) (Expr term (● expr type) (● expr loc)))))
        (match (● expr term)
          ((Lambda params body captures?)
           (naming count ((body (normal callees body)))
                   (Pair (rebuild (Lambda params body captures?)) count)))
          ((App callee args) (normal-call count callees expr callee args))
          ((If test then otherwise)
           (naming count ((test (normal callees test))
                          (then (normal callees then))
                          (otherwise (normal callees otherwise)))
                   (named count callees test (lambda (test) (rebuild (If test then otherwise))))))
          ((Let name value body)
           (naming count ((value (normal callees value))
                          (body (normal callees body)))
                   (Pair (rebuild (Let name value body)) count)))
          ((Seq first rest)
           (naming count ((first (normal callees first))
                          (rest (normal callees rest)))
                   (sequence count callees expr first rest)))
          ((Match scrutinee clauses)
           (naming count ((scrutinee (normal callees scrutinee))
                          (clauses (normal-clauses callees clauses)))
                   (named count
                          callees
                          scrutinee
                          (lambda (scrutinee) (rebuild (Match scrutinee clauses))))))
          ((ScopedInstances _ _) (panic "internal error: instance scope survived checking"))
          ((FieldRead _ _ _) (panic "internal error: field selection survived checking"))
          ((Ann inner type)
           (naming count ((inner (normal callees inner))) (Pair (rebuild (Ann inner type)) count)))
          ((Convert inner target)
           (naming count ((inner (normal callees inner)))
                   (named count callees inner (lambda (inner) (rebuild (Convert inner target))))))
          ((TypeTest inner target)
           (naming count ((inner (normal callees inner)))
                   (named count callees inner (lambda (inner) (rebuild (TypeTest inner target))))))
          ((Handle effect implementations body)
           (normal-handle count callees expr effect implementations body))
          (_ (Pair expr count)))))

    (define (normal-all (count I64) (callees Callees) (exprs (List Expr)))
      (→ (Pair (List Expr) I64))
      (match exprs
        ((Cons expr rest)
         (naming count ((expr (normal callees expr))
                        (rest (normal-all callees rest)))
                 (Pair (Cons expr rest) count)))
        ((Nil) (Pair (Nil) count))))

    (define (normal-clauses (count I64) (callees Callees) (clauses (List Clause)))
      (→ (Pair (List Clause) I64))
      (match clauses
        ((Cons clause rest)
         (naming count ((body (normal callees (● clause body)))
                        (rest (normal-clauses callees rest)))
                 (Pair (Cons (Clause (● clause pattern) body) rest) count)))
        ((Nil) (Pair (Nil) count))))

    ;; `make` applied to `operand`, or, when the operand may yield, to a
    ;; temporary that a let binds to it first.

    (define (named (count I64) (callees Callees) (operand Expr) (make (Fn Expr → Expr)))
      (→ (Pair Expr I64))
      (if (null? (yields callees operand))
          (Pair (make operand) count)
          (let ((name (temporary-name count)))
            (Pair (bind name operand (make (temporary name operand))) (+ count 1)))))

    ;; A sequence whose first part may yield binds it, so the let tests it.

    (define (sequence (count I64) (callees Callees) (expr Expr) (first Expr) (rest Expr))
      (→ (Pair Expr I64))
      (if (null? (yields callees first))
          (Pair (Expr (Seq first rest) (● expr type) (● expr loc)) count)
          (Pair (bind (temporary-name count) first rest) (+ count 1))))

    (define (normal-call (count I64) (callees Callees) (expr Expr) (callee Expr) (args (List Expr)))
      (→ (Pair Expr I64))
      (naming count ((operands (normal-all callees (Cons callee args)))
                     (bound (bind-operands callees operands)))
              (match (● bound operands)
                ((Cons callee args)
                 (Pair (wrap-lets bound (Expr (App callee args) (● expr type) (● expr loc)))
                       count))
                ((Nil) (panic "internal error: a call without a callee")))))

    ;; A handle evaluates its implementations in its effect's operation
    ;; order, before its body runs.

    (define (normal-handle (count I64)
                           (callees Callees)
                           (expr Expr)
                           (effect String)
                           (implementations (List (Pair String Expr)))
                           (body Expr))
      (→ (Pair Expr I64))
      (let* ((operations (● (program-effect (callees-program callees) effect) operations))
             (values
              (map (lambda (operation) (implementation-of implementations operation)) operations)))
        (naming count ((values (normal-all callees values))
                       (bound (bind-operands callees values))
                       (body (normal callees body)))
                (Pair (wrap-lets bound
                                 (Expr (Handle effect (zip operations (● bound operands)) body)
                                       (● expr type)
                                       (● expr loc)))
                      count))))

    (define (implementation-of (implementations (List (Pair String Expr))) (operation String))
      (→ Expr)
      (match (assoc-ref implementations operation)
        ((Some implementation) implementation)
        ((None) (panic "internal error: missing implementation"))))

    ;; ---- Operands ----

    ;; Operands in evaluation order, after the lets that must run before
    ;; them. Each operand before the last that may yield is named, so it
    ;; still runs before that one, unless evaluating it has no effect; the
    ;; last that may yield is named, so the let tests it.
    (struct Bound
      ((lets (List (Pair String Expr)))
       (operands (List Expr))))

    (define (wrap-lets (bound Bound) (body Expr)) (→ Expr)
      (fold-right (lambda (entry body) (bind (● entry first) (● entry second) body))
                  body
                  (● bound lets)))

    (define (bind-operands (count I64) (callees Callees) (operands (List Expr)))
      (→ (Pair Bound I64))
      (let ((final (fold-left (lambda (final entry)
                                (if (null? (yields callees (● entry second)))
                                    final
                                    (● entry first)))
                              -1 (zip (iota (length operands)) operands))))
        (bind-from count callees final 0 operands)))

    (define (bind-from (count I64) (callees Callees) (final I64) (index I64) (operands (List Expr)))
      (→ (Pair Bound I64))
      (match operands
        ((Cons operand rest)
         (if (and (<= index final) (or (= index final) (not (inert? callees operand))))
             (let ((name (temporary-name count)) (next (+ count 1)))
               (naming next ((bound (bind-from callees final (+ index 1) rest)))
                       (Pair (Bound (Cons (Pair name operand) (● bound lets))
                                    (Cons (temporary name operand) (● bound operands)))
                             next)))
             (naming count ((bound (bind-from callees final (+ index 1) rest)))
                     (Pair (Bound (● bound lets) (Cons operand (● bound operands)))
                           count))))
        ((Nil) (Pair (Bound (Nil) (Nil)) count))))

    ;; A value global may initialize or panic. Preserve that read before a
    ;; later yielding operand; ordinary locals and function references are inert.

    (define (inert? (callees Callees) (expr Expr)) (→ Bool)
      (match (● expr term)
        ((Lit _) #t)
        ((Var name _ _)
         (match (table-ref (● (● callees declarations) bindings) name)
           ((Some binding) (● binding function?))
           ((None) #t)))
        ((Lambda _ _ _) #t)
        (_ #f)))

    ;; ---- Lowering a batch ----

    ;; A batch owns its normalized items and the requests cleanup discovers.
    (struct Lowered
      ((items (List Item))
       (state State)))

    (define (lower-item (lowered Lowered) (callees Callees) (item Item)) (→ Lowered)
      (match (lower-droppers (● lowered state) callees (control-item callees item))
        ((Pair item state) (Lowered (Cons item (● lowered items)) state))))

    (define (check-exposure (callees Callees) (item Item)) (→ Unit) (! compile)
      (match item
        ((Expose name _ _ loc) (check-entry-function callees name loc))
        ((Entry name loc) (check-entry-function callees name loc))
        (_ (unit))))

    (define (check-entry-function (callees Callees) (name String) (loc Loc)) (→ Unit) (! compile)
      (match (table-ref (● (● callees declarations) bindings) name)
        ((Some binding)
         (unless (● binding function?)
           (compile-error loc "an entry must be defined as a function")))
        ((None) (panic "internal error: an entry has no binding"))))

    ;; ---- Droppers ----

    ;; A frame owns the linear and counted locals assigned to its yield
    ;; point. `with-cleanup` carries their ordered cancellation code; the
    ;; backend emits it over the frame's own environment. A once lambda
    ;; keeps a separate thunk for its linear captures, so `once` becomes
    ;; `once-dropping`. Cleanup references are reserved immediately in the
    ;; specialization worklist; their bodies are completed by the next batch.
    ;; Cleanup is built in one rewriting traversal, threading that registry
    ;; alongside lexical scopes.

    (define unit-type (→ Type) (TCon "Unit" (Nil)))

    ;; The unit value, as a dropper ends.

    (define (unit-expr (loc Loc)) (→ Expr)
      (Expr (App (Expr (Var "prim:unit" (Nil) (Nil)) (TFun (Nil) unit-type empty-row) loc) (Nil))
            unit-type
            loc))

    (define-syntax cleaning
      (syntax-rules ()
        ((_ state () body ...) (begin body ...))
        ((_ state ((name (f arg ...)) step ...) body ...)
         (match (f state arg ...)
           ((Pair name state) (cleaning state (step ...) body ...))))))

    (define (lower-droppers (state State) (callees Callees) (item Item)) (→ (Pair Item State))
      (match item
        ((Define name value)
         (if (needs-droppers? callees value)
             (cleaning state ((value (droppers callees (Nil) value)))
                       (Pair (Define name value) state))
             (Pair item state)))
        (_ (Pair item state))))

    ;; Most definitions own no continuation or one-shot closure. Avoid
    ;; building ownership scopes for them; the base library declares dyn-cast
    ;; even in programs that never use it.

    (define (needs-droppers? (callees Callees) (expr Expr)) (→ Bool)
      (or (not (yield-free? callees expr)) (holds-once? expr)))

    (define (holds-once? (expr Expr)) (→ Bool)
      (or (match (● expr term)
            ((App (Expr (Var "prim:once" _ _) _ _) _) #t)
            ((Lambda _ _ _) (match (● expr type) ((TCon "FnOnce" _) #t) (_ #f)))
            (_ #f))
          (any? holds-once? (expr-children expr))))



    ;; Owners assigned to this expression, newest binding first. Splitting
    ;; the scope keeps each owner in exactly one continuation; the list
    ;; fixes cleanup order without depending on table iteration order.

    (define (droppers (state State) (callees Callees)
                      (scope (List (Pair String Type))) (expr Expr))
      (→ (Pair Expr State))
      (let ((rebuild (lambda (term) (Expr term (● expr type) (● expr loc)))))
        (match (● expr term)
          ((Lambda params body captures?)
           (cleaning state
                     ((body (droppers callees
                                      (bind-params (taken-scope callees scope expr)
                                                   params (● expr type)) body)))
                     (let ((value (rebuild (Lambda params body captures?))))
                       (if (match (● expr type) ((TCon "FnOnce" _) #t) (_ #f))
                           (dropper-lambda state callees scope value)
                           (Pair value state)))))
          ((App callee args) (dropper-call state callees scope expr callee args))
          ((If test then otherwise)
           (let ((after (remaining-scope callees scope test)))
             (cleaning state ((test (droppers callees (taken-scope callees scope test) test))
                              (then (droppers callees after then))
                              (otherwise (droppers callees after otherwise)))
                       (Pair (rebuild (If test then otherwise)) state))))
          ((Let name value body) (dropper-let state callees scope expr name value body))
          ((Seq first rest)
           (let ((after (remaining-scope callees scope first)))
             (cleaning state ((first (droppers callees (taken-scope callees scope first) first))
                              (rest (droppers callees after rest)))
                       (Pair (rebuild (Seq first rest)) state))))
          ((Match scrutinee clauses)
           (let ((after (remaining-scope callees scope scrutinee)))
             (cleaning state
                       ((scrutinee
                         (droppers callees (taken-scope callees scope scrutinee) scrutinee))
                        (clauses (dropper-clauses callees after clauses)))
                       (Pair (rebuild (Match scrutinee clauses)) state))))
          ((ScopedInstances _ _) (panic "internal error: instance scope survived checking"))
          ((FieldRead _ _ _) (panic "internal error: field selection survived checking"))
          ((Ann inner type)
           (cleaning state ((inner (droppers callees scope inner)))
                     (Pair (rebuild (Ann inner type)) state)))
          ((Convert inner target)
           (cleaning state ((inner (droppers callees scope inner)))
                     (Pair (rebuild (Convert inner target)) state)))
          ((TypeTest inner target)
           (cleaning state ((inner (droppers callees scope inner)))
                     (Pair (rebuild (TypeTest inner target)) state)))
          ((Handle effect implementations body)
           (cleaning state
                     ((values (droppers-all callees scope
                                            (map (lambda (record) (● record second))
                                                 implementations)))
                      (body (droppers callees (taken-scope callees scope body) body)))
                     (hold-abandoned state callees scope expr
                                     (rebuild (Handle effect
                                                      (zip (map (lambda (record) (● record first))
                                                                implementations) values)
                                                      body)))))
          (_ (Pair expr state)))))

    (define (droppers-all (state State) (callees Callees)
                          (scope (List (Pair String Type))) (exprs (List Expr)))
      (→ (Pair (List Expr) State))
      (match exprs
        ((Cons expr rest)
         (let ((after (remaining-scope callees scope expr)))
           (cleaning state ((expr (droppers callees (taken-scope callees scope expr) expr))
                            (rest (droppers-all callees after rest)))
                     (Pair (Cons expr rest) state))))
        ((Nil) (Pair (Nil) state))))

    (define (dropper-clauses (state State) (callees Callees)
                             (scope (List (Pair String Type))) (clauses (List Clause)))
      (→ (Pair (List Clause) State))
      (match clauses
        ((Cons clause rest)
         (cleaning state
                   ((body (droppers callees (bind-pattern-types scope (● clause pattern))
                                    (● clause body)))
                    (rest (dropper-clauses callees scope rest)))
                   (Pair (Cons (Clause (● clause pattern) body) rest) state)))
        ((Nil) (Pair (Nil) state))))

    (define (bind-params (scope (List (Pair String Type))) (params (List String)) (type Type))
      (→ (List (Pair String Type)))
      (match (fn-arrow type)
        ((TFun types _ _)
         (fold-left (lambda (scope pair) (Cons pair scope))
                    scope
                    (zip params types)))
        (_ scope)))

    (define (bind-pattern-types (scope (List (Pair String Type))) (pattern Pattern))
      (→ (List (Pair String Type)))
      (match pattern
        ((PVar name type) (Cons (Pair name type) scope))
        ((PCon _ args _) (fold-left bind-pattern-types scope args))
        (_ scope)))

    ;; A let whose value may yield saves its body as a frame holding the
    ;; owners retained by its caller, even when an aborting body never
    ;; reads them: the let's value carries their ordered cleanup code.

    (define (dropper-let (state State) (callees Callees)
                         (scope (List (Pair String Type))) (expr Expr)
                         (name String) (value Expr) (body Expr))
      (→ (Pair Expr State))
      (let ((after (remaining-scope callees scope value)))
        (cleaning state
                  ((value (droppers callees (taken-scope callees scope value) value))
                   (body (droppers callees (Cons (Pair name (● value type)) after) body))
                   (value (with-cleanup value
                                        (if (null? (yields callees value)) (Nil)
                                            (owned-locals callees after)))))
                  (Pair (Expr (Let name value body) (● expr type) (● expr loc)) state))))

    ;; `once` of a lambda with linear captures marks it with their dropper.

    (define (dropper-call (state State) (callees Callees)
                          (scope (List (Pair String Type))) (expr Expr)
                          (callee Expr) (args (List Expr)))
      (→ (Pair Expr State))
      (cleaning state ((operands (droppers-all callees scope (Cons callee args))))
                (match operands
                  ((Cons callee args)
                   (match (Pair (● callee term) args)
                     ((Pair (Var "prim:once" _ _) (Cons procedure (Nil)))
                      (once-dropping state expr callee procedure
                                     (lambda-captures callees scope procedure)))
                     (_ (hold-abandoned state callees scope expr
                                        (Expr (App callee args) (● expr type) (● expr loc))))))
                  (_ (panic "internal error: a call without a callee")))))

    ;; Assign each owner to the expression that consumes it; owners not
    ;; used by a subexpression stay in its caller's continuation. This also
    ;; retains owners a Never branch never mentions, which liveness from
    ;; the normal continuation alone cannot discover.

    (define (selected-scope (scope (List (Pair String Type)))
                            (names (List String))
                            (selected? Bool))
      (→ (List (Pair String Type)))
      (filter (lambda (entry)
                (if selected? (member? (● entry first) names)
                    (not (member? (● entry first) names)))) scope))

    (define (taken-scope (callees Callees) (scope (List (Pair String Type))) (expr Expr))
      (→ (List (Pair String Type)))
      (selected-scope scope (consumed-references (callees-program callees) expr) #t))

    (define (remaining-scope (callees Callees) (scope (List (Pair String Type))) (expr Expr))
      (→ (List (Pair String Type)))
      (selected-scope scope (consumed-references (callees-program callees) expr) #f))

    (define (hold-abandoned (state State) (callees Callees)
                            (scope (List (Pair String Type))) (original Expr) (value Expr))
      (→ (Pair Expr State))
      (let* ((after (remaining-scope callees scope original))
             (live (if (null? (yields callees value)) (Nil) (owned-locals callees after))))
        (if (null? live) (Pair value state)
            (let* ((name (string-append "control:abandoned."
                                        (string-join (map (lambda (record) (● record first)) live)
                                                     "|")))
                   (result (Expr (Var name (Nil) (Nil)) (● value type) (● value loc))))
              (cleaning state ((value (with-cleanup value live)))
                        (Pair (bind name value result) state))))))

    (define (lambda-captures (callees Callees) (scope (List (Pair String Type))) (procedure Expr))
      (→ (List (Pair String Type)))
      (match (● procedure term)
        ((Lambda _ _ _) (linear-locals callees (taken-scope callees scope procedure)))
        (_ (Nil))))

    ;; A concrete reusable callable owns its environment until it is dropped;
    ;; a consuming callable owns it until its one call or drop. Both keep the
    ;; same capture dropper beside their code. Invocation access is static.

    (define (dropper-lambda (state State) (callees Callees)
                            (scope (List (Pair String Type))) (value Expr))
      (→ (Pair Expr State))
      (let ((captured (lambda-captures callees scope value)) (loc (● value loc)))
        (if (null? captured) (Pair value state)
            (let ((identity (Expr (Var "prim:once" (Nil) (Nil))
                                  (TFun (list (● value type)) (● value type) empty-row) loc)))
              (once-dropping state value identity value captured)))))

    ;; The owners in this scope, in cleanup order.

    (define (linear-locals (callees Callees) (scope (List (Pair String Type))))
      (→ (List (Pair String Type)))
      (filter (lambda (entry)
                (linear-type? (callees-program callees) (Nil) (● entry second)))
              scope))

    (define (owned-locals (callees Callees) (scope (List (Pair String Type))))
      (→ (List (Pair String Type)))
      (filter (lambda (entry)
                (let ((program (callees-program callees)) (type (● entry second)))
                  (or (linear-type? program (Nil) type) (shared-type? program type)))) scope))

    ;; Mark a value with the cleanup of the owners its continuation keeps.
    ;; This is code for the frame's cancellation entry, not a second closure
    ;; owning backup copies. Resume and cancel consume the same environment.

    (define (with-cleanup (state State) (value Expr) (live (List (Pair String Type))))
      (→ (Pair Expr State))
      (if (null? live) (Pair value state)
          (cleaning state ((cleanup (drop-body live (● value loc))))
                    (let ((type (● value type)) (loc (● value loc)))
                      (Pair (Expr (App (Expr (Var "prim:with-cleanup" (Nil) (Nil))
                                             (TFun (list type unit-type) type empty-row) loc)
                                       (list value cleanup)) type loc) state)))))

    (define (once-dropping (state State) (expr Expr) (callee Expr)
                           (procedure Expr) (captured (List (Pair String Type))))
      (→ (Pair Expr State))
      (let ((type (● expr type)) (loc (● expr loc)))
        (if (null? captured) (Pair (Expr (App callee (list procedure)) type loc) state)
            (cleaning state ((thunk (dropper captured loc)))
                      (Pair (Expr (App (Expr (Var "prim:once-dropping" (Nil) (Nil))
                                             (TFun (list (● procedure type) (● thunk type))
                                                   type empty-row) loc)
                                       (list procedure thunk)) type loc) state)))))

    ;; Reserve each required Drop before constructing its call. The registry
    ;; provides a complete signature immediately, even for recursive cleanup.

    (define (dropper (state State) (live (List (Pair String Type))) (loc Loc))
      (→ (Pair Expr State))
      (cleaning state ((body (drop-body live loc)))
                (Pair (Expr (Lambda (Nil) body #t)
                            (TFun (Nil) unit-type empty-row) loc) state)))

    (define (drop-body (state State) (live (List (Pair String Type))) (loc Loc))
      (→ (Pair Expr State))
      (match live
        ((Cons local rest)
         (cleaning state ((drop (request-drop (● local second) loc))
                          (rest (drop-body rest loc)))
                   (let ((call (Expr (App drop (list (Expr (Var (● local first) (Nil) (Nil))
                                                           (● local second) loc))) unit-type loc)))
                     (Pair (Expr (Seq call rest) unit-type loc) state))))
        ((Nil) (Pair (unit-expr loc) state))))

    ;; Each function numbers its own temporaries from zero.

    (define (control-item (callees Callees) (item Item)) (→ Item)
      (match item
        ((Define name value) (Define name (● (control-expr 0 callees value) first)))
        (_ item)))

    (define (control-expr (count I64) (callees Callees) (expr Expr)) (→ (Pair Expr I64))
      (if (yield-free? callees expr) (Pair expr count) (normal count callees expr)))

    (define (check-item (callees Callees) (item Item)) (→ Unit) (! compile)
      (check-exposure callees item)
      (unless (null? (callees-control callees))
        (match item
          ((Define _ value) (check-restrictions callees value))
          (_ (unit)))))

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
        (lambda () (test-yields)
                (test-globals)
                (test-operands)
                (test-flow)
                (test-unchanged)
                (test-holds)
                (test-restrictions)
                (test-resuming)
                (test-reading)
                (test-latent)))

      (define i64 (TCon "I64" (Nil)))
      (define bool (TCon "Bool" (Nil)))
      (define loc (Loc "control" 1 1))
      (define abort-row (TRow (list "t:Abort") (None)))
      (define local (lambda (name type) (Expr (Var name (Nil) (Nil)) type loc)))
      (define number (lambda (n) (Expr (Lit (DInt n)) i64 loc)))
      (define call
        (lambda (callee args) (Expr (App callee args) (function-result (● callee type)) loc)))
      (define function-result (lambda (type) (match type ((TFun _ result _) result) (_ i64))))
      ;; `f` may yield to Abort; `g` cannot.
      (define f (local "f" (TFun (list i64) i64 abort-row)))
      (define g (local "g" (TFun (list i64) i64 empty-row)))
      (define predicate (local "predicate" (TFun (list) bool abort-row)))
      (define add (local "add" (TFun (list i64 i64) i64 empty-row)))

      ;; Abort is a control effect; Log and Io are not, but Io's fetch names
      ;; Abort in its type.
      (define operation
        (lambda (effect latent) (Operation effect
                                           (Scheme (Nil)
                                                   (Nil)
                                                   (Nil)
                                                   (TFun (list i64)
                                                         i64
                                                         (TRow (Cons effect latent) (None)))))))

      (define program
        (fold-left (lambda (program entry)
                     (program-with-value program (● entry first) (● entry second)))
                   (fold-left program-with-effect empty-program
                              (list (Effect "t:Abort" (list "t:abort") (list "t:abort") (Nil) #f)
                                    (Effect "t:Log" (list "t:log") (Nil) (Nil) #f)
                                    (Effect "t:Io" (list "t:fetch") (Nil) (Nil) #f)))
                   (list (Pair "t:abort" (operation "t:Abort" (Nil)))
                         (Pair "t:log" (operation "t:Log" (Nil)))
                         (Pair "t:fetch" (operation "t:Io" (list "t:Abort"))))))

      (define test-callees
        (lambda (definitions) (let* ((items (map (lambda (name)
                                                   (Define name
                                                     (match (table-ref definitions name)
                                                       ((Some value) value))))
                                                 (table-keys definitions)))
                                     (schemes (fold-left (lambda (schemes item)
                                                           (match item
                                                             ((Define name value)
                                                              (table-set schemes name
                                                                         (Scheme (Nil)
                                                                                 (Nil)
                                                                                 (Nil)
                                                                                 (● value type))))))
                                                         empty-table items))
                                     (state
                                      (new-state
                                       (prepare-specialization (Typed program items schemes))
                                       (Some "t"))))
                                (specialization-callees
                                 (● (complete-specializations
                                     (● (start-specialization state items) second)) second)))))

      (define callees (test-callees empty-table))

      (define normalized (lambda (expr) (shape (● (normal 0 callees expr) first))))

      ;; A readable form of an expression's structure.
      (define shape
        (lambda (expr) (match (● expr term)
                         ((Lit (DInt n)) (i64->string n))
                         ((Var name _ _) name)
                         ((Lambda params body _) (string-append "(lambda " (shape body) ")"))
                         ((App callee args)
                          (string-append "(" (string-join (map shape (Cons callee args)) " ") ")"))
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
                         ((Handle effect _ body)
                          (string-append "(handle " effect " " (shape body) ")"))
                         (_ "?"))))

      (define handle-abort
        (lambda (body) (Expr (Handle "t:Abort"
                                     (list (Pair "t:abort"
                                                 (local "catch" (TFun (list i64) i64 empty-row))))
                                     body)
                             i64
                             loc)))

      ;; A call yields what its callee's row names, a lambda yields nothing
      ;; until called, and a handle keeps what its body yields to other
      ;; effects.
      (define test-yields
        (lambda () (expect (yields callees (call g (list (number 1)))) (Nil))
                (expect (yields callees (call add (list (number 1) (call f (list (number 2))))))
                        (list "t:Abort"))
                (expect
                 (yields callees
                         (Expr (Lambda (list "x") (call f (list (number 1))) #t) (● f type) loc))
                 (Nil))
                (expect (yields callees (handle-abort (call f (list (number 1))))) (Nil))))

      ;; A global's definition says what calling it may yield to, not the
      ;; row the checker opened to its context at the use.
      (define test-globals
        (lambda () (let* ((opened (local "t:pure" (TFun (list i64) i64 abort-row)))
                          (pure
                           (Expr (Lambda (list "x.1") (local "x.1" i64) #t)
                                 (TFun (list i64) i64 empty-row)
                                 loc))
                          (defined (test-callees (table-set empty-table "t:pure" pure))))
                     (expect (yields defined (call opened (list (number 1)))) (Nil))
                     (expect (yields callees (call opened (list (number 1)))) (list "t:Abort")))))

      ;; Operands that run before a call that may yield are named first, so
      ;; they still run first; variables and literals stay where they are,
      ;; and so do operands after it.
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

      ;; A call whose value flows out stays where it is: in tail position,
      ;; in a branch, in a let's value. A test or a sequence's first part
      ;; that may yield is named.
      (define test-flow
        (lambda () (expect (normalized (call f (list (call g (list (number 1)))))) "(f (g 1))")
                (expect (normalized
                         (Expr (If (call predicate (Nil)) (call f (list (number 1))) (number 2))
                               i64
                               loc))
                        "(let %control.0% (predicate) (if %control.0% (f 1) 2))")
                (expect (normalized (Expr (Seq (call f (list (number 1))) (number 2)) i64 loc))
                        "(let %control.0% (f 1) 2)")
                (expect
                 (normalized
                  (Expr (Let "x.1" (call f (list (number 1))) (call g (list (local "x.1" i64))))
                        i64
                        loc))
                 "(let x.1 (f 1) (g x.1))")
                (expect
                 (normalized
                  (Expr (Lambda (list "x.1") (call g (list (call f (list (number 1))))) #t)
                        (● g type)
                        loc))
                 "(lambda (let %control.0% (f 1) (g %control.0%)))")))

      ;; An item without a call that may yield is returned itself.
      (define test-unchanged
        (lambda ()
          (let ((pure (call add (list (call g (list (number 1))) (call g (list (number 2)))))))
            (expect (eq? (● (control-expr 0 callees pure) first) pure) #t))))

      ;; A value holds a yield point when a let inside it, outside its
      ;; lambdas, binds a value that may yield; a call that may yield is not
      ;; one, since the let it is the value of tests it.
      (define test-holds
        (lambda ()
          (let ((inner
                 (Expr (Let "x.1" (call f (list (number 1))) (call g (list (local "x.1" i64))))
                       i64
                       loc)))
            (expect (holds-yield-point? callees inner) #t)
            (expect
             (holds-yield-point? callees (Expr (If (local "c.1" bool) inner (number 2)) i64 loc))
             #t)
            (expect (holds-yield-point? callees (call f (list (number 1)))) #f)
            (expect
             (holds-yield-point? callees (Expr (Lambda (list "y.1") inner #t) (● g type) loc))
             #f))))

      ;; A thunk unsafe-total calls cannot yield, but a lambda whose row
      ;; names Abort and whose body yields nothing can be called anywhere;
      ;; an implementation of an operation without ctl cannot yield.
      (define test-restrictions
        (lambda () (let* ((thunk-type (TFun (list) i64 abort-row))
                          (total (local "prim:unsafe-total" (TFun (list thunk-type) i64 empty-row)))
                          (log (Expr (Lambda (list "m.1") (call f (list (number 1))) #t)
                                     (TFun (list i64) i64 empty-row)
                                     loc)))
                     (expect (refused? (call total (list (local "thunk" thunk-type))))
                             "an unsafe-total thunk cannot reach a control operation")
                     (expect (refused? (call total
                                             (list
                                              (Expr (Lambda (Nil) (number 1) #t) thunk-type loc))))
                             #f)
                     (expect (refused?
                              (Expr (Handle "t:Log" (list (Pair "t:log" log)) (number 1)) i64 loc))
                             "the implementation of log can yield only to the control effects its operation's type names"))))

      ;; A `resume` closed over its handlers in its handle's implementation
      ;; yields to the handle's effect only if an implementation does, as
      ;; one that calls `f` does; outside a handle, it may.
      (define test-resuming
        (lambda () (let* ((resume-type (TFun (list i64) i64 abort-row))
                          (inherit (local "prim:inherit-handlers-1"
                                          (TFun (list resume-type) i64 empty-row)))
                          (implementation-type (TFun (list i64 resume-type) i64 empty-row))
                          (closing (Expr (Lambda (list "v.1" "resume.1")
                                                 (call inherit
                                                       (list (local "resume.1" resume-type)))
                                                 #t)
                                         implementation-type
                                         loc))
                          (forwarding
                           (Expr (Lambda (list "v.2" "resume.2")
                                         (call add
                                               (list (call f (list (number 1)))
                                                     (call inherit
                                                           (list (local "resume.2" resume-type)))))
                                         #t)
                                 implementation-type
                                 loc)))
                     (expect
                      (refused?
                       (Expr (Handle "t:Abort" (list (Pair "t:abort" closing)) (number 1)) i64 loc))
                      #f)
                     (expect
                      (refused?
                       (Expr (Handle "t:Abort" (list (Pair "t:abort" forwarding)) (number 1))
                             i64
                             loc))
                      "a procedure given to inherit-handlers-1 cannot reach a control operation")
                     (expect (refused? (call inherit (list (local "resume.3" resume-type))))
                             "a procedure given to inherit-handlers-1 cannot reach a control operation"))))

      ;; A restriction check takes a global defined by a lambda at its body:
      ;; the handle in `t:caught` catches the Abort its row names, so a thunk
      ;; that calls it may be closed over its handlers, and one that calls
      ;; `f` may not.
      (define test-reading
        (lambda () (let* ((caught-type (TFun (list i64) i64 abort-row))
                          (caught
                           (Expr (Lambda (list "x.2")
                                         (handle-abort (call f (list (local "x.2" i64))))
                                         #t)
                                 caught-type
                                 loc))
                          (reading (test-callees (table-set empty-table "t:caught" caught)))
                          (thunk-type (TFun (Nil) i64 abort-row))
                          (inherit
                           (local "prim:inherit-handlers" (TFun (list thunk-type) i64 empty-row)))
                          (thunk (lambda (body) (Expr (Lambda (Nil) body #t) thunk-type loc))))
                     (expect (refused-in? reading
                                          (call inherit
                                                (list (thunk (call (local "t:caught" caught-type)
                                                                   (list (number 1)))))))
                             #f)
                     (expect
                      (refused-in? reading (call inherit (list (thunk (call f (list (number 1)))))))
                      "a procedure given to inherit-handlers cannot reach a control operation"))))

      ;; Calling an operation whose type names Abort may yield to Abort, and
      ;; its implementation may.
      (define test-latent
        (lambda () (let ((fetch (local "t:fetch" (TFun (list i64) i64 empty-row)))
                         (yielding (Expr (Lambda (list "n.1") (call f (list (number 1))) #t)
                                         (TFun (list i64) i64 abort-row)
                                         loc)))
                     (expect (yields callees (call fetch (list (number 1)))) (list "t:Abort"))
                     (expect
                      (yields callees
                              (call (local "t:log" (TFun (list i64) i64 empty-row))
                                    (list (number 1))))
                      (Nil))
                     (expect
                      (refused?
                       (Expr (Handle "t:Io" (list (Pair "t:fetch" yielding)) (number 1)) i64 loc))
                      #f))))

      ;; The start of the diagnostic `expr` is refused with, or #f.
      (define refused?
        (lambda (expr) (refused-in? callees expr)))

      (define refused-in?
        (lambda (callees expr)
          (let ((message (compile-failure (lambda () (check-restrictions callees expr)))))
            (and message
                 (substring message
                            (+ (string-index-of message ": ") 2)
                            (string-index-of message ";"))))))

      (define string-index-of
        (lambda (text pattern) (let loop ((index 0))
                                 (if
                                  (string=? (substring text index (+ index (string-length pattern)))
                                            pattern)
                                  index
                                  (loop (+ index 1))))))))
   (else)))

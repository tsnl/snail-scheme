;; Preparation closes specialization, checks concrete original bodies, and
;; produces fixed declarations and normalized items.
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
   (only (snail shell compiler check) Typed)
   (snail shell compiler specialize))
  (begin

    ;; ---- Prepared code ----

    ;; Fixed declarations and concrete function bodies consumed by emission.
    (record Prepared
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

    ;; The whole reachable graph is specialized before any original body is
    ;; checked, so each check reads complete callees. Lowering then rewrites
    ;; each body on its own.

    (define (prepare (input Specialization) (owner (Option String)) (items (List Item)))
      (→ Prepared) (! compile)
      (match (start-specialization (new-state input owner) items)
        ((Pair exported state)
         (match (complete-specializations state)
           ((Pair definitions state)
            (let* ((roots (filter (lambda (item) (match item ((Define _ _) #f) (_ #t))) items))
                   (items (append roots definitions))
                   (callees (specialization-callees state)))
              (for-each (lambda (item) (check-item callees item)) items)
              (prepared state (map (lambda (item) (control-item callees item)) items)
                        exported)))))))

    (define (prepared (state State) (items (List Item)) (exported (List String))) (→ Prepared)
      (new Prepared (declarations (specialization-declarations state))
           (definitions (filter (lambda (item) (match item ((Define _ _) #t) (_ #f))) items))
           (entry (match (find (lambda (item) (match item ((Entry _ _) #t) (_ #f))) items)
                    ((Some (Entry name _)) (Some name))
                    (_ (None))))
           (exposed (filter (lambda (item) (match item ((Expose _ _ _) #t) (_ #f))) items))
           (exported exported)))

    ;; ---- Yields ----

    ;; Checks read the original concrete bodies of a closed graph. Emission
    ;; uses the same fixed call contracts with no original bodies attached.
    ;; Reading/resumption assumptions belong to each inspection, not a binding.
    (record Callees
      ((declarations Declarations)
       (definitions (Table Expr))
       (resumes (List (Pair String String)))
       (reading (Option (List String)))))

    (define (specialization-callees (state State)) (→ Callees)
      (new Callees (declarations (specialization-declarations state))
           (definitions (if (null? (● state control))
                            (empty-table)
                            (specialization-definitions state)))
           (resumes (Nil)) (reading (None))))

    (define (declaration-callees (declarations Declarations)) (→ Callees)
      (new Callees
        (declarations declarations)
        (definitions (empty-table))
        (resumes (Nil))
        (reading (None))))

    (define (callees-program (callees Callees)) (→ Program)
      (● (● callees declarations) program))

    (define (callees-control (callees Callees)) (→ (List String))
      (● (● callees declarations) control))

    ;; The control effects a value of a procedure type may yield to when
    ;; called: those its row names.

    (define (call-row (type Type)) (→ (List String))
      (match (fn-arrow type)
        ((TFun _ _ (TRow labels _)) labels)
        (_ (Nil))))

    ;; What calling `callee` may yield to. The checker opens the row of each
    ;; use of a global to its context's, so a global's own definition or
    ;; declaration says instead: a constructor, an accessor or a foreign
    ;; function yields nothing, an operation yields to the control effects
    ;; among its effect and its latent row, which its implementation may
    ;; yield to, and a primitive yields only through a row variable in its
    ;; type. Closing a procedure over its handlers charges its row without
    ;; calling it, so it yields nothing.

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

    ;; A contextual check reads the cached source body. Imported definitions
    ;; and recursive inspection use the declared row.

    (define (definition-row (callees Callees) (name String) (binding Binding)) (→ (List String))
      (let ((row (call-row (● binding type))))
        (match (● callees reading)
          ((Some reading)
           (if (or (● binding external?) (member? name reading))
               row
               (match (table-ref (● callees definitions) name)
                 ((Some (Expr (Lambda _ body ) _ _))
                  (yields (Callees-reading-set callees (Some (Cons name reading))) body))
                 (_ row))))
          ((None) row))))

    (define (declared-row (callees Callees) (name String) (type Type)) (→ (List String))
      (match (program-value (callees-program callees) name)
        ((Some (Operation effect scheme)) (operation-row callees effect scheme))
        ((Some (Primitive scheme))
         (if (or (closed-row? (● scheme type)) (member? name (closing-primitives)))
             (Nil)
             (call-row type)))
        ((Some (Foreign _ _)) (Nil))
        ((Some (Constructor _ _)) (Nil))
        ((Some (Accessor _ _ _)) (Nil))
        ((Some (Replacer _ _ _)) (Nil))
        ((Some (Setter _ _ _)) (Nil))
        (_ (resume-row callees name type))))

    (define (closing-primitives)
      (→ (List String))
      (list "prim:inherit-handlers" "prim:inherit-handlers-1"))

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
          ((Lambda _ _ ) (Nil))
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
    ;; otherwise what calling the procedure may.

    (define (procedure-yields (callees Callees) (procedure Expr)) (→ (List String))
      (match (● procedure term)
        ((Lambda _ body ) (yields callees body))
        ((Ann inner _) (procedure-yields callees inner))
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
        ((Lambda _ _ ) #f)
        ((Let _ value body)
         (or (not (null? (yields callees value))) (holds-yield-point? callees body)))
        (_ (any? (lambda (child) (holds-yield-point? callees child)) (expr-children expr)))))

    ;; ---- Restrictions ----

    ;; A function whose procedure argument runs where no yield test can
    ;; reach: the argument's position, what to call it in a diagnostic, and
    ;; the control effects it may yield to all the same.
    (record Restriction
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

    (define (named-restriction (name String)) (→ (Option Restriction))
      (case name
        (("prim:vector-generate")
         (Some (new Restriction (position 1) (what "a vector-generate callback") (allowed (Nil)))))
        (("prim:string-generate")
         (Some (new Restriction (position 1) (what "a string-generate callback") (allowed (Nil)))))
        (("prim:unsafe-total")
         (Some (new Restriction (position 0) (what "an unsafe-total thunk") (allowed (Nil)))))
        (("prim:cache" "prim:unsafe-effectful-cache")
         (Some (new Restriction (position 0) (what "a cache callback") (allowed (Nil)))))
        (("prim:lru-cache" "prim:unsafe-effectful-lru-cache")
         (Some (new Restriction (position 1) (what "an lru-cache callback") (allowed (Nil)))))
        (("prim:inherit-handlers")
         (Some (new Restriction
                 (position 0)
                 (what "a procedure given to inherit-handlers")
                 (allowed (Nil)))))
        (("prim:inherit-handlers-1")
         (Some (new Restriction
                 (position 0)
                 (what "a procedure given to inherit-handlers-1")
                 (allowed (Nil)))))
        (("snail.shell.task:dispatch-local")
         (Some (new Restriction
                 (position 0)
                 (what "work given to dispatch-local")
                 (allowed (list "snail.shell.task:tasks")))))
        (("snail.shell.task:dispatch-task")
         (Some (new Restriction
                 (position 0)
                 (what "work given to dispatch-task")
                 (allowed (list "snail.shell.task:tasks")))))
        (("snail.shell.async:dispatch")
         (Some (new Restriction
                 (position 0)
                 (what "work given to dispatch")
                 (allowed (list "snail.shell.task:tasks")))))
        (else (None))))

    (define (restriction (callee Expr)) (→ (Option Restriction))
      (match (● callee term)
        ((Ann inner _) (restriction inner))
        ((Var name _ _) (named-restriction (generic-name name)))
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
         (check-cache-primitive callee)
         (match (restriction callee)
           ((Some (Restriction index what allowed))
            (refuse-labels
             (label-difference (procedure-yields (reading callees) (list-ref args index)) allowed)
             what
             (● expr loc)))
           ((None) (check-restrictions callees callee)))
         (for-each (lambda (arg) (check-restrictions callees arg)) args))
        ((Var _ _ _)
         (check-cache-primitive expr)
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

    ;; The wrapper has exactly its callback's signature. Its keys are
    ;; hashed and compared, which a raw Funcref does not support.
    (define (check-cache-primitive (expr Expr)) (→ Unit) (! compile)
      (match (● expr term)
        ((Ann inner _) (check-cache-primitive inner))
        ((Var name _ _)
         (when (member? name (list "prim:cache" "prim:lru-cache"
                                   "prim:unsafe-effectful-cache" "prim:unsafe-effectful-lru-cache"))
           (match (● expr type)
             ((TFun _ (TFun params _ _) _)
              (for-each (lambda (type) (check-cache-key type (● expr loc))) params))
             (_ (compile-error (● expr loc) "cache requires an ordinary Fn function")))))
        (_ (unit))))

    (define (check-cache-key (type Type) (loc Loc)) (→ Unit) (! compile)
      (match type
        ((TCon "Funcref" _) (compile-error loc "cache keys cannot be raw Funcref values"))
        (_ (unit))))

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
                                  ((Lambda params _ )
                                   (match (last params)
                                     ((Some resume)
                                      (list (new Pair (first resume) (second effect))))
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
      (new Expr (term (Var name (Nil) (Nil))) (type (● value type)) (loc (● value loc))))

    (define (bind (name String) (value Expr) (body Expr)) (→ Expr)
      (new Expr (term (Let name value body)) (type (● body type)) (loc (● value loc))))

    ;; `expr` with each call that may yield, and each operand that runs
    ;; before one, named by a let, except where its value flows out of
    ;; `expr`: through a branch, a let's body, the rest of a sequence, a
    ;; clause body or an annotation. A let's value, a handle's body and a
    ;; lambda's body are each a place values flow out of as well.

    (define (normal (count I64) (callees Callees) (expr Expr)) (→ (Pair Expr I64))
      (let ((rebuild
             (lambda (term) (new Expr (term term) (type (● expr type)) (loc (● expr loc))))))
        (match (● expr term)
          ((Lambda params body )
           (naming count ((body (normal callees body)))
                   (new Pair (first (rebuild (Lambda params body ))) (second count))))
          ((App callee args) (normal-call count callees expr callee args))
          ((If test then otherwise)
           (naming count ((test (normal callees test))
                          (then (normal callees then))
                          (otherwise (normal callees otherwise)))
                   (named count callees test (lambda (test) (rebuild (If test then otherwise))))))
          ((Let name value body)
           (naming count ((value (normal callees value))
                          (body (normal callees body)))
                   (new Pair (first (rebuild (Let name value body))) (second count))))
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

          ((FieldRead _ _ _) (panic "internal error: field selection survived checking"))
          ((New _ _) (panic "internal error: named construction survived checking"))
          ((Ann inner type)
           (naming count ((inner (normal callees inner)))
                   (new Pair (first (rebuild (Ann inner type))) (second count))))
          ((BoxAny inner)
           (naming count ((inner (normal callees inner)))
                   (named count callees inner (lambda (inner) (rebuild (BoxAny inner))))))
          ((Downcast inner target)
           (naming count ((inner (normal callees inner)))
                   (named count callees inner (lambda (inner) (rebuild (Downcast inner target))))))
          ((Handle effect implementations body)
           (normal-handle count callees expr effect implementations body))
          (_ (new Pair (first expr) (second count))))))

    (define (normal-all (count I64) (callees Callees) (exprs (List Expr)))
      (→ (Pair (List Expr) I64))
      (match exprs
        ((Cons expr rest)
         (naming count ((expr (normal callees expr))
                        (rest (normal-all callees rest)))
                 (new Pair (first (Cons expr rest)) (second count))))
        ((Nil) (new Pair (first (Nil)) (second count)))))

    (define (normal-clauses (count I64) (callees Callees) (clauses (List Clause)))
      (→ (Pair (List Clause) I64))
      (match clauses
        ((Cons clause rest)
         (naming count ((body (normal callees (● clause body)))
                        (rest (normal-clauses callees rest)))
                 (new Pair
                   (first (Cons (new Clause (pattern (● clause pattern)) (body body)) rest))
                   (second count))))
        ((Nil) (new Pair (first (Nil)) (second count)))))

    ;; `make` applied to `operand`, or, when the operand may yield, to a
    ;; temporary that a let binds to it first.

    (define (named (count I64) (callees Callees) (operand Expr) (make (Fn Expr → Expr)))
      (→ (Pair Expr I64))
      (if (null? (yields callees operand))
          (new Pair (first (make operand)) (second count))
          (let ((name (temporary-name count)))
            (new Pair
              (first (bind name operand (make (temporary name operand))))
              (second (+ count 1))))))

    ;; A sequence whose first part may yield binds it, so the let tests it.

    (define (sequence (count I64) (callees Callees) (expr Expr) (first Expr) (rest Expr))
      (→ (Pair Expr I64))
      (if (null? (yields callees first))
          (new Pair
            (first (new Expr (term (Seq first rest)) (type (● expr type)) (loc (● expr loc))))
            (second count))
          (new Pair (first (bind (temporary-name count) first rest)) (second (+ count 1)))))

    (define (normal-call (count I64) (callees Callees) (expr Expr) (callee Expr) (args (List Expr)))
      (→ (Pair Expr I64))
      (match (new Pair (first (● callee term)) (second args))
        ((Pair (Var "prim:set!" _ _) (Cons place (Cons value (Nil))))
         (normal-write count callees expr callee place value))
        (_ (naming count ((operands (normal-all callees (Cons callee args)))
                          (bound (bind-operands callees operands)))
                   (match (● bound operands)
                     ((Cons callee args)
                      (new Pair (first (wrap-lets bound (applied expr callee args)))
                           (second count)))
                     ((Nil) (panic "internal error: a call without a callee")))))))

    (define (applied (expr Expr) (callee Expr) (args (List Expr))) (→ Expr)
      (new Expr (term (App callee args)) (type (● expr type)) (loc (● expr loc))))

    ;; A write's place stays a field read, which the backend resolves to
    ;; the field it writes, so the operand named is the place's record.

    (define (normal-write (count I64)
                          (callees Callees)
                          (expr Expr)
                          (callee Expr)
                          (place Expr)
                          (value Expr))
      (→ (Pair Expr I64))
      (naming count ((operands (normal-all callees (list (place-record place) value)))
                     (bound (bind-operands callees (Cons callee operands))))
              (match (● bound operands)
                ((Cons callee (Cons record (Cons value (Nil))))
                 (new Pair
                   (first
                    (wrap-lets bound (applied expr callee (list (place-at place record) value))))
                   (second count)))
                (_ (panic "internal error: a write has a place and a value")))))

    (define (place-record (place Expr)) (→ Expr)
      (match (● place term)
        ((Ann inner _) (place-record inner))
        ((App _ (Cons record (Nil))) record)
        (_ (panic "internal error: a place reads a field"))))

    (define (place-at (place Expr) (record Expr)) (→ Expr)
      (let ((rebuild
             (lambda (term) (new Expr (term term) (type (● place type)) (loc (● place loc))))))
        (match (● place term)
          ((Ann inner type) (rebuild (Ann (place-at inner record) type)))
          ((App accessor (Cons _ (Nil))) (rebuild (App accessor (list record))))
          (_ (panic "internal error: a place reads a field")))))

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
                (new Pair (first (wrap-lets bound
                                            (new Expr
                                              (term (Handle effect
                                                            (zip operations (● bound operands))
                                                            body))
                                              (type (● expr type))
                                              (loc (● expr loc)))))
                     (second count)))))

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
    (record Bound
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
         (if (and (<= index final) (or (= index final) (not (inert? operand))))
             (let ((name (temporary-name count)) (next (+ count 1)))
               (naming next ((bound (bind-from callees final (+ index 1) rest)))
                       (new Pair
                         (first (new Bound
                                  (lets
                                   (Cons (new Pair (first name) (second operand)) (● bound lets)))
                                  (operands (Cons (temporary name operand) (● bound operands)))))
                         (second next))))
             (naming count ((bound (bind-from callees final (+ index 1) rest)))
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

    (define (control-item (callees Callees) (item Item)) (→ Item)
      (match item
        ((Define name value) (Define name (● (control-expr 0 callees value) first)))
        (_ item)))

    (define (control-expr (count I64) (callees Callees) (expr Expr)) (→ (Pair Expr I64))
      (if (yield-free? callees expr)
          (new Pair (first expr) (second count))
          (normal count callees expr)))

    (define (check-item (callees Callees) (item Item)) (→ Unit) (! compile)
      (match item
        ((Define _ value) (check-restrictions callees value))
        (_ (unit))))

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

          (define loc (new Loc (file "control") (line 1) (column 1)))

          (define abort-row (TRow (list "t:Abort") (None)))

          (define local
            (lambda (name type) (new Expr (term (Var name (Nil) (Nil))) (type type) (loc loc))))

          (define number (lambda (n) (new Expr (term (Lit (DInt n))) (type i64) (loc loc))))

          (define call
            (lambda (callee args)
              (new Expr
                (term (App callee args))
                (type (function-result (● callee type)))
                (loc loc))))

          (define function-result (lambda (type) (match type ((TFun _ result _) result) (_ i64))))

          (define f (local "f" (TFun (list i64) i64 abort-row)))

          (define g (local "g" (TFun (list i64) i64 (empty-row))))

          (define predicate (local "predicate" (TFun (list) bool abort-row)))

          (define add (local "add" (TFun (list i64 i64) i64 (empty-row))))

          (define operation
            (lambda (effect latent) (Operation effect
                                               (new Scheme (vars (Nil))
                                                    (constraints (Nil))
                                                    (type (TFun (list i64)
                                                                i64
                                                                (TRow (Cons effect latent)
                                                                      (None))))))))

          (define program
            (fold-left (lambda (program entry)
                         (program-with-value program (● entry first) (● entry second)))
                       (fold-left program-with-effect (empty-program)
                                  (list
                                   (new Effect
                                     (name "t:Abort")
                                     (operations (list "t:abort"))
                                     (control (list "t:abort"))
                                     (defaults (Nil))
                                     (around-main #f))
                                   (new Effect
                                     (name "t:Log")
                                     (operations (list "t:log"))
                                     (control (Nil))
                                     (defaults (Nil))
                                     (around-main #f))
                                   (new Effect
                                     (name "t:Io")
                                     (operations (list "t:fetch"))
                                     (control (Nil))
                                     (defaults (Nil))
                                     (around-main #f))))
                       (list (new Pair (first "t:abort") (second (operation "t:Abort" (Nil))))
                             (new Pair (first "t:log") (second (operation "t:Log" (Nil))))
                             (new Pair
                               (first "t:fetch")
                               (second (operation "t:Io" (list "t:Abort")))))))

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
                                                                             (new Scheme
                                                                               (vars (Nil))
                                                                               (constraints (Nil))
                                                                               (type (● value
                                                                                        type)))))))
                                                             (empty-table) items))
                                         (state
                                          (new-state
                                           (prepare-specialization (new Typed
                                                                     (program program)
                                                                     (items items)
                                                                     (schemes schemes)))
                                           (Some "t"))))
                                    (specialization-callees
                                     (● (complete-specializations
                                         (● (start-specialization state items) second)) second)))))

          (define callees (test-callees (empty-table)))

          (define normalized (lambda (expr) (shape (● (normal 0 callees expr) first))))

          (define shape
            (lambda (expr) (match (● expr term)
                             ((Lit (DInt n)) (i64->string n))
                             ((Var name _ _) name)
                             ((Lambda params body ) (string-append "(lambda " (shape body) ")"))
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
                             ((Handle effect _ body)
                              (string-append "(handle " effect " " (shape body) ")"))
                             (_ "?"))))

          (define handle-abort
            (lambda (body) (new Expr (term (Handle "t:Abort"
                                                   (list (new Pair (first "t:abort")
                                                              (second (local "catch"
                                                                             (TFun (list i64)
                                                                                   i64
                                                                                   (empty-row))))))
                                                   body))
                                (type i64)
                                (loc loc))))

          (define test-yields
            (lambda () (expect (yields callees (call g (list (number 1)))) (Nil))
                    (expect (yields callees (call add (list (number 1) (call f (list (number 2))))))
                            (list "t:Abort"))
                    (expect
                     (yields callees
                             (new Expr
                               (term (Lambda (list "x") (call f (list (number 1))) ))
                               (type (● f type))
                               (loc loc)))
                     (Nil))
                    (expect (yields callees (handle-abort (call f (list (number 1))))) (Nil))))

          (define test-globals
            (lambda () (let* ((opened (local "t:pure" (TFun (list i64) i64 abort-row)))
                              (pure
                               (new Expr (term (Lambda (list "x.1") (local "x.1" i64) ))
                                    (type (TFun (list i64) i64 (empty-row)))
                                    (loc loc)))
                              (defined (test-callees (table-set (empty-table) "t:pure" pure))))
                         (expect (yields defined (call opened (list (number 1)))) (Nil))
                         (expect (yields callees (call opened (list (number 1))))
                                 (list "t:Abort")))))

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
                      "(let %control.1% (let %control.0% (f 1) (f %control.0%)) (g %control.1%))")
              (let* ((unit (TCon "Unit" (Nil)))
                     (write (local "prim:set!" (TFun (list i64 i64) unit (empty-row))))
                     (read (local "x" (TFun (list i64) i64 (empty-row))))
                     (record (call g (list (number 1)))))
                (expect (normalized (call write (list (call read (list record))
                                                      (call f (list (number 2))))))
                        "(let %control.0% (g 1) (let %control.1% (f 2) (prim:set! (x %control.0%) %control.1%)))"))))

          (define test-flow
            (lambda () (expect (normalized (call f (list (call g (list (number 1)))))) "(f (g 1))")
                    (expect (normalized
                             (new Expr
                               (term
                                (If (call predicate (Nil)) (call f (list (number 1))) (number 2)))
                               (type i64)
                               (loc loc)))
                            "(let %control.0% (predicate) (if %control.0% (f 1) 2))")
                    (expect (normalized (new Expr
                                          (term (Seq (call f (list (number 1))) (number 2)))
                                          (type i64)
                                          (loc loc)))
                            "(let %control.0% (f 1) 2)")
                    (expect
                     (normalized
                      (new Expr
                        (term
                         (Let "x.1" (call f (list (number 1))) (call g (list (local "x.1" i64)))))
                        (type i64)
                        (loc loc)))
                     "(let x.1 (f 1) (g x.1))")
                    (expect
                     (normalized
                      (new Expr
                        (term (Lambda (list "x.1") (call g (list (call f (list (number 1))))) ))
                        (type (● g type))
                        (loc loc)))
                     "(lambda (let %control.0% (f 1) (g %control.0%)))")))

          (define test-unchanged
            (lambda ()
              (let ((pure (call add (list (call g (list (number 1))) (call g (list (number 2)))))))
                (expect (eq? (● (control-expr 0 callees pure) first) pure) #t))))

          (define test-holds
            (lambda ()
              (let ((inner
                     (new Expr
                       (term
                        (Let "x.1" (call f (list (number 1))) (call g (list (local "x.1" i64)))))
                       (type i64)
                       (loc loc))))
                (expect (holds-yield-point? callees inner) #t)
                (expect
                 (holds-yield-point? callees
                                     (new Expr
                                       (term (If (local "c.1" bool) inner (number 2)))
                                       (type i64)
                                       (loc loc)))
                 #t)
                (expect (holds-yield-point? callees (call f (list (number 1)))) #f)
                (expect
                 (holds-yield-point? callees
                                     (new Expr
                                       (term (Lambda (list "y.1") inner ))
                                       (type (● g type))
                                       (loc loc)))
                 #f))))

          (define test-restrictions
            (lambda () (let* ((thunk-type (TFun (list) i64 abort-row))
                              (total
                               (local "prim:unsafe-total" (TFun (list thunk-type) i64 (empty-row))))
                              (log
                               (new Expr (term (Lambda (list "m.1") (call f (list (number 1))) ))
                                    (type (TFun (list i64) i64 (empty-row)))
                                    (loc loc))))
                         (expect (refused? (call total (list (local "thunk" thunk-type))))
                                 "an unsafe-total thunk cannot reach a control operation")
                         (expect (refused? (call total
                                                 (list
                                                  (new Expr (term (Lambda (Nil) (number 1) ))
                                                       (type thunk-type)
                                                       (loc loc)))))
                                 #f)
                         (expect (refused?
                                  (new Expr
                                    (term (Handle "t:Log"
                                                  (list (new Pair (first "t:log") (second log)))
                                                  (number 1)))
                                    (type i64)
                                    (loc loc)))
                                 "the implementation of log can yield only to the control effects its operation's type names"))))

          (define test-resuming
            (lambda () (let* ((resume-type (TFun (list i64) i64 abort-row))
                              (inherit (local "prim:inherit-handlers-1"
                                              (TFun (list resume-type) i64 (empty-row))))
                              (implementation-type (TFun (list i64 resume-type) i64 (empty-row)))
                              (closing (new Expr (term (Lambda (list "v.1" "resume.1")
                                                               (call inherit
                                                                     (list (local "resume.1"
                                                                                  resume-type)))
                                                               ))
                                            (type implementation-type)
                                            (loc loc)))
                              (forwarding
                               (new Expr (term (Lambda (list "v.2" "resume.2")
                                                       (call add
                                                             (list (call f (list (number 1)))
                                                                   (call inherit
                                                                         (list
                                                                          (local "resume.2"
                                                                                 resume-type)))))
                                                       ))
                                    (type implementation-type)
                                    (loc loc))))
                         (expect
                          (refused?
                           (new Expr
                             (term (Handle "t:Abort"
                                           (list (new Pair (first "t:abort") (second closing)))
                                           (number 1)))
                             (type i64)
                             (loc loc)))
                          #f)
                         (expect
                          (refused?
                           (new Expr
                             (term (Handle "t:Abort"
                                           (list (new Pair (first "t:abort") (second forwarding)))
                                           (number 1)))
                             (type i64)
                             (loc loc)))
                          "a procedure given to inherit-handlers-1 cannot reach a control operation")
                         (expect (refused? (call inherit (list (local "resume.3" resume-type))))
                                 "a procedure given to inherit-handlers-1 cannot reach a control operation"))))

          (define test-reading
            (lambda () (let* ((caught-type (TFun (list i64) i64 abort-row))
                              (caught
                               (new Expr (term (Lambda (list "x.2")
                                                       (handle-abort
                                                        (call f (list (local "x.2" i64))))
                                                       ))
                                    (type caught-type)
                                    (loc loc)))
                              (reading (test-callees (table-set (empty-table) "t:caught" caught)))
                              (thunk-type (TFun (Nil) i64 abort-row))
                              (inherit
                               (local "prim:inherit-handlers"
                                      (TFun (list thunk-type) i64 (empty-row))))
                              (thunk (lambda (body)
                                       (new Expr
                                         (term (Lambda (Nil) body ))
                                         (type thunk-type)
                                         (loc loc)))))
                         (expect (refused-in? reading
                                              (call inherit
                                                    (list
                                                     (thunk (call (local "t:caught" caught-type)
                                                                  (list (number 1)))))))
                                 #f)
                         (expect
                          (refused-in? reading
                                       (call inherit (list (thunk (call f (list (number 1)))))))
                          "a procedure given to inherit-handlers cannot reach a control operation"))))

          (define test-latent
            (lambda () (let ((fetch (local "t:fetch" (TFun (list i64) i64 (empty-row))))
                             (yielding
                              (new Expr (term (Lambda (list "n.1") (call f (list (number 1))) ))
                                   (type (TFun (list i64) i64 abort-row))
                                   (loc loc))))
                         (expect (yields callees (call fetch (list (number 1)))) (list "t:Abort"))
                         (expect
                          (yields callees
                                  (call (local "t:log" (TFun (list i64) i64 (empty-row)))
                                        (list (number 1))))
                          (Nil))
                         (expect
                          (refused?
                           (new Expr
                             (term (Handle "t:Io"
                                           (list (new Pair (first "t:fetch") (second yielding)))
                                           (number 1)))
                             (type i64)
                             (loc loc)))
                          #f))))

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
                                      (string=?
                                       (substring text index (+ index (string-length pattern)))
                                       pattern)
                                      index
                                      (loop (+ index 1))))))
          (test-yields)
          (test-globals)
          (test-operands)
          (test-flow)
          (test-unchanged)
          (test-holds)
          (test-restrictions)
          (test-resuming)
          (test-reading)
          (test-latent)))))
   (else)))

;; Monomorphic program to monomorphic program in which nothing runs after a
;; call that may yield before the backend has tested for the yield. After
;; specialization a row keeps only control effects, so a call may yield
;; exactly when its callee's row names one: a global's as it is defined or
;; declared, a local's as its type says. Such a call stays where it is
;; when its value flows straight out of a function, a handle body or a
;; let's value; anywhere else, a let names it, with the rest of the
;; expression as the let's body, and names first each operand that runs
;; before it, so those still run first. The backend tests for a yield after
;; each let whose value may yield. A program without control effects comes
;; back as it went in, as does each item without a call that may yield.
;;
;; The pass also refuses a control row wherever nothing could carry a
;; yield: in the callbacks that the WAT loops of vector-generate and
;; string-generate call, in an unsafe-total thunk, in a procedure closed
;; over its handlers, in dispatched work but to `tasks`, and in the
;; implementation of an operation declared without ctl.
(define-library (snail shell compiler control)
  (export
   name-yield-points
   Callees
   module-callees
   yields
   holds-yield-point?)
  (import
   (snail core base)
   (snail core table)
   (snail shell compiler read)
   (snail shell compiler core)
   (snail shell compiler mono))
  (begin

    ;; ---- Yields ----

    ;; Where a callee is defined or declared: the program's entities, its
    ;; control effects, and the definitions a module holds and those it
    ;; imports. An import keeps the type it was checked at, whose rows name
    ;; every effect. A restriction check also knows the `resume` parameters
    ;; in scope, each with the effect its handle handles, and reads the
    ;; bodies of the definitions it calls, naming those it is reading.
    (struct Callees
      ((program Program)
       (control (List String))
       (definitions (Table Expr))
       (externals (Table Expr))
       (resumes (List (Pair String String)))
       (reading (Option (List String)))))

    (: module-callees (-> Mono (List String) Callees))
    (define (module-callees mono control)
      (Callees (Mono-program mono)
               control
               (item-definitions (Mono-items mono))
               (Mono-externals mono)
               (Nil)
               (None)))

    ;; The control effects a value of a procedure type may yield to when
    ;; called: those its row names. Calling a `FnOnce` calls the procedure it
    ;; holds.
    (: call-row (-> Type (List String)))
    (define (call-row type)
      (match type
        ((TFun _ _ (TRow labels _)) labels)
        ((TCon "FnOnce" (Cons procedure (Nil))) (call-row procedure))
        (_ (Nil))))

    ;; What calling `callee` may yield to. The checker opens the row of each
    ;; use of a global to its context's, so a global's own definition or
    ;; declaration says instead: a constructor, an accessor or a foreign
    ;; function yields nothing, an operation yields to the control effects
    ;; among its effect and its latent row, which its implementation may
    ;; yield to, and a primitive yields only through a row variable, as
    ;; call-once does through its procedure's. Closing a procedure over its
    ;; handlers charges its row without calling it, so it yields nothing.
    (: callee-row (-> Callees Expr (List String)))
    (define (callee-row callees callee)
      (match (Expr-term callee)
        ((Var name _ _)
         (match (table-ref (Callees-definitions callees) name)
           ((Some definition) (definition-row callees name definition))
           ((None)
            (match (table-ref (Callees-externals callees) name)
              ((Some definition)
               (filter (lambda (label) (member? label (Callees-control callees)))
                       (call-row (Expr-type definition))))
              ((None) (declared-row callees name (Expr-type callee)))))))
        (_ (call-row (Expr-type callee)))))

    ;; What calling a definition may yield to: what its row names, or in a
    ;; restriction check, what the body of its lambda yields to. A row can
    ;; name a control effect the function only passes on from a row
    ;; variable, which a handle in its body catches: (snail shell task)'s
    ;; `start-task` has the row `mut e`, which names `tasks` when its work
    ;; is dispatched inside a task. A definition already being read is
    ;; taken at its row, so recursion ends.
    (: definition-row (-> Callees String Expr (List String)))
    (define (definition-row callees name definition)
      (match (Pair (Callees-reading callees) (Expr-term definition))
        ((Pair (Some reading) (Lambda _ body))
         (if (member? name reading)
             (call-row (Expr-type definition))
             (yields (Callees-reading-set callees (Some (Cons name reading))) body)))
        (_ (call-row (Expr-type definition)))))

    (: declared-row (-> Callees String Type (List String)))
    (define (declared-row callees name type)
      (match (program-value (Callees-program callees) name)
        ((Some (Operation effect scheme)) (operation-row callees effect scheme))
        ((Some (Primitive scheme))
         (if (or (closed-row? (Scheme-type scheme)) (member? name closing-primitives))
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
    (: resume-row (-> Callees String Type (List String)))
    (define (resume-row callees name type)
      (match (assoc-ref (Callees-resumes callees) name)
        ((Some effect) (label-difference (call-row type) (list effect)))
        ((None) (call-row type))))

    (: operation-row (-> Callees String Scheme (List String)))
    (define (operation-row callees effect scheme)
      (filter (lambda (label) (member? label (Callees-control callees)))
              (Cons effect (operation-latent effect scheme))))

    (: closed-row? (-> Type Bool))
    (define (closed-row? type)
      (match type
        ((TFun _ _ (TRow _ (None))) #t)
        (_ #f)))

    ;; The control effects evaluating `expr` may yield to. Making a closure
    ;; yields nothing; its body yields when it is called. A handle catches
    ;; what its body yields to its own effect, and runs its control
    ;; implementations itself, once the body has unwound to it.
    (: yields (-> Callees Expr (List String)))
    (define (yields callees expr)
      (let ((all (lambda (exprs)
                   (fold-left (lambda (labels expr) (label-union labels (yields callees expr)))
                              (Nil)
                              exprs))))
        (match (Expr-term expr)
          ((Lambda _ _) (Nil))
          ((App callee args) (label-union (callee-row callees callee) (all (Cons callee args))))
          ((Handle effect implementations body)
           (label-union (all (map Pair-second implementations))
                        (label-union (label-difference (yields callees body) (list effect))
                                     (control-implementation-yields callees
                                                                    effect
                                                                    implementations))))
          (_ (all (subexpressions expr))))))

    (: control-implementation-yields (-> Callees String (List (Pair String Expr)) (List String)))
    (define (control-implementation-yields callees effect implementations)
      (let ((control (Effect-control (program-effect (Callees-program callees) effect))))
        (fold-left (lambda (labels entry)
                     (if (member? (Pair-first entry) control)
                         (label-union labels (procedure-yields callees (Pair-second entry)))
                         labels))
                   (Nil) implementations)))

    ;; What calling a procedure may yield to: what a lambda's body may, and
    ;; otherwise what calling the procedure may. `(once procedure)` holds
    ;; the procedure it is given.
    (: procedure-yields (-> Callees Expr (List String)))
    (define (procedure-yields callees procedure)
      (match (Expr-term procedure)
        ((Lambda _ body) (yields callees body))
        ((App (Expr (Var "prim:once" _ _) _ _) (Cons held (Nil))) (procedure-yields callees held))
        (_ (callee-row callees procedure))))

    ;; Whether no call anywhere in `expr`, lambda bodies included, may yield.
    (: yield-free? (-> Callees Expr Bool))
    (define (yield-free? callees expr)
      (and (match (Expr-term expr)
             ((App callee _) (null? (callee-row callees callee)))
             (_ #t))
           (every? (lambda (child) (yield-free? callees child)) (subexpressions expr))))

    ;; Whether a let inside `expr`, outside its lambdas, has a value that
    ;; may yield. The backend tests for a yield after such a let and leaves
    ;; while one is set, so a value that holds one is a block it can leave.
    (: holds-yield-point? (-> Callees Expr Bool))
    (define (holds-yield-point? callees expr)
      (match (Expr-term expr)
        ((Lambda _ _) #f)
        ((Let _ value body)
         (or (not (null? (yields callees value))) (holds-yield-point? callees body)))
        (_ (any? (lambda (child) (holds-yield-point? callees child)) (subexpressions expr)))))

    (: subexpressions (-> Expr (List Expr)))
    (define (subexpressions expr)
      (match (Expr-term expr)
        ((Lambda _ body) (list body))
        ((App callee args) (Cons callee args))
        ((If test then otherwise) (list test then otherwise))
        ((Let _ value body) (list value body))
        ((Seq first rest) (list first rest))
        ((Match scrutinee clauses) (Cons scrutinee (map Clause-body clauses)))
        ((Handle _ implementations body) (append (map Pair-second implementations) (list body)))
        ((Ann inner _) (list inner))
        ((Convert inner _) (list inner))
        ((TypeTest inner _) (list inner))
        (_ (Nil))))

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
    (: restrictions (List (Pair String Restriction)))
    (define restrictions
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
                  (Restriction 0 "work given to dispatch-task" (list "snail.shell.task:tasks")))))

    (: restriction (-> Expr (Option Restriction)))
    (define (restriction callee)
      (match (Expr-term callee)
        ((Var name _ _) (assoc-ref restrictions (generic-name name)))
        (_ (None))))

    ;; Mono names a specialization by its definition and the types it is
    ;; at, `name<types>`; a restriction names the definition.
    (: generic-name (-> String String))
    (define (generic-name name)
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
    (: check-restrictions (-> Callees Expr Unit ! compile))
    (define (check-restrictions callees expr)
      (match (Expr-term expr)
        ((App callee args)
         (match (restriction callee)
           ((Some (Restriction index what allowed))
            (refuse-labels
             (label-difference (procedure-yields (reading callees) (list-ref args index)) allowed)
             what
             (Expr-loc expr)))
           ((None) (check-restrictions callees callee)))
         (for-each (lambda (arg) (check-restrictions callees arg)) args))
        ((Var _ _ _)
         (match (restriction expr)
           ((Some (Restriction index what allowed))
            (refuse-labels
             (label-difference (call-row (list-ref (function-params (Expr-type expr)) index))
                               allowed)
             what
             (Expr-loc expr)))
           ((None) (unit))))
        ((Handle effect implementations body)
         (check-implementations callees effect implementations)
         (check-restrictions callees body)
         (let ((inside (resuming callees effect implementations)))
           (for-each (lambda (entry) (check-restrictions inside (Pair-second entry)))
                     implementations)))
        (_ (for-each (lambda (child) (check-restrictions callees child)) (subexpressions expr)))))

    ;; A restriction check reads the bodies of the definitions it reaches.
    (: reading (-> Callees Callees))
    (define (reading callees)
      (match (Callees-reading callees)
        ((Some _) callees)
        ((None) (Callees-reading-set callees (Some (Nil))))))

    ;; Inside its control implementations, a handle's `resume`s yield to its
    ;; effect only if an implementation does, so a scheduler can close a
    ;; resumption over its handlers when its continuation would yield to
    ;; the scheduler's own effect. Whether one does is asked assuming they
    ;; do not; if one does even so, the assumption is dropped.
    (: resuming (-> Callees String (List (Pair String Expr)) Callees))
    (define (resuming callees effect implementations)
      (let ((assumed (Callees-resumes-set callees
                                          (append (resume-names callees effect implementations)
                                                  (Callees-resumes callees)))))
        (if (member? effect (control-implementation-yields assumed effect implementations))
            callees
            assumed)))

    ;; Each control implementation written as a lambda takes its `resume`
    ;; last.
    (: resume-names
       (-> Callees String (List (Pair String Expr)) (List (Pair String String))))
    (define (resume-names callees effect implementations)
      (let ((control (Effect-control (program-effect (Callees-program callees) effect))))
        (concatenate (map (lambda (entry)
                            (if (member? (Pair-first entry) control)
                                (match (Expr-term (Pair-second entry))
                                  ((Lambda params _)
                                   (match (last params)
                                     ((Some resume) (list (Pair resume effect)))
                                     ((None) (Nil))))
                                  (_ (Nil)))
                                (Nil)))
                          implementations))))

    (: check-implementations (-> Callees String (List (Pair String Expr)) Unit ! compile))
    (define (check-implementations callees effect implementations)
      (let ((control (Effect-control (program-effect (Callees-program callees) effect))))
        (for-each (lambda (entry)
                    (unless (member? (Pair-first entry) control)
                      (check-implementation callees (Pair-first entry) (Pair-second entry))))
                  implementations)))

    (: check-implementation (-> Callees String Expr Unit ! compile))
    (define (check-implementation callees operation implementation)
      (match (program-value (Callees-program callees) operation)
        ((Some (Operation effect scheme))
         (let ((labels (label-difference (procedure-yields callees implementation)
                                         (operation-latent effect scheme))))
           (unless (null? labels)
             (compile-error (Expr-loc implementation)
                            (string-append "the implementation of " (short-name operation)
                                           " can yield only to the control effects its operation's type names; it may yield to"
                                           (labels->string labels))))))
        (_ (panic "internal error: not an operation"))))

    (: refuse-labels (-> (List String) String Loc Unit ! compile))
    (define (refuse-labels labels what loc)
      (unless (null? labels)
        (compile-error loc
                       (string-append what
                                      " cannot reach a control operation; it may yield to"
                                      (labels->string labels)))))

    (: function-params (-> Type (List Type)))
    (define (function-params type)
      (match type
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
    (: temporary-name (-> I64 String))
    (define (temporary-name count)
      (string-append "%control." (i64->string count) "%"))

    (: temporary (-> String Expr Expr))
    (define (temporary name value)
      (Expr (Var name (Nil) (Nil)) (Expr-type value) (Expr-loc value)))

    (: bind (-> String Expr Expr Expr))
    (define (bind name value body)
      (Expr (Let name value body) (Expr-type body) (Expr-loc value)))

    ;; `expr` with each call that may yield, and each operand that runs
    ;; before one, named by a let, except where its value flows out of
    ;; `expr`: through a branch, a let's body, the rest of a sequence, a
    ;; clause body or an annotation. A let's value, a handle's body and a
    ;; lambda's body are each a place values flow out of as well.
    (: normal (-> I64 Callees Expr (Pair Expr I64)))
    (define (normal count callees expr)
      (let ((rebuild (lambda (term) (Expr term (Expr-type expr) (Expr-loc expr)))))
        (match (Expr-term expr)
          ((Lambda params body)
           (naming count ((body (normal callees body)))
                   (Pair (rebuild (Lambda params body)) count)))
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

    (: normal-all (-> I64 Callees (List Expr) (Pair (List Expr) I64)))
    (define (normal-all count callees exprs)
      (match exprs
        ((Cons expr rest)
         (naming count ((expr (normal callees expr))
                        (rest (normal-all callees rest)))
                 (Pair (Cons expr rest) count)))
        ((Nil) (Pair (Nil) count))))

    (: normal-clauses (-> I64 Callees (List Clause) (Pair (List Clause) I64)))
    (define (normal-clauses count callees clauses)
      (match clauses
        ((Cons clause rest)
         (naming count ((body (normal callees (Clause-body clause)))
                        (rest (normal-clauses callees rest)))
                 (Pair (Cons (Clause (Clause-pattern clause) body) rest) count)))
        ((Nil) (Pair (Nil) count))))

    ;; `make` applied to `operand`, or, when the operand may yield, to a
    ;; temporary that a let binds to it first.
    (: named (-> I64 Callees Expr (-> Expr Expr) (Pair Expr I64)))
    (define (named count callees operand make)
      (if (null? (yields callees operand))
          (Pair (make operand) count)
          (let ((name (temporary-name count)))
            (Pair (bind name operand (make (temporary name operand))) (+ count 1)))))

    ;; A sequence whose first part may yield binds it, so the let tests it.
    (: sequence (-> I64 Callees Expr Expr Expr (Pair Expr I64)))
    (define (sequence count callees expr first rest)
      (if (null? (yields callees first))
          (Pair (Expr (Seq first rest) (Expr-type expr) (Expr-loc expr)) count)
          (Pair (bind (temporary-name count) first rest) (+ count 1))))

    (: normal-call (-> I64 Callees Expr Expr (List Expr) (Pair Expr I64)))
    (define (normal-call count callees expr callee args)
      (naming count ((operands (normal-all callees (Cons callee args)))
                     (bound (bind-operands callees operands)))
              (match (Bound-operands bound)
                ((Cons callee args)
                 (Pair (wrap-lets bound (Expr (App callee args) (Expr-type expr) (Expr-loc expr)))
                       count))
                ((Nil) (panic "internal error: a call without a callee")))))

    ;; A handle evaluates its implementations in its effect's operation
    ;; order, before its body runs.
    (: normal-handle (-> I64 Callees Expr String (List (Pair String Expr)) Expr (Pair Expr I64)))
    (define (normal-handle count callees expr effect implementations body)
      (let* ((operations (Effect-operations (program-effect (Callees-program callees) effect)))
             (values
              (map (lambda (operation) (implementation-of implementations operation)) operations)))
        (naming count ((values (normal-all callees values))
                       (bound (bind-operands callees values))
                       (body (normal callees body)))
                (Pair (wrap-lets bound
                                 (Expr (Handle effect (zip operations (Bound-operands bound)) body)
                                       (Expr-type expr)
                                       (Expr-loc expr)))
                      count))))

    (: implementation-of (-> (List (Pair String Expr)) String Expr))
    (define (implementation-of implementations operation)
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

    (: wrap-lets (-> Bound Expr Expr))
    (define (wrap-lets bound body)
      (fold-right (lambda (entry body) (bind (Pair-first entry) (Pair-second entry) body))
                  body
                  (Bound-lets bound)))

    (: bind-operands (-> I64 Callees (List Expr) (Pair Bound I64)))
    (define (bind-operands count callees operands)
      (let ((final (fold-left (lambda (final entry)
                                (if (null? (yields callees (Pair-second entry)))
                                    final
                                    (Pair-first entry)))
                              -1 (zip (iota (length operands)) operands))))
        (bind-from count final 0 operands)))

    (: bind-from (-> I64 I64 I64 (List Expr) (Pair Bound I64)))
    (define (bind-from count final index operands)
      (match operands
        ((Cons operand rest)
         (if (and (<= index final) (or (= index final) (not (inert? operand))))
             (let ((name (temporary-name count)) (next (+ count 1)))
               (naming next ((bound (bind-from final (+ index 1) rest)))
                       (Pair (Bound (Cons (Pair name operand) (Bound-lets bound))
                                    (Cons (temporary name operand) (Bound-operands bound)))
                             next)))
             (naming count ((bound (bind-from final (+ index 1) rest)))
                     (Pair (Bound (Bound-lets bound) (Cons operand (Bound-operands bound)))
                           count))))
        ((Nil) (Pair (Bound (Nil) (Nil)) count))))

    ;; Evaluating a literal, a variable or a lambda has no effect a yield
    ;; could reorder. Reading an owned variable moves it out of its owner,
    ;; and left in place it is read after the operand that yields. On that
    ;; path the frame moves the value into itself first, and the resumed
    ;; frame reads it from there, so the call still receives the value.
    (: inert? (-> Expr Bool))
    (define (inert? expr)
      (match (Expr-term expr)
        ((Lit _) #t)
        ((Var _ _ _) #t)
        ((Lambda _ _) #t)
        (_ #f)))

    ;; ---- Exposures ----

    ;; An exposed function is exported through a wrapper that calls its code
    ;; directly, so the definition the checker found, this library's or an
    ;; imported one, must have a lambda as its value. Only here, after
    ;; specialization, is an imported definition's value at hand.
    (: check-exposures (-> Mono Unit ! compile))
    (define (check-exposures mono)
      (let ((callees (module-callees mono (Nil))))
        (for-each (lambda (item)
                    (match item
                      ((Expose name _ _ loc) (check-exposure callees name loc))
                      (_ (unit))))
                  (Mono-items mono))))

    (: check-exposure (-> Callees String Loc Unit ! compile))
    (define (check-exposure callees name loc)
      (match (callee-definition callees name)
        ((Some definition)
         (unless (lambda-expr? definition)
           (compile-error loc "an exposed function must be defined with lambda")))
        ((None) (panic "internal error: an exposed function has no definition"))))

    ;; A global's definition, in this library or another, as the backend
    ;; finds it.
    (: callee-definition (-> Callees String (Option Expr)))
    (define (callee-definition callees name)
      (match (table-ref (Callees-definitions callees) name)
        ((Some definition) (Some definition))
        ((None) (table-ref (Callees-externals callees) name))))

    ;; ---- Programs ----

    ;; Each item with its yield points named, after the restrictions are
    ;; checked everywhere. Every program passes through here, so the one
    ;; rule the backend relies on that needs specialized definitions is
    ;; checked here too, and the backend reports no source errors.
    (: name-yield-points (-> Mono Mono ! compile))
    (define (name-yield-points mono)
      (check-exposures mono)
      (let ((control (control-effects (Mono-program mono))))
        (if (null? control)
            mono
            (let ((callees (module-callees mono control)))
              (check-items callees (Mono-items mono))
              (Mono (Mono-program mono)
                    (control-items 0 callees (Mono-items mono))
                    (Mono-externals mono)
                    (Mono-exported mono))))))

    ;; Temporaries are numbered within the Wasm function they land in: a
    ;; function's definition counts from zero, while the statements and the
    ;; other definitions' values all run in `main`, and share one count.
    (: control-items (-> I64 Callees (List Item) (List Item)))
    (define (control-items count callees items)
      (match items
        ((Cons item rest)
         (naming count ((item (control-item callees item)))
                 (Cons item (control-items count callees rest))))
        ((Nil) (Nil))))

    (: control-item (-> I64 Callees Item (Pair Item I64)))
    (define (control-item count callees item)
      (match item
        ((Define name value)
         (if (lambda-expr? value)
             (Pair (Define name (Pair-first (control-expr 0 callees value))) count)
             (naming count ((value (control-expr callees value)))
                     (Pair (Define name value) count))))
        ((Do expr) (naming count ((expr (control-expr callees expr))) (Pair (Do expr) count)))
        (_ (Pair item count))))

    (: control-expr (-> I64 Callees Expr (Pair Expr I64)))
    (define (control-expr count callees expr)
      (if (yield-free? callees expr) (Pair expr count) (normal count callees expr)))

    ;; Restrictions are checked from the last item back. A copy of a
    ;; generic comes before the code that made it, in a library's build,
    ;; where mono puts the copies of other libraries' generics first, and
    ;; in a whole program's, where each takes its generic's place, so a
    ;; refusal names the use rather than the copy: work that yields to
    ;; Abort is refused where it is dispatched, not in (snail shell task).
    (: check-items (-> Callees (List Item) Unit ! compile))
    (define (check-items callees items)
      (for-each (lambda (item) (check-item callees item)) (reverse items)))

    (: check-item (-> Callees Item Unit ! compile))
    (define (check-item callees item)
      (match item
        ((Define _ value) (check-restrictions callees value))
        ((Do expr) (check-restrictions callees expr))
        (_ (unit))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export test-control)
    (import
     (only (scheme base) eq?)
     (snail stage0 testing))
    (begin
      (define (test-control)
        (test-yields)
        (test-globals)
        (test-operands)
        (test-flow)
        (test-unchanged)
        (test-holds)
        (test-restrictions)
        (test-resuming)
        (test-reading)
        (test-latent))

      (define i64 (TCon "I64" (Nil)))
      (define bool (TCon "Bool" (Nil)))
      (define loc (Loc "control" 1 1))
      (define abort-row (TRow (list "t:Abort") (None)))
      (define (local name type) (Expr (Var name (Nil) (Nil)) type loc))
      (define (number n) (Expr (Lit (DInt n)) i64 loc))
      (define (call callee args) (Expr (App callee args) (function-result (Expr-type callee)) loc))
      (define (function-result type) (match type ((TFun _ result _) result) (_ i64)))
      ;; `f` may yield to Abort; `g` cannot.
      (define f (local "f" (TFun (list i64) i64 abort-row)))
      (define g (local "g" (TFun (list i64) i64 empty-row)))
      (define predicate (local "predicate" (TFun (list) bool abort-row)))
      (define add (local "add" (TFun (list i64 i64) i64 empty-row)))

      ;; Abort is a control effect; Log and Io are not, but Io's fetch names
      ;; Abort in its type.
      (define (operation effect latent)
        (Operation effect
                   (Scheme (Nil)
                           (Nil)
                           (Nil)
                           (TFun (list i64) i64 (TRow (Cons effect latent) (None))))))

      (define program
        (fold-left (lambda (program entry)
                     (program-with-value program (Pair-first entry) (Pair-second entry)))
                   (fold-left program-with-effect empty-program
                              (list (Effect "t:Abort" (list "t:abort") (list "t:abort") (Nil))
                                    (Effect "t:Log" (list "t:log") (Nil) (Nil))
                                    (Effect "t:Io" (list "t:fetch") (Nil) (Nil))))
                   (list (Pair "t:abort" (operation "t:Abort" (Nil)))
                         (Pair "t:log" (operation "t:Log" (Nil)))
                         (Pair "t:fetch" (operation "t:Io" (list "t:Abort"))))))

      (define callees (Callees program (list "t:Abort") empty-table empty-table (Nil) (None)))

      (define (normalized expr) (shape (Pair-first (normal 0 callees expr))))

      ;; A readable form of an expression's structure.
      (define (shape expr)
        (match (Expr-term expr)
          ((Lit (DInt n)) (i64->string n))
          ((Var name _ _) name)
          ((Lambda params body) (string-append "(lambda " (shape body) ")"))
          ((App callee args)
           (string-append "(" (string-join (map shape (Cons callee args)) " ") ")"))
          ((If test then otherwise)
           (string-append "(if " (shape test) " " (shape then) " " (shape otherwise) ")"))
          ((Let name value body)
           (string-append "(let " name " " (shape value) " " (shape body) ")"))
          ((Seq first rest) (string-append "(begin " (shape first) " " (shape rest) ")"))
          ((Handle effect _ body) (string-append "(handle " effect " " (shape body) ")"))
          (_ "?")))

      (define (handle-abort body)
        (Expr (Handle "t:Abort"
                      (list (Pair "t:abort" (local "catch" (TFun (list i64) i64 empty-row))))
                      body)
              i64
              loc))

      ;; A call yields what its callee's row names, a lambda yields nothing
      ;; until called, and a handle keeps what its body yields to other
      ;; effects.
      (define (test-yields)
        (expect (yields callees (call g (list (number 1)))) (Nil))
        (expect (yields callees (call add (list (number 1) (call f (list (number 2))))))
                (list "t:Abort"))
        (expect
         (yields callees (Expr (Lambda (list "x") (call f (list (number 1)))) (Expr-type f) loc))
         (Nil))
        (expect (yields callees (handle-abort (call f (list (number 1))))) (Nil)))

      ;; A global's definition says what calling it may yield to, not the
      ;; row the checker opened to its context at the use.
      (define (test-globals)
        (let* ((opened (local "t:pure" (TFun (list i64) i64 abort-row)))
               (pure
                (Expr (Lambda (list "x.1") (local "x.1" i64)) (TFun (list i64) i64 empty-row) loc))
               (defined (Callees program
                                 (list "t:Abort")
                                 (table-set empty-table "t:pure" pure)
                                 empty-table
                                 (Nil)
                                 (None))))
          (expect (yields defined (call opened (list (number 1)))) (Nil))
          (expect (yields callees (call opened (list (number 1)))) (list "t:Abort"))))

      ;; Operands that run before a call that may yield are named first, so
      ;; they still run first; variables and literals stay where they are,
      ;; and so do operands after it.
      (define (test-operands)
        (expect (normalized (call add (list (call g (list (number 1))) (call f (list (number 2))))))
                "(let %control.0% (g 1) (let %control.1% (f 2) (add %control.0% %control.1%)))")
        (expect (normalized (call add (list (number 1) (call f (list (number 2))))))
                "(let %control.0% (f 2) (add 1 %control.0%))")
        (expect (normalized (call add (list (call f (list (number 1))) (call g (list (number 2))))))
                "(let %control.0% (f 1) (add %control.0% (g 2)))")
        (expect (normalized (call g (list (call f (list (call f (list (number 1))))))))
                "(let %control.1% (let %control.0% (f 1) (f %control.0%)) (g %control.1%))"))

      ;; A call whose value flows out stays where it is: in tail position,
      ;; in a branch, in a let's value. A test or a sequence's first part
      ;; that may yield is named.
      (define (test-flow)
        (expect (normalized (call f (list (call g (list (number 1)))))) "(f (g 1))")
        (expect (normalized
                 (Expr (If (call predicate (Nil)) (call f (list (number 1))) (number 2)) i64 loc))
                "(let %control.0% (predicate) (if %control.0% (f 1) 2))")
        (expect (normalized (Expr (Seq (call f (list (number 1))) (number 2)) i64 loc))
                "(let %control.0% (f 1) 2)")
        (expect
         (normalized (Expr (Let "x.1" (call f (list (number 1))) (call g (list (local "x.1" i64))))
                           i64
                           loc))
         "(let x.1 (f 1) (g x.1))")
        (expect (normalized (Expr (Lambda (list "x.1") (call g (list (call f (list (number 1))))))
                                  (Expr-type g)
                                  loc))
                "(lambda (let %control.0% (f 1) (g %control.0%)))"))

      ;; An item without a call that may yield is returned itself.
      (define (test-unchanged)
        (let ((pure (call add (list (call g (list (number 1))) (call g (list (number 2)))))))
          (expect (eq? (Pair-first (control-expr 0 callees pure)) pure) #t)))

      ;; A value holds a yield point when a let inside it, outside its
      ;; lambdas, binds a value that may yield; a call that may yield is not
      ;; one, since the let it is the value of tests it.
      (define (test-holds)
        (let ((inner (Expr (Let "x.1" (call f (list (number 1))) (call g (list (local "x.1" i64))))
                           i64
                           loc)))
          (expect (holds-yield-point? callees inner) #t)
          (expect
           (holds-yield-point? callees (Expr (If (local "c.1" bool) inner (number 2)) i64 loc))
           #t)
          (expect (holds-yield-point? callees (call f (list (number 1)))) #f)
          (expect (holds-yield-point? callees (Expr (Lambda (list "y.1") inner) (Expr-type g) loc))
                  #f)))

      ;; A thunk unsafe-total calls cannot yield, but a lambda whose row
      ;; names Abort and whose body yields nothing can be called anywhere;
      ;; an implementation of an operation without ctl cannot yield.
      (define (test-restrictions)
        (let* ((thunk-type (TFun (list) i64 abort-row))
               (total (local "prim:unsafe-total" (TFun (list thunk-type) i64 empty-row)))
               (log (Expr (Lambda (list "m.1") (call f (list (number 1))))
                          (TFun (list i64) i64 empty-row)
                          loc)))
          (expect (refused? (call total (list (local "thunk" thunk-type))))
                  "an unsafe-total thunk cannot reach a control operation")
          (expect (refused? (call total (list (Expr (Lambda (Nil) (number 1)) thunk-type loc)))) #f)
          (expect (refused? (Expr (Handle "t:Log" (list (Pair "t:log" log)) (number 1)) i64 loc))
                  "the implementation of log can yield only to the control effects its operation's type names")))

      ;; A `resume` closed over its handlers in its handle's implementation
      ;; yields to the handle's effect only if an implementation does, as
      ;; one that calls `f` does; outside a handle, it may.
      (define (test-resuming)
        (let* ((resume-type (TFun (list i64) i64 abort-row))
               (inherit (local "prim:inherit-handlers-1" (TFun (list resume-type) i64 empty-row)))
               (implementation-type (TFun (list i64 resume-type) i64 empty-row))
               (closing (Expr (Lambda (list "v.1" "resume.1")
                                      (call inherit (list (local "resume.1" resume-type))))
                              implementation-type
                              loc))
               (forwarding
                (Expr (Lambda (list "v.2" "resume.2")
                              (call add
                                    (list (call f (list (number 1)))
                                          (call inherit (list (local "resume.2" resume-type))))))
                      implementation-type
                      loc)))
          (expect
           (refused? (Expr (Handle "t:Abort" (list (Pair "t:abort" closing)) (number 1)) i64 loc))
           #f)
          (expect
           (refused?
            (Expr (Handle "t:Abort" (list (Pair "t:abort" forwarding)) (number 1)) i64 loc))
           "a procedure given to inherit-handlers-1 cannot reach a control operation")
          (expect (refused? (call inherit (list (local "resume.3" resume-type))))
                  "a procedure given to inherit-handlers-1 cannot reach a control operation")))

      ;; A restriction check takes a global defined by a lambda at its body:
      ;; the handle in `t:caught` catches the Abort its row names, so a thunk
      ;; that calls it may be closed over its handlers, and one that calls
      ;; `f` may not.
      (define (test-reading)
        (let* ((caught-type (TFun (list i64) i64 abort-row))
               (caught (Expr (Lambda (list "x.2") (handle-abort (call f (list (local "x.2" i64)))))
                             caught-type
                             loc))
               (reading (Callees program
                                 (list "t:Abort")
                                 (table-set empty-table "t:caught" caught)
                                 empty-table
                                 (Nil)
                                 (None)))
               (thunk-type (TFun (Nil) i64 abort-row))
               (inherit (local "prim:inherit-handlers" (TFun (list thunk-type) i64 empty-row)))
               (thunk (lambda (body) (Expr (Lambda (Nil) body) thunk-type loc))))
          (expect (refused-in? reading
                               (call inherit
                                     (list (thunk (call (local "t:caught" caught-type)
                                                        (list (number 1)))))))
                  #f)
          (expect (refused-in? reading (call inherit (list (thunk (call f (list (number 1)))))))
                  "a procedure given to inherit-handlers cannot reach a control operation")))

      ;; Calling an operation whose type names Abort may yield to Abort, and
      ;; its implementation may.
      (define (test-latent)
        (let ((fetch (local "t:fetch" (TFun (list i64) i64 empty-row)))
              (yielding (Expr (Lambda (list "n.1") (call f (list (number 1))))
                              (TFun (list i64) i64 abort-row)
                              loc)))
          (expect (yields callees (call fetch (list (number 1)))) (list "t:Abort"))
          (expect
           (yields callees (call (local "t:log" (TFun (list i64) i64 empty-row)) (list (number 1))))
           (Nil))
          (expect
           (refused? (Expr (Handle "t:Io" (list (Pair "t:fetch" yielding)) (number 1)) i64 loc))
           #f)))

      ;; The start of the diagnostic `expr` is refused with, or #f.
      (define (refused? expr)
        (refused-in? callees expr))

      (define (refused-in? callees expr)
        (let ((message (compile-failure (lambda () (check-restrictions callees expr)))))
          (and message
               (substring message
                          (+ (string-index-of message ": ") 2)
                          (string-index-of message ";")))))

      (define (string-index-of text pattern)
        (let loop ((index 0))
          (if (string=? (substring text index (+ index (string-length pattern))) pattern)
              index
              (loop (+ index 1)))))))
   (else)))

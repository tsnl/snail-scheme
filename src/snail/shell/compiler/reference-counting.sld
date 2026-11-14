;; Concrete shared ownership. Every expression produces an owned result;
;; locals keep their own reference until their scope exits. Reads retain,
;; calls transfer arguments, and releases become visible before control
;; lowering decides which owners a suspended frame must carry.
(define-library (snail shell compiler reference-counting)
  (export lower-reference-counting)
  (import
   (snail core base)
   (snail core table)
   (snail shell compiler read)
   (snail shell compiler core)
   (snail shell compiler capabilities)
   (snail shell compiler ownership)
   (snail shell compiler specialize))
  (begin

    ;; ---- Concrete ownership ----

    (record Counting
      ((program Program)
       (globals (Table Binding))
       (shared (Table Bool))
       (next I64)))

    (define-syntax lowering
      (syntax-rules ()
        ((_ state () body ...) (begin body ...))
        ((_ state ((name (f arg ...)) step ...) body ...)
         (match (f state arg ...)
           ((Pair name state) (lowering state (step ...) body ...))))))

    (define (shared? (state Counting) (type Type)) (→ Bool)
      (match type
        ((TFun _ _ _) #t)
        ((TCon "Rc" _) #t)
        ((TCon "WeakRc" _) #f)
        (_ (match (table-ref (● state shared) (type-key type))
             ((Some answer) answer)
             ((None) (shared-type? (● state program) type))))))

    (define (known-types (program Program) (table (Table Bool)) (expr Expr)) (→ (Table Bool))
      (let* ((type (● expr type)) (key (type-key type))
             (table (if (table-contains? table key) table
                        (table-set table key (shared-type? program type)))))
        (fold-left (lambda (table child) (known-types program table child))
                   table
                   (expr-children expr))))

    (define (global? (state Counting) (name String)) (→ Bool)
      (or (table-contains? (● state globals) name)
          (match (program-value (● state program) name) ((Some _) #t) ((None) #f))))

    (define (fresh (state Counting) (type Type) (loc Loc)) (→ (Pair Expr Counting))
      (new Pair (first (local (string-append "%counting." (i64->string (● state next))) type loc))
           (second (Counting-next-set state (+ (● state next) 1)))))

    (define (local (name String) (type Type) (loc Loc)) (→ Expr)
      (new Expr (term (Var name (Nil) (Nil))) (type type) (loc loc)))

    (define (name-of (expr Expr)) (→ String)
      (match (● expr term) ((Var name _ _) name) (_ (panic "internal error: expected a local"))))

    (define (bind (name Expr) (value Expr) (body Expr)) (→ Expr)
      (new Expr (term (Let (name-of name) value body)) (type (● body type)) (loc (● value loc))))

    (define (intrinsic (name String) (args (List Expr)) (type Type) (loc Loc)) (→ Expr)
      (new Expr
        (term
         (App (local name (TFun (map (lambda (arg) (● arg type)) args) type (empty-row)) loc) args))
        (type type)
        (loc loc)))

    (define (retained (state Counting) (value Expr)) (→ Expr)
      (if (shared? state (● value type))
          (intrinsic "prim:retain" (list value) (● value type) (● value loc)) value))

    (define (release (value Expr)) (→ Expr)
      (intrinsic "prim:release" (list value) (TCon "Unit" (Nil)) (● value loc)))

    (define (releasing (values (List Expr)) (body Expr)) (→ Expr)
      (fold-right
       (lambda (value body)
         (new Expr (term (Seq (release value) body)) (type (● body type)) (loc (● value loc))))
       body values))

    ;; ---- Expressions ----

    ;; A batch of definitions shares one table of which of its types are
    ;; counted: the answers depend only on the program's types, and the
    ;; same few generic instances recur in every definition.

    (define (lower-reference-counting (declarations Declarations) (items (List Item)))
      (→ (List Item))
      (let ((known (fold-left (lambda (known item)
                                (match item
                                  ((Define _ value)
                                   (known-types (● declarations program) known value))
                                  (_ known)))
                              (empty-table)
                              items)))
        (map (lambda (item) (lower-definition declarations known item)) items)))

    (define (lower-definition (declarations Declarations) (known (Table Bool)) (item Item))
      (→ Item)
      (match item
        ((Define name value)
         (let ((state (new Counting
                        (program (● declarations program))
                        (globals (● declarations bindings))
                        (shared known)
                        (next 0))))
           (Define name (● (lower-function state value #t) first))))
        (_ item)))

    ;; Pending releases follow result positions in the original tree. Operands
    ;; start with no pending releases; their surrounding expression owns the
    ;; result. A handler is a boundary, so its caller's releases stay outside.
    (define (lower (state Counting) (expr Expr)) (→ (Pair Expr Counting))
      (lower-exit state expr (Nil) #f))

    (define (lower-exit (state Counting) (expr Expr) (owners (List Expr)) (tail? Bool))
      (→ (Pair Expr Counting))
      (let ((rebuild
             (lambda (term) (new Expr (term term) (type (● expr type)) (loc (● expr loc))))))
        (match (● expr term)
          ((Let name value body)
           (lowering state
                     ((value (lower value))
                      (body (lower-exit body
                                        (append
                                         (owned-local state name (● value type) (● value loc))
                                         owners) tail?)))
                     (new Pair (first (rebuild (Let name value body))) (second state))))
          ((Seq first rest)
           (lowering state ((first (lower first)) (rest (lower-exit rest owners tail?)))
                     (new Pair
                       (first
                        (rebuild (Seq (if (shared? state (● first type)) (release first) first)
                                      rest))) (second state))))
          ((If test yes no)
           (lowering state ((test (lower test)) (yes (lower-exit yes owners tail?))
                            (no (lower-exit no owners tail?)))
                     (new Pair (first (rebuild (If test yes no))) (second state))))
          ((Match value clauses) (lower-match state expr value clauses owners tail?))
          (_ (lowering state ((value (lower-value expr)))
                       (finish-exit state value owners
                                    (and tail? (match (● expr term)
                                                 ((App callee _)
                                                  (ordinary-call? (● state program) callee))
                                                 (_ #f)))))))))

    (define (lower-value (state Counting) (expr Expr)) (→ (Pair Expr Counting))
      (let ((rebuild
             (lambda (term) (new Expr (term term) (type (● expr type)) (loc (● expr loc))))))
        (match (● expr term)
          ((Var name _ _)
           (new Pair (first (if (global? state name) expr (retained state expr))) (second state)))
          ((Lambda _ _ ) (lower-function state expr #f))
          ((App callee args) (lower-call state expr callee args))
          ((Ann inner type)
           (lowering state
                     ((inner (lower inner)))
                     (new Pair (first (rebuild (Ann inner type))) (second state))))
          ((BoxAny inner)
           (lowering state
                     ((inner (lower inner)))
                     (new Pair (first (rebuild (BoxAny inner))) (second state))))
          ((Downcast inner type)
           (lowering state ((inner (lower inner)))
                     (new Pair (first (rebuild (Downcast inner type))) (second state))))
          ((Handle effect implementations body)
           (lowering state
                     ((values (lower-all (map (lambda (entry) (● entry second)) implementations)))
                      (body (lower body)))
                     (new Pair (first (rebuild (Handle effect
                                                       (zip
                                                        (map (lambda (entry) (● entry first))
                                                             implementations)
                                                        values) body))) (second state))))
          (_ (new Pair (first expr) (second state))))))

    (define (owned-local (state Counting) (name String) (type Type) (loc Loc)) (→ (List Expr))
      (if (shared? state type) (list (local name type loc)) (Nil)))

    (define (lower-all (state Counting) (values (List Expr))) (→ (Pair (List Expr) Counting))
      (match values
        ((Nil) (new Pair (first (Nil)) (second state)))
        ((Cons first rest)
         (lowering state ((first (lower first)) (rest (lower-all rest)))
                   (new Pair (first (Cons first rest)) (second state))))))

    ;; A closure activation owns the incoming closure reference. Its fields
    ;; are observed through that owner; reads of a shared capture retain as
    ;; usual. A direct top-level function has no closure argument.
    (define (lower-function (state Counting) (expr Expr) (top? Bool)) (→ (Pair Expr Counting))
      (match (new Pair (first (● expr term)) (second (fn-arrow (● expr type))))
        ((Pair (Lambda params body ) (TFun types _ _))
         (let ((owners (reverse (concatenate
                                 (map (lambda (pair)
                                        (owned-local state
                                                     (● pair first)
                                                     (● pair second)
                                                     (● expr loc)))
                                      (zip params types)))))
               (closure? (not top?)))
           (if closure?
               (lowering state ((self (fresh (fn-arrow (● expr type)) (● expr loc)))
                                (body (lower-exit body (append owners (list self)) #t)))
                         (new Pair (first (new Expr (term (Lambda params
                                                                  (bind self
                                                                        (intrinsic
                                                                         "prim:current-closure"
                                                                         (Nil)
                                                                         (● self type) (● expr loc))
                                                                        body) ))
                                               (type (● expr type))
                                               (loc (● expr loc))))
                              (second state)))
               (lowering state ((body (lower-exit body owners #t)))
                         (new Pair
                           (first (new Expr
                                    (term (Lambda params body ))
                                    (type (● expr type))
                                    (loc (● expr loc))))
                           (second state))))))
        (_ (lower state expr))))

    ;; ---- Scope exits ----

    ;; Tail transfer exits the caller after evaluating outgoing operands and
    ;; before entering the callee. This ordering preserves tail calls with
    ;; deterministic cleanup. A handle is a boundary: cleanup belonging
    ;; outside it stays outside its evidence scope.
    (define (finish-exit (state Counting) (expr Expr) (owners (List Expr)) (transfer? Bool))
      (→ (Pair Expr Counting))
      (if (null? owners) (new Pair (first expr) (second state))
          (match (● expr term)
            ((App callee args)
             (if transfer? (tail-transfer state expr callee args owners)
                 (finish-result state expr owners)))
            (_ (finish-result state expr owners)))))

    (define (finish-result (state Counting) (expr Expr) (owners (List Expr)))
      (→ (Pair Expr Counting))
      (lowering state ((result (fresh (● expr type) (● expr loc))))
                (new Pair (first (bind result expr (releasing owners result))) (second state))))

    (record Named
      ((reads (List Expr))
       (bindings (List (Pair Expr Expr)))))

    (define (name-values (state Counting) (values (List Expr))) (→ (Pair Named Counting))
      (match values
        ((Nil) (new Pair (first (new Named (reads (Nil)) (bindings (Nil)))) (second state)))
        ((Cons value rest)
         (lowering state ((read (fresh (● value type) (● value loc))) (named (name-values rest)))
                   (new Pair
                     (first (new Named
                              (reads (Cons read (● named reads)))
                              (bindings
                               (Cons (new Pair (first read) (second value)) (● named bindings)))))
                     (second state))))))

    (define (with-bindings (bindings (List (Pair Expr Expr))) (body Expr)) (→ Expr)
      (fold-right (lambda (binding body) (bind (● binding first) (● binding second) body))
                  body
                  bindings))

    (define (tail-transfer (state Counting)
                           (expr Expr)
                           (callee Expr)
                           (args (List Expr))
                           (owners (List Expr)))
      (→ (Pair Expr Counting))
      (let ((direct? (match (● callee term) ((Var name _ _) (global? state name)) (_ #f))))
        (lowering state ((named (name-values (if direct? args (Cons callee args)))))
                  (let* ((values (● named reads))
                         (call (if direct?
                                   (App callee values)
                                   (App (list-ref values 0) (list-drop values 1)))))
                    (new Pair (first (with-bindings (● named bindings)
                                                    (releasing owners
                                                               (new Expr
                                                                 (term call)
                                                                 (type (● expr type))
                                                                 (loc (● expr loc))))))
                         (second state))))))

    ;; ---- Calls and observation ----

    ;; Constructors and ordinary calls consume their arguments. An accessor
    ;; or primitive may only observe one; name those operands so their
    ;; ownership survives until the result has acquired its own reference.
    (define (lower-call (state Counting) (expr Expr) (callee Expr) (args (List Expr)))
      (→ (Pair Expr Counting))
      (match (● callee term)
        ((Var "prim:set!" _ _) (lower-place-call state expr callee args #f))
        ((Var "prim:replace!" _ _) (lower-place-call state expr callee args #t))
        (_
         (let ((operation (match (● callee term)
                            ((Var name _ _) (program-value (● state program) name))
                            (_ (None)))))
           (lowering state ((callee (lower callee)) (args (lower-all args)))
                     (lower-observation state expr callee args operation))))))

    (define (lower-observation (state Counting) (expr Expr) (callee Expr) (args (List Expr))
                               (operation (Option Value)))
      (→ (Pair Expr Counting))
      (let ((released (map-indexed (lambda (index value)
                                     (and (observes-argument? operation callee index)
                                          (shared? state (● value type))))
                                   args)))
        (if (not (any? (lambda (value) value) released))
            (let ((call
                   (new Expr (term (App callee args)) (type (● expr type)) (loc (● expr loc)))))
              (new Pair
                (first (if (alias-result? operation callee) (retained state call) call))
                (second state)))
            (lowering state ((named (name-values args)))
                      (let* ((call (new Expr
                                     (term (App callee (● named reads)))
                                     (type (● expr type))
                                     (loc (● expr loc))))
                             (result
                              (if (alias-result? operation callee) (retained state call) call))
                             (owners (map (lambda (pair) (● pair first))
                                          (filter (lambda (pair) (● pair second))
                                                  (zip (● named reads) released)))))
                        (lowering state ((body (finish-result result (reverse owners))))
                                  (new Pair
                                    (first (with-bindings (● named bindings) body))
                                    (second state))))))))

    ;; A written place is an address, so its final getter must not run. The
    ;; receiver is evaluated and held while the incoming expression runs.
    (define (lower-place-call (state Counting)
                              (expr Expr)
                              (callee Expr)
                              (args (List Expr))
                              (swap? Bool))
      (→ (Pair Expr Counting))
      (match args
        ((Cons place (Cons incoming (Nil)))
         (match (● place term)
           ((Ann inner _) (lower-place-call state expr callee (list inner incoming) swap?))
           ((App getter (Cons receiver (Nil)))
            (match (● getter term)
              ((Var name _ _)
               (match (program-value (● state program) name)
                 ((Some (Accessor case index scheme))
                  (let* ((operation
                          (if swap? (Swapper case index scheme) (Setter case index scheme)))
                         (name (field-operation-name case index (if swap? "replace!" "set!")))
                         (callee (local name (TFun (list (● receiver type) (● incoming type))
                                                   (● expr type) (empty-row)) (● expr loc))))
                    (lowering state ((receiver (lower receiver)) (incoming (lower incoming)))
                              (lower-observation state
                                                 expr
                                                 callee
                                                 (list receiver incoming)
                                                 (Some operation)))))
                 (_ (panic "internal error: written place is not an accessor"))))
              (_ (panic "internal error: written place is not a global accessor"))))
           (_ (panic "internal error: written place is not a field"))))
        (_ (panic "internal error: written place has two operands"))))

    ;; ---- Patterns ----

    ;; Tests borrow the scrutinee until a whole clause matches. Its prologue
    ;; then acquires shared bindings and releases the matched owner. These
    ;; acquisitions cannot yield, so failed alternatives acquire nothing.
    (record PatternPlan
      ((pattern Pattern)
       (bindings (List (Pair Expr Expr)))
       (owners (List Expr))))

    (define (pattern-type (pattern Pattern)) (→ Type)
      (match pattern
        ((PVar _ type) type)
        ((PWild type) type)
        ((PLit _ type) type)
        ((PCon _ _ type) type)))

    (define (pattern-plan (state Counting) (pattern Pattern) (loc Loc))
      (→ (Pair PatternPlan Counting))
      (match pattern
        ((PVar name type)
         (if (shared? state type)
             (lowering state ((read (fresh type loc)))
                       (let ((owner (local name type loc)))
                         (new Pair (first (new PatternPlan (pattern (PVar (name-of read) type))
                                               (bindings (list (new Pair (first owner)
                                                                    (second (intrinsic
                                                                             "prim:pattern-retain"
                                                                             (list read)
                                                                             type
                                                                             loc)))))
                                               (owners (list owner)))) (second state))))
             (new Pair
               (first (new PatternPlan (pattern pattern) (bindings (Nil)) (owners (Nil))))
               (second state))))
        ((PCon name args type)
         (lowering state ((plans (pattern-plans args loc)))
                   (new Pair
                     (first (new PatternPlan
                              (pattern
                               (PCon name (map (lambda (plan) (● plan pattern)) plans) type))
                              (bindings (concatenate (map (lambda (plan) (● plan bindings)) plans)))
                              (owners (concatenate (map (lambda (plan) (● plan owners)) plans)))))
                     (second state))))
        (_ (new Pair
             (first (new PatternPlan (pattern pattern) (bindings (Nil)) (owners (Nil))))
             (second state)))))

    (define (pattern-plans (state Counting) (patterns (List Pattern)) (loc Loc))
      (→ (Pair (List PatternPlan) Counting))
      (match patterns
        ((Nil) (new Pair (first (Nil)) (second state)))
        ((Cons first rest)
         (lowering state ((first (pattern-plan first loc)) (rest (pattern-plans rest loc)))
                   (new Pair (first (Cons first rest)) (second state))))))

    (define (lower-match (state Counting)
                         (expr Expr)
                         (value Expr)
                         (clauses (List Clause))
                         (owners (List Expr))
                         (tail? Bool))
      (→ (Pair Expr Counting))
      (lowering state ((value (lower value)) (read (fresh (● value type) (● value loc)))
                       (clauses (lower-clauses read clauses owners tail?)))
                (new Pair
                  (first (bind read
                               value
                               (new Expr
                                 (term (Match read clauses))
                                 (type (● expr type))
                                 (loc (● expr loc)))))
                  (second state))))

    (define (lower-clauses (state Counting) (read Expr) (clauses (List Clause))
                           (owners (List Expr)) (tail? Bool))
      (→ (Pair (List Clause) Counting))
      (match clauses
        ((Nil) (new Pair (first (Nil)) (second state)))
        ((Cons clause rest)
         (lowering state ((plan (pattern-plan (● clause pattern) (● read loc)))
                          (body (lower-exit (● clause body)
                                            (append (reverse (● plan owners)) owners)
                                            tail?))
                          (rest (lower-clauses read rest owners tail?)))
                   (new Pair (first (Cons (new Clause (pattern (● plan pattern))
                                               (body (with-bindings (● plan bindings)
                                                                    (releasing
                                                                     (pattern-release state
                                                                                      (● clause
                                                                                         pattern)
                                                                                      read)
                                                                     body))))
                                          rest))
                        (second state))))))

    ;; A shared record owns its fields once, so releasing it is sufficient.
    ;; A linear record is taken apart: linear variable patterns transfer
    ;; their whole subtree, while destructured records release the shared
    ;; fields whose ownership their shell used to hold.
    (define (pattern-release (state Counting) (pattern Pattern) (read Expr)) (→ (List Expr))
      (if (shared? state (● read type)) (list read)
          (match pattern
            ((PCon name args _)
             (match (program-value (● state program) name)
               ((Some (Constructor case _))
                (concatenate
                 (map-indexed
                  (lambda (index child)
                    (let* ((field (list-ref (● case fields) index))
                           (name (field-operation-name case index "get"))
                           (access (intrinsic name (list read) (pattern-type child) (● read loc))))
                      (pattern-release state child access))) args)))
               (_ (panic "internal error: pattern has no constructor"))))
            (_ (Nil)))))

    ))

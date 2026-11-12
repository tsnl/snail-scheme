;; Concrete shared ownership. Every expression produces an owned result;
;; locals keep their own reference until their scope exits. Reads retain,
;; calls transfer arguments, and releases become visible before control
;; lowering decides which owners a suspended frame must carry.
(define-library (snail shell compiler lifetimes)
  (export lower-lifetimes)
  (import
   (snail core base)
   (snail core table)
   (snail shell compiler read)
   (snail shell compiler core)
   (snail shell compiler capabilities)
   (snail shell compiler specialize))
  (begin

    ;; ---- Concrete ownership ----

    (struct Lifetime
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

    (define (shared? (state Lifetime) (type Type)) (→ Bool)
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

    (define (global? (state Lifetime) (name String)) (→ Bool)
      (or (table-contains? (● state globals) name)
          (match (program-value (● state program) name) ((Some _) #t) ((None) #f))))

    (define (fresh (state Lifetime) (type Type) (loc Loc)) (→ (Pair Expr Lifetime))
      (Pair (local (string-append "%lifetime." (i64->string (● state next))) type loc)
            (Lifetime-next-set state (+ (● state next) 1))))

    (define (local (name String) (type Type) (loc Loc)) (→ Expr)
      (Expr (Var name (Nil) (Nil)) type loc))

    (define (name-of (expr Expr)) (→ String)
      (match (● expr term) ((Var name _ _) name) (_ (panic "internal error: expected a local"))))

    (define (bind (name Expr) (value Expr) (body Expr)) (→ Expr)
      (Expr (Let (name-of name) value body) (● body type) (● value loc)))

    (define (intrinsic (name String) (args (List Expr)) (type Type) (loc Loc)) (→ Expr)
      (Expr (App (local name (TFun (map (lambda (arg) (● arg type)) args) type empty-row) loc) args)
            type
            loc))

    (define (retained (state Lifetime) (value Expr)) (→ Expr)
      (if (shared? state (● value type))
          (intrinsic "prim:retain" (list value) (● value type) (● value loc)) value))

    (define (release (value Expr)) (→ Expr)
      (intrinsic "prim:release" (list value) (TCon "Unit" (Nil)) (● value loc)))

    (define (releasing (values (List Expr)) (body Expr)) (→ Expr)
      (fold-right
       (lambda (value body) (Expr (Seq (release value) body) (● body type) (● value loc)))
       body values))

    ;; ---- Expressions ----

    (define (lower-lifetimes (declarations Declarations) (item Item)) (→ Item)
      (match item
        ((Define name value)
         (let ((state (new-lifetime declarations value)))
           (Define name (● (lower-function state value #t) first))))
        ((Do value) (Do (● (lower (new-lifetime declarations value) value) first)))
        (_ item)))

    (define (new-lifetime (declarations Declarations) (value Expr)) (→ Lifetime)
      (Lifetime (● declarations program) (● declarations bindings)
                (known-types (● declarations program) empty-table value) 0))

    (define (lower (state Lifetime) (expr Expr)) (→ (Pair Expr Lifetime))
      (lower-tail state expr #f))

    (define (lower-tail (state Lifetime) (expr Expr) (tail? Bool)) (→ (Pair Expr Lifetime))
      (let ((rebuild (lambda (term) (Expr term (● expr type) (● expr loc)))))
        (match (● expr term)
          ((Var name _ _) (Pair (if (global? state name) expr (retained state expr)) state))
          ((Lambda _ _ _) (lower-function state expr #f))
          ((App callee args) (lower-call state expr callee args))
          ((Let name value body)
           (lowering state ((value (lower value)) (body (lower-tail body tail?))
                            (body (finish-tail body
                                               (owned-local state name (● value type) (● value loc))
                                               tail?)))
                     (Pair (rebuild (Let name value body)) state)))
          ((Seq first rest)
           (lowering state ((first (lower first)) (rest (lower-tail rest tail?)))
                     (Pair
                      (rebuild (Seq (if (shared? state (● first type)) (release first) first) rest))
                      state)))
          ((If test yes no)
           (lowering state
                     ((test (lower test)) (yes (lower-tail yes tail?)) (no (lower-tail no tail?)))
                     (Pair (rebuild (If test yes no)) state)))
          ((Match value clauses) (lower-match state expr value clauses tail?))
          ((Ann inner type)
           (lowering state ((inner (lower inner))) (Pair (rebuild (Ann inner type)) state)))
          ((Convert inner type)
           (lowering state ((inner (lower inner))) (Pair (rebuild (Convert inner type)) state)))
          ((TypeTest inner type)
           (lowering state ((inner (lower inner)) (read (fresh (● inner type) (● inner loc))))
                     (lowering state ((body (finish (rebuild (TypeTest read type))
                                                    (if (shared? state (● inner type))
                                                        (list read)
                                                        (Nil)))))
                               (Pair (bind read inner body) state))))
          ((Handle effect implementations body)
           (lowering state
                     ((values (lower-all (map (lambda (entry) (● entry second)) implementations)))
                      (body (lower body)))
                     (Pair (rebuild (Handle effect
                                            (zip
                                             (map (lambda (entry) (● entry first)) implementations)
                                             values)
                                            body))
                           state)))
          (_ (Pair expr state)))))

    (define (owned-local (state Lifetime) (name String) (type Type) (loc Loc)) (→ (List Expr))
      (if (shared? state type) (list (local name type loc)) (Nil)))

    (define (lower-all (state Lifetime) (values (List Expr))) (→ (Pair (List Expr) Lifetime))
      (match values
        ((Nil) (Pair (Nil) state))
        ((Cons first rest)
         (lowering state ((first (lower first)) (rest (lower-all rest)))
                   (Pair (Cons first rest) state)))))

    ;; A closure activation owns the incoming closure reference. Its fields
    ;; are observed through that owner; reads of a shared capture retain as
    ;; usual. A direct top-level function has no closure argument.
    (define (lower-function (state Lifetime) (expr Expr) (top? Bool)) (→ (Pair Expr Lifetime))
      (match (Pair (● expr term) (fn-arrow (● expr type)))
        ((Pair (Lambda params body captures?) (TFun types _ _))
         (let ((owners (reverse (concatenate
                                 (map (lambda (pair)
                                        (owned-local state
                                                     (● pair first)
                                                     (● pair second)
                                                     (● expr loc)))
                                      (zip params types)))))
               (closure? (and (not top?) (not (match (● expr type) ((TCon "fn" _) #t) (_ #f))))))
           (lowering state ((body (lower-tail body #t)))
                     (if closure?
                         (lowering state ((self (fresh (fn-arrow (● expr type)) (● expr loc)))
                                          (body (finish-tail body (append owners (list self)) #t)))
                                   (Pair (Expr (Lambda params
                                                       (bind self
                                                             (intrinsic "prim:current-closure"
                                                                        (Nil)
                                                                        (● self type)
                                                                        (● expr loc))
                                                             body)
                                                       captures?) (● expr type) (● expr loc))
                                         state))
                         (lowering state ((body (finish-tail body owners #t)))
                                   (Pair
                                    (Expr (Lambda params body captures?) (● expr type) (● expr loc))
                                    state))))))
        (_ (lower state expr))))

    ;; ---- Scope exits ----

    ;; Tail transfer exits the caller after evaluating outgoing operands and
    ;; before entering the callee. This ordering preserves tail calls with
    ;; deterministic cleanup. A handle is a boundary: cleanup belonging
    ;; outside it stays outside its evidence scope.
    (define (finish (state Lifetime) (expr Expr) (owners (List Expr))) (→ (Pair Expr Lifetime))
      (finish-tail state expr owners #f))

    (define (finish-tail (state Lifetime) (expr Expr) (owners (List Expr)) (tail? Bool))
      (→ (Pair Expr Lifetime))
      (if (null? owners) (Pair expr state)
          (let ((rebuild (lambda (term) (Expr term (● expr type) (● expr loc)))))
            (match (● expr term)
              ((Let name value body)
               (lowering state
                         ((body (finish-tail body owners tail?)))
                         (Pair (rebuild (Let name value body)) state)))
              ((Seq first rest)
               (lowering state
                         ((rest (finish-tail rest owners tail?)))
                         (Pair (rebuild (Seq first rest)) state)))
              ((If test yes no)
               (lowering state
                         ((yes (finish-tail yes owners tail?)) (no (finish-tail no owners tail?)))
                         (Pair (rebuild (If test yes no)) state)))
              ((Match value clauses)
               (lowering state ((clauses (finish-clauses clauses owners tail?)))
                         (Pair (rebuild (Match value clauses)) state)))
              ((App callee args)
               (if (and tail? (ordinary-call? state callee))
                   (tail-transfer state expr callee args owners)
                   (finish-result state expr owners)))
              (_ (finish-result state expr owners))))))

    (define (finish-result (state Lifetime) (expr Expr) (owners (List Expr)))
      (→ (Pair Expr Lifetime))
      (lowering state ((result (fresh (● expr type) (● expr loc))))
                (Pair (bind result expr (releasing owners result)) state)))

    (define (finish-clauses (state Lifetime)
                            (clauses (List Clause))
                            (owners (List Expr))
                            (tail? Bool))
      (→ (Pair (List Clause) Lifetime))
      (match clauses
        ((Nil) (Pair (Nil) state))
        ((Cons clause rest)
         (lowering state
                   ((body (finish-tail (● clause body) owners tail?))
                    (rest (finish-clauses rest owners tail?)))
                   (Pair (Cons (Clause (● clause pattern) body) rest) state)))))

    (define (ordinary-call? (state Lifetime) (callee Expr)) (→ Bool)
      (match (● callee term)
        ((Var name _ _)
         (match (program-value (● state program) name)
           ((Some (Defined _ _ _)) #t)
           ((Some _) #f)
           ((None) #t)))
        (_ #t)))

    (struct Named
      ((reads (List Expr))
       (bindings (List (Pair Expr Expr)))))

    (define (name-values (state Lifetime) (values (List Expr))) (→ (Pair Named Lifetime))
      (match values
        ((Nil) (Pair (Named (Nil) (Nil)) state))
        ((Cons value rest)
         (lowering state ((read (fresh (● value type) (● value loc))) (named (name-values rest)))
                   (Pair
                    (Named (Cons read (● named reads)) (Cons (Pair read value) (● named bindings)))
                    state)))))

    (define (with-bindings (bindings (List (Pair Expr Expr))) (body Expr)) (→ Expr)
      (fold-right (lambda (binding body) (bind (● binding first) (● binding second) body))
                  body
                  bindings))

    (define (tail-transfer (state Lifetime)
                           (expr Expr)
                           (callee Expr)
                           (args (List Expr))
                           (owners (List Expr)))
      (→ (Pair Expr Lifetime))
      (let ((direct? (match (● callee term) ((Var name _ _) (global? state name)) (_ #f))))
        (lowering state ((named (name-values (if direct? args (Cons callee args)))))
                  (let* ((values (● named reads))
                         (call (if direct?
                                   (App callee values)
                                   (App (list-ref values 0) (list-drop values 1)))))
                    (Pair (with-bindings (● named bindings)
                                         (releasing owners (Expr call (● expr type) (● expr loc))))
                          state)))))

    ;; ---- Calls and observation ----

    ;; Constructors and ordinary calls consume their arguments. An accessor
    ;; or primitive may only observe one; name those operands so their
    ;; ownership survives until the result has acquired its own reference.
    (define (lower-call (state Lifetime) (expr Expr) (callee Expr) (args (List Expr)))
      (→ (Pair Expr Lifetime))
      (match (● callee term)
        ((Var "prim:set!" _ _) (lower-place-call state expr callee args #f))
        ((Var "prim:replace!" _ _) (lower-place-call state expr callee args #t))
        (_
         (let ((operation (match (● callee term)
                            ((Var name _ _) (program-value (● state program) name))
                            (_ (None)))))
           (lowering state ((callee (lower callee)) (args (lower-all args)))
                     (lower-observation state expr callee args operation))))))

    (define (observes? (operation (Option Value)) (callee Expr) (index I64)) (→ Bool)
      (match operation
        ((Some (Accessor _ _ _)) #t)
        ((Some (Setter _ _ _)) (= index 0))
        ((Some (Swapper _ _ _)) (= index 0))
        ((Some (Replacer _ _ _)) (= index 0))
        ((Some (Primitive _))
         (match (● callee term)
           ((Var name _ _)
            (and (not (member? name
                               (list "prim:unsafe-total"
                                     "prim:inherit-handlers"
                                     "prim:inherit-handlers-1"
                                     "prim:once"
                                     "prim:call-once"
                                     "prim:drop-once"
                                     "prim:discard"
                                     "prim:rc-new"
                                     "prim:constant-array"
                                     "prim:retain"
                                     "prim:release")))
                 (not (and (= index 2) (member? name (list "prim:array-set!" "prim:vector-set"))))))
           (_ #f)))
        ((Some (Foreign _ _)) #t)
        (_ #f)))

    (define (alias-result? (operation (Option Value)) (callee Expr)) (→ Bool)
      (match operation
        ((Some (Accessor _ _ _)) #t)
        ((Some (Primitive _))
         (match (● callee term)
           ((Var name _ _) (member? name (list "prim:rc-get" "prim:array-ref" "prim:vector-ref")))
           (_ #f)))
        (_ #f)))

    (define (lower-observation (state Lifetime) (expr Expr) (callee Expr) (args (List Expr))
                               (operation (Option Value)))
      (→ (Pair Expr Lifetime))
      (let ((released (map-indexed (lambda (index value)
                                     (and (observes? operation callee index)
                                          (shared? state (● value type))))
                                   args)))
        (if (not (any? (lambda (value) value) released))
            (let ((call (Expr (App callee args) (● expr type) (● expr loc))))
              (Pair (if (alias-result? operation callee) (retained state call) call) state))
            (lowering state ((named (name-values args)))
                      (let* ((call (Expr (App callee (● named reads)) (● expr type) (● expr loc)))
                             (result
                              (if (alias-result? operation callee) (retained state call) call))
                             (owners (map (lambda (pair) (● pair first))
                                          (filter (lambda (pair) (● pair second))
                                                  (zip (● named reads) released)))))
                        (lowering state ((body (finish-result result (reverse owners))))
                                  (Pair (with-bindings (● named bindings) body) state)))))))

    ;; A written place is an address, so its final getter must not run. The
    ;; receiver is evaluated and held while the incoming expression runs.
    (define (lower-place-call (state Lifetime)
                              (expr Expr)
                              (callee Expr)
                              (args (List Expr))
                              (swap? Bool))
      (→ (Pair Expr Lifetime))
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
                         (name (string-append name (if swap? "-replace!" "-set!")))
                         (callee (local name (TFun (list (● receiver type) (● incoming type))
                                                   (● expr type) empty-row) (● expr loc))))
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
    (struct PatternPlan
      ((pattern Pattern)
       (bindings (List (Pair Expr Expr)))
       (owners (List Expr))))

    (define (pattern-type (pattern Pattern)) (→ Type)
      (match pattern
        ((PVar _ type) type)
        ((PWild type) type)
        ((PLit _ type) type)
        ((PCon _ _ type) type)))

    (define (pattern-plan (state Lifetime) (pattern Pattern) (loc Loc))
      (→ (Pair PatternPlan Lifetime))
      (match pattern
        ((PVar name type)
         (if (shared? state type)
             (lowering state ((read (fresh type loc)))
                       (let ((owner (local name type loc)))
                         (Pair (PatternPlan (PVar (name-of read) type)
                                            (list (Pair owner
                                                        (intrinsic "prim:pattern-retain"
                                                                   (list read)
                                                                   type
                                                                   loc)))
                                            (list owner)) state)))
             (Pair (PatternPlan pattern (Nil) (Nil)) state)))
        ((PCon name args type)
         (lowering state ((plans (pattern-plans args loc)))
                   (Pair (PatternPlan (PCon name (map (lambda (plan) (● plan pattern)) plans) type)
                                      (concatenate (map (lambda (plan) (● plan bindings)) plans))
                                      (concatenate (map (lambda (plan) (● plan owners)) plans)))
                         state)))
        (_ (Pair (PatternPlan pattern (Nil) (Nil)) state))))

    (define (pattern-plans (state Lifetime) (patterns (List Pattern)) (loc Loc))
      (→ (Pair (List PatternPlan) Lifetime))
      (match patterns
        ((Nil) (Pair (Nil) state))
        ((Cons first rest)
         (lowering state ((first (pattern-plan first loc)) (rest (pattern-plans rest loc)))
                   (Pair (Cons first rest) state)))))

    (define (lower-match (state Lifetime)
                         (expr Expr)
                         (value Expr)
                         (clauses (List Clause))
                         (tail? Bool))
      (→ (Pair Expr Lifetime))
      (lowering state ((value (lower value)) (read (fresh (● value type) (● value loc)))
                       (clauses (lower-clauses read clauses tail?)))
                (Pair (bind read value (Expr (Match read clauses) (● expr type) (● expr loc)))
                      state)))

    (define (lower-clauses (state Lifetime) (read Expr) (clauses (List Clause)) (tail? Bool))
      (→ (Pair (List Clause) Lifetime))
      (match clauses
        ((Nil) (Pair (Nil) state))
        ((Cons clause rest)
         (lowering state ((plan (pattern-plan (● clause pattern) (● read loc)))
                          (body (lower-tail (● clause body) tail?))
                          (body (finish-tail body (reverse (● plan owners)) tail?))
                          (rest (lower-clauses read rest tail?)))
                   (Pair (Cons (Clause (● plan pattern)
                                       (with-bindings (● plan bindings)
                                                      (releasing (pattern-release state
                                                                                  (● clause pattern)
                                                                                  read)
                                                                 body)))
                               rest)
                         state)))))

    ;; A shared record owns its fields once, so releasing it is sufficient.
    ;; A linear record is taken apart: linear variable patterns transfer
    ;; their whole subtree, while destructured records release the shared
    ;; fields whose ownership their shell used to hold.
    (define (pattern-release (state Lifetime) (pattern Pattern) (read Expr)) (→ (List Expr))
      (if (shared? state (● read type)) (list read)
          (match pattern
            ((PCon name args _)
             (match (program-value (● state program) name)
               ((Some (Constructor case _))
                (concatenate
                 (map-indexed
                  (lambda (index child)
                    (let* ((field (list-ref (● case fields) index))
                           (name (string-append (● case name) "-" (● field name)))
                           (access (intrinsic name (list read) (pattern-type child) (● read loc))))
                      (pattern-release state child access))) args)))
               (_ (panic "internal error: pattern has no constructor"))))
            (_ (Nil)))))

    ))

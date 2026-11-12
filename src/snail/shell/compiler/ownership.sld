;; Linear values are used exactly once on every path that returns. This
;; check follows each path through a checked body: a use of a linear name
;; consumes it, a second use is an error, and so is a name still live at
;; the end of the scope that bound it; alternatives must consume the same
;; names. It inserts nothing. A value is released by a call someone wrote,
;; such as `drop` or `call-once`, or by a match that moves its fields out.
;; Ordinary arrows stay unrestricted; only an immediate `once` lambda may
;; move linear captures into its environment. A field operation acts on
;; its record in place, so a linear local it is applied to stays live,
;; except a replacement, which consumes its record and answers it. A
;; type variable is linear unless its definition requires (Copy A), so
;; each generic body is checked once, before specialization, for every
;; instantiation, and a refusal it causes names the requirement that would
;; lift it.
(define-library (snail shell compiler ownership)
  (export
   check-owned-fields
   check-item-ownership
   consumed-references
   observes-argument?
   alias-result?
   ordinary-call?
   surviving-references)
  (import
   (snail core base)
   (snail core table)
   (snail shell compiler read)
   (snail shell compiler core)
   (snail shell compiler capabilities))
  (begin

    (define no-loc (→ Loc) (Loc "ownership" 0 0))

    ;; ---- Shared call ownership ----

    ;; Ordinary calls and constructors consume their operands. Observation
    ;; keeps an owned operand until the result has acquired any shared alias.
    (define (observes-argument? (operation (Option Value)) (callee Expr) (index I64)) (→ Bool)
      (match operation
        ((Some (Accessor _ _ _)) #t)
        ((Some (Setter _ _ _)) (= index 0))
        ((Some (Swapper _ _ _)) (= index 0))
        ((Some (Replacer _ _ _)) (= index 0))
        ((Some (Primitive _))
         (match (● callee term)
           ((Var name _ _)
            (if (member? name (list "prim:constant-array-fill"))
                (= index 0)
                (and (not (member? name
                                   (list "prim:unsafe-total"
                                         "prim:inherit-handlers"
                                         "prim:inherit-handlers-1"
                                         "prim:once"
                                         "prim:call-once"
                                         "prim:drop-once"
                                         "prim:discard"
                                         "prim:rc" "prim:rc-new" "prim:set!" "prim:replace!"
                                         "prim:constant-array" "prim:retain" "prim:release")))
                     (not (and (= index 2)
                               (member? name (list "prim:array-set!" "prim:vector-set")))))))
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

    (define (ordinary-call? (program Program) (callee Expr)) (→ Bool)
      (match (● callee term)
        ((Var name _ _)
         (match (program-value program name)
           ((Some (Defined _ _ _)) #t)
           ((Some _) #f)
           ((None) #t)))
        ((Ann inner _) (ordinary-call? program inner))
        (_ #t)))

    ;; ---- Owners surviving an exit ----

    ;; These are exact local identities, not heap reachability. Bindings and
    ;; closure captures cannot be reassigned. A directly returned constructor
    ;; is still private, but a previously bound mutable record is not: its
    ;; fields may have changed. No user call promises an alias in its result.
    (define (surviving-references (program Program) (expr Expr) (tail? Bool)) (→ (List String))
      (match (● expr term)
        ((Var name _ _) (list name))
        ((Convert inner _) (surviving-references program inner #f))
        ((Ann inner _) (surviving-references program inner tail?))
        ((Lambda _ _ _) (expr-references expr))
        ((Let name value body)
         (let ((names (surviving-references program body tail?)))
           (if (member? name names)
               (label-union (label-difference names (list name)) (stable-aliases program value))
               names)))
        ((Seq _ rest) (surviving-references program rest tail?))
        ((If _ yes no)
         (intersection (surviving-references program yes tail?)
                       (surviving-references program no tail?)))
        ((Match _ clauses)
         (match clauses
           ((Nil) (Nil))
           ((Cons first rest)
            (fold-left (lambda (names clause)
                         (intersection names (surviving-references program (● clause body) tail?)))
                       (surviving-references program (● first body) tail?) rest))))
        ((App callee args)
         (if (and tail? (ordinary-call? program callee))
             (surviving-operands program (Cons callee args))
             (match (● callee term)
               ((Var name _ _)
                (match (program-value program name)
                  ((Some (Constructor _ _)) (surviving-operands program args))
                  (_ (if (member? name (list "prim:rc" "prim:rc-new" "prim:once"
                                             "prim:inherit-handlers" "prim:inherit-handlers-1"))
                         (surviving-operands program args) (Nil)))))
               (_ (Nil)))))
        (_ (Nil))))

    (define (surviving-operands (program Program) (args (List Expr))) (→ (List String))
      (fold-left (lambda (names arg) (label-union names (surviving-references program arg #f)))
                 (Nil) args))

    (define (stable-aliases (program Program) (value Expr)) (→ (List String))
      (match (● value term)
        ((Var name _ _) (list name))
        ((Lambda _ _ _) (expr-references value))
        ((Ann inner _) (stable-aliases program inner))
        (_ (Nil))))

    (define (intersection (left (List String)) (right (List String))) (→ (List String))
      (filter (lambda (name) (member? name right)) left))

    ;; ---- Representable ownership ----

    ;; Sequence reads leave elements in place, so they require Copy elements.
    ;; Ordinary aggregates are linear whenever a member is linear. Rc alone
    ;; may own linear content while remaining Copy; WeakRc does not own it.
    ;; `copy` names the type variables proven Copy by a declaration.

    (define (check-type (program Program) (copy (List String)) (type Type) (loc Loc))
      (→ Unit) (! compile)
      (match type
        ((TCon name args)
         (for-each (lambda (arg)
                     (when (and (member? name (list "Array" "Vector"))
                                (linear-type? program copy arg))
                       (compile-error loc
                                      (explain-type program copy arg
                                                    "an Array or Vector element must be Copy; use Rc to share a linear value")))
                     (check-type program copy arg loc)) args))
        ((TFun params result _)
         (for-each (lambda (part) (check-type program copy part loc)) (Cons result params)))
        (_ (unit))))

    ;; A message about a value of a linear type, with the Copy that would
    ;; have made the type unrestricted, if one would.

    (define (explain-type (program Program) (copy (List String)) (type Type) (message String))
      (→ String)
      (match (missing-copy program copy type)
        ((Nil) message)
        (names
         (string-append message
                        " (its type is linear unless the definition requires "
                        (copy-declaration names)
                        ")"))))

    ;; A declaration's fields are checked with its parameters ω, since they
    ;; are checked where the declaration is used.

    (define (check-owned-fields (program Program)) (→ Unit) (! compile)
      (for-each (lambda (data)
                  (for-each (lambda (case)
                              (for-each (lambda (field)
                                          (check-type program
                                                      (● data params)
                                                      (● field type)
                                                      no-loc))
                                        (● case fields)))
                            (● data cases))) (table-values (● program types))))

    ;; An item's types, with the variables its scheme declares ω.

    (define (check-owned-types (program Program) (schemes (Table Scheme)) (item Item))
      (→ Unit)
      (! compile)
      (match item
        ((Define name value)
         (check-type program (item-copy schemes item) (● value type) (● value loc))
         (when (linear-type? program (scheme-vars schemes name) (● value type))
           (compile-error (● value loc) "a linear value cannot be a global"))
         (check-expression-types program (item-copy schemes item) value))
        (_ (unit))))

    ;; A global's own type variables. A polymorphic global's initializer
    ;; is total, so it holds no value of them, and its uses may share it.

    (define (scheme-vars (schemes (Table Scheme)) (name String)) (→ (List String))
      (match (table-ref schemes name)
        ((Some scheme) (● scheme vars))
        ((None) (Nil))))

    ;; The type variables an item's scheme declares ω.

    (define (item-copy (schemes (Table Scheme)) (item Item)) (→ (List String))
      (match item
        ((Define name _) (match (table-ref schemes name)
                           ((Some scheme) (● scheme copy))
                           ((None) (Nil))))
        (_ (Nil))))

    (define (item-constraints (schemes (Table Scheme)) (item Item)) (→ (List Constraint))
      (match item
        ((Define name _)
         (match (table-ref schemes name)
           ((Some scheme) (● scheme constraints)) ((None) (Nil))))
        (_ (Nil))))

    (define (check-expression-types (program Program) (copy (List String)) (expr Expr))
      (→ Unit) (! compile)
      (check-type program copy (● expr type) (● expr loc))
      (for-each (lambda (child) (check-expression-types program copy child)) (expr-children expr)))

    ;; ---- Paths ----

    ;; One path through a body, as far as the check has followed it: the
    ;; type variables the body's scheme declares ω, the linear names still
    ;; live on it, and whether it can still return.
    ;; Names are unique, so a name's liveness needs no scoping. A path that
    ;; reaches a panic or a value of type Never cannot return, so it never
    ;; reaches the end of a scope. Control lowering drops what an abort
    ;; leaves live; fatal panic retains its separate fatal contract.
    (struct Path
      ((program Program)
       (copy (List String))
       (constraints (List Constraint))
       (live (List Owner))
       (returns Bool)
       (row (Option Type))))

    ;; A live linear name, with the type that makes it linear, which a
    ;; diagnostic about it explains.
    (struct Owner
      ((name String)
       (type Type)))

    (define (linear? (path Path) (type Type)) (→ Bool)
      (linear-type? (● path program) (● path copy) type))

    (define (live? (path Path) (name String)) (→ Bool)
      (any? (lambda (owner) (string=? (● owner name) name)) (● path live)))

    ;; The same for a value on this path, under its definition's Copy.

    (define (explain (path Path) (type Type) (message String)) (→ String)
      (explain-type (● path program) (● path copy) type message))

    ;; Only linear owners enter the live set; counted copies are reusable.

    (define (bind (path Path) (name String) (type Type)) (→ Path)
      (if (linear? path type) (Path-live-set path (Cons (Owner name type) (● path live))) path))

    (define (consume (path Path) (owner Owner) (loc Loc)) (→ Path) (! compile)
      (require-live path owner loc)
      (Path-live-set path
                     (filter (lambda (live) (not (string=? (● live name) (● owner name))))
                             (● path live))))

    (define (require-live (path Path) (owner Owner) (loc Loc)) (→ Unit) (! compile)
      (unless (live? path (● owner name))
        (compile-error loc
                       (explain path
                                (● owner type)
                                (string-append "linear value used more than once: "
                                               (local-name (● owner name)))))))

    ;; The end of a scope opened on `outer`: if the path returns, it has
    ;; consumed each linear name the scope bound.

    (define (close-scope (outer Path) (inner Path) (loc Loc)) (→ Path) (! compile)
      (let ((outside? (lambda (owner) (live? outer (● owner name)))))
        (match (filter (lambda (owner) (not (outside? owner))) (● inner live))
          ((Cons owner _)
           (when (● inner returns)
             (compile-error loc
                            (explain inner
                                     (● owner type)
                                     (string-append "linear value never consumed: "
                                                    (local-name (● owner name))
                                                    "; use it once, or drop it")))))
          ((Nil) (unit)))
        (Path-live-set inner (filter outside? (● inner live)))))

    ;; Alternatives start from one path. Those that return must leave the
    ;; same names live; if none returns, neither does the whole.

    (define (join (path Path) (branches (List Path)) (loc Loc)) (→ Path) (! compile)
      (match (filter (lambda (record) (● record returns)) branches)
        ((Cons first rest)
         (for-each (lambda (branch) (agree first branch loc)) rest)
         (Path-live-set path (● first live)))
        ((Nil) (Path-returns-set path #f))))

    (define (agree (one Path) (other Path) (loc Loc)) (→ Unit) (! compile)
      (for-each (lambda (owner)
                  (let ((name (● owner name)))
                    (unless (and (live? one name) (live? other name))
                      (compile-error loc
                                     (explain one
                                              (● owner type)
                                              (string-append
                                               "alternatives must consume the same linear values: "
                                               (local-name name)))))))
                (append (● one live) (● other live))))

    ;; ---- Expressions ----

    (define (check (path Path) (expr Expr)) (→ Path) (! compile)
      (let ((path (check-term path expr)))
        (if (never-type? (● expr type)) (Path-returns-set path #f) path)))

    (define (check-all (path Path) (exprs (List Expr))) (→ Path) (! compile)
      (fold-left check path exprs))

    (define (check-term (path Path) (expr Expr)) (→ Path) (! compile)
      (let ((loc (● expr loc)))
        (match (● expr term)
          ((Lit _) path)
          ((Var name _ _) (check-reference path expr name))
          ((Lambda _ _ _) (check-lambda path expr))
          ((App callee args) (check-call path callee args))
          ((If test then otherwise)
           (let ((path (check path test)))
             (join path (list (check path then) (check path otherwise)) loc)))
          ((Let name value body) (check-let path name value body loc))
          ((Seq first rest)
           (check-discardable path first)
           (check (check path first) rest))
          ((Match value clauses)
           (let ((path (check path value)))
             (join path (map (lambda (clause) (check-clause path clause loc)) clauses) loc)))
          ((Handle effect implementations body)
           (let* ((path (check-all path (map (lambda (record) (● record second)) implementations)))
                  (inner (match (● path row)
                           ((Some row) (Path-row-set path (Some (TRow (list effect) (Some row)))))
                           ((None) path))))
             ;; Cleanup in the body can use its installed handlers. A
             ;; handled abort may return even when the body does not.
             (Path-returns-set (Path-row-set (check inner body) (● path row))
                               (● path returns))))
          ((ScopedInstances _ _) (panic "internal error: instance scope survived checking"))
          ((FieldRead _ _ _) (panic "internal error: field selection survived checking"))
          ((Ann inner _)
           (check path inner))
          ((Convert inner target) (check-conversion path expr inner target))
          ((TryConvert _ _)
           (panic "internal error: try-convert must be lowered before ownership checking"))
          ((TypeTest inner target) (check-conversion path expr inner target)))))

    ;; The body must consume every linear owner introduced by its binding.

    (define (check-let (path Path) (name String) (value Expr) (body Expr) (loc Loc))
      (→ Path) (! compile)
      (let ((path (check path value)))
        (close-scope path (check (bind path name (● value type)) body) loc)))

    ;; A use of a linear local consumes it. A global is shared, as nothing
    ;; linear is one.

    (define (check-reference (path Path) (expr Expr) (name String)) (→ Path) (! compile)
      (match (field-operation path expr)
        ((Some operation) (check-field-value path operation expr) path)
        ((None)
         (match (program-value (● path program) name)
           ((Some value) (check-instantiation path expr value) path)
           ((None)
            (if (linear? path (● expr type))
                (consume path (Owner name (● expr type)) (● expr loc))
                path))))))

    ;; `once` may move a lambda's linear captures into it. A panic never
    ;; returns. A field operation acts on its record in place.

    (define (check-call (path Path) (callee Expr) (args (List Expr))) (→ Path) (! compile)
      (match (Pair (● callee term) args)
        ((Pair (Var "prim:rc" _ _) (Cons value (Nil)))
         (match (lifecycle-rows (● path program) drop-class (● path copy)
                                (● path constraints) (● value type))
           ((Err problem) (compile-error (● value loc) problem))
           ((Ok _) (unit)))
         (check path value))
        ((Pair (Var "prim:once" _ _) (Cons value (Nil)))
         (if (lambda-expr? value)
             (check-lambda path
                           (Expr (● value term)
                                 (TCon "FnOnce" (list (● value type)))
                                 (● value loc)))
             (check path value)))
        ((Pair (Var "prim:panic" _ _) _) (Path-returns-set (check-all path args) #f))
        ((Pair (Var "prim:set!" _ _) (Cons place (Cons value (Nil))))
         (check-place-write path place value))
        ((Pair (Var "prim:replace!" _ _) (Cons place (Cons value (Nil))))
         (check-place-write path place value))
        ((Pair (Var _ _ _) (Cons record rest))
         (match (field-operation path callee)
           ((Some operation)
            (check-field-grades path operation (● callee type) (● callee loc))
            (match operation
              ;; A replacement answers its record with the field replaced, so
              ;; it consumes the record, after its other operand, which may
              ;; read the record in place.
              ((Replacer _ _ _) (check (check-all path rest) record))
              ((Setter _ _ _) (check-field-write path record rest))
              ((Swapper _ _ _) (check-field-write path record rest))
              (_ (check-all (check-chain path record) rest))))
           ((None) (check-ordinary-call path callee args))))
        (_ (check-ordinary-call path callee args))))

    ;; Calls transfer their arguments, including the receiver of a FnOnce.

    (define (check-ordinary-call (path Path) (callee Expr) (args (List Expr))) (→ Path) (! compile)
      (check-yield-holds (check-all path (Cons callee args)) callee))

    ;; The references that move ownership into an expression. Field reads
    ;; observe their place; pure replacements consume their record. Control
    ;; uses the same distinction for saved or aborted scopes.

    (define (consumed-references (program Program) (expr Expr)) (→ (List String))
      (match (● expr term)
        ((Var name _ _) (list name))
        ;; Retaining observes a slot; the result becomes another owner.
        ;; Pattern acquisition consumes its temporary pattern binding.
        ((App (Expr (Var "prim:retain" _ _) _ _) _) (Nil))
        ;; Checking may inspect cleanup before deferred selections are resolved.
        ;; Reading a field observes its receiver, just as a direct accessor does.
        ((FieldRead _ _ _) (Nil))
        ((Lambda params body _)
         (let ((types (expr-reference-types body)))
           (filter (lambda (name)
                     (and (not (member? name params))
                          (match (table-ref types name)
                            ((Some type) (linear-type? program (Nil) type))
                            ((None) #f)))) (expr-references body))))
        ((App (Expr (Var "prim:set!" _ _) _ _) (Cons _ (Cons value (Nil))))
         (consumed-references program value))
        ((App (Expr (Var "prim:replace!" _ _) _ _) (Cons _ (Cons value (Nil))))
         (consumed-references program value))

        ((App callee (Cons record rest))
         (match (field-operation (Path program (Nil) (Nil) (Nil) #t (None)) callee)
           ((Some (Replacer _ _ _)) (consumed-children program expr))
           ((Some _) (concatenate (map (lambda (arg) (consumed-references program arg)) rest)))
           ((None) (consumed-children program expr))))
        (_ (consumed-children program expr))))

    (define (consumed-children (program Program) (expr Expr)) (→ (List String))
      (delete-duplicates string=?
                         (concatenate (map (lambda (child) (consumed-references program child))
                                           (expr-children expr)))))

    ;; ---- Drops that may run ----

    ;; Dropping a FnOnce unrun drops what it captured, and dropping a
    ;; `resume` drops what its frames hold, under the row of the FnOnce
    ;; being dropped (capabilities.sld, `trivial-rows`). So a linear value a
    ;; once lambda captures, or that is live across a call that may yield,
    ;; may be dropped by whoever holds the closure, and its drop must
    ;; perform no more than that row. Three checks keep the rows honest: a
    ;; captured value's drop fits the lambda's row; a value live across a
    ;; call that may yield fits this function's row, since the frame is
    ;; this function's; and a generic function may hold a value of a type
    ;; variable across a yield, so each linear type a use binds to one
    ;; fits the use's row. Values of a type variable's type inside the
    ;; generic function itself are covered by that last check at its uses.

    ;; A call may yield when its row names a control effect, or ends in a
    ;; row variable that may stand for one.

    (define (may-yield-row? (path Path) (row Type)) (→ Bool)
      (match row
        ((TRow labels tail)
         (or (any? (lambda (label) (control-effect? (● path program) label)) labels)
             (match tail
               ((Some _) #t)
               ((None) #f))))
        (_ #f)))

    (define (control-effect? (program Program) (label String)) (→ Bool)
      (match (table-ref (● program effects) label)
        ((Some effect) (not (null? (● effect control))))
        ((None) #f)))

    (define (arrow-row (type Type)) (→ (Option Type))
      (match (fn-arrow type)
        ((TFun _ _ row) (Some row))
        (_ (None))))

    ;; Whether `allowed` admits everything `performed` names: its labels,
    ;; and its tail, which must be allowed's own.

    (define (row-within? (performed Type) (allowed Type)) (→ Bool)
      (match (Pair (row-parts performed) (row-parts allowed))
        ((Pair (Pair labels tail) (Pair allowed-labels allowed-tail))
         (and (every? (lambda (label) (member? label allowed-labels)) labels)
              (match tail
                ((None) #t)
                ((Some name)
                 (match allowed-tail
                   ((Some other) (string=? name other))
                   ((None) #f))))))))

    (define (row-parts (row Type)) (→ (Pair (List String) (Option String)))
      (match row
        ((TRow labels (Some (TRigid name))) (Pair labels (Some name)))
        ((TRow labels (Some tail))
         (match (row-parts tail)
           ((Pair more name) (Pair (append labels more) name))))
        ((TRow labels (None)) (Pair labels (None)))
        ((TRigid name) (Pair (Nil) (Some name)))
        (_ (Pair (Nil) (None)))))

    ;; A type without type variables, whose drop the checker can find.

    (define (ground-type? (type Type)) (→ Bool)
      (match type
        ((TRigid _) #f)
        ((TCon _ args) (every? ground-type? args))
        ((TFun params result _) (and (every? ground-type? params) (ground-type? result)))
        (_ #t)))

    ;; Refuses a drop of `type` that `allowed`, the row of whoever may run
    ;; it, does not admit. A type with variables is covered where they are
    ;; bound, and a statement's row allows anything.

    (define (check-drop-rows (path Path)
                             (type Type)
                             (allowed (Option Type))
                             (what String)
                             (loc Loc))
      (→ Unit)
      (! compile)
      (match allowed
        ((Some row)
         (when (ground-type? type)
           (match (lifecycle-rows (● path program) drop-class (● path copy) (Nil) type)
             ((Ok rows)
              (for-each (lambda (performed)
                          (unless (row-within? performed row)
                            (compile-error loc
                                           (string-append what
                                                          ", and dropping a "
                                                          (type->string type)
                                                          " performs "
                                                          (type->string performed)
                                                          ", which the row "
                                                          (type->string row)
                                                          " does not allow"))))
                        rows))
             ((Err _) (unit)))))
        ((None) (unit))))

    ;; A linear value live after a call that may yield is held by this
    ;; function's frame.

    (define (check-yield-holds (path Path) (callee Expr)) (→ Path) (! compile)
      (when (callee-may-yield? path callee)
        (for-each (lambda (owner)
                    (check-drop-rows path
                                     (● owner type)
                                     (● path row)
                                     (string-append (local-label (● owner name))
                                                    " is live across a call that may yield, so a dropped resume may drop it")
                                     (● callee loc)))
                  (● path live)))
      path)

    ;; Whether calling `callee` may yield. The checker opens each use of a
    ;; global to its context's row, so a global's own scheme says: its
    ;; labels, and its row variable at the type this use gave it. A selected
    ;; class instance supplies its own rows. A local's type says for itself.

    (define (callee-may-yield? (path Path) (callee Expr)) (→ Bool)
      (match (● callee term)

        ((Ann inner _) (callee-may-yield? path inner))
        ((Var name types evidence)
         (match (program-value (● path program) name)
           ((Some (Method class scheme))
            (scheme-may-yield? path scheme
                               (selected-method-arguments (● path program)
                                                          class
                                                          types
                                                          evidence)))
           ((Some value)
            (match (value-scheme value)
              ((Some scheme) (scheme-may-yield? path scheme types))
              ((None) (type-may-yield? path (● callee type)))))
           ((None) (type-may-yield? path (● callee type)))))
        (_ (type-may-yield? path (● callee type)))))

    (define (type-may-yield? (path Path) (type Type)) (→ Bool)
      (match (arrow-row type)
        ((Some row) (may-yield-row? path row))
        ((None) #f)))

    (define (scheme-may-yield? (path Path) (scheme Scheme) (types (List Type))) (→ Bool)
      (match (arrow-row (● scheme type))
        ((Some (TRow labels tail))
         (or (any? (lambda (label) (control-effect? (● path program) label)) labels)
             (match tail
               ((Some (TRigid var))
                (match (assoc-ref (zip (● scheme vars) types) var)
                  ((Some row) (may-yield-row? path row))
                  ((None) #t)))
               ((Some _) #t)
               ((None) #f))))
        (_ #f)))

    ;; A use of a generic function that may yield binds its type variables
    ;; to types it may hold across the yield. Only a definition or a method
    ;; has a body that could; a primitive, an operation or a constructor
    ;; holds nothing.

    (define (check-instantiation (path Path) (expr Expr) (value Value)) (→ Unit) (! compile)
      (match (Pair (● expr term) (arrow-row (● expr type)))
        ((Pair (Var name types _) (Some row))
         (for-each (lambda (type)
                     (check-type (● path program) (● path copy) type (● expr loc))) types)
         (when (and (has-body? value) (callee-may-yield? path expr))
           (for-each (lambda (type)
                       (check-drop-rows path
                                        type
                                        (Some row)
                                        (string-append (short-name name)
                                                       " may hold a "
                                                       (type->string type)
                                                       " across a yield")
                                        (● expr loc)))
                     types)))
        (_ (unit))))

    (define (has-body? (value Value)) (→ Bool)
      (match value
        ((Defined _ _ _) #t)
        ((Method _ _) #t)
        (_ #f)))

    ;; A once lambda's captures are dropped with it when it is dropped
    ;; unrun, under its own row.

    (define (check-capture (path Path) (owner Owner) (lambda-type Type) (loc Loc))
      (→ Unit)
      (! compile)
      (match (arrow-row lambda-type)
        ((Some row)
         (if (ground-type? (● owner type))
             (check-drop-rows path
                              (● owner type)
                              (Some row)
                              (string-append "a once lambda captures "
                                             (local-label (● owner name))
                                             ", which it drops if it is dropped unrun")
                              loc)
             (match (● path row)
               ((Some enclosing)
                (unless (row-within? enclosing row)
                  (compile-error loc
                                 (string-append "a once lambda captures "
                                                (local-label (● owner name))
                                                ", a value of a type variable's type, whose drop this function's row "
                                                (type->string enclosing)
                                                " bounds, so the lambda's row must include it"))))
               ((None) (unit)))))
        ((None) (unit))))

    ;; A local's source name: unique names end in a dot and digits.

    (define (local-label (name String)) (→ String)
      (let ((chars (string->vector name)))
        (let loop ((index (- (vector-length chars) 1)))
          (cond ((< index 0) name)
                ((char=? (vector-ref chars index) #\.) (substring name 0 index))
                (else (loop (- index 1)))))))

    ;; ---- Fields ----

    ;; The value a callee denotes when it is an accessor, a replacement, a
    ;; setter or a swapper. Checking has resolved every ● selection to an
    ;; accessor for the actual slot, including implicit pointer traversal.

    (define (field-operation (path Path) (callee Expr)) (→ (Option Value))
      (match (● callee term)
        ((Var name _ evidence)
         (match (program-value (● path program) name)
           ((Some value) (if (field-value? value) (Some value) (None)))
           ((None) (None))))
        (_ (None))))

    (define (field-value? (value Value)) (→ Bool)
      (match value
        ((Accessor _ _ _) #t)
        ((Replacer _ _ _) #t)
        ((Setter _ _ _) #t)
        ((Swapper _ _ _) #t)
        (_ #f)))

    ;; What a field operation may not do with a linear value, given its
    ;; type at this use: read one, which would leave a second owner where
    ;; it was, or discard the one a setter or a replacement overwrites. A
    ;; replacement moves its record's other fields into its answer, and a
    ;; swapper moves the old content out, so neither duplicates anything.

    (define (check-field-grades (path Path) (operation Value) (type Type) (loc Loc))
      (→ Unit)
      (! compile)
      (match (Pair operation type)
        ((Pair (Accessor case index _) (TFun _ result _))
         (when (linear? path result)
           (compile-error loc (explain path result (linear-read-advice case index)))))
        ((Pair (Setter case index _) (TFun (Cons _ (Cons content _)) _ _))
         (when (linear? path content)
           (compile-error loc
                          (explain path
                                   content
                                   (string-append
                                    "setting a mutable field would discard its linear content; swap it out with "
                                    (swapper-name case index))))))
        ((Pair (Replacer _ _ _) (TFun (Cons _ (Cons content _)) _ _))
         (when (linear? path content)
           (compile-error loc
                          (explain path
                                   content
                                   "a replacement would discard its field's linear content; take the record apart with match"))))
        (_ (unit))))

    (define (linear-read-advice (case Case) (index I64)) (→ String)
      (string-append
       "reading a field would duplicate its linear content; destructure its owner or swap it out with "
       (swapper-name case index)))

    (define (swapper-name (case Case) (index I64)) (→ String)
      (string-append (short-name (● case name))
                     "-"
                     (● (list-ref (● case fields) index) name)
                     "-replace!"))

    ;; A field operation used as a value is checked as a call to it is, and
    ;; it consumes the record it is later applied to: on a linear record
    ;; that would leave the other fields with no owner, unless it is a
    ;; replacement, which answers them.

    (define (check-field-value (path Path) (operation Value) (expr Expr)) (→ Unit) (! compile)
      (check-field-grades path operation (● expr type) (● expr loc))
      (match (Pair operation (● expr type))
        ((Pair (Replacer _ _ _) _) (unit))
        ((Pair _ (TFun (Cons record _) _ _))
         (when (linear? path record)
           (compile-error (● expr loc)
                          (explain path
                                   record
                                   "apply a field operation to a linear record by name; as a value it would consume the record"))))
        (_ (unit))))

    ;; Each intermediate field is an ordinary value. A linear field cannot
    ;; be followed through an alias: another write could remove and finalize
    ;; it while the incoming expression runs. Move it out with replace!
    ;; first. A named linear root remains available in its own scope.

    (define (check-chain (path Path) (record Expr)) (→ Path) (! compile)
      (match (● record term)
        ((Ann inner _) (check-chain path inner))
        ((App callee (Cons inner (Nil)))
         (match (field-operation path callee)
           ((Some (Accessor case index scheme))
            (check-field-grades path (Accessor case index scheme) (● callee type) (● record loc))
            (check-chain path inner))
           (_ (check-place path record))))
        (_ (check-place path record))))

    ;; The record a field read reads from, when an expression is one.

    (define (chain-record (path Path) (expr Expr)) (→ (Option Expr))
      (match (● expr term)
        ((Ann inner _) (chain-record path inner))
        ((App callee (Cons record (Nil)))
         (match (field-operation path callee)
           ((Some (Accessor _ _ _)) (Some record))
           (_ (None))))
        (_ (None))))

    ;; A written place is addressed down to the cell it is in, whose
    ;; expression is checked; the checker proved the links are fields.

    (define (check-place-write (path Path) (place Expr) (value Expr)) (→ Path) (! compile)
      (match (chain-record path place)
        ((Some record) (check-field-write path record (list value)))
        ((None) (panic "internal error: a written place is a field"))))

    (define (check-field-write (path Path) (record Expr) (args (List Expr))) (→ Path) (! compile)
      (let ((after (check-all (check-chain path record) args)))
        (require-place-live after record)
        after))

    ;; The incoming value may consume other owners, but the receiver must
    ;; still exist when the write happens. This is an exactly-once check,
    ;; not a loan: Copy receivers may be freely aliased and mutated.
    (define (require-place-live (path Path) (record Expr)) (→ Unit) (! compile)
      (match (chain-record path record)
        ((Some inner) (require-place-live path inner))
        ((None)
         (match (● record term)
           ((Ann inner _) (require-place-live path inner))
           ((Var name _ _)
            (when (linear? path (● record type))
              (require-live path (Owner name (● record type)) (● record loc))))
           (_ (unit))))))

    ;; The place rule: a field operation reads or writes its record where it
    ;; is, so a linear local it is applied to stays live. A linear record
    ;; that is not a local has nowhere to stay, and its other fields would
    ;; be left with no owner.

    (define (check-place (path Path) (record Expr)) (→ Path) (! compile)
      (let ((type (● record type)))
        (if (linear? path type)
            (match (● record term)
              ((Var name _ _)
               (require-live path (Owner name type) (● record loc))
               path)
              (_ (compile-error (● record loc)
                                (explain path
                                         type
                                         "a field operation works on a linear record in place; bind the record to a name first"))))
            (check path record))))

    ;; A closure's body is a path of its own, which starts with the linear
    ;; names it captures and its linear parameters live, and must consume
    ;; them all. Creating the closure moves the captures into it. It
    ;; captures the live names it refers to; one consumed already is not
    ;; live in the body either, so the body's use of it is a second use.

    (define (check-lambda (path Path) (expr Expr)) (→ Path) (! compile)
      (let ((once? (match (callable-kind (● expr type))
                     ((Some "FnOnce") #t) (_ #f)))
            (captured (let ((references (expr-references expr)))
                        (filter (lambda (owner) (member? (● owner name) references))
                                (● path live))))
            (loc (● expr loc)))
        (match (Pair once? captured)
          ((Pair #f (Cons owner _))
           (compile-error loc
                          (explain path (● owner type)
                                   "a reusable procedure cannot capture a linear value; wrap it in Rc or use FnOnce")))
          (_ (unit)))
        (for-each (lambda (owner) (check-capture path owner (● expr type) loc)) captured)
        (check-closure-body path expr captured once?)
        (fold-left (lambda (path owner) (consume path owner loc)) path captured)))

    ;; The body starts with the captures and the linear parameters live, as
    ;; the only names in scope, and must consume them all.

    (define (check-closure-body (path Path) (expr Expr) (captured (List Owner)) (once? Bool))
      (→ Unit)
      (! compile)
      (match (Pair (● expr term) (fn-arrow (● expr type)))
        ((Pair (Lambda params body _) (TFun types _ row))
         (let* ((empty
                 (Path (● path program) (● path copy) (● path constraints) (Nil) #t (Some row)))
                (start
                 (fold-left
                  (lambda (inner pair) (bind inner (● pair first) (● pair second)))
                  (Path-live-set empty captured)
                  (zip params types))))
           (close-scope empty (check start body) (● expr loc))
           (unit)))
        (_ (panic "internal error: untyped closure"))))

    ;; A clause's pattern binds the fields it names. A wildcard cannot
    ;; discard a linear one.

    (define (check-clause (path Path) (clause Clause) (loc Loc)) (→ Path) (! compile)
      (let ((body (● clause body)))
        (close-scope path
                     (check (bind-pattern path (● clause pattern) loc) body)
                     (● body loc))))

    (define (bind-pattern (path Path) (pattern Pattern) (loc Loc)) (→ Path) (! compile)
      (match pattern
        ((PWild type)
         (when (linear? path type)
           (compile-error loc
                          (explain path
                                   type
                                   "a wildcard cannot discard a linear value; bind it and use it")))
         path)
        ((PVar name type) (bind path name type))
        ((PLit _ _) path)
        ((PCon constructor args _)
         (fold-left (lambda (path pair)
                      (bind-pattern path (● pair second) loc))
                    path (zip (constructor-fields path constructor) args)))))

    ;; A mutable position holds only `_`, which the checker requires, and it
    ;; may skip linear content: a shared record's other owners can still
    ;; swap it out, and a record consumed here abandons it, as a lost cell
    ;; abandons what it holds.

    (define (constructor-fields (path Path) (constructor String)) (→ (List Field))
      (match (program-value (● path program) constructor)
        ((Some (Constructor case _)) (● case fields))
        (_ (panic "internal error: a pattern names a constructor"))))

    (define (check-conversion (path Path) (expr Expr) (inner Expr) (target Type))
      (→ Path)
      (! compile)
      (when (or (linear? path (● inner type)) (linear? path target))
        (compile-error (● expr loc) "a linear value cannot cross a dynamic type boundary"))
      (check path inner))

    ;; A statement's value is discarded, so it cannot be linear.

    (define (check-discardable (path Path) (statement Expr)) (→ Unit) (! compile)
      (let ((type (● statement type)))
        (when (linear? path type)
          (compile-error (● statement loc)
                         (explain path type "a linear value cannot be discarded; drop it")))))

    ;; ---- Items ----

    ;; Each item is a path of its own, under the variables its scheme
    ;; declares ω, once its types are representable: no linear value is a
    ;; global, and a statement cannot discard one. An item's ownership is
    ;; its own, so one item's failure says nothing of another's.

    (define (check-item-ownership (program Program) (schemes (Table Scheme)) (item Item))
      (→ Unit)
      (! compile)
      (check-owned-types program schemes item)
      (check-item
       (Path program
             (item-copy schemes item)
             (item-constraints schemes item)
             (Nil)
             #t
             (item-row schemes item))
       item))

    ;; A definition's row bounds the drops its frames may run; a statement's
    ;; is unbounded.

    (define (item-row (schemes (Table Scheme)) (item Item)) (→ (Option Type))
      (match item
        ((Define name _)
         (match (table-ref schemes name)
           ((Some scheme) (arrow-row (● scheme type)))
           ((None) (None))))
        (_ (None))))

    (define (check-item (path Path) (item Item)) (→ Unit) (! compile)
      (match item
        ((Define _ value) (check path value) (unit))
        (_ (unit))))))

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
   check-boundary-type
   check-item-ownership
   consumed-references)
  (import
   (snail core base)
   (snail core table)
   (snail shell compiler read)
   (snail shell compiler core)
   (snail shell compiler capabilities))
  (begin

    (define no-loc (→ Loc) (Loc "ownership" 0 0))

    ;; ---- Representable ownership ----

    ;; A Vector or an Array holds only ω values, since reading one leaves
    ;; its element in place, and so does a Ref: a cell is shared, so nothing
    ;; would finalize linear content it still held. Other data moves its
    ;; fields out with `match`, so it may hold a linear value, and the
    ;; runtime's UnsafeSlot (snail shell slot) is the one shared place a
    ;; linear value rests between frames. `copy` names the type variables
    ;; declared ω.

    (define (check-type (program Program) (copy (List String)) (type Type) (loc Loc))
      (→ Unit)
      (! compile)
      (match type
        ((TCon "Borrow" _)
         (compile-error loc "a Borrow cannot escape into an owned type, result or storage"))
        ((TCon name args)
         (for-each (lambda (arg)
                     (when (and (member? name (list "Array" "Vector"))
                                (linear-type? program copy arg))
                       (compile-error loc
                                      (explain-type program
                                                    copy
                                                    arg
                                                    "a type argument must be unrestricted: a Vector or Array holds no linear value")))
                     (when (and (string=? name "snail.core.base:Ref")
                                (linear-type? program copy arg))
                       (compile-error loc
                                      (explain-type program
                                                    copy
                                                    arg
                                                    "a cell holds no linear value: own it in a frame or in the application's state")))
                     (check-type program copy arg loc)) args))
        ((TFun params result _)
         (for-each (lambda (param) (check-local-type program copy param loc)) params)
         (check-type program copy result loc))
        (_ (unit))))

    ;; A borrowed value is allowed only as a local or explicit parameter.
    ;; Its target is owned: there are no nested or stored Borrow values.

    (define (check-local-type (program Program) (copy (List String)) (type Type) (loc Loc))
      (→ Unit)
      (! compile)
      (check-type program copy (borrow-target type) loc))

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
                                                      (::params data)
                                                      (::type field)
                                                      no-loc))
                                        (::fields case)))
                            (::cases data))) (table-values (::types program))))

    ;; An item's types, with the variables its scheme declares ω.

    (define (check-owned-types (program Program) (schemes (Table Scheme)) (item Item))
      (→ Unit)
      (! compile)
      (match item
        ((Define name value)
         (check-type program (item-copy schemes item) (::type value) (::loc value))
         (when (linear-type? program (scheme-vars schemes name) (::type value))
           (compile-error (::loc value) "a linear value cannot be a global"))
         (check-expression-types program (item-copy schemes item) value))
        ((Do value) (check-expression-types program (Nil) value))
        (_ (unit))))

    ;; A global's own type variables. A polymorphic global's initializer
    ;; is total, so it holds no value of them, and its uses may share it.

    (define (scheme-vars (schemes (Table Scheme)) (name String)) (→ (List String))
      (match (table-ref schemes name)
        ((Some scheme) (::vars scheme))
        ((None) (Nil))))

    ;; The type variables an item's scheme declares ω.

    (define (item-copy (schemes (Table Scheme)) (item Item)) (→ (List String))
      (match item
        ((Define name _) (match (table-ref schemes name)
                           ((Some scheme) (::copy scheme))
                           ((None) (Nil))))
        (_ (Nil))))

    (define (item-constraints (schemes (Table Scheme)) (item Item)) (→ (List Constraint))
      (match item
        ((Define name _)
         (match (table-ref schemes name)
           ((Some scheme) (::constraints scheme)) ((None) (Nil))))
        (_ (Nil))))

    (define (check-expression-types (program Program) (copy (List String)) (expr Expr))
      (→ Unit)
      (! compile)
      (if (borrow-intrinsic? program expr)
          (match (::type expr)
            ((TFun params result _)
             (for-each (lambda (type) (check-local-type program copy type (::loc expr)))
                       (Cons result params)))
            (_ (panic "internal error: a borrow intrinsic is not a function")))
          (check-local-type program copy (::type expr) (::loc expr)))
      (for-each (lambda (child) (check-expression-types program copy child)) (expr-children expr)))

    ;; Only introduction and direct immutable projections may produce a
    ;; Borrow. They are compiler operations, never borrow-returning helpers.

    (define (borrow-intrinsic? (program Program) (expr Expr)) (→ Bool)
      (match (::term expr)
        ((Var name _ _)
         (or (string=? name "prim:borrow")
             (match (Pair
                     (field-operation (Path program (Nil) (Nil) (Nil) (Nil) (Nil) #t (None)) expr)
                     (::type expr))
               ((Pair (Some (Accessor _ _ _)) (TFun (Cons type _) _ _)) (borrow-type? type))
               (_ #f))))
        (_ #f)))

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
       (borrowed (List Owner))
       (exclusive (List String))
       (returns Bool)
       (row (Option Type))))

    ;; A live linear name, with the type that makes it linear, which a
    ;; diagnostic about it explains.
    (struct Owner
      ((name String)
       (type Type)))

    (define (linear? (path Path) (type Type)) (→ Bool)
      (linear-type? (::program path) (::copy path) type))

    (define (live? (path Path) (name String)) (→ Bool)
      (any? (lambda (owner) (string=? (::name owner) name)) (::live path)))

    (define (borrowed? (path Path) (name String)) (→ Bool)
      (any? (lambda (owner) (string=? (::name owner) name)) (::borrowed path)))

    ;; The same for a value on this path, under its definition's Copy.

    (define (explain (path Path) (type Type) (message String)) (→ String)
      (explain-type (::program path) (::copy path) type message))

    ;; Borrow aliases are reusable within their lexical scope. They share
    ;; its capture restriction; linear owners retain their once-only use.

    (define (bind (path Path) (name String) (type Type)) (→ Path)
      (cond ((borrow-type? type)
             (Path-borrowed-set path (Cons (Owner name type) (::borrowed path))))
            ((linear? path type) (Path-live-set path (Cons (Owner name type) (::live path))))
            (else path)))

    (define (consume (path Path) (owner Owner) (loc Loc)) (→ Path) (! compile)
      (when (borrowed? path (::name owner))
        (compile-error loc "an owner cannot be moved while it is borrowed"))
      (require-live path owner loc)
      (Path-live-set path
                     (filter (lambda (live) (not (string=? (::name live) (::name owner))))
                             (::live path))))

    (define (require-live (path Path) (owner Owner) (loc Loc)) (→ Unit) (! compile)
      (unless (live? path (::name owner))
        (compile-error loc
                       (explain path
                                (::type owner)
                                (string-append "linear value used more than once: "
                                               (local-name (::name owner)))))))

    ;; The end of a scope opened on `outer`: if the path returns, it has
    ;; consumed each linear name the scope bound.

    (define (close-scope (outer Path) (inner Path) (loc Loc)) (→ Path) (! compile)
      (let ((outside? (lambda (owner) (live? outer (::name owner)))))
        (match (filter (lambda (owner) (not (outside? owner))) (::live inner))
          ((Cons owner _)
           (when (::returns inner)
             (compile-error loc
                            (explain inner
                                     (::type owner)
                                     (string-append "linear value never consumed: "
                                                    (local-name (::name owner))
                                                    "; use it once, or drop it")))))
          ((Nil) (unit)))
        (Path-exclusive-set
         (Path-borrowed-set (Path-live-set inner (filter outside? (::live inner)))
                            (::borrowed outer)) (::exclusive outer))))

    ;; Alternatives start from one path. Those that return must leave the
    ;; same names live; if none returns, neither does the whole.

    (define (join (path Path) (branches (List Path)) (loc Loc)) (→ Path) (! compile)
      (match (filter ::returns branches)
        ((Cons first rest)
         (for-each (lambda (branch) (agree first branch loc)) rest)
         (Path-live-set path (::live first)))
        ((Nil) (Path-returns-set path #f))))

    (define (agree (one Path) (other Path) (loc Loc)) (→ Unit) (! compile)
      (for-each (lambda (owner)
                  (let ((name (::name owner)))
                    (unless (and (live? one name) (live? other name))
                      (compile-error loc
                                     (explain one
                                              (::type owner)
                                              (string-append
                                               "alternatives must consume the same linear values: "
                                               (local-name name)))))))
                (append (::live one) (::live other))))

    ;; ---- Expressions ----

    (define (check (path Path) (expr Expr)) (→ Path) (! compile)
      (let ((path (check-term path expr)))
        (if (never-type? (::type expr)) (Path-returns-set path #f) path)))

    (define (check-all (path Path) (exprs (List Expr))) (→ Path) (! compile)
      (fold-left check path exprs))

    (define (check-term (path Path) (expr Expr)) (→ Path) (! compile)
      (let ((loc (::loc expr)))
        (match (::term expr)
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
           (let* ((path (check-all path (map ::second implementations)))
                  (inner (match (::row path)
                           ((Some row) (Path-row-set path (Some (TRow (list effect) (Some row)))))
                           ((None) path))))
             ;; Cleanup in the body can use its installed handlers. A
             ;; handled abort may return even when the body does not.
             (Path-returns-set (Path-row-set (check inner body) (::row path))
                               (::returns path))))
          ((ScopedInstances _ _) (panic "internal error: instance scope survived checking"))
          ((Ann inner _)
           (when (match (callable-kind (::type expr)) ((Some "FnOnce") #t) (_ #f))
             (check-consuming-adaptation path (::type inner) (fn-arrow (::type expr)) loc))
           (check path inner))
          ((Convert inner target) (check-conversion path expr inner target))
          ((TryConvert _ _)
           (panic "internal error: try-convert must be lowered before ownership checking"))
          ((TypeTest inner target) (check-conversion path expr inner target)))))

    ;; A private borrow initializer opens a lexical loan. Every exit must
    ;; return owned data, and closing restores only loan metadata, keeping
    ;; any consumption of other owners performed by the body.

    (define (check-let (path Path) (name String) (value Expr) (body Expr) (loc Loc))
      (→ Path)
      (! compile)
      (match (::term value)
        ((App (Expr (Var "prim:borrow" _ _) _ _) (Cons owner (Nil)))
         (check-type (::program path) (::copy path) (::type body) (::loc body))
         (close-scope path (check (bind (lend path owner) name (::type value)) body) loc))
        (_ (let ((path (check path value)))
             (close-scope path (check (bind path name (::type value)) body) loc)))))

    ;; A use of a linear local consumes it. A global is shared, as nothing
    ;; linear is one.

    (define (check-reference (path Path) (expr Expr) (name String)) (→ Path) (! compile)
      (when (and (borrowed? path name) (linear? path (::type expr)))
        (compile-error (::loc expr) "an owner cannot be moved while it is borrowed"))
      (match (field-operation path expr)
        ((Some operation) (check-field-value path operation expr) path)
        ((None)
         (match (program-value (::program path) name)
           ((Some value) (check-instantiation path expr value) path)
           ((None)
            (if (linear? path (::type expr))
                (consume path (Owner name (::type expr)) (::loc expr))
                path))))))

    ;; `once` may move a lambda's linear captures into it. A panic never
    ;; returns. A field operation acts on its record in place.

    (define (check-call (path Path) (callee Expr) (args (List Expr))) (→ Path) (! compile)
      (match (Pair (::term callee) args)
        ((Pair (Var "prim:borrow" _ _) _)
         (compile-error (::loc callee) "a borrow must be introduced by with-borrow"))
        ((Pair (Var "prim:panic" _ _) _) (Path-returns-set (check-all path args) #f))
        ((Pair (Var "prim:set!" _ _) (Cons place (Cons value (Nil))))
         (check (check-place-root path place) value))
        ((Pair (Var "prim:replace!" _ _) (Cons place (Cons value (Nil))))
         (check (check-place-root path place) value))
        ((Pair (Var _ _ _) (Cons record rest))
         (match (field-operation path callee)
           ((Some operation)
            (check-field-grades path operation (::type callee) (::loc callee))
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

    ;; Borrow parameters receive already-scoped values. Calls never turn
    ;; an owner into a borrow implicitly, including higher-order calls.

    (define (check-ordinary-call (path Path) (callee Expr) (args (List Expr))) (→ Path) (! compile)
      (match (receiver-mode callee)
        ((Some mode)
         (if (or (string=? mode "FnMut")
                 (and (string=? mode "Fn") (linear? path (::type callee))))
             (check-receiver-call path callee args mode)
             (check-yield-holds (check-all path (Cons callee args)) callee)))
        ((None) (check-yield-holds (check-all path (Cons callee args)) callee))))

    (define (receiver-mode (callee Expr)) (→ (Option String))
      (match (invocation-mode callee)
        ((Some mode) (Some mode))
        ((None) (callable-kind (::type callee)))))

    (define (receiver-value (callee Expr)) (→ Expr)
      (match (::term callee)
        ((Ann inner (TCon "$invoke" _)) inner)
        (_ callee)))

    ;; The receiver stays owned by its lexical scope. Its loan lasts through
    ;; argument evaluation and the call, so the existing continuation rule
    ;; also refuses suspension that could outlive this owner. FnMut forbids
    ;; another use of the loaned root while its exclusive call is prepared.

    (define (check-receiver-call (path Path) (callee Expr) (args (List Expr)) (mode String))
      (→ Path)
      (! compile)
      (let* ((loan (lend path (receiver-value callee)))
             (owner (list-ref (::borrowed loan) 0)))
        (when (and (string=? mode "FnMut")
                   (or (and (borrowed? path (::name owner))
                            (not (member? (::name owner) (::exclusive path))))
                       (any? (lambda (arg) (member? (::name owner) (expr-references arg))) args)))
          (compile-error (::loc callee) "an FnMut call requires exclusive access to its receiver"))
        (Path-borrowed-set (check-yield-holds (check-all loan args) callee) (::borrowed path))))

    ;; Only a local or a path of immutable fields is a lendable place.
    ;; Mutable content can be replaced through an alias while later
    ;; arguments run, so it must first be read into an owned local.

    (define (lend (path Path) (value Expr)) (→ Path) (! compile)
      (match (::term value)
        ((Var name _ _)
         (when (borrow-type? (::type value))
           (compile-error (::loc value)
                          "alias a Borrow with let; with-borrow requires an owner"))
         (when (and (linear? path (::type value)) (not (borrowed? path name)))
           (require-live path (Owner name (::type value)) (::loc value)))
         (Path-borrowed-set path (Cons (Owner name (::type value)) (::borrowed path))))
        ((Ann inner _) (lend path inner))
        ((App callee (Cons record (Nil))) (lend-field path value callee record))
        (_ (compile-error (::loc value)
                          "a borrow must name a local owner or an immutable field path"))))

    (define (lend-field (path Path) (value Expr) (callee Expr) (record Expr)) (→ Path) (! compile)
      (match (field-operation path callee)
        ((Some (Accessor case index _))
         (when (::mutable? (list-ref (::fields case) index))
           (compile-error (::loc value) "a borrow cannot refer to mutable field storage"))
         (lend path record))
        (_ (compile-error (::loc value)
                          "a borrow must name a local owner or an immutable field path"))))

    ;; The references that move ownership into an expression. Field reads
    ;; borrow their place; a replacement consumes its record. Control uses
    ;; the same distinction when assigning owners to saved or aborted scopes.

    (define (consumed-references (program Program) (expr Expr)) (→ (List String))
      (match (::term expr)
        ((Var name _ _) (list name))
        ((Lambda params body _)
         (filter (lambda (name) (not (member? name params))) (expr-references body)))
        ((App (Expr (Var "prim:set!" _ _) _ _) (Cons _ (Cons value (Nil))))
         (consumed-references program value))
        ((App (Expr (Var "prim:borrow" _ _) _ _) _) (Nil))
        ((App (Expr (Var "prim:replace!" _ _) _ _) (Cons _ (Cons value (Nil))))
         (consumed-references program value))
        ((App (Expr (Ann _ (TCon "$invoke" (Cons (TCon mode (Nil)) _))) _ _) args)
         (if (string=? mode "FnOnce")
             (consumed-children program expr)
             (concatenate (map (lambda (arg) (consumed-references program arg)) args))))
        ((App callee (Cons record rest))
         (match (field-operation (Path program (Nil) (Nil) (Nil) (Nil) (Nil) #t (None)) callee)
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
         (or (any? (lambda (label) (control-effect? (::program path) label)) labels)
             (match tail
               ((Some _) #t)
               ((None) #f))))
        (_ #f)))

    (define (control-effect? (program Program) (label String)) (→ Bool)
      (match (table-ref (::effects program) label)
        ((Some effect) (not (null? (::control effect))))
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
           (match (lifecycle-rows (::program path) drop-class (::copy path) (Nil) type)
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
        (unless (null? (::borrowed path))
          (compile-error (::loc callee)
                         "a call cannot capture a continuation while a lexical borrow is active"))
        (for-each (lambda (owner)
                    (check-drop-rows path
                                     (::type owner)
                                     (::row path)
                                     (string-append (local-label (::name owner))
                                                    " is live across a call that may yield, so a dropped resume may drop it")
                                     (::loc callee)))
                  (::live path)))
      path)

    ;; Whether calling `callee` may yield. The checker opens each use of a
    ;; global to its context's row, so a global's own scheme says: its
    ;; labels, and its row variable at the type this use gave it. A selected
    ;; class instance supplies its own rows. A local's type says for itself.

    (define (callee-may-yield? (path Path) (callee Expr)) (→ Bool)
      (match (::term callee)
        ((Ann inner (TCon "$invoke" (Cons _ (Cons (TFun _ _ row) (Nil)))))
         (match (::type inner)
           ((TRigid _) (may-yield-row? path row))
           (_ (callee-may-yield? path inner))))
        ((Ann inner _) (callee-may-yield? path inner))
        ((Var name types evidence)
         (match (program-value (::program path) name)
           ((Some (Method class scheme))
            (scheme-may-yield? path scheme
                               (selected-method-arguments (::program path)
                                                          class
                                                          types
                                                          evidence)))
           ((Some value)
            (match (value-scheme value)
              ((Some scheme) (scheme-may-yield? path scheme types))
              ((None) (type-may-yield? path (::type callee)))))
           ((None) (type-may-yield? path (::type callee)))))
        (_ (type-may-yield? path (::type callee)))))

    (define (type-may-yield? (path Path) (type Type)) (→ Bool)
      (match (arrow-row type)
        ((Some row) (may-yield-row? path row))
        ((None) #f)))

    (define (scheme-may-yield? (path Path) (scheme Scheme) (types (List Type))) (→ Bool)
      (match (arrow-row (::type scheme))
        ((Some (TRow labels tail))
         (or (any? (lambda (label) (control-effect? (::program path) label)) labels)
             (match tail
               ((Some (TRigid var))
                (match (assoc-ref (zip (::vars scheme) types) var)
                  ((Some row) (may-yield-row? path row))
                  ((None) #t)))
               ((Some _) #t)
               ((None) #f))))
        (_ #f)))

    ;; Ordinary type variables range over owned values, even when they are
    ;; Copy. This prevents polymorphic code from hiding a Borrow in a
    ;; closure, container or opaque result. Explicit Borrow<T> helpers keep
    ;; T owned and their non-retention contract visible.
    ;;
    ;; A use of a generic function that may yield binds its type variables
    ;; to types it may hold across the yield. Only a definition or a method
    ;; has a body that could; a primitive, an operation or a constructor
    ;; holds nothing.

    (define (check-instantiation (path Path) (expr Expr) (value Value)) (→ Unit) (! compile)
      (match value
        ((Foreign _ _) (check-boundary-type (::type expr) (::loc expr)))
        (_ (unit)))
      (match (Pair (::term expr) (arrow-row (::type expr)))
        ((Pair (Var name types _) (Some row))
         (match (value-scheme value)
           ((Some scheme) (check-consuming-requirements path scheme types (::loc expr)))
           ((None) (unit)))
         (for-each (lambda (type)
                     (check-type (::program path) (::copy path) type (::loc expr))) types)
         (when (and (has-body? value) (callee-may-yield? path expr))
           (for-each (lambda (type)
                       (when (linear? path type)
                         (check-drop-rows path
                                          type
                                          (Some row)
                                          (string-append (short-name name)
                                                         " may hold a "
                                                         (type->string type)
                                                         " across a yield")
                                          (::loc expr))))
                     types)))
        (_ (unit))))

    ;; Fn -> FnOnce adaptation still calls through a receiver loan. Owning
    ;; the adapter is not a proof that a suspended loan can outlive it.

    (define (check-consuming-requirements (path Path) (scheme Scheme) (types (List Type)) (loc Loc))
      (→ Unit)
      (! compile)
      (for-each
       (lambda (requirement)
         (match (substitute-constraint (zip (::vars scheme) types) requirement)
           ((Constraint "snail.core.base:FnOnce" (Cons receiver (Cons signature (Nil))))
            (check-consuming-adaptation path receiver signature loc))
           (_ (unit))))
       (::constraints scheme)))

    (define (check-consuming-adaptation (path Path) (receiver Type) (signature Type) (loc Loc))
      (→ Unit)
      (! compile)
      (when (and (linear? path receiver) (shared-callable? path receiver)
                 (type-may-yield? path signature))
        (compile-error loc
                       "an owned shared or exclusive receiver cannot adapt to a suspending FnOnce call while its lexical borrow is active")))

    (define (shared-callable? (path Path) (receiver Type)) (→ Bool)
      (match (callable-kind receiver)
        ((Some kind) (member? kind (list "Fn" "FnMut")))
        ((None)
         (any? (lambda (requirement)
                 (and (member? (::class requirement)
                               (list (callable-class "Fn") (callable-class "FnMut")))
                      (type=? receiver (list-ref (::types requirement) 0))))
               (::constraints path)))))

    ;; Any and host code cannot enforce lexical scope. Check a foreign
    ;; reference, not just its calls, so aliasing cannot hide the boundary.

    (define (check-boundary-type (type Type) (loc Loc)) (→ Unit) (! compile)
      (match type
        ((TCon "Borrow" _)
         (compile-error loc "a Borrow cannot escape through an Any or host boundary"))
        ((TCon _ args) (for-each (lambda (arg) (check-boundary-type arg loc)) args))
        ((TFun params result _)
         (for-each (lambda (arg) (check-boundary-type arg loc)) (Cons result params)))
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
         (if (ground-type? (::type owner))
             (check-drop-rows path
                              (::type owner)
                              (Some row)
                              (string-append "a once lambda captures "
                                             (local-label (::name owner))
                                             ", which it drops if it is dropped unrun")
                              loc)
             (match (::row path)
               ((Some enclosing)
                (unless (row-within? enclosing row)
                  (compile-error loc
                                 (string-append "a once lambda captures "
                                                (local-label (::name owner))
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
    ;; setter or a swapper, or a field path read through a struct's own
    ;; instance, which is that field's accessor. A path read through a
    ;; requirement is an ordinary call: it consumes a linear record.

    (define (field-operation (path Path) (callee Expr)) (→ (Option Value))
      (match (::term callee)
        ((Var name _ evidence)
         (match (program-value (::program path) name)
           ((Some (Method class _))
            (if (field-class? class) (field-method-operation path class evidence) (None)))
           ((Some value) (if (field-value? value) (Some value) (None)))
           ((None) (None))))
        (_ (None))))

    (define (field-method-operation (path Path) (class String) (evidence (List Evidence)))
      (→ (Option Value))
      (match evidence
        ((Cons (EvInstance instance _ _) _)
         (field-instance-accessor (::program path) class instance))
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
      (if (::mutable? (list-ref (::fields case) index))
          (string-append
           "reading a mutable field would duplicate its linear content; swap it out with "
           (swapper-name case index))
          "destructure a linear record with match to move its linear field out"))

    (define (swapper-name (case Case) (index I64)) (→ String)
      (string-append (short-name (::name case))
                     "-"
                     (::name (list-ref (::fields case) index))
                     "-replace!"))

    ;; A field operation used as a value is checked as a call to it is, and
    ;; it consumes the record it is later applied to: on a linear record
    ;; that would leave the other fields with no owner, unless it is a
    ;; replacement, which answers them.

    (define (check-field-value (path Path) (operation Value) (expr Expr)) (→ Unit) (! compile)
      (check-field-grades path operation (::type expr) (::loc expr))
      (match (Pair operation (::type expr))
        ((Pair (Replacer _ _ _) _) (unit))
        ((Pair _ (TFun (Cons record _) _ _))
         (when (linear? path record)
           (compile-error (::loc expr)
                          (explain path
                                   record
                                   "apply a field operation to a linear record by name; as a value it would consume the record"))))
        (_ (unit))))

    ;; A chain of field reads, `(::x (::from s))` or `(::live (ref-get r))`,
    ;; copies one value, the last field, out of the record at its root:
    ;; the fields along the way are addressed, not read, so their grades
    ;; do not matter, and only the outermost read's result is checked. The
    ;; root is the record of the innermost read.

    (define (check-chain (path Path) (record Expr)) (→ Path) (! compile)
      (match (chain-record path record)
        ((Some inner) (check-chain path inner))
        ((None) (check-place path record))))

    ;; The record a field read reads from, when an expression is one.

    (define (chain-record (path Path) (expr Expr)) (→ (Option Expr))
      (match (::term expr)
        ((Ann inner _) (chain-record path inner))
        ((App callee (Cons record (Nil)))
         (match (field-operation path callee)
           ((Some (Accessor _ _ _)) (Some record))
           (_ (None))))
        (_ (None))))

    ;; A written place is addressed down to the cell it is in, whose
    ;; expression is checked; the checker proved the links are fields.

    (define (check-place-root (path Path) (place Expr)) (→ Path) (! compile)
      (match (chain-record path place)
        ((Some inner) (check-place-root path inner))
        ((None)
         (check-write-loan path place)
         (match (::term place)
           ((Var name _ _) (if (member? name (::exclusive path)) path (check path place)))
           (_ (check path place))))))

    (define (check-field-write (path Path) (record Expr) (args (List Expr))) (→ Path) (! compile)
      (check-write-loan path record)
      (check-all (check-chain path record) args))

    ;; Shared captured owners are read-only. An FnMut body gets exclusive
    ;; access to its captures without gaining permission to move them out.

    (define (check-write-loan (path Path) (record Expr)) (→ Unit) (! compile)
      (match (chain-record path record)
        ((Some inner) (check-write-loan path inner))
        ((None)
         (match (::term record)
           ((Var name _ _)
            (when (and (borrowed? path name) (not (member? name (::exclusive path))))
              (compile-error (::loc record)
                             "mutating an owned capture requires an FnMut receiver")))
           (_ (unit))))))

    ;; The place rule: a field operation reads or writes its record where it
    ;; is, so a linear local it is applied to stays live. A linear record
    ;; that is not a local has nowhere to stay, and its other fields would
    ;; be left with no owner.

    (define (check-place (path Path) (record Expr)) (→ Path) (! compile)
      (let ((type (::type record)))
        (if (linear? path type)
            (match (::term record)
              ((Var name _ _)
               (unless (borrowed? path name)
                 (require-live path (Owner name type) (::loc record)))
               path)
              (_ (compile-error (::loc record)
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
      (when (any? (lambda (owner) (member? (::name owner) (expr-references expr)))
                  (::borrowed path))
        (compile-error (::loc expr)
                       "a closure cannot capture a Borrow or a frozen owner"))
      (let ((once? (match (callable-kind (::type expr))
                     ((Some "FnOnce") #t) (_ #f)))
            (captured (let ((references (expr-references expr)))
                        (filter (lambda (owner) (member? (::name owner) references))
                                (::live path))))
            (loc (::loc expr)))
        (match (Pair once? captured)
          ((Pair #f (Cons owner _))
           (unless (concrete-callable? (::type expr))
             (compile-error loc
                            (explain path
                                     (::type owner)
                                     "an unrestricted procedure cannot capture a linear value"))))
          (_ (unit)))
        (for-each (lambda (owner) (check-capture path owner (::type expr) loc)) captured)
        (check-closure-body path expr captured once?)
        (fold-left (lambda (path owner) (consume path owner loc)) path captured)))

    ;; The body starts with the captures and the linear parameters live, as
    ;; the only names in scope, and must consume them all.

    (define (check-closure-body (path Path) (expr Expr) (captured (List Owner)) (once? Bool))
      (→ Unit)
      (! compile)
      (match (Pair (::term expr) (fn-arrow (::type expr)))
        ((Pair (Lambda params body _) (TFun types _ row))
         (let* ((empty (Path (::program path)
                             (::copy path)
                             (::constraints path)
                             (Nil)
                             (Nil)
                             (Nil)
                             #t
                             (Some row)))
                (start
                 (fold-left
                  (lambda (inner pair) (bind inner (::first pair) (::second pair)))
                  (if once? (Path-live-set empty captured)
                      (Path-exclusive-set
                       (Path-borrowed-set empty captured)
                       (match (callable-kind (::type expr))
                         ((Some "FnMut") (map ::name captured)) (_ (Nil)))))
                  (zip params types))))
           (close-scope empty (check start body) (::loc expr))
           (unit)))
        (_ (panic "internal error: untyped closure"))))

    ;; A clause's pattern binds the fields it names. A wildcard cannot
    ;; discard a linear one.

    (define (check-clause (path Path) (clause Clause) (loc Loc)) (→ Path) (! compile)
      (let ((body (::body clause)))
        (close-scope path
                     (check (bind-pattern path (::pattern clause) loc) body)
                     (::loc body))))

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
                      (if (::mutable? (::first pair))
                          path
                          (bind-pattern path (::second pair) loc)))
                    path (zip (constructor-fields path constructor) args)))))

    ;; A mutable position holds only `_`, which the checker requires, and it
    ;; may skip linear content: a shared record's other owners can still
    ;; swap it out, and a record consumed here abandons it, as a lost cell
    ;; abandons what it holds.

    (define (constructor-fields (path Path) (constructor String)) (→ (List Field))
      (match (program-value (::program path) constructor)
        ((Some (Constructor case _)) (::fields case))
        (_ (panic "internal error: a pattern names a constructor"))))

    (define (check-conversion (path Path) (expr Expr) (inner Expr) (target Type))
      (→ Path)
      (! compile)
      (when (or (linear? path (::type inner)) (linear? path target))
        (compile-error (::loc expr) "a linear value cannot cross a dynamic type boundary"))
      (check path inner))

    ;; A statement's value is discarded, so it cannot be linear.

    (define (check-discardable (path Path) (statement Expr)) (→ Unit) (! compile)
      (let ((type (::type statement)))
        (when (linear? path type)
          (compile-error (::loc statement)
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
             (Nil)
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
           ((Some scheme) (arrow-row (::type scheme)))
           ((None) (None))))
        (_ (None))))

    (define (check-item (path Path) (item Item)) (→ Unit) (! compile)
      (match item
        ((Define _ value) (check path value) (unit))
        ((Do value) (check-discardable path value) (check path value) (unit))
        (_ (unit))))))

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
   check-item-ownership)
  (import
   (snail core base)
   (snail core table)
   (snail shell compiler read)
   (snail shell compiler core)
   (snail shell compiler capabilities))
  (begin

    (: no-loc Loc)
    (define no-loc (Loc "ownership" 0 0))

    ;; ---- Representable ownership ----

    ;; A Vector or an Array holds only ω values, since reading one leaves
    ;; its element in place, and so does a Ref: a cell is shared, so nothing
    ;; would finalize linear content it still held. Other data moves its
    ;; fields out with `match`, so it may hold a linear value, and the
    ;; runtime's UnsafeSlot (snail shell slot) is the one shared place a
    ;; linear value rests between frames. `copy` names the type variables
    ;; declared ω.
    (: check-type (-> Program (List String) Type Loc Unit ! compile))
    (define (check-type program copy type loc)
      (match type
        ((TCon "FnOnce" (Cons (TFun params result _) (Nil)))
         (for-each (lambda (part) (check-type program copy part loc)) (Cons result params)))
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
         (for-each (lambda (part) (check-type program copy part loc)) (Cons result params)))
        (_ (unit))))

    ;; A message about a value of a linear type, with the Copy that would
    ;; have made the type unrestricted, if one would.
    (: explain-type (-> Program (List String) Type String String))
    (define (explain-type program copy type message)
      (match (missing-copy program copy type)
        ((Nil) message)
        (names
         (string-append message
                        " (its type is linear unless the definition requires "
                        (copy-declaration names)
                        ")"))))

    ;; A declaration's fields are checked with its parameters ω, since they
    ;; are checked where the declaration is used.
    (: check-owned-fields (-> Program Unit ! compile))
    (define (check-owned-fields program)
      (for-each (lambda (data)
                  (for-each (lambda (case)
                              (for-each (lambda (field)
                                          (check-type program
                                                      (DataType-params data)
                                                      (Field-type field)
                                                      no-loc))
                                        (Case-fields case)))
                            (DataType-cases data))) (table-values (Program-types program))))

    ;; An item's types, with the variables its scheme declares ω.
    (: check-owned-types (-> Program (Table Scheme) Item Unit ! compile))
    (define (check-owned-types program schemes item)
      (match item
        ((Define name value)
         (when (linear-type? program (scheme-vars schemes name) (Expr-type value))
           (compile-error (Expr-loc value) "a linear value cannot be a global"))
         (check-expression-types program (item-copy schemes item) value))
        ((Do value) (check-expression-types program (Nil) value))
        (_ (unit))))

    ;; A global's own type variables. A polymorphic global's initializer
    ;; is total, so it holds no value of them, and its uses may share it.
    (: scheme-vars (-> (Table Scheme) String (List String)))
    (define (scheme-vars schemes name)
      (match (table-ref schemes name)
        ((Some scheme) (Scheme-vars scheme))
        ((None) (Nil))))

    ;; The type variables an item's scheme declares ω.
    (: item-copy (-> (Table Scheme) Item (List String)))
    (define (item-copy schemes item)
      (match item
        ((Define name _) (match (table-ref schemes name)
                           ((Some scheme) (Scheme-copy scheme))
                           ((None) (Nil))))
        (_ (Nil))))

    (: check-expression-types (-> Program (List String) Expr Unit ! compile))
    (define (check-expression-types program copy expr)
      (check-type program copy (Expr-type expr) (Expr-loc expr))
      (for-each (lambda (child) (check-expression-types program copy child)) (expr-children expr)))

    ;; ---- Paths ----

    ;; One path through a body, as far as the check has followed it: the
    ;; type variables the body's scheme declares ω, the linear names still
    ;; live on it, and whether it can still return.
    ;; Names are unique, so a name's liveness needs no scoping. A path that
    ;; reaches a panic or a value of type Never cannot return, so it never
    ;; reaches the end of a scope: what it leaves live is abandoned, as a
    ;; dropped `resume` abandons its frames.
    (struct Path
      ((program Program)
       (copy (List String))
       (live (List Owner))
       (returns Bool)))

    ;; A live linear name, with the type that makes it linear, which a
    ;; diagnostic about it explains.
    (struct Owner
      ((name String)
       (type Type)))

    (: linear? (-> Path Type Bool))
    (define (linear? path type)
      (linear-type? (Path-program path) (Path-copy path) type))

    (: live? (-> Path String Bool))
    (define (live? path name)
      (any? (lambda (owner) (string=? (Owner-name owner) name)) (Path-live path)))

    ;; The same for a value on this path, under its definition's Copy.
    (: explain (-> Path Type String String))
    (define (explain path type message)
      (explain-type (Path-program path) (Path-copy path) type message))

    ;; A linear name is live from its binding until it is consumed.
    (: bind (-> Path String Type Path))
    (define (bind path name type)
      (if (linear? path type) (Path-live-set path (Cons (Owner name type) (Path-live path))) path))

    (: consume (-> Path Owner Loc Path ! compile))
    (define (consume path owner loc)
      (require-live path owner loc)
      (Path-live-set path
                     (filter (lambda (live) (not (string=? (Owner-name live) (Owner-name owner))))
                             (Path-live path))))

    (: require-live (-> Path Owner Loc Unit ! compile))
    (define (require-live path owner loc)
      (unless (live? path (Owner-name owner))
        (compile-error loc
                       (explain path
                                (Owner-type owner)
                                (string-append "linear value used more than once: "
                                               (local-name (Owner-name owner)))))))

    ;; The end of a scope opened on `outer`: if the path returns, it has
    ;; consumed each linear name the scope bound.
    (: close-scope (-> Path Path Loc Path ! compile))
    (define (close-scope outer inner loc)
      (let ((outside? (lambda (owner) (live? outer (Owner-name owner)))))
        (match (filter (lambda (owner) (not (outside? owner))) (Path-live inner))
          ((Cons owner _)
           (when (Path-returns inner)
             (compile-error loc
                            (explain inner
                                     (Owner-type owner)
                                     (string-append "linear value never consumed: "
                                                    (local-name (Owner-name owner))
                                                    "; use it once, or drop it")))))
          ((Nil) (unit)))
        (Path-live-set inner (filter outside? (Path-live inner)))))

    ;; Alternatives start from one path. Those that return must leave the
    ;; same names live; if none returns, neither does the whole.
    (: join (-> Path (List Path) Loc Path ! compile))
    (define (join path branches loc)
      (match (filter Path-returns branches)
        ((Cons first rest)
         (for-each (lambda (branch) (agree first branch loc)) rest)
         (Path-live-set path (Path-live first)))
        ((Nil) (Path-returns-set path #f))))

    (: agree (-> Path Path Loc Unit ! compile))
    (define (agree one other loc)
      (for-each (lambda (owner)
                  (let ((name (Owner-name owner)))
                    (unless (and (live? one name) (live? other name))
                      (compile-error loc
                                     (explain one
                                              (Owner-type owner)
                                              (string-append
                                               "alternatives must consume the same linear values: "
                                               (local-name name)))))))
                (append (Path-live one) (Path-live other))))

    ;; ---- Expressions ----

    (: check (-> Path Expr Path ! compile))
    (define (check path expr)
      (let ((path (check-term path expr)))
        (if (never-type? (Expr-type expr)) (Path-returns-set path #f) path)))

    (: check-all (-> Path (List Expr) Path ! compile))
    (define (check-all path exprs)
      (fold-left check path exprs))

    (: check-term (-> Path Expr Path ! compile))
    (define (check-term path expr)
      (let ((loc (Expr-loc expr)))
        (match (Expr-term expr)
          ((Lit _) path)
          ((Var name _ _) (check-reference path expr name))
          ((Lambda _ _ _) (check-lambda path expr #f))
          ((App callee args) (check-call path callee args))
          ((If test then otherwise)
           (let ((path (check path test)))
             (join path (list (check path then) (check path otherwise)) loc)))
          ((Let name value body)
           (let ((path (check path value)))
             (close-scope path (check (bind path name (Expr-type value)) body) loc)))
          ((Seq first rest)
           (check-discardable path first)
           (check (check path first) rest))
          ((Match value clauses)
           (let ((path (check path value)))
             (join path (map (lambda (clause) (check-clause path clause loc)) clauses) loc)))
          ((Handle _ implementations body)
           (check (check-all path (map Pair-second implementations)) body))
          ((Ann inner _) (check path inner))
          ((Convert inner target) (check-conversion path expr inner target))
          ((TypeTest inner target) (check-conversion path expr inner target)))))

    ;; A use of a linear local consumes it. A global is shared, as nothing
    ;; linear is one.
    (: check-reference (-> Path Expr String Path ! compile))
    (define (check-reference path expr name)
      (match (field-operation path expr)
        ((Some operation) (check-field-value path operation expr) path)
        ((None)
         (match (program-value (Path-program path) name)
           ((Some _) path)
           ((None)
            (if (linear? path (Expr-type expr))
                (consume path (Owner name (Expr-type expr)) (Expr-loc expr))
                path))))))

    ;; `once` may move a lambda's linear captures into it. A panic never
    ;; returns. A field operation acts on its record in place.
    (: check-call (-> Path Expr (List Expr) Path ! compile))
    (define (check-call path callee args)
      (match (Pair (Expr-term callee) args)
        ((Pair (Var "prim:once" _ _) (Cons value (Nil)))
         (if (lambda-expr? value) (check-lambda path value #t) (check path value)))
        ((Pair (Var "prim:panic" _ _) _) (Path-returns-set (check-all path args) #f))
        ((Pair (Var "prim:set!" _ _) (Cons place (Cons value (Nil))))
         (check (check-place-root path place) value))
        ((Pair (Var "prim:replace!" _ _) (Cons place (Cons value (Nil))))
         (check (check-place-root path place) value))
        ((Pair (Var _ _ _) (Cons record rest))
         (match (field-operation path callee)
           ((Some operation)
            (check-field-grades path operation (Expr-type callee) (Expr-loc callee))
            (match operation
              ;; A replacement answers its record with the field replaced, so
              ;; it consumes the record, after its other operand, which may
              ;; read the record in place.
              ((Replacer _ _ _) (check (check-all path rest) record))
              (_ (check-all (check-chain path record) rest))))
           ((None) (check-all path (Cons callee args)))))
        (_ (check-all path (Cons callee args)))))

    ;; ---- Fields ----

    ;; The value a callee denotes when it is an accessor, a replacement, a
    ;; setter or a swapper, or a field path read through a struct's own
    ;; instance, which is that field's accessor. A path read through a
    ;; requirement is an ordinary call: it consumes a linear record.
    (: field-operation (-> Path Expr (Option Value)))
    (define (field-operation path callee)
      (match (Expr-term callee)
        ((Var name _ evidence)
         (match (program-value (Path-program path) name)
           ((Some (Method class _))
            (if (field-class? class) (field-method-operation path class evidence) (None)))
           ((Some value) (if (field-value? value) (Some value) (None)))
           ((None) (None))))
        (_ (None))))

    (: field-method-operation (-> Path String (List Evidence) (Option Value)))
    (define (field-method-operation path class evidence)
      (match evidence
        ((Cons (EvInstance instance _ _) _)
         (field-instance-accessor (Path-program path) class instance))
        (_ (None))))

    (: field-value? (-> Value Bool))
    (define (field-value? value)
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
    (: check-field-grades (-> Path Value Type Loc Unit ! compile))
    (define (check-field-grades path operation type loc)
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

    (: linear-read-advice (-> Case I64 String))
    (define (linear-read-advice case index)
      (if (Field-mutable? (list-ref (Case-fields case) index))
          (string-append
           "reading a mutable field would duplicate its linear content; swap it out with "
           (swapper-name case index))
          "destructure a linear record with match to move its linear field out"))

    (: swapper-name (-> Case I64 String))
    (define (swapper-name case index)
      (string-append (short-name (Case-name case))
                     "-"
                     (Field-name (list-ref (Case-fields case) index))
                     "-replace!"))

    ;; A field operation used as a value is checked as a call to it is, and
    ;; it consumes the record it is later applied to: on a linear record
    ;; that would leave the other fields with no owner, unless it is a
    ;; replacement, which answers them.
    (: check-field-value (-> Path Value Expr Unit ! compile))
    (define (check-field-value path operation expr)
      (check-field-grades path operation (Expr-type expr) (Expr-loc expr))
      (match (Pair operation (Expr-type expr))
        ((Pair (Replacer _ _ _) _) (unit))
        ((Pair _ (TFun (Cons record _) _ _))
         (when (linear? path record)
           (compile-error (Expr-loc expr)
                          (explain path
                                   record
                                   "apply a field operation to a linear record by name; as a value it would consume the record"))))
        (_ (unit))))

    ;; A chain of field reads, `(::x (::from s))` or `(::live (ref-get r))`,
    ;; copies one value, the last field, out of the record at its root:
    ;; the fields along the way are addressed, not read, so their grades
    ;; do not matter, and only the outermost read's result is checked. The
    ;; root is the record of the innermost read.
    (: check-chain (-> Path Expr Path ! compile))
    (define (check-chain path record)
      (match (chain-record path record)
        ((Some inner) (check-chain path inner))
        ((None) (check-place path record))))

    ;; The record a field read reads from, when an expression is one.
    (: chain-record (-> Path Expr (Option Expr)))
    (define (chain-record path expr)
      (match (Expr-term expr)
        ((Ann inner _) (chain-record path inner))
        ((App callee (Cons record (Nil)))
         (match (field-operation path callee)
           ((Some (Accessor _ _ _)) (Some record))
           (_ (None))))
        (_ (None))))

    ;; A written place is addressed down to the cell it is in, whose
    ;; expression is checked; the checker proved the links are fields.
    (: check-place-root (-> Path Expr Path ! compile))
    (define (check-place-root path place)
      (match (chain-record path place)
        ((Some inner) (check-place-root path inner))
        ((None) (check path place))))

    ;; The place rule: a field operation reads or writes its record where it
    ;; is, so a linear local it is applied to stays live. A linear record
    ;; that is not a local has nowhere to stay, and its other fields would
    ;; be left with no owner.
    (: check-place (-> Path Expr Path ! compile))
    (define (check-place path record)
      (let ((type (Expr-type record)))
        (if (linear? path type)
            (match (Expr-term record)
              ((Var name _ _) (require-live path (Owner name type) (Expr-loc record)) path)
              (_ (compile-error (Expr-loc record)
                                (explain path
                                         type
                                         "a field operation works on a linear record in place; bind the record to a name first"))))
            (check path record))))

    ;; A closure's body is a path of its own, which starts with the linear
    ;; names it captures and its linear parameters live, and must consume
    ;; them all. Creating the closure moves the captures into it. It
    ;; captures the live names it refers to; one consumed already is not
    ;; live in the body either, so the body's use of it is a second use.
    (: check-lambda (-> Path Expr Bool Path ! compile))
    (define (check-lambda path expr once?)
      (let ((captured (let ((references (expr-references expr)))
                        (filter (lambda (owner) (member? (Owner-name owner) references))
                                (Path-live path))))
            (loc (Expr-loc expr)))
        (match (Pair once? captured)
          ((Pair #f (Cons owner _))
           (compile-error loc
                          (explain path
                                   (Owner-type owner)
                                   "an unrestricted procedure cannot capture a linear value")))
          (_ (check-closure-body path expr captured)
             (fold-left (lambda (path owner) (consume path owner loc)) path captured)))))

    ;; The body starts with the captures and the linear parameters live, as
    ;; the only names in scope, and must consume them all.
    (: check-closure-body (-> Path Expr (List Owner) Unit ! compile))
    (define (check-closure-body path expr captured)
      (match (Pair (Expr-term expr) (fn-arrow (Expr-type expr)))
        ((Pair (Lambda params body _) (TFun types _ _))
         (let* ((empty (Path (Path-program path) (Path-copy path) (Nil) #t))
                (start
                 (fold-left (lambda (inner pair) (bind inner (Pair-first pair) (Pair-second pair)))
                            (Path-live-set empty captured)
                            (zip params types))))
           (close-scope empty (check start body) (Expr-loc expr))
           (unit)))
        (_ (panic "internal error: untyped closure"))))

    ;; A clause's pattern binds the fields it names. A wildcard cannot
    ;; discard a linear one.
    (: check-clause (-> Path Clause Loc Path ! compile))
    (define (check-clause path clause loc)
      (let ((body (Clause-body clause)))
        (close-scope path
                     (check (bind-pattern path (Clause-pattern clause) loc) body)
                     (Expr-loc body))))

    (: bind-pattern (-> Path Pattern Loc Path ! compile))
    (define (bind-pattern path pattern loc)
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
                      (if (Field-mutable? (Pair-first pair))
                          path
                          (bind-pattern path (Pair-second pair) loc)))
                    path (zip (constructor-fields path constructor) args)))))

    ;; A mutable position holds only `_`, which the checker requires, and it
    ;; may skip linear content: a shared record's other owners can still
    ;; swap it out, and a record consumed here abandons it, as a lost cell
    ;; abandons what it holds.
    (: constructor-fields (-> Path String (List Field)))
    (define (constructor-fields path constructor)
      (match (program-value (Path-program path) constructor)
        ((Some (Constructor case _)) (Case-fields case))
        (_ (panic "internal error: a pattern names a constructor"))))

    (: check-conversion (-> Path Expr Expr Type Path ! compile))
    (define (check-conversion path expr inner target)
      (when (or (linear? path (Expr-type inner)) (linear? path target))
        (compile-error (Expr-loc expr) "a linear value cannot cross a dynamic type boundary"))
      (check path inner))

    ;; A statement's value is discarded, so it cannot be linear.
    (: check-discardable (-> Path Expr Unit ! compile))
    (define (check-discardable path statement)
      (let ((type (Expr-type statement)))
        (when (linear? path type)
          (compile-error (Expr-loc statement)
                         (explain path type "a linear value cannot be discarded; drop it")))))

    ;; ---- Items ----

    ;; Each item is a path of its own, under the variables its scheme
    ;; declares ω, once its types are representable: no linear value is a
    ;; global, and a statement cannot discard one. An item's ownership is
    ;; its own, so one item's failure says nothing of another's.
    (: check-item-ownership (-> Program (Table Scheme) Item Unit ! compile))
    (define (check-item-ownership program schemes item)
      (check-owned-types program schemes item)
      (check-item (Path program (item-copy schemes item) (Nil) #t) item))

    (: check-item (-> Path Item Unit ! compile))
    (define (check-item path item)
      (match item
        ((Define _ value) (check path value) (unit))
        ((Do value) (check-discardable path value) (check path value) (unit))
        (_ (unit))))))

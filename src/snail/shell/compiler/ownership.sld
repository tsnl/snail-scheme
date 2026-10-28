;; Linear values are used exactly once on every path that returns. This
;; check follows each path through a checked body: a use of a linear name
;; consumes it, a second use is an error, and so is a name still live at
;; the end of the scope that bound it; alternatives must consume the same
;; names. It inserts nothing. A value is released by a call someone wrote,
;; such as `drop` or `call-once`, or by a match that moves its fields out.
;; Ordinary arrows stay unrestricted; only an immediate `once` lambda may
;; move linear captures into its environment.
(define-library (snail shell compiler ownership)
  (export check-ownership check-owned-types)
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

    (: check-type (-> Program Type Loc Unit ! compile))
    (define (check-type program type loc)
      (match type
        ((TCon "Once" args)
         (match args
           ((Cons (TFun params result _) (Nil))
            (for-each (lambda (part) (check-type program part loc)) (Cons result params)))
           (_ (compile-error loc "Once requires a procedure type"))))
        ((TCon _ args)
         (for-each (lambda (arg)
                     (when (linear-type? program arg)
                       (compile-error loc
                                      "a type argument must be unrestricted; use a concrete linear field"))
                     (check-type program arg loc)) args))
        ((TFun params result _)
         (for-each (lambda (part) (check-type program part loc)) (Cons result params)))
        (_ (unit))))

    (: check-owned-types (-> Program (List Item) Unit ! compile))
    (define (check-owned-types program items)
      (for-each (lambda (data)
                  (for-each (lambda (case)
                              (for-each
                               (lambda (field) (check-type program (Field-type field) no-loc))
                               (Case-fields case)))
                            (DataType-cases data))) (table-values (Program-types program)))
      (for-each (lambda (item)
                  (match item
                    ((Define _ value)
                     (when (linear-type? program (Expr-type value))
                       (compile-error (Expr-loc value) "a linear value cannot be a global"))
                     (check-expression-types program value))
                    ((Do value) (check-expression-types program value))
                    (_ (unit)))) items))

    (: check-expression-types (-> Program Expr Unit ! compile))
    (define (check-expression-types program expr)
      (check-type program (Expr-type expr) (Expr-loc expr))
      (for-each (lambda (child) (check-expression-types program child)) (children expr)))

    (: children (-> Expr (List Expr)))
    (define (children expr)
      (match (Expr-term expr)
        ((Lambda _ body) (list body))
        ((App callee args) (Cons callee args))
        ((If test then otherwise) (list test then otherwise))
        ((Let _ value body) (list value body))
        ((Seq first rest) (list first rest))
        ((Match value clauses) (Cons value (map Clause-body clauses)))
        ((Handle _ implementations body) (append (map Pair-second implementations) (list body)))
        ((Ann inner _) (list inner))
        ((Convert inner _) (list inner))
        ((TypeTest inner _) (list inner))
        (_ (Nil))))

    ;; ---- Paths ----

    ;; One path through a body, as far as the check has followed it: the
    ;; linear names still live on it, and whether it can still return.
    ;; Names are unique, so a name's liveness needs no scoping. A path that
    ;; reaches a panic or a value of type Never cannot return, so it never
    ;; reaches the end of a scope: what it leaves live is abandoned, as a
    ;; dropped `resume` abandons its frames.
    (struct Path
      ((program Program)
       (live (List String))
       (returns Bool)))

    (: linear? (-> Path Type Bool))
    (define (linear? path type)
      (linear-type? (Path-program path) type))

    ;; A linear name is live from its binding until it is consumed.
    (: bind (-> Path String Type Path))
    (define (bind path name type)
      (if (linear? path type) (Path-live-set path (Cons name (Path-live path))) path))

    (: consume (-> Path String Loc Path ! compile))
    (define (consume path name loc)
      (unless (member? name (Path-live path))
        (compile-error loc (string-append "linear value used more than once: " (local-name name))))
      (Path-live-set path (filter (lambda (live) (not (string=? live name))) (Path-live path))))

    ;; The end of a scope opened on `outer`: if the path returns, it has
    ;; consumed each linear name the scope bound.
    (: close-scope (-> Path Path Loc Path ! compile))
    (define (close-scope outer inner loc)
      (let ((outside? (lambda (name) (member? name (Path-live outer)))))
        (match (filter (lambda (name) (not (outside? name))) (Path-live inner))
          ((Cons name _)
           (when (Path-returns inner)
             (compile-error loc
                            (string-append "linear value never consumed: "
                                           (local-name name)
                                           "; use it once, or drop it"))))
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
      (for-each (lambda (name)
                  (unless (and (member? name (Path-live one)) (member? name (Path-live other)))
                    (compile-error loc
                                   (string-append
                                    "alternatives must consume the same linear values: "
                                    (local-name name)))))
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
          ((Lambda _ _) (check-lambda path expr #f))
          ((App callee args) (check-call path callee args))
          ((If test then otherwise)
           (let ((path (check path test)))
             (join path (list (check path then) (check path otherwise)) loc)))
          ((Let name value body)
           (let ((path (check path value)))
             (close-scope path (check (bind path name (Expr-type value)) body) loc)))
          ((Seq first rest)
           (when (linear? path (Expr-type first))
             (compile-error (Expr-loc first) "a linear value cannot be discarded; drop it"))
           (check (check path first) rest))
          ((Match value clauses)
           (let ((path (check path value)))
             (join path (map (lambda (clause) (check-clause path clause loc)) clauses) loc)))
          ((Handle _ implementations body)
           (check (check-all path (map Pair-second implementations)) body))
          ((Ann inner _) (check path inner))
          ((Convert inner target) (check-conversion path expr inner target))
          ((TypeTest inner target) (check-conversion path expr inner target)))))

    ;; A use of a linear name consumes it. A linear record's accessors and
    ;; replacements would give its fields a second owner.
    (: check-reference (-> Path Expr String Path ! compile))
    (define (check-reference path expr name)
      (match (program-value (Path-program path) name)
        ((Some (Accessor _ _ _)) (check-accessor path expr))
        ((Some (Replacer _ _ _)) (check-accessor path expr))
        (_ (unit)))
      (if (linear? path (Expr-type expr)) (consume path name (Expr-loc expr)) path))

    (: check-accessor (-> Path Expr Unit ! compile))
    (define (check-accessor path expr)
      (match (Expr-type expr)
        ((TFun (Cons type _) _ _)
         (when (linear? path type)
           (compile-error (Expr-loc expr)
                          "destructure a linear record with match; accessors would duplicate ownership")))
        (_ (unit))))

    ;; `once` may move a lambda's linear captures into it. A panic never
    ;; returns.
    (: check-call (-> Path Expr (List Expr) Path ! compile))
    (define (check-call path callee args)
      (match (Pair (Expr-term callee) args)
        ((Pair (Var "prim:once" _ _) (Cons value (Nil)))
         (if (lambda-expr? value) (check-lambda path value #t) (check path value)))
        ((Pair (Var "prim:panic" _ _) _) (Path-returns-set (check-all path args) #f))
        (_ (check-all path (Cons callee args)))))

    ;; A closure's body is a path of its own, which starts with the linear
    ;; names it captures and its linear parameters live, and must consume
    ;; them all. Creating the closure moves the captures into it. It
    ;; captures the live names it refers to; one consumed already is not
    ;; live in the body either, so the body's use of it is a second use.
    (: check-lambda (-> Path Expr Bool Path ! compile))
    (define (check-lambda path expr once?)
      (match (Pair (Expr-term expr) (Expr-type expr))
        ((Pair (Lambda params body) (TFun types _ _))
         (let ((captured (filter (lambda (name) (member? name (Path-live path)))
                                 (expr-references expr)))
               (loc (Expr-loc expr)))
           (unless (or once? (null? captured))
             (compile-error loc "an unrestricted procedure cannot capture a linear value"))
           (let* ((empty (Path (Path-program path) (Nil) #t))
                  (start (fold-left (lambda (inner pair)
                                      (bind inner (Pair-first pair) (Pair-second pair)))
                                    (Path-live-set empty captured)
                                    (zip params types))))
             (close-scope empty (check start body) loc)
             (fold-left (lambda (path name) (consume path name loc)) path captured))))
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
           (compile-error loc "a wildcard cannot discard a linear value; bind it and use it"))
         path)
        ((PVar name type) (bind path name type))
        ((PLit _ _) path)
        ((PCon _ args _) (fold-left (lambda (path arg) (bind-pattern path arg loc)) path args))))

    (: check-conversion (-> Path Expr Expr Type Path ! compile))
    (define (check-conversion path expr inner target)
      (when (or (linear? path (Expr-type inner)) (linear? path target))
        (compile-error (Expr-loc expr) "a linear value cannot cross a dynamic type boundary"))
      (check path inner))

    ;; ---- Items ----

    ;; Each item is a path of its own: no linear value is a global, and a
    ;; statement cannot discard one.
    (: check-ownership (-> Program (List Item) Unit ! compile))
    (define (check-ownership program items)
      (for-each (lambda (item) (check-item (Path program (Nil) #t) item)) items))

    (: check-item (-> Path Item Unit ! compile))
    (define (check-item path item)
      (match item
        ((Define _ value) (check path value) (unit))
        ((Do value)
         (when (linear? path (Expr-type value))
           (compile-error (Expr-loc value) "a linear value cannot be discarded; drop it"))
         (check path value)
         (unit))
        (_ (unit))))))

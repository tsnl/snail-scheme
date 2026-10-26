;; Affine values have one owner on each execution path. This pass consumes
;; local names, joins alternatives, and inserts drops where a path has no
;; remaining use. Ordinary arrows stay unrestricted; only an immediate
;; `once` lambda may move owned captures into its environment.
(define-library (lofi compiler ownership)
  (export own-items check-owned-types)
  (import
   (lofi base)
   (lofi table)
   (lofi compiler read)
   (lofi compiler core)
   (lofi compiler capabilities))
  (begin

    (: no-loc Loc)
    (define no-loc (Loc "ownership" 0 0))

    ;; ---- Representable ownership ----

    (: check-type (-> Program Type Loc Unit))
    (define (check-type program type loc)
      (match type
        ((TCon "Once" args)
         (match args
           ((Cons (TFun (Nil) (TCon "Unit" (Nil)) _) (Nil)) (unit))
           (_ (compile-error loc "Once requires a zero-argument procedure returning Unit"))))
        ((TCon _ args)
         (for-each (lambda (arg)
                     (when (affine-type? program arg)
                       (compile-error loc "a type argument must be unrestricted; use a concrete affine field"))
                     (check-type program arg loc)) args))
        ((TFun params result _) (for-each (lambda (part) (check-type program part loc)) (Cons result params)))
        (_ (unit))))

    (: check-owned-types (-> Program (List Item) Unit))
    (define (check-owned-types program items)
      (for-each (lambda (data)
                  (for-each (lambda (case)
                              (for-each (lambda (field) (check-type program (Field-type field) no-loc)) (Case-fields case)))
                            (DataType-cases data))) (table-values (Program-types program)))
      (for-each (lambda (item)
                  (match item
                    ((Define _ value)
                     (when (affine-type? program (Expr-type value))
                       (compile-error (Expr-loc value) "an affine value cannot be a global"))
                     (check-expression-types program value))
                    ((Do value) (check-expression-types program value))
                    (_ (unit)))) items))

    (: check-expression-types (-> Program Expr Unit))
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

    ;; ---- Owners and last uses ----

    ;; Branches share immutable types and the unique-name counter, but fork
    ;; the live owners. Names disappear on a move or drop, never on a read.
    (struct Scope
      ((program Program)
       (types (Table Type))
       (live (Ref (List String)))
       (counter (Ref I64))))

    (: owned? (-> Scope Type Bool))
    (define (owned? scope type) (affine-type? (Scope-program scope) type))

    (: bind (-> Scope String Type Scope ! mut))
    (define (bind scope name type)
      (when (owned? scope type) (ref-set! (Scope-live scope) (Cons name (ref-get (Scope-live scope)))))
      (Scope (Scope-program scope) (table-set (Scope-types scope) name type) (Scope-live scope) (Scope-counter scope)))

    (: consume! (-> Scope String Loc Unit ! mut))
    (define (consume! scope name loc)
      (unless (member? name (ref-get (Scope-live scope)))
        (compile-error loc (string-append "affine value used more than once: " (short-name name))))
      (ref-set! (Scope-live scope) (filter (lambda (live) (not (string=? live name))) (ref-get (Scope-live scope)))))

    (: rebuild (-> Expr Term Expr))
    (define (rebuild expr term) (Expr term (Expr-type expr) (Expr-loc expr)))

    (: discard (-> Expr Expr))
    (define (discard value)
      (let* ((unit-type (TCon "Unit" (Nil)))
             (callee (Expr (Var "prim:drop-owned" (Nil) (Nil)) (TFun (list (Expr-type value)) unit-type empty-row) (Expr-loc value))))
        (Expr (App callee (list value)) unit-type (Expr-loc value))))

    ;; A dropped name is no longer live before the remaining expression is
    ;; checked. `future` consists of later uses in the same activation.
    (: own (-> Scope Expr (List String) Expr ! mut))
    (define (own scope expr future)
      (let* ((needed (append (expr-references expr) future))
             (dead (filter (lambda (name) (not (member? name needed))) (ref-get (Scope-live scope)))))
        (for-each (lambda (name) (consume! scope name (Expr-loc expr))) dead)
        (let ((value (own-term scope expr future)))
          (fold-right (lambda (name rest)
                        (match (table-ref (Scope-types scope) name)
                          ((Some type) (rebuild rest (Seq (discard (Expr (Var name (Nil) (Nil)) type (Expr-loc expr))) rest)))
                          ((None) (panic "internal error: owner has no type"))))
                      value dead))))

    (: own-list (-> Scope (List Expr) (List String) (List Expr) ! mut))
    (define (own-list scope values future)
      (match values
        ((Nil) (Nil))
        ((Cons value rest)
         (let ((value (own scope value (append (concatenate (map expr-references rest)) future))))
           (Cons value (own-list scope rest future))))))

    ;; ---- Closures and alternatives ----

    (: own-lambda (-> Scope Expr Bool Expr ! mut))
    (define (own-lambda scope expr once?)
      (match (Expr-term expr)
        ((Lambda params body)
         (let ((captured (filter (lambda (name) (table-contains? (Scope-types scope) name)) (expr-references expr))))
           (for-each (lambda (name)
                       (match (table-ref (Scope-types scope) name)
                         ((Some type)
                          (when (owned? scope type)
                            (unless once? (compile-error (Expr-loc expr) "an unrestricted procedure cannot capture an affine value"))
                            (consume! scope name (Expr-loc expr))))
                         (_ (unit)))) captured)
           (let* ((inner (Scope (Scope-program scope) empty-table (ref (Nil)) (Scope-counter scope)))
                  (inner (fold-left (lambda (inner name)
                                      (match (table-ref (Scope-types scope) name)
                                        ((Some type) (bind inner name type)) (_ inner))) inner captured)))
             (match (Expr-type expr)
               ((TFun types _ _)
                (let ((inner (fold-left (lambda (inner pair) (bind inner (Pair-first pair) (Pair-second pair))) inner (zip params types))))
                  (rebuild expr (Lambda params (own inner body (Nil))))))
               (_ (panic "internal error: untyped owned closure"))))))
        (_ (own scope expr (Nil)))))

    (: fork (-> Scope Scope ! mut))
    (define (fork scope)
      (Scope (Scope-program scope) (Scope-types scope) (ref (ref-get (Scope-live scope))) (Scope-counter scope)))

    (: join! (-> Scope (List Scope) Unit ! mut))
    (define (join! scope branches)
      (ref-set! (Scope-live scope)
                (filter (lambda (name) (every? (lambda (branch) (member? name (ref-get (Scope-live branch)))) branches))
                        (ref-get (Scope-live scope)))))

    (: own-if (-> Scope Expr Expr Expr Expr (List String) Expr ! mut))
    (define (own-if scope expr test then otherwise future)
      (let* ((test (own scope test (append (expr-references then) (append (expr-references otherwise) future))))
             (left (fork scope)) (right (fork scope))
             (then (own left then future)) (otherwise (own right otherwise future)))
        (join! scope (list left right))
        (rebuild expr (If test then otherwise))))

    ;; Owned wildcards become named owners, so the same last-use rule drops
    ;; them before the chosen clause runs. Failed tests do not bind owners.
    (: own-pattern (-> Scope Pattern Pattern ! mut))
    (define (own-pattern scope pattern)
      (match pattern
        ((PWild type)
         (if (owned? scope type)
             (let ((next (+ 1 (ref-get (Scope-counter scope)))))
               (ref-set! (Scope-counter scope) next)
               ;; Source locals end in .digits; globals contain a colon.
               (PVar (string-append "%owned." (i64->string next) "%") type)) pattern))
        ((PCon name args type) (PCon name (map (lambda (arg) (own-pattern scope arg)) args) type))
        (_ pattern)))

    (: bind-pattern (-> Scope Pattern Scope ! mut))
    (define (bind-pattern scope pattern)
      (match pattern
        ((PVar name type) (bind scope name type))
        ((PCon _ args _) (fold-left bind-pattern scope args))
        (_ scope)))

    (: own-match (-> Scope Expr Expr (List Clause) (List String) Expr ! mut))
    (define (own-match scope expr value clauses future)
      (let* ((value (own scope value (append (concatenate (map (lambda (clause) (expr-references (Clause-body clause))) clauses)) future)))
             (branches (map (lambda (clause)
                              (let* ((pattern (own-pattern scope (Clause-pattern clause)))
                                     (branch (bind-pattern (fork scope) pattern)))
                                (Pair branch (Clause pattern (own branch (Clause-body clause) future))))) clauses)))
        (join! scope (map Pair-first branches))
        (rebuild expr (Match value (map Pair-second branches)))))

    ;; ---- Expression transitions ----

    (: check-reference (-> Scope Expr String Unit ! mut))
    (define (check-reference scope expr name)
      (when (owned? scope (Expr-type expr)) (consume! scope name (Expr-loc expr)))
      (match (program-value (Scope-program scope) name)
        ((Some (Accessor _ _ _)) (check-accessor scope expr))
        ((Some (Replacer _ _ _)) (check-accessor scope expr))
        (_ (unit))))

    (: check-accessor (-> Scope Expr Unit ! mut))
    (define (check-accessor scope expr)
      (match (Expr-type expr)
        ((TFun (Cons type _) _ _)
         (when (owned? scope type) (compile-error (Expr-loc expr) "destructure an affine record with match; accessors would duplicate ownership")))
        (_ (unit))))

    (: own-term (-> Scope Expr (List String) Expr ! mut))
    (define (own-term scope expr future)
      (match (Expr-term expr)
        ((Var name _ _) (check-reference scope expr name) expr)
        ((Lambda _ _) (own-lambda scope expr #f))
        ((App callee args)
         (match (Expr-term callee)
           ((Var "prim:once" _ _)
            (let ((value (list-ref args 0)))
              (rebuild expr (App callee (list (if (lambda-expr? value) (own-lambda scope value #t) (own scope value future)))))))
           (_ (let ((values (own-list scope (Cons callee args) future)))
                (match values ((Cons callee args) (rebuild expr (App callee args))) (_ expr))))))
        ((Let name value body)
         (let* ((value (own scope value (append (expr-references body) future)))
                (inner (bind scope name (Expr-type value))))
           (rebuild expr (Let name value (own inner body future)))))
        ((Seq first rest)
         (let ((first (own scope first (append (expr-references rest) future))))
           (rebuild expr (Seq (if (owned? scope (Expr-type first)) (discard first) first) (own scope rest future)))))
        ((If test then otherwise) (own-if scope expr test then otherwise future))
        ((Match value clauses) (own-match scope expr value clauses future))
        ((Handle effect implementations body)
         (let* ((values (own-list scope (map Pair-second implementations) (append (expr-references body) future)))
                (body (own scope body future)))
           (rebuild expr (Handle effect (zip (map Pair-first implementations) values) body))))
        ((Ann inner type) (rebuild expr (Ann (own scope inner future) type)))
        ((Convert inner target) (own-conversion scope expr inner target future #f))
        ((TypeTest inner target) (own-conversion scope expr inner target future #t))
        (_ expr)))

    (: own-conversion (-> Scope Expr Expr Type (List String) Bool Expr ! mut))
    (define (own-conversion scope expr inner target future test?)
      (when (or (owned? scope (Expr-type inner)) (owned? scope target))
        (compile-error (Expr-loc expr) "an affine value cannot cross a dynamic type boundary"))
      (let ((inner (own scope inner future)))
        (rebuild expr (if test? (TypeTest inner target) (Convert inner target)))))

    ;; The checker already proved representability. Specialization substitutes
    ;; only unrestricted types and erases rows, so that proof still holds here.
    (: own-items (-> Program (List Item) (List Item) ! mut))
    (define (own-items program items)
      (map (lambda (item)
             (let ((scope (Scope program empty-table (ref (Nil)) (ref 0))))
               (match item
                 ((Define name value) (Define name (own scope value (Nil))))
                 ((Do value) (let ((value (own scope value (Nil)))) (Do (if (owned? scope (Expr-type value)) (discard value) value))))
                 (_ item)))) items))))

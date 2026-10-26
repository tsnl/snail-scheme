;; Ordinary handlers are reusable shared capabilities. Check the values they
;; retain, including the global dependencies of captured code, after generic
;; calls and method evidence have been specialized. Invocation parameters and
;; fresh local storage are not captures of that invocation.
(define-library (lofi compiler handlers)
  (export check-handlers)
  (import
   (lofi base)
   (lofi table)
   (lofi compiler read)
   (lofi compiler core)
   (only (lofi compiler check) outside-reads)
   (lofi compiler capabilities))
  (begin

    ;; ---- Captured environments ----

    (struct Context
      ((program Program)
       (definitions (Table Expr))))

    (: shared-type? (-> Context Type Bool))
    (define (shared-type? cx type)
      (and (capability-type? (Context-program cx) "lofi.base:Send" type (Nil) (Nil))
           (capability-type? (Context-program cx) "lofi.base:Sync" type (Nil) (Nil))))

    ;; An ordinary arrow carries no capture proof. Recover only concrete
    ;; lambdas and aliases; an opaque callback or function-returning call fails.
    ;; Specialization preserves each expression's unique resolved binders.
    (: shared-value? (-> Context (Table Expr) Expr (List String) Bool))
    (define (shared-value? cx locals value visiting)
      (or (shared-type? cx (Expr-type value))
          (match (Expr-term value)
            ((Lambda _ _) (every? (lambda (reference) (shared-reference? cx locals reference visiting)) (outside-reads value)))
            ((Var _ _ _) (shared-reference? cx locals value visiting))
            (_ #f))))

    (: shared-reference? (-> Context (Table Expr) Expr (List String) Bool))
    (define (shared-reference? cx locals reference visiting)
      (match (Expr-term reference)
        ((Var name _ evidence)
         (match (table-ref locals name)
           ((Some value)
            (if (same-reference? name value)
                (shared-type? cx (Expr-type value))
                (or (member? name visiting) (shared-value? cx locals value (Cons name visiting)))))
           ((None) (shared-global? cx name evidence visiting))))
        (_ #f)))

    (: same-reference? (-> String Expr Bool))
    (define (same-reference? name value)
      (match (Expr-term value)
        ((Var other _ _) (string=? name other))
        (_ #f)))

    ;; A known function may recurse, but all its other edges still have to
    ;; pass. A global's initializer is inspected only for the value it retains.
    (: shared-global? (-> Context String (List Evidence) (List String) Bool))
    (define (shared-global? cx name evidence visiting)
      (match (table-ref (Context-definitions cx) name)
        ((Some value) (or (member? name visiting) (shared-value? cx empty-table value (Cons name visiting))))
        ((None)
         (match (program-value (Context-program cx) name)
           ((Some (Method class _)) (shared-method? cx class name evidence visiting))
           ((Some (Defined _)) #f)
           ((Some _) #t) ;; Constructors, operations, primitives and trusted FFI.
           ((None) #f)))))

    ;; Imported monomorphic code may still name methods in its typed body.
    ;; Its selected evidence is a dependency, never a proof of safe captures.
    (: shared-method? (-> Context String String (List Evidence) (List String) Bool))
    (define (shared-method? cx class method evidence visiting)
      (match evidence
        ((Cons (EvInstance name _ _) _)
         (match (find (lambda (instance) (string=? name (Instance-name instance))) (class-instances (Context-program cx) class))
           ((Some instance)
            (match (assoc-ref (Instance-methods instance) method)
              ((Some global) (shared-global? cx global (Nil) visiting))
              ((None) #f)))
           ((None) #f)))
        (_ #f)))

    (: children (-> Expr (List Expr)))
    (define (children expr)
      (match (Expr-term expr)
        ((App callee args) (Cons callee args))
        ((If test then otherwise) (list test then otherwise))
        ((Seq first rest) (list first rest))
        ((Handle _ implementations body) (append (map Pair-second implementations) (list body)))
        ((Ann inner _) (list inner))
        ((Convert inner _) (list inner))
        ((TypeTest inner _) (list inner))
        (_ (Nil))))

    ;; ---- Handler installations ----

    ;; A parameter is represented by its own typed reference: its data type
    ;; may prove sharing, but its ordinary function type cannot prove captures.
    (: bind-parameters (-> (Table Expr) (List String) (List Type) Loc (Table Expr)))
    (define (bind-parameters locals names types loc)
      (fold-left (lambda (scope entry)
                   (table-set scope (Pair-first entry) (Expr (Var (Pair-first entry) (Nil) (Nil)) (Pair-second entry) loc)))
                 locals (zip names types)))

    (: bind-pattern (-> (Table Expr) Pattern Loc (Table Expr)))
    (define (bind-pattern locals pattern loc)
      (match pattern
        ((PVar name type) (bind-parameters locals (list name) (list type) loc))
        ((PCon _ args _) (fold-left (lambda (scope arg) (bind-pattern scope arg loc)) locals args))
        (_ locals)))

    (: check-expression (-> Context (Table Expr) Expr Unit))
    (define (check-expression cx locals expr)
      (match (Expr-term expr)
        ((Lambda params body)
         (match (Expr-type expr)
           ((TFun types _ _) (check-expression cx (bind-parameters locals params types (Expr-loc expr)) body))
           (_ (panic "internal error: untyped handler closure"))))
        ((Let name value body)
         (let ((scope (table-set locals name value)))
           (check-expression cx (if (lambda-expr? value) scope locals) value)
           (check-expression cx scope body)))
        ((Match value clauses)
         (check-expression cx locals value)
         (for-each (lambda (clause) (check-expression cx (bind-pattern locals (Clause-pattern clause) (Expr-loc expr)) (Clause-body clause))) clauses))
        ((Handle _ implementations body)
         (for-each (lambda (entry)
                     (let ((value (Pair-second entry)))
                       (unless (shared-value? cx locals value (Nil))
                         (compile-error (Expr-loc value) "a handler and its captures must satisfy Send + Sync and be reusable"))
                       (check-expression cx locals value))) implementations)
         (check-expression cx locals body))
        (_ (for-each (lambda (child) (check-expression cx locals child)) (children expr)))))

    (: check-handlers (-> Program (Table Expr) (List Item) Unit))
    (define (check-handlers program definitions items)
      (let ((cx (Context program definitions)))
        (for-each (lambda (item)
                    (match item
                      ((Define _ value) (check-expression cx empty-table value))
                      ((Do value) (check-expression cx empty-table value))
                      (_ (unit)))) items)))))

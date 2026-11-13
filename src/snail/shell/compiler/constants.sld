;; Evaluate closed values before control and lifetime lowering. Functions
;; remain code; reading a constant forces its initializer and copies its
;; object graph. No compiler-owned mutable object becomes a runtime global.
(define-library (snail shell compiler constants)
  (export fold-constants constant-declarations)
  (import
   (snail core base)
   (snail core table)
   (snail shell compiler read)
   (snail shell compiler core)
   (snail shell compiler specialize)
   (only (snail shell compiler capabilities) shared-type? linear-type?)
   (snail shell compiler constant-scalars))
  (begin

    ;; ---- Values and evaluation ----

    ;; Objects have identities independent of structural equality. The heap
    ;; belongs to this evaluation, and updates replace one entry in it.
    (struct Known
      ((type Type)
       (value Constant)))

    (enum Constant
      (Scalar ((datum Datum)))
      (RealValue ((value F64)))
      (Global ((name String)))
      (Object ((id String))))

    (enum ObjectValue
      (RecordValue ((constructor String) (fields (List Known))))
      (VectorValue ((items (List Known))))
      ;; Packed bytes keep embedded assets compact; identity still belongs to the heap.
      (ByteVectorValue ((bytes Bytes)))
      (DynamicValue ((inner Known)))
      (ClosureValue ((recipe String) (environment (Table Known))))
      (CodeValue ((expression Expr) (environment (Table Known))))
      (RcValue ((payload (Option Known)) (finalizer Known)))
      (ResumeValue ((suspension (Option Suspension))))
      (BoundValue ((function Known) (handlers (List ConstantHandler))))
      (OnceValue ((function Known)))
      (SpentValue))

    (struct Evaluation
      ((state State)
       (bodies (Table Expr))
       (values (Table Known))
       (forcing (List String))
       (heap (Table ObjectValue))
       (next I64)
       (counts (Table I64))
       (recipes (Table ClosureRecipe))
       (fuel I64)
       (cells-left I64)
       (prepare (Fn State String Expr → (Pair Expr State) ! compile))))

    ;; Source recipes survive evaluation so frozen closures re-enter the
    ;; ordinary runtime pipeline. Only their execution uses prepared code.
    (struct ClosureRecipe
      ((expression Expr)
       (captures (List (Pair String Type)))
       (cleanup (List String))
       (self (Option String))))

    (struct ConstantHandler
      ((id String)
       (effect String)
       (operations (List (Pair String Known)))))

    (struct Suspension
      ((frames (List EvaluationFrame))
       (handlers (List ConstantHandler))))

    (enum EvaluationFrame
      (ApplyFunction ((environment (Table Known)) (arguments (List Expr)) (type Type) (loc Loc)))
      (ApplyArgument ((function Known) (values (List Known)) (environment (Table Known))
                      (remaining (List Expr)) (type Type) (loc Loc)))
      (BindValue ((name String) (environment (Table Known)) (body Expr)))
      (ChooseBranch ((environment (Table Known)) (yes Expr) (no Expr) (loc Loc)))
      (NextExpression ((environment (Table Known)) (body Expr)))
      (ChooseClause ((environment (Table Known)) (clauses (List Clause)) (loc Loc)))
      (ConvertValue ((target Type) (loc Loc)))
      (TestValue ((target Type) (type Type) (loc Loc)))
      (InstallHandler ((effect String) (names (List String)) (values (List Known))
                       (environment (Table Known)) (remaining (List Expr)) (body Expr)))
      (HandlerBoundary ((handler ConstantHandler)))
      (RestoreHandlers ((handlers (List ConstantHandler))))
      ;; Prepared guards own exactly the values assigned by control lowering.
      ;; Their environments are observations, never additional counted copies.
      (CancellationGuard ((environment (Table Known)) (cleanup Expr)))
      (ContinueAction ((action EvaluationAction)))
      (ReleaseFunction ((function Known)))
      (ReleaseCaptured ((handlers (List ConstantHandler))))
      (GeneratedElement ((function Known) (index I64) (size I64)
                         (values (List Known)) (type Type) (loc Loc))))

    (enum EvaluationAction
      (Evaluate ((environment (Table Known)) (expression Expr)))
      (Invoke ((function Known) (arguments (List Known)) (type Type) (loc Loc)))
      (ReturnValue ((value Known)))
      (CancelFrames ((frames (List EvaluationFrame)) (next EvaluationAction)))
      (ReleaseValues ((values (List Known)) (next EvaluationAction))))

    (define-syntax evaluating
      (syntax-rules ()
        ((_ ev () body ...) (begin body ...))
        ((_ ev ((name (f arg ...)) step ...) body ...)
         (match (f ev arg ...)
           ((Pair name ev) (evaluating ev (step ...) body ...))))))

    (define (program (ev Evaluation)) (→ Program)
      (specialization-program (● ev state)))

    (define (reserve-object (ev Evaluation) (object ObjectValue)) (→ Evaluation) (! compile)
      (let ((size (+ 1 (length (object-children ev object)))))
        (when (> size (● ev cells-left))
          (compile-error (Loc "constant" 0 0)
                         "constant evaluation exceeds the limit of 1000000 heap cells"))
        (Evaluation-cells-left-set ev (- (● ev cells-left) size))))

    (define (allocate (ev Evaluation) (type Type) (value ObjectValue))
      (→ (Pair Known Evaluation)) (! compile)
      (let ((id (i64->string (● ev next))) (ev (reserve-object ev value)))
        (Pair (Known type (Object id))
              (Evaluation-next-set
               (Evaluation-heap-set (Evaluation-counts-set ev (table-set (● ev counts) id 1))
                                    (table-set (● ev heap) id value)) (+ (● ev next) 1)))))

    (define (object-value (ev Evaluation) (value Known) (loc Loc)) (→ ObjectValue) (! compile)
      (match (● value value)
        ((Object id)
         (match (table-ref (● ev heap) id)
           ((Some object) object)
           ((None) (panic "internal error: missing constant object"))))
        (_ (compile-error loc "constant evaluation expected an object"))))

    (define (body-of (ev Evaluation) (name String)) (→ (Pair Expr Evaluation)) (! compile)
      (match (table-ref (● ev bodies) name)
        ((Some body) (Pair body ev))
        ((None)
         (match (constant-body (● ev state) name)
           ((Pair body state) (prepared-body (Evaluation-state-set ev state) name body))))))

    ;; ---- Source closures and prepared execution ----

    (define (bind-types (scope (List (Pair String Type))) (names (List String)) (types (List Type)))
      (→ (List (Pair String Type)))
      (fold-left (lambda (scope pair) (Cons pair scope)) scope (zip names types)))



    (define (recipe (ev Evaluation) (name String)) (→ ClosureRecipe)
      (match (table-ref (● ev recipes) name)
        ((Some recipe) recipe)
        ((None) (panic "internal error: missing constant closure recipe"))))

    (define (lift-closure (ev Evaluation)
                          (scope (List (Pair String Type)))
                          (expr Expr)
                          (self (Option String)))
      (→ (Pair Expr Evaluation))
      (let* ((names (filter (lambda (name)
                              (and (match (assoc-ref scope name) ((Some _) #t) ((None) #f))
                                   (match self
                                     ((Some own) (not (string=? name own)))
                                     ((None) #t))))
                            (expr-references expr)))
             (captures (map (lambda (name)
                              (match (assoc-ref scope name)
                                ((Some type) (Pair name type))
                                ((None) (panic "internal error: missing closure capture"))))
                            names))
             (name (string-append "constant-closure:" (i64->string (● ev next))))
             (cleanup (append
                       (map (lambda (entry) (● entry first))
                            (filter (lambda (entry)
                                      (and (member? (● entry first) names)
                                           (linear-type? (program ev) (Nil) (● entry second))))
                                    scope))
                       (map (lambda (entry) (● entry first))
                            (filter (lambda (entry)
                                      (not (linear-type? (program ev) (Nil) (● entry second))))
                                    captures))))
             (value (ClosureRecipe expr captures cleanup self)))
        (Pair (constant-call name
                             (map (lambda (entry)
                                    (Expr (Var (● entry first) (Nil) (Nil))
                                          (● entry second) (● expr loc))) captures)
                             (● expr type) (● expr loc))
              (Evaluation-next-set
               (Evaluation-recipes-set ev (table-set (● ev recipes) name value))
               (+ (● ev next) 1)))))

    (define (lift-pattern (scope (List (Pair String Type))) (pattern Pattern))
      (→ (List (Pair String Type)))
      (match pattern
        ((PVar name type) (Cons (Pair name type) scope))
        ((PCon _ args _) (fold-left lift-pattern scope args))
        (_ scope)))

    ;; The pending steps carry lexical scope explicitly. Lambda bodies stay
    ;; in recipes; only their construction sites are traversed here. A finish
    ;; step consumes exactly its direct children from the result stack.
    (enum LiftStep
      (LiftVisit ((scope (List (Pair String Type))) (expression Expr) (self (Option String))))
      (LiftFinish ((expression Expr) (count I64))))

    (define (lift-expression (ev Evaluation) (scope (List (Pair String Type))) (expr Expr))
      (→ (Pair Expr Evaluation))
      (let loop ((ev ev) (pending (list (LiftVisit scope expr (None)))) (values (Nil)))
        (match pending
          ((Nil) (Pair (list-ref values 0) ev))
          ((Cons step rest)
           (match step
             ((LiftVisit scope expr self)
              (match (● expr term)
                ((Lambda _ _ _)
                 (match (lift-closure ev scope expr self)
                   ((Pair value ev) (loop ev rest (Cons value values)))))
                (_ (let ((children (lift-children scope expr self)))
                     (if (null? children) (loop ev rest (Cons expr values))
                         (loop ev (append children (Cons (LiftFinish expr (length children)) rest))
                               values))))))
             ((LiftFinish expr count)
              (loop ev rest
                    (Cons (rebuild-expression expr (reverse (take values count)))
                          (list-drop values count)))))))))

    (define (lift-children (scope (List (Pair String Type))) (expr Expr) (self (Option String)))
      (→ (List LiftStep))
      (match (● expr term)
        ((Let name value body)
         (list (LiftVisit scope value (Some name))
               (LiftVisit (Cons (Pair name (● value type)) scope) body (None))))
        ((Match value clauses)
         (Cons (LiftVisit scope value (None))
               (map (lambda (clause)
                      (LiftVisit (lift-pattern scope (● clause pattern)) (● clause body) (None)))
                    clauses)))
        ((Ann inner _) (list (LiftVisit scope inner self)))
        (_ (map (lambda (child) (LiftVisit scope child (None))) (expr-children expr)))))

    ;; Exhaustive reconstruction keeps each source constructor visible. The
    ;; worklist already established the number and order of its children.
    (define (rebuild-expression (expr Expr) (values (List Expr))) (→ Expr)
      (Expr
       (match (● expr term)
         ((Lambda params _ captures?) (Lambda params (list-ref values 0) captures?))
         ((App _ _) (App (list-ref values 0) (list-drop values 1)))
         ((Let name _ _) (Let name (list-ref values 0) (list-ref values 1)))
         ((If _ _ _) (If (list-ref values 0) (list-ref values 1) (list-ref values 2)))
         ((Seq _ _) (Seq (list-ref values 0) (list-ref values 1)))
         ((Match _ clauses)
          (Match (list-ref values 0)
                 (map (lambda (pair) (Clause (● (● pair first) pattern) (● pair second)))
                      (zip clauses (list-drop values 1)))))
         ((Handle effect implementations _)
          (Handle effect
                  (zip (map (lambda (entry) (● entry first)) implementations)
                       (take values (length implementations)))
                  (list-ref values (length implementations))))
         ((Ann _ type) (Ann (list-ref values 0) type))
         ((Convert _ type) (Convert (list-ref values 0) type))
         ((TryConvert _ type) (TryConvert (list-ref values 0) type))
         ((TypeTest _ type) (TypeTest (list-ref values 0) type))
         ((FieldRead _ label usage) (FieldRead (list-ref values 0) label usage))
         ((ScopedInstances instances _) (ScopedInstances instances (list-ref values 0)))
         (_ (panic "internal error: closure lifting cannot rebuild a leaf")))
       (● expr type) (● expr loc)))

    (define (lift-body (ev Evaluation) (body Expr)) (→ (Pair Expr Evaluation))
      (match (Pair (● body term) (fn-arrow (● body type)))
        ((Pair (Lambda params value captures?) (TFun types _ _))
         (evaluating ev ((value (lift-expression (bind-types (Nil) params types) value)))
                     (Pair (Expr (Lambda params value captures?) (● body type) (● body loc)) ev)))
        (_ (lift-expression ev (Nil) body))))

    (define (prepared-body (ev Evaluation) (name String) (body Expr))
      (→ (Pair Expr Evaluation)) (! compile)
      (evaluating ev ((body (lift-body body)))
                  (match ((● ev prepare) (● ev state) name body)
                    ((Pair body state)
                     (Pair body (Evaluation-bodies-set (Evaluation-state-set ev state)
                                                       (table-set (● ev bodies) name body)))))))

    (define (closure-body (ev Evaluation) (name String)) (→ (Pair Expr Evaluation)) (! compile)
      (match (table-ref (● ev bodies) name)
        ((Some body) (Pair body ev))
        ((None)
         (let* ((source (recipe ev name)) (expr (● source expression))
                (captured (map (lambda (name)
                                 (Pair name (match (assoc-ref (● source captures) name)
                                              ((Some type) type)
                                              ((None)
                                               (panic "internal error: missing capture type")))))
                               (reverse (● source cleanup))))
                (captured (match (● source self)
                            ((Some self) (Cons (Pair self (● expr type)) captured))
                            ((None) captured))))
           (match (Pair (● expr term) (fn-arrow (● expr type)))
             ((Pair (Lambda params body _) (TFun types result row))
              (prepared-body ev name
                             (Expr (Lambda (append (map (lambda (entry) (● entry first)) captured)
                                                   params)
                                           body #f)
                                   (TFun (append (map (lambda (entry) (● entry second)) captured)
                                                 types)
                                         result row) (● expr loc))))
             (_ (panic "internal error: source closure recipe is not a lambda")))))))


    ;; Only actually evaluated references force a value. Ordinary recursion
    ;; enters function bodies without putting their names on this stack.
    (define (force-value (ev Evaluation) (name String) (loc Loc))
      (→ (Pair Known Evaluation)) (! compile)
      (match (table-ref (● ev values) name)
        ((Some value) (Pair value ev))
        ((None)
         (when (member? name (● ev forcing))
           (compile-error loc (string-append "constant initialization cycle: "
                                             (string-join (reverse (Cons name (● ev forcing)))
                                                          " → "))))
         (evaluating ev ((body (body-of name)))
                     (let ((outer (● ev forcing)))
                       (let ((ev (Evaluation-forcing-set ev (Cons name outer))))
                         (evaluating ev ((value (evaluate empty-table body)))
                                     (Pair value
                                           (Evaluation-values-set
                                            (Evaluation-forcing-set ev outer)
                                            (table-set (● ev values)
                                                       name
                                                       value))))))))))

    (define (reference (ev Evaluation) (env (Table Known)) (expr Expr) (name String))
      (→ (Pair Known Evaluation)) (! compile)
      (match (table-ref env name)
        ((Some value) (Pair value ev))
        ((None)
         (if (constant-binding? (● ev state) name)
             (evaluating ev ((value (force-value name (● expr loc))))
                         (copy-value ev value))
             (Pair (Known (● expr type) (Global name)) ev)))))



    ;; ---- The evaluation machine ----

    ;; Each transition consumes fuel. Source continuations contain pending
    ;; work and cleanup guards, never an old snapshot of the mutable heap.
    (define (evaluate (ev Evaluation) (env (Table Known)) (expr Expr))
      (→ (Pair Known Evaluation)) (! compile)
      (run-evaluation ev (Nil) (Nil) (Evaluate env expr)))

    (define (spend (ev Evaluation)) (→ Evaluation) (! compile)
      (when (= (● ev fuel) 0)
        (compile-error (Loc "constant" 0 0)
                       "constant evaluation exceeds the limit of 10000000 steps"))
      (Evaluation-fuel-set ev (- (● ev fuel) 1)))

    (define (run-evaluation (ev Evaluation) (handlers (List ConstantHandler))
                            (frames (List EvaluationFrame)) (action EvaluationAction))
      (→ (Pair Known Evaluation)) (! compile)
      (let ((ev (spend ev)))
        (match action
          ((Evaluate env expr) (evaluate-step ev handlers frames env expr))
          ((Invoke function args type loc)
           (invoke-step ev handlers frames function args type loc))
          ((ReturnValue value)
           (match frames
             ((Nil) (Pair value ev))
             ((Cons frame rest) (continue-evaluation ev handlers rest frame value))))
          ((CancelFrames abandoned next) (cancel-frames ev handlers frames abandoned next))
          ((ReleaseValues values next) (release-values ev handlers frames values next)))))

    (define (return-result (result (Pair Known Evaluation)) (handlers (List ConstantHandler))
                           (frames (List EvaluationFrame)))
      (→ (Pair Known Evaluation)) (! compile)
      (run-evaluation (● result second) handlers frames (ReturnValue (● result first))))

    (define (evaluate-step (ev Evaluation) (handlers (List ConstantHandler))
                           (frames (List EvaluationFrame)) (env (Table Known)) (expr Expr))
      (→ (Pair Known Evaluation)) (! compile)
      (match (● expr term)
        ((Lit datum)
         (return-result (literal-value ev (● expr type) datum (● expr loc)) handlers frames))
        ((Var name _ _) (return-result (reference ev env expr name) handlers frames))
        ((Lambda _ _ _)
         (return-result (allocate ev (● expr type) (CodeValue expr env)) handlers frames))
        ((App (Expr (Var "prim:with-dropper" _ _) _ _) (Cons value (Cons cleanup (Nil))))
         (run-evaluation ev
                         handlers
                         (Cons (CancellationGuard env cleanup) frames)
                         (Evaluate env value)))
        ((App callee args)
         (run-evaluation ev
                         handlers
                         (Cons (ApplyFunction env args (● expr type) (● expr loc)) frames)
                         (Evaluate env callee)))
        ((Let name value body)
         (run-evaluation ev
                         handlers
                         (Cons (BindValue name env body) frames)
                         (Evaluate env value)))
        ((If test yes no)
         (run-evaluation ev
                         handlers
                         (Cons (ChooseBranch env yes no (● expr loc)) frames)
                         (Evaluate env test)))
        ((Seq first rest)
         (run-evaluation ev
                         handlers
                         (Cons (NextExpression env rest) frames)
                         (Evaluate env first)))
        ((Match value clauses)
         (run-evaluation ev
                         handlers
                         (Cons (ChooseClause env clauses (● expr loc)) frames)
                         (Evaluate env value)))
        ((Ann inner _) (run-evaluation ev handlers frames (Evaluate env inner)))
        ((Convert inner target)
         (run-evaluation ev
                         handlers
                         (Cons (ConvertValue target (● expr loc)) frames)
                         (Evaluate env inner)))
        ((TypeTest inner target)
         (run-evaluation ev
                         handlers
                         (Cons (TestValue target (● expr type) (● expr loc)) frames)
                         (Evaluate env inner)))
        ((Handle effect implementations body)
         (install-handler ev handlers frames effect
                          (map (lambda (entry) (● entry first)) implementations) (Nil) env
                          (map (lambda (entry) (● entry second)) implementations) body))
        (_ (compile-error (● expr loc) "internal error: unprepared constant expression"))))

    (define (continue-evaluation (ev Evaluation) (handlers (List ConstantHandler))
                                 (frames (List EvaluationFrame))
                                 (frame EvaluationFrame)
                                 (value Known))
      (→ (Pair Known Evaluation)) (! compile)
      (match frame
        ((ApplyFunction env args type loc)
         (evaluate-arguments ev handlers frames value (Nil) env args type loc))
        ((ApplyArgument function values env remaining type loc)
         (evaluate-arguments ev
                             handlers
                             frames
                             function
                             (Cons value values)
                             env
                             remaining
                             type
                             loc))
        ((BindValue name env body)
         (run-evaluation ev handlers frames (Evaluate (table-set env name value) body)))
        ((ChooseBranch env yes no loc)
         (run-evaluation ev handlers frames (Evaluate env (if (boolean-value value loc) yes no))))
        ((NextExpression env body) (run-evaluation ev handlers frames (Evaluate env body)))
        ((ChooseClause env clauses loc) (choose-clause ev handlers frames env value clauses loc))
        ((ConvertValue target loc)
         (evaluating ev ((result (convert-value value target loc)))
                     (if (and (any-type? (● value type)) (not (any-type? target)))
                         (run-evaluation (retain-known ev result) handlers frames
                                         (ReleaseValues (list value) (ReturnValue result)))
                         (run-evaluation ev handlers frames (ReturnValue result)))))
        ((TestValue target type loc)
         (return-result (scalar ev type
                                (DBool (string=? (type-key (● (dynamic-inner ev value loc) type))
                                                 (type-key target))))
                        handlers frames))
        ((InstallHandler effect names values env remaining body)
         (install-handler ev handlers frames effect names (Cons value values) env remaining body))
        ((HandlerBoundary handler)
         (run-evaluation ev (handler-outside handlers (● handler id)) frames
                         (ReleaseValues
                          (map (lambda (entry) (● entry second)) (● handler operations))
                          (ReturnValue value))))
        ((RestoreHandlers previous) (run-evaluation ev previous frames (ReturnValue value)))
        ((CancellationGuard _ _) (run-evaluation ev handlers frames (ReturnValue value)))
        ((ContinueAction next) (run-evaluation ev handlers frames next))
        ((ReleaseFunction function)
         (run-evaluation ev handlers frames (ReleaseValues (list function) (ReturnValue value))))
        ((ReleaseCaptured captured)
         (run-evaluation ev
                         handlers
                         frames
                         (ReleaseValues (handler-values captured) (ReturnValue value))))
        ((GeneratedElement function index size values type loc)
         (generate-element ev
                           handlers
                           frames
                           function
                           (+ index 1)
                           size
                           (Cons value values)
                           type
                           loc))))

    (define (evaluate-arguments (ev Evaluation) (handlers (List ConstantHandler))
                                (frames (List EvaluationFrame))
                                (function Known)
                                (values (List Known))
                                (env (Table Known)) (remaining (List Expr)) (type Type) (loc Loc))
      (→ (Pair Known Evaluation)) (! compile)
      (match remaining
        ((Nil) (run-evaluation ev handlers frames (Invoke function (reverse values) type loc)))
        ((Cons first rest)
         (run-evaluation ev
                         handlers
                         (Cons (ApplyArgument function values env rest type loc) frames)
                         (Evaluate env first)))))

    (define (choose-clause (ev Evaluation) (handlers (List ConstantHandler))
                           (frames (List EvaluationFrame)) (env (Table Known)) (value Known)
                           (clauses (List Clause)) (loc Loc))
      (→ (Pair Known Evaluation)) (! compile)
      (match clauses
        ((Nil) (compile-error loc "non-exhaustive match during constant evaluation"))
        ((Cons clause rest)
         (match (match-value ev env (● clause pattern) value loc)
           ((Some inner) (run-evaluation ev handlers frames (Evaluate inner (● clause body))))
           ((None) (choose-clause ev handlers frames env value rest loc))))))

    (define (bind-values (env (Table Known)) (names (List String)) (values (List Known)))
      (→ (Table Known))
      (fold-left (lambda (env pair) (table-set env (● pair first) (● pair second)))
                 env
                 (zip names values)))

    (define (enter-code (ev Evaluation) (handlers (List ConstantHandler))
                        (frames (List EvaluationFrame))
                        (env (Table Known))
                        (expr Expr)
                        (args (List Known)))
      (→ (Pair Known Evaluation)) (! compile)
      (match (● expr term)
        ((Lambda params body _)
         (run-evaluation ev handlers frames (Evaluate (bind-values env params args) body)))
        (_ (compile-error (● expr loc) "constant evaluation expected a function"))))

    (define (invoke-step (ev Evaluation) (handlers (List ConstantHandler))
                         (frames (List EvaluationFrame))
                         (function Known)
                         (args (List Known))
                         (type Type)
                         (loc Loc))
      (→ (Pair Known Evaluation)) (! compile)
      (match (● function value)
        ((Global name) (invoke-global ev handlers frames name args type loc))
        ((Object _)
         (match (object-value ev function loc)
           ((ClosureValue name env)
            (invoke-closure ev handlers frames function name env args loc))
           ((CodeValue expr env) (enter-code ev handlers frames env expr args))
           ((ResumeValue (Some suspended))
            (resume-evaluation ev handlers frames function suspended args loc))
           ((ResumeValue (None)) (compile-error loc "constant resumption was already consumed"))
           ((OnceValue inner)
            (run-evaluation (replace-object ev function (SpentValue))
                            handlers
                            frames
                            (Invoke inner args type loc)))
           ((BoundValue inner captured)
            (run-evaluation (replace-object ev function (SpentValue)) captured
                            (Cons (RestoreHandlers handlers)
                                  (Cons (ReleaseCaptured captured) frames))
                            (Invoke inner args type loc)))
           (_ (compile-error loc "constant evaluation expected a function"))))
        (_ (compile-error loc "constant evaluation expected a function"))))

    (define (once-type? (type Type)) (→ Bool)
      (match type ((TCon "FnOnce" _) #t) (_ #f)))

    (define (closure-captures (ev Evaluation) (name String) (env (Table Known))) (→ (List Known))
      (concatenate (map (lambda (entry)
                          (match (table-ref env (● entry first))
                            ((Some value) (list value))
                            ((None) (Nil))))
                        (● (recipe ev name) captures))))

    ;; Linear captures follow lexical cleanup order, then shared captures
    ;; release in environment order, as the prepared runtime dropper does.
    (define (closure-cleanup (ev Evaluation) (name String) (env (Table Known)))
      (→ (List Known))
      (concatenate (map (lambda (name)
                          (match (table-ref env name)
                            ((Some value) (list value)) ((None) (Nil))))
                        (● (recipe ev name) cleanup))))

    (define (invoke-closure (ev Evaluation) (handlers (List ConstantHandler))
                            (frames (List EvaluationFrame)) (function Known) (name String)
                            (env (Table Known)) (args (List Known)) (loc Loc))
      (→ (Pair Known Evaluation)) (! compile)
      (let* ((source (recipe ev name))
             (captures (closure-captures ev name env))
             (move-captures?
              (or (once-type? (● function type))
                  (any? (lambda (value) (linear-type? (program ev) (Nil) (● value type)))
                        captures)))
             (ev (if move-captures? (replace-object ev function (ClosureValue name empty-table))
                     (fold-left retain-known ev captures)))
             (ev (match (● source self) ((Some _) (retain-known ev function)) ((None) ev))))
        (evaluating ev ((body (closure-body name)))
                    (enter-code ev
                                handlers
                                (Cons (ReleaseFunction function) frames)
                                empty-table
                                body
                                (append (match (● source self)
                                          ((Some _) (Cons function
                                                          (map
                                                           (lambda (name) (table-ref-or env name))
                                                           (reverse (● source cleanup)))))
                                          ((None) (map (lambda (name) (table-ref-or env name))
                                                       (reverse (● source cleanup)))))
                                        args)))))

    (define (invoke-global (ev Evaluation) (handlers (List ConstantHandler))
                           (frames (List EvaluationFrame))
                           (name String)
                           (args (List Known))
                           (type Type)
                           (loc Loc))
      (→ (Pair Known Evaluation)) (! compile)
      (cond
       ((table-contains? (● ev recipes) name)
        (let ((source (recipe ev name)))
          (return-result (allocate ev type
                                   (ClosureValue name
                                                 (bind-values empty-table
                                                              (map
                                                               (lambda (entry) (● entry first))
                                                               (● source captures))
                                                              args)))
                         handlers frames)))
       ((string-prefix? "prim:" name) (invoke-primitive ev handlers frames name args type loc))
       (else
        (match (program-value (program ev) name)
          ((Some (Constructor _ _))
           (return-result (allocate ev type (RecordValue name args)) handlers frames))
          ((Some (Accessor case index _))
           (check-record-case ev case (car-value args loc) loc)
           (run-evaluation ev
                           handlers
                           frames
                           (ReturnValue
                            (list-ref (record-fields ev (car-value args loc) loc) index))))
          ((Some (Replacer _ index _))
           (if (linear-type? (program ev) (Nil) (● (car-value args loc) type))
               (evaluating ev ((old (record-swap (car-value args loc) index (list-ref args 1) loc)))
                           (run-evaluation ev
                                           handlers
                                           frames
                                           (ReleaseValues (list old)
                                                          (ReturnValue (car-value args loc)))))
               (let* ((fields (record-fields ev (car-value args loc) loc))
                      (ev (fold-left retain-known ev (map-indexed (lambda (i field)
                                                                    (if (= i index)
                                                                        (Known (TCon "Unit" (Nil))
                                                                               (Scalar (DUnit)))
                                                                        field))
                                                                  fields)))
                      (constructor
                       (match (object-value ev (record-owner ev (car-value args loc) loc) loc)
                         ((RecordValue constructor _) constructor)
                         (_ (panic "internal error: record replacement")))))
                 (return-result (allocate ev
                                          type
                                          (RecordValue constructor
                                                       (replace-at fields index (list-ref args 1))))
                                handlers
                                frames))))
          ((Some (Setter case index _))
           (check-record-case ev case (car-value args loc) loc)
           (evaluating ev ((old (record-swap (car-value args loc) index (list-ref args 1) loc)))
                       (run-evaluation ev
                                       handlers
                                       frames
                                       (ReleaseValues (list old) (ReturnValue (unit-known))))))
          ((Some (Swapper case index _))
           (check-record-case ev case (car-value args loc) loc)
           (return-result (record-swap ev (car-value args loc) index (list-ref args 1) loc)
                          handlers
                          frames))
          ((Some (Foreign import _))
           (return-result (foreign-value ev import args type loc) handlers frames))
          ((Some (Operation effect _))
           (perform-operation ev handlers frames effect name args type loc))
          (_ (evaluating ev ((body (body-of name)))
                         (enter-code ev handlers frames empty-table body args)))))))

    (define (check-record-case (ev Evaluation) (case Case) (value Known) (loc Loc))
      (→ Unit) (! compile)
      (match (object-value ev (record-owner ev value loc) loc)
        ((RecordValue constructor _)
         (unless (string=? constructor (● case name))
           (compile-error loc
                          "field access selects the wrong enum case during constant evaluation")))
        (_ (panic "internal error: expected a constant record"))))

    (define (unit-known) (→ Known) (Known (TCon "Unit" (Nil)) (Scalar (DUnit))))

    ;; ---- Source handlers ----

    (define (install-handler (ev Evaluation) (handlers (List ConstantHandler))
                             (frames (List EvaluationFrame)) (effect String) (names (List String))
                             (values (List Known))
                             (env (Table Known))
                             (remaining (List Expr))
                             (body Expr))
      (→ (Pair Known Evaluation)) (! compile)
      (match remaining
        ((Cons first rest)
         (run-evaluation ev
                         handlers
                         (Cons (InstallHandler effect names values env rest body) frames)
                         (Evaluate env first)))
        ((Nil)
         (let ((handler
                (ConstantHandler (i64->string (● ev next)) effect (zip names (reverse values)))))
           (run-evaluation (Evaluation-next-set ev (+ (● ev next) 1)) (Cons handler handlers)
                           (Cons (HandlerBoundary handler) frames) (Evaluate env body))))))

    (define (handler-outside (handlers (List ConstantHandler)) (id String))
      (→ (List ConstantHandler))
      (match handlers
        ((Cons handler rest) (if (string=? (● handler id) id) rest (handler-outside rest id)))
        ((Nil) (panic "internal error: missing constant handler boundary"))))

    (define (handler-prefix (handlers (List ConstantHandler)) (id String))
      (→ (List ConstantHandler))
      (match handlers
        ((Cons handler rest)
         (Cons handler (if (string=? (● handler id) id) (Nil) (handler-prefix rest id))))
        ((Nil) (panic "internal error: missing captured constant handler"))))

    (define (split-frames (frames (List EvaluationFrame)) (id String))
      (→ (Pair (List EvaluationFrame) (List EvaluationFrame)))
      (match frames
        ((Nil) (panic "internal error: constant control handler has no delimiter"))
        ((Cons frame rest)
         (if (match frame ((HandlerBoundary handler) (string=? (● handler id) id)) (_ #f))
             (Pair (list frame) rest)
             (match (split-frames rest id)
               ((Pair inner outer) (Pair (Cons frame inner) outer)))))))

    (define (perform-operation (ev Evaluation) (handlers (List ConstantHandler))
                               (frames (List EvaluationFrame)) (effect String) (name String)
                               (args (List Known)) (type Type) (loc Loc))
      (→ (Pair Known Evaluation)) (! compile)
      (match (find (lambda (handler) (string=? (● handler effect) effect)) handlers)
        ((None)
         (match (assoc-ref (● (program-effect (program ev) effect) defaults) name)
           ((Some default) (invoke-global ev handlers frames default args type loc))
           ((None) (compile-error loc "a compile-time value cannot perform an unhandled effect"))))
        ((Some handler)
         (match (assoc-ref (● handler operations) name)
           ((None) (panic "internal error: incomplete constant handler"))
           ((Some implementation)
            (let ((ev (retain-known ev implementation))
                  (outside (handler-outside handlers (● handler id))))
              (if (member? name (● (program-effect (program ev) effect) control))
                  (perform-control ev handlers frames handler implementation args type loc)
                  (run-evaluation ev outside (Cons (RestoreHandlers handlers) frames)
                                  (Invoke implementation args type loc)))))))))

    (define (perform-control (ev Evaluation) (handlers (List ConstantHandler))
                             (frames (List EvaluationFrame)) (handler ConstantHandler)
                             (implementation Known) (args (List Known)) (type Type) (loc Loc))
      (→ (Pair Known Evaluation)) (! compile)
      (let ((outside (handler-outside handlers (● handler id))))
        (match (split-frames frames (● handler id))
          ((Pair captured frames)
           (if (never-type? type)
               (run-evaluation ev handlers (Cons (RestoreHandlers outside) frames)
                               (CancelFrames captured (Invoke implementation args type loc)))
               (let ((resume-type (match (fn-arrow (● implementation type))
                                    ((TFun params _ _) (list-ref params (- (length params) 1)))
                                    (_ (panic "internal error: control clause has no resume"))))
                     (suspended (Suspension captured (handler-prefix handlers (● handler id)))))
                 (evaluating ev ((resume (allocate resume-type (ResumeValue (Some suspended)))))
                             (run-evaluation ev outside (Cons (RestoreHandlers outside) frames)
                                             (Invoke implementation
                                                     (append args (list resume))
                                                     type
                                                     loc)))))))))

    ;; Fresh activations keep a resumed handler distinct from an identical
    ;; handler still present at the invocation site. There are no mutable
    ;; outside links, so resuming beneath a descendant cannot form a cycle.
    (define (captured-handlers (frames (List EvaluationFrame))) (→ (List ConstantHandler))
      (concatenate (map (lambda (frame)
                          (match frame ((HandlerBoundary handler) (list handler)) (_ (Nil))))
                        frames)))

    (define (renew-handlers (ev Evaluation) (handlers (List ConstantHandler)))
      (→ (Pair (List (Pair String ConstantHandler)) Evaluation))
      (match handlers
        ((Nil) (Pair (Nil) ev))
        ((Cons handler rest)
         (let* ((fresh (ConstantHandler (i64->string (● ev next))
                                        (● handler effect)
                                        (● handler operations)))
                (ev (Evaluation-next-set ev (+ (● ev next) 1))))
           (evaluating ev ((rest (renew-handlers rest)))
                       (Pair (Cons (Pair (● handler id) fresh) rest) ev))))))

    (define (rebase-handlers (saved (List ConstantHandler))
                             (renewed (List (Pair String ConstantHandler)))
                             (outside (List ConstantHandler))) (→ (List ConstantHandler))
                             (match saved
                               ((Nil) outside)
                               ((Cons handler rest)
                                (match (assoc-ref renewed (● handler id))
                                  ((Some fresh)
                                   (Cons fresh (rebase-handlers rest renewed outside)))
                                  ((None) outside)))))

    (define (rebase-frame (frame EvaluationFrame) (renewed (List (Pair String ConstantHandler)))
                          (outside (List ConstantHandler))) (→ EvaluationFrame)
                          (match frame
                            ((HandlerBoundary handler)
                             (match (assoc-ref renewed (● handler id))
                               ((Some fresh) (HandlerBoundary fresh)) ((None) frame)))
                            ((RestoreHandlers saved)
                             (RestoreHandlers (rebase-handlers saved renewed outside)))
                            (_ frame)))

    (define (resume-evaluation (ev Evaluation) (handlers (List ConstantHandler))
                               (frames (List EvaluationFrame))
                               (resume Known)
                               (suspended Suspension)
                               (args (List Known)) (loc Loc))
      (→ (Pair Known Evaluation)) (! compile)
      (let ((ev (replace-object ev resume (ResumeValue (None)))))
        (evaluating ev ((renewed (renew-handlers (captured-handlers (● suspended frames)))))
                    (run-evaluation ev (rebase-handlers (● suspended handlers) renewed handlers)
                                    (append
                                     (map (lambda (frame) (rebase-frame frame renewed handlers))
                                          (● suspended frames))
                                     (Cons (RestoreHandlers handlers) frames))
                                    (ReturnValue (car-value args loc))))))

    (define (cancel-frames (ev Evaluation) (handlers (List ConstantHandler))
                           (frames (List EvaluationFrame))
                           (abandoned (List EvaluationFrame))
                           (next EvaluationAction))
      (→ (Pair Known Evaluation)) (! compile)
      (match abandoned
        ((Nil) (run-evaluation ev handlers frames next))
        ((Cons frame rest)
         (match frame
           ((CancellationGuard env cleanup)
            (match (● cleanup term)
              ((Lambda _ body _)
               (run-evaluation ev
                               handlers
                               (Cons (ContinueAction (CancelFrames rest next)) frames)
                               (Evaluate env body)))
              (_ (panic "internal error: constant cleanup is not a thunk"))))
           ((HandlerBoundary handler)
            (run-evaluation ev (handler-outside handlers (● handler id)) frames
                            (ReleaseValues
                             (map (lambda (entry) (● entry second)) (● handler operations))
                             (CancelFrames rest next))))
           ((RestoreHandlers saved) (run-evaluation ev saved frames (CancelFrames rest next)))
           ((ReleaseFunction function)
            (run-evaluation ev
                            handlers
                            frames
                            (ReleaseValues (list function) (CancelFrames rest next))))
           ((ReleaseCaptured captured)
            (run-evaluation ev
                            handlers
                            frames
                            (ReleaseValues (handler-values captured) (CancelFrames rest next))))
           (_ (run-evaluation ev handlers frames (CancelFrames rest next)))))))


    ;; ---- Interpreted reference counts ----

    (define (replace-object (ev Evaluation) (value Known) (object ObjectValue)) (→ Evaluation)
      (match (● value value)
        ((Object id) (Evaluation-heap-set ev (table-set (● ev heap) id object)))
        (_ (panic "internal error: constant object has no identity"))))

    (define (owner-count (ev Evaluation) (id String)) (→ I64)
      (match (table-ref (● ev counts) id)
        ((Some count) count) ((None) (panic "internal error: constant owner has no count"))))

    (define (retain-known (ev Evaluation) (value Known)) (→ Evaluation)
      (match (● value value)
        ((Object id)
         (if (shared-type? (program ev) (● value type))
             (let ((count (owner-count ev id)))
               (when (<= count 0) (panic "internal error: retaining a dead constant owner"))
               (Evaluation-counts-set ev (table-set (● ev counts) id (+ count 1)))) ev))
        (_ ev)))

    (define (release-values (ev Evaluation) (handlers (List ConstantHandler))
                            (frames (List EvaluationFrame))
                            (values (List Known))
                            (next EvaluationAction))
      (→ (Pair Known Evaluation)) (! compile)
      (match values
        ((Nil) (run-evaluation ev handlers frames next))
        ((Cons value rest)
         (let ((next (ReleaseValues rest next)))
           (match (● value value)
             ((Object id)
              (if (shared-type? (program ev) (● value type))
                  (let ((count (owner-count ev id)))
                    (when (<= count 0) (panic "internal error: releasing a dead constant owner"))
                    (let ((ev
                           (Evaluation-counts-set ev (table-set (● ev counts) id (- count 1)))))
                      (if (= count 1) (finalize-object ev handlers frames value next)
                          (run-evaluation ev handlers frames next))))
                  (run-evaluation ev handlers frames next)))
             (_ (run-evaluation ev handlers frames next)))))))

    (define (finalize-object (ev Evaluation) (handlers (List ConstantHandler))
                             (frames (List EvaluationFrame))
                             (value Known)
                             (next EvaluationAction))
      (→ (Pair Known Evaluation)) (! compile)
      (match (object-value ev value (Loc "constant" 0 0))
        ((RecordValue _ fields) (run-evaluation ev handlers frames (ReleaseValues fields next)))
        ((VectorValue items) (run-evaluation ev handlers frames (ReleaseValues items next)))
        ((DynamicValue inner)
         (run-evaluation ev handlers frames (ReleaseValues (list inner) next)))
        ((ClosureValue name env)
         (let* ((values (closure-captures ev name env))
                (ev (replace-object ev value (ClosureValue name empty-table))))
           (if (any? (lambda (value) (linear-type? (program ev) (Nil) (● value type))) values)
               (drop-captures ev
                              handlers
                              (Cons (ContinueAction next) frames)
                              (closure-cleanup ev name env)
                              (Loc "constant finalizer" 0 0))
               (run-evaluation ev handlers frames (ReleaseValues values next)))))
        ((RcValue (Some payload) finalizer)
         (run-evaluation (replace-object ev value (RcValue (None) finalizer)) handlers
                         (Cons (ContinueAction next) frames)
                         (Invoke finalizer
                                 (list payload)
                                 (TCon "Unit" (Nil))
                                 (Loc "constant finalizer" 0 0))))
        ((BoundValue inner _)
         (run-evaluation ev handlers frames (ReleaseValues (list inner) next)))
        (_ (run-evaluation ev handlers frames next))))

    (define (record-owner (ev Evaluation) (value Known) (loc Loc)) (→ Known) (! compile)
      (match (● value type)
        ((TCon "Rc" _)
         (match (object-value ev value loc)
           ((RcValue (Some payload) _) (record-owner ev payload loc))
           (_ (compile-error loc "constant Rc has already been finalized"))))
        (_ value)))

    (define (drop-closure (ev Evaluation) (handlers (List ConstantHandler))
                          (frames (List EvaluationFrame)) (function Known) (loc Loc))
      (→ (Pair Known Evaluation)) (! compile)
      (match (object-value ev function loc)
        ((ResumeValue (Some suspended))
         (let ((ev (replace-object ev function (ResumeValue (None)))))
           (evaluating ev ((renewed (renew-handlers (captured-handlers (● suspended frames)))))
                       (run-evaluation ev
                                       (rebase-handlers (● suspended handlers) renewed handlers)
                                       (Cons (RestoreHandlers handlers) frames)
                                       (CancelFrames
                                        (map
                                         (lambda (frame) (rebase-frame frame renewed handlers))
                                         (● suspended frames))
                                        (ReturnValue (unit-known)))))))
        ((ResumeValue (None)) (compile-error loc "constant resumption was already consumed"))
        ((ClosureValue name env)
         (let ((ev (replace-object ev function (ClosureValue name empty-table)))
               (values (closure-cleanup ev name env)))
           (drop-captures ev handlers frames values loc)))
        ((CodeValue expr env) (enter-code ev handlers frames env expr (Nil)))
        ((OnceValue inner)
         (run-evaluation (replace-object ev function (SpentValue)) handlers frames
                         (ReleaseValues (list inner) (ReturnValue (unit-known)))))
        ((BoundValue inner captured)
         (run-evaluation (replace-object ev function (SpentValue)) captured
                         (Cons (RestoreHandlers handlers) (Cons (ReleaseCaptured captured) frames))
                         (Invoke (Known (TFun (list (● inner type)) (TCon "Unit" (Nil)) empty-row)
                                        (Global "prim:drop-once"))
                                 (list inner) (TCon "Unit" (Nil)) loc)))
        (_ (compile-error loc "constant drop-once expected a one-shot function"))))

    (define (drop-captures (ev Evaluation) (handlers (List ConstantHandler))
                           (frames (List EvaluationFrame)) (values (List Known)) (loc Loc))
      (→ (Pair Known Evaluation)) (! compile)
      (match (request-drops (● ev state) (map (lambda (value) (● value type)) values) loc)
        ((Pair drops state)
         (let ((ev (Evaluation-state-set ev state)))
           (run-evaluation ev handlers frames
                           (Evaluate (bind-values empty-table
                                                  (map (lambda (index)
                                                         (string-append "%drop."
                                                                        (i64->string index)))
                                                       (iota (length values)))
                                                  values)
                                     (fold-right
                                      (lambda (pair rest)
                                        (let* ((value (● pair second))
                                               (name
                                                (string-append "%drop."
                                                               (i64->string (● pair first))))
                                               (drop
                                                (match (table-ref drops (type-key (● value type)))
                                                  ((Some drop) drop)
                                                  ((None)
                                                   (panic
                                                    "internal error: missing constant drop")))))
                                          (Expr (Seq (Expr (App drop
                                                                (list (Expr (Var name (Nil) (Nil))
                                                                            (● value type)
                                                                            loc)))
                                                           (TCon "Unit" (Nil)) loc) rest)
                                                (TCon "Unit" (Nil))
                                                loc)))
                                      (Expr (Lit (DUnit)) (TCon "Unit" (Nil)) loc)
                                      (zip (iota (length values)) values))))))))

    ;; ---- Calls implemented by the evaluator ----

    (define (invoke-primitive (ev Evaluation) (handlers (List ConstantHandler))
                              (frames (List EvaluationFrame))
                              (name String)
                              (args (List Known))
                              (type Type)
                              (loc Loc))
      (→ (Pair Known Evaluation)) (! compile)
      (case name
        (("prim:retain" "prim:pattern-retain")
         (run-evaluation (retain-known ev (car-value args loc))
                         handlers
                         frames
                         (ReturnValue (car-value args loc))))
        (("prim:release" "prim:discard")
         (run-evaluation ev handlers frames (ReleaseValues args (ReturnValue (unit-known)))))
        (("prim:rc-new")
         (return-result (allocate ev type (RcValue (Some (car-value args loc)) (list-ref args 1)))
                        handlers
                        frames))
        (("prim:rc-get")
         (match (object-value ev (car-value args loc) loc)
           ((RcValue (Some payload) _) (run-evaluation ev handlers frames (ReturnValue payload)))
           (_ (compile-error loc "constant Rc has already been finalized"))))
        (("prim:rc-downgrade")
         (run-evaluation ev
                         handlers
                         frames
                         (ReturnValue (Known type (● (car-value args loc) value)))))
        (("prim:once")
         (return-result (allocate ev type (OnceValue (car-value args loc))) handlers frames))
        (("prim:weak-rc-upgrade")
         (upgrade-constant ev handlers frames (car-value args loc) type loc))
        (("prim:unsafe-total" "prim:call-once")
         (run-evaluation ev
                         handlers
                         frames
                         (Invoke (car-value args loc) (list-drop args 1) type loc)))
        (("prim:drop-once")
         (match (● (car-value args loc) value)
           ((Global _) (run-evaluation ev handlers frames (ReturnValue (unit-known))))
           (_ (drop-closure ev handlers frames (car-value args loc) loc))))
        (("prim:once-dropping")
         (if (once-type? type)
             (return-result (allocate ev type (OnceValue (car-value args loc))) handlers frames)
             (run-evaluation ev handlers frames (ReturnValue (car-value args loc)))))
        (("prim:inherit-handlers" "prim:inherit-handlers-1")
         (return-result
          (allocate (retained-handlers ev handlers) type (BoundValue (car-value args loc) handlers))
          handlers
          frames))
        (("prim:vector-generate" "prim:string-generate")
         (let ((size (integer-value (car-value args loc) loc)))
           (check-size size loc)
           (generate-element ev handlers frames (list-ref args 1) 0 size (Nil) type loc)))
        (("prim:vector-set!")
         (let* ((array (car-value args loc)) (index (integer-value (list-ref args 1) loc))
                (items (sequence-values ev array loc)))
           (check-range index 1 (length items) loc)
           (evaluating ev ((result (write-vector-element array index (list-ref args 2) type loc)))
                       (run-evaluation ev
                                       handlers
                                       frames
                                       (ReleaseValues (list (list-ref items index))
                                                      (ReturnValue result))))))
        (("prim:vector-copy!")
         (copy-vector-contents ev handlers frames args type loc))
        (("prim:vector-set")
         (let* ((items (sequence-values ev (car-value args loc) loc))
                (index (integer-value (list-ref args 1) loc)))
           (check-range index 1 (length items) loc)
           (let ((ev (fold-left (lambda (ev pair)
                                  (if (= (● pair first) index)
                                      ev
                                      (retain-known ev (● pair second))))
                                ev (zip (iota (length items)) items))))
             (return-result
              (sequence-value ev type (replace-at items index (list-ref args 2)) loc)
              handlers
              frames))))
        (("prim:make-string" "prim:make-vector")
         (let ((size (integer-value (car-value args loc) loc)) (value (list-ref args 1)))
           (check-size size loc)
           (let* ((items (map (lambda (index) value) (iota size)))
                  (ev (fold-left retain-known ev items)))
             (return-result (sequence-value ev type items loc) handlers frames))))
        (("prim:vector-append"
          "prim:string-append"
          "prim:subvector"
          "prim:substring"
          "prim:vector-copy")
         (evaluating ev ((value (primitive-value name args type loc)))
                     (run-evaluation (fold-left retain-known ev (sequence-values ev value loc))
                                     handlers
                                     frames
                                     (ReturnValue value))))
        (("prim:string->vector" "prim:vector->string")
         (return-result (sequence-value ev type (sequence-values ev (car-value args loc) loc) loc)
                        handlers frames))
        (("prim:vector") (return-result (sequence-value ev type (Nil) loc) handlers frames))
        (("prim:vector-push!")
         (let* ((vector (car-value args loc)) (items (sequence-values ev vector loc)))
           (check-size (+ (length items) 1) loc)
           (return-result
            (scalar (replace-vector-contents ev vector (append items (list (list-ref args 1))) loc)
                    type (DUnit)) handlers frames)))
        (("prim:vector-take-last!")
         (let* ((vector (car-value args loc))
                (items (sequence-values ev vector loc))
                (size (length items)))
           (check-range (- size 1) 1 size loc)
           (run-evaluation (replace-vector-contents ev vector (take items (- size 1)) loc)
                           handlers frames (ReturnValue (list-ref items (- size 1))))))
        (else (return-result (primitive-value ev name args type loc) handlers frames))))

    (define (check-size (size I64) (loc Loc)) (→ Unit) (! compile)
      (when (or (< size 0) (> size 1000000))
        (compile-error loc "constant vector length must be between 0 and 1000000")))

    (define (generate-element (ev Evaluation) (handlers (List ConstantHandler))
                              (frames (List EvaluationFrame))
                              (function Known)
                              (index I64)
                              (size I64)
                              (values (List Known)) (type Type) (loc Loc))
      (→ (Pair Known Evaluation)) (! compile)
      (if (= index size)
          (return-result (sequence-value ev type (reverse values) loc) handlers frames)
          (let ((element (match type
                           ((TCon "String" _) (TCon "Char" (Nil)))
                           ((TCon _ (Cons element _)) element)
                           (_ (panic "internal error: array type")))))
            (run-evaluation (retain-known ev function) handlers
                            (Cons (GeneratedElement function index size values type loc) frames)
                            (Invoke function
                                    (list (Known (TCon "I64" (Nil)) (Scalar (DInt index))))
                                    element
                                    loc)))))

    (define (upgrade-constant (ev Evaluation) (handlers (List ConstantHandler))
                              (frames (List EvaluationFrame)) (weak Known) (type Type) (loc Loc))
      (→ (Pair Known Evaluation)) (! compile)
      (let* ((strong-type (match type ((TCon _ (Cons strong (Nil))) strong)
                                 (_ (panic "internal error: weak upgrade result"))))
             (strong (Known strong-type (● weak value)))
             (live? (match (● weak value) ((Object id) (> (owner-count ev id) 0)) (_ #f))))
        (return-result (allocate (if live? (retain-known ev strong) ev) type
                                 (RecordValue
                                  (if live? "snail.core.base:Some" "snail.core.base:None")
                                  (if live? (list strong) (Nil)))) handlers frames)))

    (define (copy-vector-contents (ev Evaluation) (handlers (List ConstantHandler))
                                  (frames (List EvaluationFrame))
                                  (args (List Known))
                                  (type Type)
                                  (loc Loc))
      (→ (Pair Known Evaluation)) (! compile)
      (let* ((target (car-value args loc)) (at (integer-value (list-ref args 1) loc))
             (source (list-ref args 2)) (from (integer-value (list-ref args 3) loc))
             (count (integer-value (list-ref args 4) loc))
             (old (sequence-values ev target loc)) (incoming (sequence-values ev source loc)))
        (check-range at count (length old) loc)
        (check-range from count (length incoming) loc)
        (let ((ev (fold-left retain-known ev (take (list-drop incoming from) count))))
          (evaluating ev ((result (copy-vector-elements target at source from count type loc)))
                      (run-evaluation ev
                                      handlers
                                      frames
                                      (ReleaseValues (take (list-drop old at) count)
                                                     (ReturnValue result)))))))


    ;; Any carries the same concrete type and payload as at runtime. Copying
    ;; its wrapper copies the payload through the shared graph identity map.
    (define (dynamic-inner (ev Evaluation) (value Known) (loc Loc)) (→ Known) (! compile)
      (match (object-value ev value loc)
        ((DynamicValue inner) inner)
        (_ (compile-error loc "constant evaluation expected Any"))))

    (define (convert-value (ev Evaluation) (value Known) (target Type) (loc Loc))
      (→ (Pair Known Evaluation)) (! compile)
      (cond ((string=? (type-key (● value type)) (type-key target)) (Pair value ev))
            ((any-type? target) (allocate ev target (DynamicValue value)))
            (else
             (let ((inner (dynamic-inner ev value loc)))
               (unless (string=? (type-key (● inner type)) (type-key target))
                 (compile-error loc "internal error: unchecked constant conversion"))
               (Pair inner ev)))))











    (define (car-value (values (List Known)) (loc Loc)) (→ Known) (! compile)
      (match values
        ((Cons value _) value)
        ((Nil) (compile-error loc "missing constant operand"))))

    (define (record-fields (ev Evaluation) (value Known) (loc Loc)) (→ (List Known)) (! compile)
      (match (object-value ev (record-owner ev value loc) loc)
        ((RecordValue _ fields) fields)
        (_ (compile-error loc "constant evaluation expected a record"))))

    (define (replace-at (values (List Known)) (index I64) (value Known)) (→ (List Known))
      (map-indexed (lambda (i previous) (if (= i index) value previous)) values))

    ;; A checked place identifies one record slot. Evaluate its owner before
    ;; the replacement, then update that identity in the evaluation heap.
    ;; Aliases observe the write; copying a constant still copies its graph.


    (define (record-swap (ev Evaluation) (owner Known) (index I64) (value Known) (loc Loc))
      (→ (Pair Known Evaluation)) (! compile)
      (let ((owner (record-owner ev owner loc)))
        (match (Pair (● owner value) (object-value ev owner loc))
          ((Pair (Object id) (RecordValue name fields))
           (Pair (list-ref fields index)
                 (Evaluation-heap-set ev
                                      (table-set (● ev heap) id
                                                 (RecordValue name
                                                              (replace-at fields index value))))))
          (_ (compile-error loc "constant field update expected a record")))))

    ;; Only deterministic scalar services are callable here. An extern's
    ;; empty row alone never authorizes host IO during compilation.
    (define (foreign-value (ev Evaluation) (import Import) (args (List Known))
                           (type Type) (loc Loc))
      (→ (Pair Known Evaluation)) (! compile)
      (unless (and (string=? (● import module) "snail.core.support")
                   (or (string-prefix? "snail:text/" (● import symbol))
                       (string=? (● import symbol) "snail:datum/whitespace")))
        (compile-error loc "a compile-time value cannot call this foreign function"))
      (let ((code (unicode-code (car-value args loc) loc))
            (index (if (= (length args) 2) (i64->i32 (integer-value (list-ref args 1) loc)) 0)))
        (when (and (string=? (● import symbol) "snail:text/full-fold-scalar")
                   (match (unicode-scalar "snail:text/full-fold-length" code 0)
                     ((Some size) (or (< index 0) (>= index size))) ((None) #t)))
          (compile-error loc "full case-fold component index out of range"))
        (match (unicode-scalar (● import symbol) code index)
          ((Some result)
           (scalar ev type (if (string=? (type-key type) "Char")
                               (DChar (integer->char (i32->i64 result)))
                               (DInt (i32->i64 result)))))
          ((None) (compile-error loc "unknown compile-time Unicode service")))))

    (define (unicode-code (value Known) (loc Loc)) (→ I32) (! compile)
      (let ((code (integer-value value loc)))
        (when (or (< code 0) (> code 1114111) (and (>= code 55296) (<= code 57343)))
          (compile-error loc "compile-time Unicode service requires a Unicode scalar"))
        (i64->i32 code)))

    ;; ---- Patterns ----



    (define (match-value (ev Evaluation)
                         (env (Table Known))
                         (pattern Pattern)
                         (value Known)
                         (loc Loc))
      (→ (Option (Table Known))) (! compile)
      (match pattern
        ((PWild _) (Some env))
        ((PVar name _) (Some (table-set env name value)))
        ((PLit datum _)
         (if (literal-matches? ev datum value loc) (Some env) (None)))
        ((PCon name args _)
         (match (object-value ev value loc)
           ((RecordValue actual fields)
            (if (string=? name actual) (match-fields ev (Some env) args fields loc) (None)))
           (_ (None))))))

    (define (literal-matches? (ev Evaluation) (datum Datum) (value Known) (loc Loc))
      (→ Bool) (! compile)
      (match datum
        ((DChar char) (= (char->integer char) (integer-value value loc)))
        ((DString text)
         (=
          (compare-characters (sequence-values ev (Known (TCon "String" (Nil)) (Scalar datum)) loc)
                              (sequence-values ev value loc) loc) 0))
        (_ (match (● value value) ((Scalar actual) (datum=? datum actual)) (_ #f)))))

    (define (match-fields (ev Evaluation) (env (Option (Table Known)))
                          (patterns (List Pattern)) (values (List Known)) (loc Loc))
      (→ (Option (Table Known))) (! compile)
      (fold-left (lambda (env pair)
                   (match env
                     ((Some inner) (match-value ev inner (● pair first) (● pair second) loc))
                     ((None) (None))))
                 env (zip patterns values)))

    ;; ---- Fresh constant graphs ----

    ;; Reserve all identities before connecting any edges. The table is only
    ;; bookkeeping: each owning field and the returned root establish their
    ;; own credits. Weak-only targets become expired cells, without copying
    ;; their payload or finalizer. No user code runs during construction.
    (struct Copying
      ((evaluation Evaluation)
       (objects (Table String))))

    (define (copy-value (ev Evaluation) (value Known)) (→ (Pair Known Evaluation)) (! compile)
      (let* ((loc (Loc "constant copy" 0 0)) (graph (ordered-graph ev value loc))
             (copying (fold-left reserve-copy (Copying ev empty-table) (● graph values)))
             (copying (fold-left (lambda (copying value)
                                   (copy-node copying
                                              value
                                              (graph-object ev (● graph owning) value loc)))
                                 copying (● graph values))))
        (match (copy-known copying value)
          ((Pair value copying) (Pair value (● copying evaluation))))))

    (define (copy-node (copying Copying) (value Known) (object ObjectValue))
      (→ Copying) (! compile)
      (match (copy-object-value
              (Copying-evaluation-set copying (reserve-object (● copying evaluation) object))
              object)
        ((Pair object copying)
         (match (● value value)
           ((Object old)
            (let* ((fresh (match (table-ref (● copying objects) old)
                            ((Some id) id)
                            ((None) (panic "internal error: missing copied identity"))))
                   (ev (● copying evaluation)))
              (Copying-evaluation-set copying
                                      (Evaluation-heap-set ev
                                                           (table-set (● ev heap) fresh object)))))
           (_ (panic "internal error: copied graph node has no identity"))))))

    (define (copy-known (copying Copying) (value Known)) (→ (Pair Known Copying))
      (match (● value value)
        ((Object old)
         (match (table-ref (● copying objects) old)
           ((Some fresh)
            (let* ((ev (● copying evaluation))
                   (count (owner-count ev fresh))
                   (ev (if (shared-type? (program ev) (● value type))
                           (Evaluation-counts-set ev (table-set (● ev counts) fresh (+ count 1)))
                           ev)))
              (Pair (Known (● value type) (Object fresh)) (Copying-evaluation-set copying ev))))
           ((None) (panic "internal error: copied reference has no reserved identity"))))
        (_ (Pair value copying))))

    (define (reserve-copy (copying Copying) (value Known)) (→ Copying)
      (match (● value value)
        ((Object old)
         (let* ((ev (● copying evaluation)) (fresh (i64->string (● ev next)))
                (ev (Evaluation-counts-set ev (table-set (● ev counts) fresh 0))))
           (Copying (Evaluation-next-set ev (+ (● ev next) 1))
                    (table-set (● copying objects) old fresh))))
        (_ (panic "internal error: copied graph node has no identity"))))

    (define (handler-values (handlers (List ConstantHandler))) (→ (List Known))
      (concatenate
       (map (lambda (handler) (map (lambda (entry) (● entry second)) (● handler operations)))
            handlers)))

    (define (retained-handlers (ev Evaluation) (handlers (List ConstantHandler))) (→ Evaluation)
      (fold-left (lambda (ev handler)
                   (fold-left (lambda (ev entry) (retain-known ev (● entry second)))
                              ev
                              (● handler operations)))
                 ev
                 handlers))

    (define (copy-handlers (copying Copying) (handlers (List ConstantHandler)))
      (→ (Pair (List ConstantHandler) Copying))
      (let loop ((copying copying) (remaining handlers) (done (Nil)))
        (match remaining
          ((Nil) (Pair (reverse done) copying))
          ((Cons handler rest)
           (match (copy-values copying
                               (map (lambda (entry) (● entry second)) (● handler operations)))
             ((Pair values copying)
              (loop copying rest
                    (Cons (ConstantHandler (● handler id) (● handler effect)
                                           (zip (map (lambda (entry) (● entry first))
                                                     (● handler operations)) values)) done))))))))

    (define (reify-bound-handlers (r Reifying)
                                  (handlers (List ConstantHandler))
                                  (body Expr)
                                  (loc Loc))
      (→ (Pair Expr Reifying)) (! compile)
      (match handlers
        ((Nil) (Pair body r))
        ((Cons handler rest)
         (match (reify-values r (map (lambda (entry) (● entry second)) (● handler operations)) loc)
           ((Pair values r)
            (reify-bound-handlers r rest
                                  (Expr (Handle (● handler effect)
                                                (zip (map (lambda (entry) (● entry first))
                                                          (● handler operations))
                                                     values)
                                                body)
                                        (● body type) loc) loc))))))

    (define (reify-bound (r Reifying)
                         (function Known)
                         (handlers (List ConstantHandler))
                         (type Type)
                         (loc Loc))
      (→ (Pair Expr Reifying)) (! compile)
      (match (reify-value r function loc)
        ((Pair function r)
         (let ((primitive (match (fn-arrow type)
                            ((TFun (Nil) _ _) "prim:inherit-handlers")
                            (_ "prim:inherit-handlers-1"))))
           (reify-bound-handlers r
                                 handlers
                                 (constant-call primitive (list function) type loc)
                                 loc)))))


    (define (copy-object-value (copying Copying) (object ObjectValue))
      (→ (Pair ObjectValue Copying)) (! compile)
      (match object
        ((RecordValue name fields)
         (match (copy-values copying fields)
           ((Pair fields copying) (Pair (RecordValue name fields) copying))))
        ((VectorValue items)
         (match (copy-values copying items)
           ((Pair items copying) (Pair (VectorValue items) copying))))
        ((ByteVectorValue bytes) (Pair (ByteVectorValue bytes) copying))
        ((DynamicValue inner)
         (match (copy-known copying inner)
           ((Pair inner copying) (Pair (DynamicValue inner) copying))))
        ((ClosureValue name env)
         (let ((names (table-keys env)))
           (match (copy-values copying (map (lambda (name) (table-ref-or env name)) names))
             ((Pair values copying)
              (Pair (ClosureValue name (bind-values empty-table names values)) copying)))))
        ((RcValue (Some payload) finalizer)
         (match (copy-values copying (list payload finalizer))
           ((Pair values copying)
            (Pair (RcValue (Some (list-ref values 0)) (list-ref values 1)) copying))))
        ((RcValue (None) _) (Pair (RcValue (None) (unit-known)) copying))
        ((OnceValue inner)
         (match (copy-known copying inner)
           ((Pair inner copying) (Pair (OnceValue inner) copying))))
        ((BoundValue inner handlers)
         (match (copy-known copying inner)
           ((Pair inner copying)
            (match (copy-handlers copying handlers)
              ((Pair handlers copying) (Pair (BoundValue inner handlers) copying))))))
        (_ (compile-error (Loc "constant" 0 0)
                          "a live interpreter continuation cannot escape in a compile-time value"))))

    (define (table-ref-or (table (Table Known)) (name String)) (→ Known)
      (match (table-ref table name)
        ((Some value) value)
        ((None) (panic "internal error: missing constant binding"))))

    (define (copy-values (copying Copying) (values (List Known)))
      (→ (Pair (List Known) Copying))
      (let loop ((copying copying) (values values) (done (Nil)))
        (match values
          ((Nil) (Pair (reverse done) copying))
          ((Cons first rest)
           (match (copy-known copying first)
             ((Pair first copying) (loop copying rest (Cons first done))))))))

    ;; ---- Floating-point values ----

    (define (literal-value (ev Evaluation) (type Type) (datum Datum) (loc Loc))
      (→ (Pair Known Evaluation)) (! compile)
      (match datum
        ((DBytes bytes) (allocate ev type (ByteVectorValue bytes)))
        ((DFloat text)
         (match (read-real text)
           ((Some value) (real-result ev type value))
           ((None) (compile-error loc "invalid floating-point constant"))))
        (_ (scalar ev type datum))))

    (define (real-value (value Known) (loc Loc)) (→ F64) (! compile)
      (match (● value value)
        ((RealValue value) value)
        ((Scalar (DInt value)) (integer-real value))
        (_ (compile-error loc "constant evaluation expected a floating-point number"))))

    (define (real-result (ev Evaluation) (type Type) (value F64)) (→ (Pair Known Evaluation))
      (Pair
       (Known type (RealValue (if (string=? (type-key type) "F32") (round-single value) value)))
       ev))

    (define (real-operation (ev Evaluation)
                            (operation String)
                            (args (List Known))
                            (type Type)
                            (loc Loc))
      (→ (Pair Known Evaluation)) (! compile)
      (let* ((op (substring operation 4 (string-length operation)))
             (a (real-value (list-ref args 0) loc))
             (b (if (= (length args) 2) (real-value (list-ref args 1) loc) 0.0)))
        (case op
          (("eq") (scalar ev type (DBool (= a b))))
          (("lt") (scalar ev type (DBool (< a b))))
          (("le") (scalar ev type (DBool (<= a b))))
          (("gt") (scalar ev type (DBool (> a b))))
          (("ge") (scalar ev type (DBool (>= a b))))
          (else (real-result ev type
                             (case op
                               (("add") (+ a b))
                               (("sub") (- a b))
                               (("mul") (* a b))
                               (("div") (/ a b))
                               (("negate")
                                (bits-real (i64-xor (real-bits a) -9223372036854775808)))
                               (("abs") (bits-real (i64-and (real-bits a) 9223372036854775807)))
                               (("min") (real-minmax a b #t))
                               (("max") (real-minmax a b #f))
                               (("sqrt") (if (< a 0.0) (bits-real 9221120237041090560) (sqrt a)))
                               (("floor" "ceiling" "truncate" "round") (real-round op a))
                               (else (compile-error loc
                                                    (string-append "unknown float primitive: "
                                                                   operation)))))))))

    (define (real-minmax (a F64) (b F64) (minimum? Bool)) (→ F64)
      (cond ((or (not (= a a)) (not (= b b))) (bits-real 9221120237041090560))
            ((and (= a 0.0) (= b 0.0))
             (bits-real (if minimum? (i64-or (real-bits a) (real-bits b))
                            (i64-and (real-bits a) (real-bits b)))))
            ((if minimum? (< a b) (> a b)) a)
            (else b)))

    (define (real-round (operation String) (value F64)) (→ F64)
      (let ((exponent (i64-and (i64-shift-right/logical (real-bits value) 52) 2047)))
        (if (= exponent 2047) value
            (let ((result (case operation
                            (("floor") (floor value))
                            (("ceiling") (ceiling value))
                            (("truncate") (truncate value))
                            (else (round value)))))
              (if (= result 0.0)
                  (bits-real (i64-and (real-bits value) -9223372036854775808))
                  result)))))

    (define (truncate-real (ev Evaluation) (type Type) (value F64) (loc Loc))
      (→ (Pair Known Evaluation)) (! compile)
      (let* ((value (real-round "truncate" value)) (small? (string=? (type-key type) "I32"))
             (limit (if small? 2147483648.0 9223372036854775808.0)))
        (unless (and (>= value (- 0.0 limit)) (< value limit))
          (compile-error loc "floating-point conversion overflow during constant evaluation"))
        (scalar ev type (DInt (real-integer value)))))

    ;; Hex literals preserve the target bits across bootstrap hosts and avoid
    ;; depending on the host's decimal printer, including negative zero.
    (define (real-datum (type Type) (value F64)) (→ Datum)
      (if (string=? (type-key type) "F32")
          (DFloat (real-hex (i32->i64 (single-bits value)) 23 8 127))
          (DFloat (real-hex (real-bits value) 52 11 1023))))

    (define (hex-digits (value I64) (digits I64)) (→ String)
      (string-generate digits
                       (lambda (index)
                         (string-ref "0123456789abcdef"
                                     (i64-and
                                      (i64-shift-right/logical value (* 4 (- (- digits 1) index)))
                                      15)))))

    (define (real-hex (bits I64) (fraction-bits I64) (exponent-bits I64) (bias I64)) (→ String)
      (let* ((sign (if (< bits 0) "-" ""))
             (maximum (- (i64-shift-left 1 exponent-bits) 1))
             (exponent (i64-and (i64-shift-right/logical bits fraction-bits) maximum))
             (fraction (i64-and bits (- (i64-shift-left 1 fraction-bits) 1)))
             (digits (quotient (+ fraction-bits 3) 4)))
        (if (= exponent maximum)
            (string-append sign
                           (if (= fraction 0)
                               "inf"
                               (string-append "nan:0x" (hex-digits fraction digits))))
            (string-append sign (if (= exponent 0) "0x0." "0x1.")
                           (hex-digits (i64-shift-left fraction (- (* digits 4) fraction-bits))
                                       digits)
                           "p" (i64->string (- (if (= exponent 0) 1 exponent) bias))))))

    ;; ---- Primitive evaluation ----

    (define (boolean-value (value Known) (loc Loc)) (→ Bool) (! compile)
      (match (● value value)
        ((Scalar (DBool value)) value)
        (_ (compile-error loc "constant evaluation expected a Boolean"))))

    (define (integer-value (value Known) (loc Loc)) (→ I64) (! compile)
      (match (● value value)
        ((Scalar (DInt value)) value)
        ((Scalar (DChar value)) (char->integer value))
        ((Scalar (DBool value)) (if value 1 0))
        (_ (compile-error loc "constant evaluation expected an integer"))))

    (define (text-value (ev Evaluation) (value Known) (loc Loc)) (→ String) (! compile)
      (match (● value value)
        ((Scalar (DString value)) value)
        (_ (list->string
            (map (lambda (value)
                   (let ((code (integer-value value loc)))
                     (integer->char (if (unicode-scalar? code) code 65533))))
                 (sequence-values ev value loc))))))

    (define (unicode-scalar? (code I64)) (→ Bool)
      (and (>= code 0) (<= code 1114111) (or (< code 55296) (> code 57343))))

    (define (sequence-values (ev Evaluation) (value Known) (loc Loc)) (→ (List Known)) (! compile)
      (match (● value value)
        ((Scalar (DString text))
         (map (lambda (char) (Known (TCon "Char" (Nil)) (Scalar (DChar char))))
              (string->list text)))
        (_ (match (object-value ev value loc)
             ((VectorValue items) items)
             ((ByteVectorValue bytes) (byte-values bytes))
             (_ (compile-error loc "constant evaluation expected a vector"))))))

    (define (scalar (ev Evaluation) (type Type) (datum Datum)) (→ (Pair Known Evaluation))
      (Pair (Known type (Scalar datum)) ev))

    (define (byte-values (bytes Bytes)) (→ (List Known))
      (map (lambda (byte) (Known (TCon "U8" (Nil)) (Scalar (DInt (i32->i64 (u8->i32 byte))))))
           (vector->list bytes)))

    (define (vector-object (type Type) (items (List Known)) (loc Loc)) (→ ObjectValue) (! compile)
      (if (bytes-type? type)
          (ByteVectorValue
           (list->vector (map (lambda (value) (i32->u8 (i64->i32 (integer-value value loc))))
                              items)))
          (VectorValue items)))

    (define (sequence-value (ev Evaluation) (type Type) (items (List Known)) (loc Loc))
      (→ (Pair Known Evaluation)) (! compile)
      (if (and (string=? (type-key type) "String")
               (every? (lambda (value) (unicode-scalar? (integer-value value loc))) items))
          (scalar ev type (DString (list->string (map (lambda (value)
                                                        (integer->char (integer-value value loc)))
                                                      items))))
          (allocate ev type (vector-object type items loc))))

    ;; Char is an i32 at the primitive boundary. Keep non-scalar code units
    ;; in arrays without asking the bootstrap host to construct a character.
    ;; Unicode services validate them separately, just as the runtime does.
    (define (compare-characters (left (List Known)) (right (List Known)) (loc Loc))
      (→ I64) (! compile)
      (match (Pair left right)
        ((Pair (Nil) (Nil)) 0)
        ((Pair (Nil) _) -1)
        ((Pair _ (Nil)) 1)
        ((Pair (Cons a left) (Cons b right))
         (let ((a (i64-and (integer-value a loc) 4294967295))
               (b (i64-and (integer-value b loc) 4294967295)))
           (cond ((< a b) -1) ((> a b) 1) (else (compare-characters left right loc)))))))

    (define (primitive-value (ev Evaluation)
                             (name String)
                             (args (List Known))
                             (type Type)
                             (loc Loc))
      (→ (Pair Known Evaluation)) (! compile)
      (let ((op (substring name 5 (string-length name)))
            (arg (lambda (index) (list-ref args index)))
            (integer (lambda (index) (integer-value (list-ref args index) loc))))
        (cond
         ((and (or (string-prefix? "i64-" op) (string-prefix? "i32-" op))
               (not (char=? (string-ref op 4) #\>)))
          (scalar ev type (integer-operation op args loc)))
         ((and (or (string-prefix? "f64-" op) (string-prefix? "f32-" op))
               (not (char=? (string-ref op 4) #\>)))
          (real-operation ev op args type loc))
         (else
          (case op
            (("i32->f64" "i64->f64" "i32->f32" "i64->f32")
             (real-result ev type (integer-real (integer 0))))
            (("f32->f64" "f64->f32") (real-result ev type (real-value (arg 0) loc)))
            (("f32->i32" "f32->i64" "f64->i32" "f64->i64")
             (truncate-real ev type (real-value (arg 0) loc) loc))
            (("f64->bits") (scalar ev type (DInt (real-bits (real-value (arg 0) loc)))))
            (("f32->bits")
             (scalar ev type (DInt (i32->i64 (single-bits (real-value (arg 0) loc))))))
            (("bits->f64") (real-result ev type (bits-real (integer 0))))
            (("bits->f32") (real-result ev type (bits-single (i64->i32 (integer 0)))))
            (("unit" "discard") (scalar ev type (DUnit)))
            (("any-type-id")
             (scalar ev type
                     (DInt (any-type-id (program ev) (● (dynamic-inner ev (arg 0) loc) type)))))
            (("panic")
             (compile-error loc (string-append "constant panic: " (text-value ev (arg 0) loc))))
            (("bool->i32" "char->i32" "u8->i32" "i32->i64") (scalar ev type (DInt (integer 0))))
            (("i64->i32") (scalar ev type (DInt (i32->i64 (i64->i32 (integer 0))))))
            (("i32->u8") (scalar ev type (DInt (i64-and (integer 0) 255))))
            (("i32->bool") (scalar ev type (DBool (not (= (integer 0) 0)))))
            (("i32->char")
             (let ((value (integer 0)))
               (scalar ev type (if (unicode-scalar? value) (DChar (integer->char value))
                                   (DInt value)))))
            (("string-length" "vector-length")
             (scalar ev type (DInt (length (sequence-values ev (arg 0) loc)))))
            (("string-ref" "vector-ref")
             (let ((items (sequence-values ev (arg 0) loc)) (index (integer 1)))
               (check-range index 1 (length items) loc)
               (Pair (list-ref items index) ev)))
            (("string-append" "vector-append")
             (sequence-value ev type (append (sequence-values ev (arg 0) loc)
                                             (sequence-values ev (arg 1) loc)) loc))
            (("substring" "subvector")
             (let ((items (sequence-values ev (arg 0) loc)) (start (integer 1)) (end (integer 2)))
               (check-range start (- end start) (length items) loc)
               (sequence-value ev type (take (list-drop items start) (- end start)) loc)))
            (("make-string" "make-vector")
             (when (< (integer 0) 0)
               (compile-error loc "negative vector length in a compile-time value"))
             (sequence-value ev type (map (lambda (index) (arg 1)) (iota (integer 0))) loc))
            (("string->vector" "vector->string" "vector-copy")
             (sequence-value ev type (sequence-values ev (arg 0) loc) loc))
            (("vector-set")
             (let ((items (sequence-values ev (arg 0) loc)))
               (check-range (integer 1) 1 (length items) loc)
               (sequence-value ev type (replace-at items (integer 1) (arg 2)) loc)))

            (("string=?")
             (scalar ev type (DBool (= (compare-characters (sequence-values ev (arg 0) loc)
                                                           (sequence-values ev (arg 1) loc) loc)
                                       0))))
            (("string-compare")
             (scalar ev type (DInt (compare-characters (sequence-values ev (arg 0) loc)
                                                       (sequence-values ev (arg 1) loc) loc))))
            ;; Total wrappers may use private, newly allocated scratch. Its
            ;; writes stay inside this interpreter's heap, never a host heap.

            (("vector-set!") (write-vector-element ev (arg 0) (integer 1) (arg 2) type loc))
            (("vector-copy!")
             (copy-vector-elements ev (arg 0) (integer 1) (arg 2) (integer 3) (integer 4) type loc))
            (else (compile-error loc
                                 (string-append
                                  "primitive is not available during constant evaluation: "
                                  op))))))))

    (define (string-prefix? (prefix String) (text String)) (→ Bool)
      (and (<= (string-length prefix) (string-length text))
           (string=? prefix (substring text 0 (string-length prefix)))))

    (define (check-range (start I64) (count I64) (size I64) (loc Loc)) (→ Unit) (! compile)
      (when (or (< start 0) (< count 0) (> start size) (> count (- size start)))
        (compile-error loc "vector index out of bounds during constant evaluation")))



    (define (replace-vector-contents (ev Evaluation) (vector Known) (items (List Known)) (loc Loc))
      (→ Evaluation) (! compile)
      (replace-object ev vector (vector-object (● vector type) items loc)))

    (define (write-vector-element (ev Evaluation) (vector Known) (index I64) (value Known)
                                  (type Type) (loc Loc)) (→ (Pair Known Evaluation)) (! compile)
                                  (let ((items (sequence-values ev vector loc)))
                                    (check-range index 1 (length items) loc)
                                    (scalar (replace-vector-contents ev
                                                                     vector
                                                                     (replace-at items index value)
                                                                     loc)
                                            type
                                            (DUnit))))

    (define (copy-vector-elements (ev Evaluation)
                                  (destination Known)
                                  (at I64)
                                  (source Known)
                                  (from I64)
                                  (count I64) (type Type) (loc Loc))
      (→ (Pair Known Evaluation)) (! compile)
      (let ((target (sequence-values ev destination loc)) (source (sequence-values ev source loc)))
        (check-range at count (length target) loc)
        (check-range from count (length source) loc)
        (scalar (replace-vector-contents ev destination
                                         (append (take target at)
                                                 (append (take (list-drop source from) count)
                                                         (list-drop target (+ at count)))) loc)
                type
                (DUnit))))

    ;; Keep target integer semantics on both the unbounded Chez host and
    ;; Wasm. Intermediate host overflow is reduced to its low 64 bits.
    (define (word64 (value I64)) (→ I64)
      (let ((low (i64-and value 9223372036854775807)))
        (if (= (i64-and (i64-shift-right/logical value 63) 1) 0) low
            (- (- low 9223372036854775807) 1))))

    (define (logical-right (value I64) (amount I64) (bits I64)) (→ I64)
      (if (= amount 0) value
          (i64-and (i64-shift-right/logical value amount)
                   (word64 (- (i64-shift-left 1 (- bits amount)) 1)))))

    (define (signed-right (value I64) (amount I64) (bits I64)) (→ I64)
      (if (or (= amount 0) (>= value 0)) (logical-right value amount bits)
          (i64-or (logical-right value amount bits)
                  (word64 (i64-shift-left -1 (- bits amount))))))

    (define (integer-operation (operation String) (args (List Known)) (loc Loc))
      (→ Datum)
      (! compile)
      (let* ((bits (if (string-prefix? "i32" operation) 32 64))
             (op (substring operation 4 (string-length operation)))
             (a (integer-value (list-ref args 0) loc))
             (b (integer-value (list-ref args 1) loc))
             (amount (i64-and b (- bits 1)))
             (wrap (lambda (value) (if (= bits 32) (i32->i64 (i64->i32 value)) (word64 value)))))
        (case op
          (("eq") (DBool (= a b)))
          (("lt") (DBool (< a b)))
          (("le") (DBool (<= a b)))
          (("gt") (DBool (> a b)))
          (("ge") (DBool (>= a b)))
          (else
           (DInt (wrap
                  (case op
                    (("add") (+ a b))
                    (("sub") (- a b))
                    (("mul") (* a b))
                    (("and") (i64-and a b))
                    (("or") (i64-or a b))
                    (("xor") (i64-xor a b))
                    (("shift-left") (i64-shift-left a amount))
                    (("shift-right/logical") (logical-right a amount bits))
                    (("shift-right") (signed-right a amount bits))
                    (("quotient" "remainder")
                     (when (= b 0)
                       (compile-error loc "division by zero during constant evaluation"))
                     (when (and (string=? op "quotient") (= b -1)
                                (= a (if (= bits 32) -2147483648 -9223372036854775808)))
                       (compile-error loc "integer division overflow during constant evaluation"))
                     (if (string=? op "quotient") (quotient a b)
                         (if (= b -1) 0 (remainder a b))))
                    (else (compile-error loc
                                         (string-append "unknown integer primitive: "
                                                        operation))))))))))

    ;; ---- Reification ----

    ;; A factory allocates its graph once per call. Each object's children
    ;; are named before the object, so repeated fields share one local.
    (struct Reifying
      ((evaluation Evaluation)
       (owning (Table Known))
       (done (Table Expr))
       (active (List String))
       (bindings (List (Pair String Expr)))))

    ;; Reserve shells for nodes with outgoing edges to break heap cycles.
    ;; Leaf nodes can be built directly. Fill shells only after every identity
    ;; exists, then publish the root; mutability does not change this order.
    (define (needs-shell? (object ObjectValue)) (→ Bool)
      (match object
        ((VectorValue _) #t)
        ((RecordValue _ fields) (not (null? fields)))
        (_ #f)))

    (define (object-children (ev Evaluation) (object ObjectValue)) (→ (List Known))
      (match object
        ((RecordValue _ fields) fields)
        ((VectorValue items) items)
        ((DynamicValue inner) (list inner))
        ((ClosureValue _ env) (table-values env))
        ((RcValue payload finalizer)
         (match payload ((Some value) (list value finalizer)) ((None) (Nil))))
        ((OnceValue inner) (list inner))
        ((BoundValue inner handlers)
         (Cons inner (concatenate (map (lambda (handler)
                                         (map (lambda (entry) (● entry second))
                                              (● handler operations)))
                                       handlers))))
        (_ (Nil))))



    (define (constant-shell (value Known) (object ObjectValue) (loc Loc)) (→ Expr)
      (match object
        ((RecordValue constructor _)
         (constant-call "prim:constant-record"
                        (list (Expr (Lit (DString constructor)) (TCon "String" (Nil)) loc))
                        (● value type) loc))
        ((VectorValue items)
         (constant-call "prim:constant-vector-shell"
                        (list (Expr (Lit (DInt (length items))) (TCon "I64" (Nil)) loc))
                        (● value type) loc))
        (_ (panic "internal error: constant shell without fields"))))

    (define (reserve-shell (r Reifying) (value Known) (loc Loc)) (→ Reifying) (! compile)
      (match (● value value)
        ((Object id)
         (let* ((object (object-value (● r evaluation) value loc))
                (name (string-append "%constant." id))
                (read (Expr (Var name (Nil) (Nil)) (● value type) loc)))
           (Reifying-bindings-set (Reifying-done-set r (table-set (● r done) id read))
                                  (Cons (Pair name (constant-shell value object loc))
                                        (● r bindings)))))
        (_ (panic "internal error: constant shell has no identity"))))

    (define (fill-shells (r Reifying) (values (List Known)) (loc Loc))
      (→ (Pair (List Expr) Reifying)) (! compile)
      (let loop ((r r) (values values) (fills (Nil)))
        (match values
          ((Nil) (Pair (reverse fills) r))
          ((Cons value rest)
           (let ((object (object-value (● r evaluation) value loc)))
             (match (reify-values r (Cons value (object-children (● r evaluation) object)) loc)
               ((Pair args r)
                (loop r rest (fold-left (lambda (fills fill) (Cons fill fills))
                                        fills
                                        (shell-fills (program (● r evaluation))
                                                     object
                                                     args
                                                     loc))))))))))

    ;; Ordinary setters safely replace inert placeholders: no placeholder
    ;; owns a source resource or invokes user code. This shares enum subtype
    ;; selection and slot ownership with every other record write.
    (define (shell-fills (program Program) (object ObjectValue) (args (List Expr)) (loc Loc))
      (→ (List Expr))
      (match object
        ((RecordValue constructor _)
         (map-indexed
          (lambda (index value)
            (match (program-value program constructor)
              ((Some (Constructor case _))
               (constant-call
                (string-append constructor "-" (● (list-ref (● case fields) index) name) "-set!")
                (list (list-ref args 0) value) (TCon "Unit" (Nil)) loc))
              (_ (panic "internal error: constant shell constructor"))))
          (list-drop args 1)))
        ((VectorValue _)
         (list (constant-call "prim:constant-vector-fill" args (TCon "Unit" (Nil)) loc)))
        (_ (panic "internal error: only records and vectors have shells"))))




    ;; Graph depth belongs in data, not the host stack. A leave action emits
    ;; a node after its children; repeated active identities mark cycles.
    (enum GraphStep
      (GraphEnter ((value Known)))
      (GraphLeave ((value Known))))

    (struct ConstantGraph
      ((values (List Known))
       (cycle? Bool)
       (owning (Table Known))))

    ;; Weak edges observe a cell but never bring its resources into a fresh
    ;; graph. First establish owning reachability; the construction walk then
    ;; follows weak links to those owned cells too, since they can form cycles.
    (define (owning-graph (ev Evaluation) (value Known) (loc Loc))
      (→ (Table Known)) (! compile)
      (let loop ((pending (list value)) (found empty-table))
        (match pending
          ((Nil) found)
          ((Cons value rest)
           (match (Pair (● value type) (● value value))
             ((Pair (TCon "WeakRc" _) _) (loop rest found))
             ((Pair _ (Object id))
              (if (table-contains? found id) (loop rest found)
                  (loop (append (object-children ev (object-value ev value loc)) rest)
                        (table-set found id value))))
             (_ (loop rest found)))))))

    (define (graph-object (ev Evaluation) (owning (Table Known)) (value Known) (loc Loc))
      (→ ObjectValue) (! compile)
      (match (Pair (● value type) (● value value))
        ((Pair (TCon "WeakRc" _) (Object id))
         (if (table-contains? owning id) (object-value ev value loc)
             (RcValue (None) (unit-known))))
        (_ (object-value ev value loc))))

    (define (ordered-graph (ev Evaluation) (value Known) (loc Loc))
      (→ ConstantGraph) (! compile)
      (let ((owning (owning-graph ev value loc)))
        (let loop ((pending (list (GraphEnter value))) (seen empty-table)
                   (ordered (Nil)) (cycle? #f))
          (match pending
            ((Nil) (ConstantGraph (reverse ordered) cycle? owning))
            ((Cons step rest)
             (match step
               ((GraphLeave value)
                (match (● value value)
                  ((Object id) (loop rest (table-set seen id #t) (Cons value ordered) cycle?))
                  (_ (panic "internal error: graph leave has no identity"))))
               ((GraphEnter value)
                (match (● value value)
                  ((Object id)
                   (match (table-ref seen id)
                     ((Some finished?) (loop rest seen ordered (or cycle? (not finished?))))
                     ((None)
                      (let ((value (match (table-ref owning id)
                                     ((Some owner) owner) ((None) value))))
                        (loop (fold-left (lambda (pending child) (Cons (GraphEnter child) pending))
                                         (Cons (GraphLeave value) rest)
                                         (reverse (object-children ev
                                                                   (graph-object ev
                                                                                 owning
                                                                                 value
                                                                                 loc))))
                              (table-set seen id #f) ordered cycle?)))))
                  (_ (loop rest seen ordered cycle?))))))))))

    (define (linear-closure? (ev Evaluation) (value Known) (loc Loc)) (→ Bool) (! compile)
      (match (● value value)
        ((Object _)
         (match (object-value ev value loc)
           ((ClosureValue key env)
            (any? (lambda (capture) (linear-type? (program ev) (Nil) (● capture type)))
                  (closure-captures ev key env)))
           (_ #f)))
        (_ #f)))

    ;; Such a lambda is source syntax inside once, never a reusable binding.
    ;; Its captured objects still occur earlier in the graph's construction order.
    (define (inline-once-objects (ev Evaluation) (values (List Known)) (loc Loc))
      (→ (Table Bool)) (! compile)
      (fold-left
       (lambda (inline value)
         (match (object-value ev value loc)
           ((OnceValue inner)
            (match (● inner value)
              ((Object id) (if (linear-closure? ev inner loc) (table-set inline id #t) inline))
              (_ inline)))
           (_ inline)))
       empty-table values))

    (define (reify-objects (r Reifying) (values (List Known)) (loc Loc))
      (→ Reifying) (! compile)
      (let ((inline (inline-once-objects (● r evaluation) values loc)))
        (fold-left (lambda (r value)
                     (match (● value value)
                       ((Object id)
                        (if (or (table-contains? inline id) (table-contains? (● r done) id)) r
                            (● (reify-value r value loc) second)))
                       (_ r))) r values)))


    (define (constant-reference (expr Expr) (type Type) (loc Loc)) (→ Expr)
      (match (Pair (● expr type) type)
        ((Pair (TCon "Rc" _) (TCon "WeakRc" _))
         (constant-call "prim:rc-downgrade" (list expr) type loc))
        (_ expr)))

    (define (constant-owner (r Reifying) (value Known)) (→ Known)
      (match (● value value)
        ((Object id)
         (match (table-ref (● r owning) id) ((Some owner) owner) ((None) value)))
        (_ value)))


    ;; Evaluation may build a large intermediate graph and reduce it to a
    ;; scalar. Only a returned graph expands into nested runtime construction
    ;; code. Bound that expansion before recursive downstream passes see it;
    ;; both objects and edges matter (one array may contain many elements).
    (define (factory-graph (ev Evaluation) (value Known) (loc Loc))
      (→ ConstantGraph) (! compile)
      (let* ((graph (ordered-graph ev value loc))
             (size (fold-left (lambda (size value)
                                (+ size (+ 1 (length (object-children ev
                                                                      (graph-object ev
                                                                                    (● graph owning)
                                                                                    value
                                                                                    loc))))))
                              0 (● graph values))))
        (when (> size 512)
          (compile-error loc
                         "constant factory exceeds 512 object/field construction steps; use a runtime function for this value"))
        graph))

    (define (reify (ev Evaluation) (value Known) (loc Loc)) (→ Expr) (! compile)
      (let* ((graph (factory-graph ev value loc)) (objects (● graph values))
             (mutable (if (● graph cycle?)
                          (filter
                           (lambda (value) (needs-shell? (object-value ev value loc)))
                           objects) (Nil)))
             (r (fold-left (lambda (r value) (reserve-shell r value loc))
                           (Reifying ev (● graph owning) empty-table (Nil) (Nil)) mutable))
             (r (reify-objects r objects loc)))
        (match (fill-shells r mutable loc)
          ((Pair fills r)
           (match (reify-value r value loc)
             ((Pair result r)
              (fold-left (lambda (body binding)
                           (Expr (Let (● binding first) (● binding second) body) (● body type) loc))
                         (fold-right (lambda (fill body) (Expr (Seq fill body) (● body type) loc))
                                     result
                                     fills)
                         (● r bindings))))))))

    (define (reify-value (r Reifying) (value Known) (loc Loc))
      (→ (Pair Expr Reifying))
      (! compile)
      (match (● value value)
        ((Scalar datum) (Pair (Expr (Lit datum) (● value type) loc) r))
        ((RealValue number)
         (Pair (Expr (Lit (real-datum (● value type) number)) (● value type) loc) r))
        ((Global name) (Pair (Expr (Var name (Nil) (Nil)) (● value type) loc) r))
        ((Object id)
         (match (table-ref (● r done) id)
           ((Some result) (Pair (constant-reference result (● value type) loc) r))
           ((None)
            (match (reify-object r id (constant-owner r value) loc)
              ((Pair result r) (Pair (constant-reference result (● value type) loc) r))))))))

    (define (reify-object (r Reifying) (id String) (value Known) (loc Loc))
      (→ (Pair Expr Reifying)) (! compile)
      (when (member? id (● r active))
        (compile-error loc "constant graph has a cycle without mutable data"))
      (let* ((name (string-append "%constant." id))
             (read (Expr (Var name (Nil) (Nil)) (● value type) loc))
             (outer (● r active))
             (r (Reifying-active-set r (Cons id outer))))
        (match (reify-object-value r
                                   name
                                   (● value type)
                                   (graph-object (● r evaluation) (● r owning) value loc)
                                   loc)
          ((Pair expression r)
           (Pair read (Reifying-bindings-set
                       (Reifying-done-set (Reifying-active-set r outer)
                                          (table-set (● r done) id read))
                       (Cons (Pair name expression) (● r bindings))))))))

    (define (reify-object-value (r Reifying)
                                (name String)
                                (type Type)
                                (object ObjectValue)
                                (loc Loc))
      (→ (Pair Expr Reifying)) (! compile)
      (match object
        ((RecordValue constructor fields)
         (match (reify-values r fields loc)
           ((Pair fields r) (Pair (constant-call constructor fields type loc) r))))
        ((VectorValue items)
         (match (reify-values r items loc)
           ((Pair items r) (Pair (constant-call "prim:constant-vector" items type loc) r))))
        ((ByteVectorValue bytes) (Pair (Expr (Lit (DBytes bytes)) type loc) r))
        ((DynamicValue inner)
         (match (reify-value r inner loc)
           ((Pair inner r) (Pair (Expr (Convert inner type) type loc) r))))
        ((ClosureValue key env)
         (reify-source-closure r (recipe (● r evaluation) key) env name type loc))
        ((RcValue (Some payload) finalizer)
         (match (reify-values r (list payload finalizer) loc)
           ((Pair args r) (Pair (constant-call "prim:rc-new" args type loc) r))))
        ((RcValue (None) _)
         (Pair (constant-call "prim:constant-dead-weak" (Nil) type loc) r))
        ((OnceValue inner) (reify-once r inner type loc))
        ((BoundValue inner handlers) (reify-bound r inner handlers type loc))
        (_ (compile-error loc
                          "this interpreter control value cannot escape in a compile-time value"))))

    ;; Preserve each lexical capture as a distinct owner even when two names
    ;; refer to the same graph object. Source references fix shared-field order;
    ;; lexical aliases recover linear cancellation order for normal preparation.
    (define (reify-source-closure (r Reifying) (source ClosureRecipe) (env (Table Known))
                                  (prefix String) (type Type) (loc Loc))
      (→ (Pair Expr Reifying)) (! compile)
      (let ((names (● source cleanup)))
        (match (reify-values r (map (lambda (name) (table-ref-or env name)) names) loc)
          ((Pair values r)
           (let* ((aliases (map (lambda (name) (string-append prefix ".capture." name)) names))
                  (reads (map (lambda (pair)
                                (Expr (Var (● pair first) (Nil) (Nil))
                                      (● (● pair second) type)
                                      loc))
                              (zip aliases values)))
                  (self (string-append prefix ".self"))
                  (bindings (zip names reads))
                  (bindings (match (● source self)
                              ((Some old) (Cons (Pair old (Expr (Var self (Nil) (Nil))
                                                                (● (● source expression) type) loc))
                                                bindings))
                              ((None) bindings)))
                  (body (substitute-locals bindings (● source expression)))
                  (body (match (● source self)
                          ((Some _) (Expr (Let self body
                                               (Expr (Var self (Nil) (Nil)) (● body type) loc))
                                          (● body type) loc))
                          ((None) body)))
                  (body
                   (if (once-type? type) (constant-call "prim:once" (list body) type loc) body)))
             (Pair (fold-left (lambda (body binding)
                                (Expr (Let (● binding first) (● binding second) body)
                                      (● body type)
                                      loc))
                              body (zip aliases values)) r))))))

    ;; A source once-lambda moves linear captures directly; keep its aliases
    ;; outside the syntactic once call, where ordinary dropper preparation sees
    ;; their lexical scope. Reusable closures can use their graph binding.
    (define (reify-once (r Reifying) (value Known) (type Type) (loc Loc))
      (→ (Pair Expr Reifying)) (! compile)
      (if (linear-closure? (● r evaluation) value loc)
          (match (Pair (● value value) (object-value (● r evaluation) value loc))
            ((Pair (Object id) (ClosureValue key env))
             (reify-source-closure r (recipe (● r evaluation) key) env
                                   (string-append "%constant.once." id) type loc))
            (_ (panic "internal error: linear source closure lost its identity")))
          (match (reify-value r value loc)
            ((Pair function r) (Pair (constant-call "prim:once" (list function) type loc) r)))))

    (define (reify-values (r Reifying) (values (List Known)) (loc Loc))
      (→ (Pair (List Expr) Reifying)) (! compile)
      (let loop ((r r) (values values) (done (Nil)))
        (match values
          ((Nil) (Pair (reverse done) r))
          ((Cons first rest)
           (match (reify-value r first loc)
             ((Pair first r) (loop r rest (Cons first done))))))))

    (define (constant-call (name String) (args (List Expr)) (type Type) (loc Loc)) (→ Expr)
      (Expr (App (Expr (Var name (Nil) (Nil))
                       (TFun (map (lambda (arg) (● arg type)) args) type empty-row) loc) args)
            type
            loc))

    (define (substitute-locals (bindings (List (Pair String Expr))) (expr Expr)) (→ Expr)
      (rewrite-variables (lambda (read)
                           (match (● read term)
                             ((Var name _ _)
                              (match (assoc-ref bindings name) ((Some value) value) ((None) read)))
                             (_ read))) expr))

    ;; Names are resolved and unique. Substitution and factory-call rewriting
    ;; share this variable walk; generated graph bindings may be far deeper than
    ;; source expressions, so traversal and reconstruction use explicit stacks.
    (enum RewriteStep
      (RewriteVisit ((expression Expr)))
      (RewriteFinish ((expression Expr) (count I64))))

    (define (rewrite-variables (read (Fn Expr → Expr)) (expr Expr)) (→ Expr)
      (let loop ((pending (list (RewriteVisit expr))) (values (Nil)))
        (match pending
          ((Nil) (list-ref values 0))
          ((Cons step rest)
           (match step
             ((RewriteVisit expr)
              (match (● expr term)
                ((Var _ _ _) (loop rest (Cons (read expr) values)))
                (_ (let ((children (expr-children expr)))
                     (if (null? children) (loop rest (Cons expr values))
                         (loop (append (map RewriteVisit children)
                                       (Cons (RewriteFinish expr (length children)) rest))
                               values))))))
             ((RewriteFinish expr count)
              (loop rest (Cons (rebuild-expression expr (reverse (take values count)))
                               (list-drop values count)))))))))

    ;; ---- Preparation ----

    (define (fold-constants (state State) (items (List Item))
                            (prepare (Fn State String Expr → (Pair Expr State) ! compile)))
      (→ (Pair (List Item) State))
      (! compile)
      (let ((ev (Evaluation state empty-table empty-table (Nil) empty-table 0
                            empty-table empty-table 10000000 1000000 prepare)))
        (match (constant-items ev items)
          ((Pair items ev)
           (Pair (map (lambda (item) (rewrite-item (● ev state) item)) items) (● ev state))))))

    (define (constant-items (ev Evaluation) (items (List Item)))
      (→ (Pair (List Item) Evaluation)) (! compile)
      (let loop ((ev ev) (items items) (done (Nil)))
        (match items
          ((Nil) (Pair (reverse done) ev))
          ((Cons first rest)
           (match (constant-item ev first)
             ((Pair first ev) (loop ev rest (Cons first done))))))))

    (define (constant-item (ev Evaluation) (item Item)) (→ (Pair Item Evaluation)) (! compile)
      (match item
        ((Define name value)
         (if (constant-binding? (● ev state) name)
             (evaluating ev ((known (force-value name (● value loc))))
                         (Pair (Define name (Expr (Lambda (Nil) (reify ev known (● value loc)) #f)
                                                  (TFun (Nil) (● value type) empty-row)
                                                  (● value loc)))
                               ev))
             (Pair item ev)))
        (_ (Pair item ev))))

    (define (rewrite-item (state State) (item Item)) (→ Item)
      (match item
        ((Define name value) (Define name (rewrite-references state value)))
        (_ item)))

    (define (rewrite-references (state State) (expr Expr)) (→ Expr)
      (rewrite-variables (lambda (read)
                           (match (● read term)
                             ((Var name _ _)
                              (if (constant-binding? state name)
                                  (constant-call name (Nil) (● read type) (● read loc)) read))
                             (_ read))) expr))

    (define (constant-declarations (declarations Declarations)) (→ Declarations)
      (Declarations (● declarations program) (● declarations owner) (● declarations control)
                    (fold-left (lambda (bindings name)
                                 (match (table-ref (● declarations bindings) name)
                                   ((Some binding)
                                    (table-set bindings name
                                               (if (● binding function?) binding
                                                   (Binding
                                                    (TFun (Nil) (● binding type) empty-row)
                                                    #t
                                                    (● binding external?)))))
                                   ((None) bindings)))
                               empty-table (table-keys (● declarations bindings)))))

    ))

;; A finite dynamic instance becomes ordinary typed methods. Its first
;; parameter of the erased class type selects a branch; every occurrence
;; of that type is checked against the same concrete type in that branch.
;; The checker then supplies ordinary class evidence and checks effects.
;; No instance registry or dictionary crosses a library boundary.
(define-library (snail shell compiler dynamic)
  (export
   Dispatch
   parse-dispatch
   dispatch-method
   GeneratedInstance
   generate-binary-instances)
  (import
   (snail core base)
   (snail shell compiler read)
   (snail shell compiler core)
   (snail shell compiler conversions))
  (begin

    ;; ---- Dispatch domain ----

    ;; Exactly one class parameter is erased. Other type arguments and
    ;; effect rows are fixed by the instance head; accepted payload types
    ;; are ground and distinct. Conversion checking will reject payloads
    ;; whose ownership or effects cannot be erased into Any.
    (struct Dispatch
      ((variable String)
       (targets (List Type))))

    (define (parse-dispatch (class Class) (instance Instance) (targets (List Type)) (loc Loc))
      (→ Dispatch)
      (! compile)
      (unless (and (null? (● instance vars))
                   (null? (● instance requires))
                   (= (length (filter any-type? (● instance types))) 1)
                   (not (lifecycle-class? (● class name))))
        (compile-error loc
                       "dispatch needs a ground instance head with exactly one Any type argument"))
      (when (null? targets) (compile-error loc "dispatch needs at least one concrete type"))
      (for-each (lambda (type)
                  (unless (and (ground-type? type) (not (any-type? type)))
                    (compile-error loc
                                   "dispatch accepts concrete types, not Any or type variables")))
                targets)
      (unless (= (length targets) (length (delete-duplicates type=? targets)))
        (compile-error loc "dispatch repeats a concrete type"))
      (Dispatch (dispatch-variable class instance) targets))

    (define (ground-type? (type Type)) (→ Bool)
      (match type
        ((TCon _ args) (every? ground-type? args))
        ((TFun params result row)
         (and (every? ground-type? params) (ground-type? result) (ground-type? row)))
        ((TRow _ (None)) #t)
        (_ #f)))

    (define (dispatch-variable (class Class) (instance Instance)) (→ String)
      (match (find (lambda (pair) (any-type? (● pair second)))
                   (zip (● class params) (● instance types)))
        ((Some pair) (● pair first))
        ((None) (panic "internal error: dispatch without Any"))))

    ;; ---- Methods ----

    ;; Keep the erased variable while substituting the fixed arguments.
    ;; This distinguishes a method's own Any parameter from an occurrence
    ;; of the class parameter that this dispatcher erases.

    (define (dispatch-method (program Program)
                             (class Class)
                             (instance Instance)
                             (method String)
                             (dispatch Dispatch)
                             (loc Loc))
      (→ Expr)
      (! compile)
      (let* ((var (● dispatch variable))
             (fixed (filter (lambda (pair) (not (string=? var (● pair first))))
                            (zip (● class params) (● instance types)))))
        (match (program-value program method)
          ((Some (Method _ (Scheme vars (Cons _ (Nil)) _ type)))
           (unless (= (length vars) (length (● class params)))
             (compile-error loc "dispatch does not support independently polymorphic methods"))
           (dispatch-lambda instance
                            method
                            var
                            (substitute fixed type)
                            (● dispatch targets)
                            loc))
          (_ (compile-error loc
                            "dispatch does not support methods with additional class requirements")))))

    (define (dispatch-lambda (instance Instance)
                             (method String)
                             (var String)
                             (type Type)
                             (targets (List Type))
                             (loc Loc))
      (→ Expr)
      (! compile)
      (match type
        ((TFun params result _)
         (for-each (lambda (part) (check-dispatch-position var part loc)) (Cons result params))
         (let* ((prefix (string-append (● instance name) "." (short-name method)))
                (names (map (lambda (index)
                              (string-append prefix ".argument." (i64->string index)))
                            (iota (length params))))
                (arguments (zip params (map (lambda (name) (reference name loc)) names))))
           (match (list-index (lambda (type) (type=? type (TRigid var))) params)
             ((Some selector)
              (expression (Lambda names
                                  (dispatch-branches prefix method var arguments result
                                                     selector targets loc)
                                  #f)
                          loc))
             ((None)
              (compile-error loc
                             "each dispatched method needs an argument of its erased class type")))))
        (_ (compile-error loc "dispatch needs function methods"))))

    ;; Nested occurrences would require element conversions or function
    ;; wrappers. This feature checks whole values; it never rebuilds them.

    (define (check-dispatch-position (var String) (type Type) (loc Loc)) (→ Unit) (! compile)
      (when (and (mentions? var type) (not (type=? type (TRigid var))))
        (compile-error loc
                       "dispatch needs the erased class type as a whole parameter or result")))

    (define (mentions? (var String) (type Type)) (→ Bool)
      (match type
        ((TRigid name) (string=? var name))
        ((TCon _ args) (any? (lambda (arg) (mentions? var arg)) args))
        ((TFun params result row)
         (any? (lambda (part) (mentions? var part)) (Cons row (Cons result params))))
        ((TRow _ (Some tail)) (mentions? var tail))
        (_ #f)))

    ;; Every selector branch is tested. The final failure describes the
    ;; whole accepted domain, not the last type we happened to try.

    (define (dispatch-branches (prefix String)
                               (method String)
                               (var String)
                               (args (List (Pair Type Expr)))
                               (result Type)
                               (index I64)
                               (targets (List Type))
                               (loc Loc))
      (→ Expr)
      (let ((selector (● (list-ref args index) second)))
        (fold-right (lambda (entry rest)
                      (dispatch-case
                       (string-append prefix ".case." (i64->string (● entry first)))
                       method var args result index (● entry second) rest loc))
                    (conversion-failure
                     (conversion-error "UnsupportedInstance" targets selector method index loc)
                     unchecked loc)
                    (zip (iota (length targets)) targets))))

    ;; The selector is already recovered in this branch. Its concrete type
    ;; marks it as an ordinary argument, so the call cannot probe it again.

    (define (dispatch-case (prefix String)
                           (method String)
                           (var String)
                           (args (List (Pair Type Expr)))
                           (result Type)
                           (index I64)
                           (target Type)
                           (rest Expr)
                           (loc Loc))
      (→ Expr)
      (let* ((name (string-append prefix ".selector"))
             (selected (map-indexed (lambda (i arg)
                                      (if (= i index) (Pair target (reference name loc)) arg))
                                    args)))
        (recover-value (● (list-ref args index) second) target name
                       (dispatch-call prefix method var selected result target loc) rest loc)))

    (define (dispatch-argument (prefix String)
                               (method String)
                               (var String)
                               (target Type)
                               (index I64)
                               (argument (Pair Type Expr))
                               (loc Loc))
      (→ Expr)
      (let ((value (● argument second)))
        (if (type=? (● argument first) (TRigid var))
            (let ((name (string-append prefix ".argument." (i64->string index))))
              (recover-value value target name (reference name loc)
                             (conversion-failure
                              (conversion-error "ArgumentMismatch"
                                                (list target)
                                                value
                                                method
                                                index
                                                loc)
                              target loc) loc))
            value)))

    (define (dispatch-call (prefix String)
                           (method String)
                           (var String)
                           (args (List (Pair Type Expr)))
                           (result Type)
                           (target Type)
                           (loc Loc))
      (→ Expr)
      (let* ((arguments (map (lambda (entry)
                               (dispatch-argument prefix method var target
                                                  (● entry first) (● entry second) loc))
                             (zip (iota (length args)) args)))
             (call (expression (App (reference method loc) arguments) loc)))
        (if (type=? result (TRigid var))
            (expression (Convert call (TCon "Any" (Nil))) loc)
            call)))

    (define (expression (term Term) (loc Loc)) (→ Expr)
      (Expr term unchecked loc))

    (define (reference (name String) (loc Loc)) (→ Expr)
      (expression (Var name (Nil) (Nil)) loc))

    ;; These ordinary matches bind typed values before the method call.
    ;; Conversion lowering consumes their unused wrappers and errors.

    (define (conversion-probe (value Expr) (target Type) (name String) (loc Loc))
      (→ (Pair Expr Pattern))
      (Pair (expression (TryConvert value target) loc)
            (PCon "snail.core.base:Ok" (list (PVar name unchecked)) unchecked)))

    (define (select-probe (probe (Pair Expr Pattern)) (success Expr) (failure Expr) (loc Loc))
      (→ Expr)
      (expression (Match (● probe first)
                         (list (Clause (● probe second) success)
                               (Clause (PWild unchecked) failure))) loc))

    (define (recover-value (value Expr)
                           (target Type)
                           (name String)
                           (success Expr)
                           (failure Expr)
                           (loc Loc))
      (→ Expr)
      (select-probe (conversion-probe value target name loc) success failure loc))

    (define (recover-pair (values (List Expr))
                          (targets (List Type))
                          (names (List String))
                          (success Expr)
                          (failure Expr)
                          (loc Loc))
      (→ Expr)
      (let* ((probes (map (lambda (index)
                            (conversion-probe (list-ref values index) (list-ref targets index)
                                              (list-ref names index) loc)) (iota 2)))
             (value (expression (App (reference "snail.core.base:Pair" loc)
                                     (map (lambda (record) (● record first)) probes)) loc))
             (pattern (PCon "snail.core.base:Pair"
                            (map (lambda (record) (● record second)) probes)
                            unchecked)))
        (select-probe (Pair value pattern) success failure loc)))

    ;; ---- Binary policies ----

    ;; The finite domain is resolved once, in the generator's lexical
    ;; scope. Each branch remembers the implementation it selected. Neither
    ;; imports nor a caller's instance sets can change that choice.
    (struct BinaryCase
      ((inputs (List Type))
       (output Type)
       (effects (List String))
       (methods (List (Pair String String)))))

    (struct GeneratedInstance
      ((instance Instance)
       (definitions (List Item))))

    (define (generate-binary-instances (program Program)
                                       (class Class)
                                       (domain (List (List Type)))
                                       (active (List String))
                                       (owner String)
                                       (name String)
                                       (loc Loc))
      (→ (List GeneratedInstance))
      (! compile)
      (check-binary-class program class loc)
      (when (or (null? domain)
                (not (= (length domain) (length (delete-duplicates types=? domain)))))
        (compile-error loc "dynamic-instances needs a nonempty domain of distinct type pairs"))
      (let* ((cases
              (map (lambda (pair) (resolve-binary-case program class pair active loc)) domain))
             (heads (delete-duplicates types=? (concatenate (map erased-heads domain)))))
        (map (lambda (entry)
               (generate-binary-instance class cases (● entry second) owner
                                         (string-append name "." (i64->string (● entry first)))
                                         loc))
             (zip (iota (length heads)) heads))))

    ;; This initial generator covers ordinary binary operation classes.
    ;; Independent method polymorphism and nested erased occurrences would
    ;; require a different conversion contract, so they fail at declaration.

    (define (check-binary-class (program Program) (class Class) (loc Loc)) (→ Unit) (! compile)
      (unless (and (= (length (● class rows)) 1)
                   (= (length (● class outputs)) 1)
                   (= (length (type-arguments class (map TRigid (● class params)))) 2)
                   (not (null? (● class methods))))
        (compile-error loc
                       "dynamic-instances needs a binary class with one effect row and one associated output"))
      (for-each (lambda (method) (check-binary-method program class method loc))
                (● class methods)))

    (define (check-binary-method (program Program) (class Class) (method String) (loc Loc))
      (→ Unit)
      (! compile)
      (match (program-value program method)
        ((Some (Method _ (Scheme vars (Cons _ (Nil)) _ (TFun params result row))))
         (unless (and (= (length vars) (length (● class params)))
                      (types=? params (type-arguments class (map TRigid (● class params))))
                      (type=? result (TRigid (list-ref (● class outputs) 0)))
                      (type=? row (TRow (Nil) (Some (TRigid (list-ref (● class rows) 0))))))
           (compile-error loc
                          "dynamic-instances needs methods of type (dyn (Fn A B → Output ! e))")))
        (_
         (compile-error loc "dynamic-instances does not support independent method requirements"))))

    (define (resolve-binary-case (program Program)
                                 (class Class)
                                 (inputs (List Type))
                                 (active (List String))
                                 (loc Loc))
      (→ BinaryCase)
      (! compile)
      (unless (and (= (length inputs) 2)
                   (every? (lambda (type) (and (ground-type? type) (not (any-type? type)))) inputs))
        (compile-error loc "dynamic-instances domain entries are two concrete, non-Any types"))
      (let ((matches (filter (lambda (instance)
                               (match (match-types (● instance vars)
                                                   (type-arguments class (● instance types))
                                                   inputs (Nil))
                                 ((Some _) #t) ((None) #f)))
                             (visible-instances program (● class name) active))))
        (match matches
          ((Cons instance (Nil)) (binary-case class instance inputs loc))
          ((Nil)
           (compile-error loc "dynamic-instances has no active source instance for a domain pair"))
          (_ (compile-error loc "dynamic-instances has overlapping source instances")))))

    (define (binary-case (class Class) (instance Instance) (inputs (List Type)) (loc Loc))
      (→ BinaryCase)
      (! compile)
      (unless (null? (● instance requires))
        (compile-error loc "dynamic-instances source instances must have no class prerequisites"))
      (match (match-types (● instance vars)
                          (type-arguments class (● instance types))
                          inputs
                          (Nil))
        ((Some bindings)
         (let* ((head (map (lambda (type) (substitute bindings type)) (● instance types)))
                (output (list-ref (output-arguments class head) 0))
                (row (list-ref (row-arguments class head) 0)))
           (unless (and (ground-type? output) (ground-type? row))
             (compile-error loc "dynamic-instances source outputs and rows must be determined"))
           (match row
             ((TRow labels (None)) (BinaryCase inputs output labels (● instance methods)))
             (_ (compile-error loc "dynamic-instances source effect rows must be closed")))))
        ((None) (panic "internal error: selected binary instance did not match"))))

    (define (erased-heads (inputs (List Type))) (→ (List (List Type)))
      (let ((any (TCon "Any" (Nil))))
        (list (list any (list-ref inputs 1)) (list (list-ref inputs 0) any) (list any any))))

    (define (accepts-pair? (head (List Type)) (branch BinaryCase)) (→ Bool)
      (every? (lambda (pair) (or (any-type? (● pair first))
                                 (type=? (● pair first) (● pair second))))
              (zip head (● branch inputs))))

    (define (generate-binary-instance (class Class)
                                      (domain (List BinaryCase))
                                      (inputs (List Type))
                                      (owner String)
                                      (name String)
                                      (loc Loc))
      (→ GeneratedInstance)
      (let* ((cases (filter (lambda (branch) (accepts-pair? inputs branch)) domain))
             (outputs (delete-duplicates type=? (map (lambda (record) (● record output)) cases)))
             (output (if (= (length outputs) 1) (list-ref outputs 0) (TCon "Any" (Nil))))
             (row (TRow (fold-left
                         (lambda (labels branch) (label-union labels (● branch effects)))
                         (list dyn-cast-label) cases) (None)))
             (methods
              (map (lambda (method) (Pair method (string-append name "." (short-name method))))
                   (● class methods)))
             (instance (Instance name (● class name) (Nil) (binary-head class inputs output row)
                                 (Nil) (Nil) methods (Some owner))))
        (GeneratedInstance instance
                           (map (lambda (method)
                                  (Define (● method second)
                                    (binary-lambda (● method first) inputs output cases
                                                   (● method second) loc))) methods))))

    (define (binary-head (class Class) (inputs (List Type)) (output Type) (row Type))
      (→ (List Type))
      (let ((bindings (zip (filter (lambda (param)
                                     (not (member? param
                                                   (append (● class rows)
                                                           (● class outputs)))))
                                   (● class params)) inputs)))
        (map (lambda (param)
               (cond ((member? param (● class rows)) row)
                     ((member? param (● class outputs)) output)
                     (else (match (assoc-ref bindings param)
                             ((Some type) type)
                             ((None) (panic "internal error: binary input parameter"))))))
             (● class params))))

    (define (binary-lambda (method String)
                           (inputs (List Type))
                           (output Type)
                           (cases (List BinaryCase))
                           (name String)
                           (loc Loc))
      (→ Expr)
      (let* ((names (list (string-append name ".left") (string-append name ".right")))
             (args (map (lambda (name) (reference name loc)) names))
             (failure (binary-failure method inputs args cases output loc)))
        (expression (Lambda names
                            (fold-right (lambda (entry rest)
                                          (binary-branch method
                                                         inputs
                                                         args
                                                         output
                                                         (● entry second)
                                                         (string-append name ".case."
                                                                        (i64->string
                                                                         (● entry first)))
                                                         rest loc))
                                        failure (zip (iota (length cases)) cases)) #f) loc)))

    ;; A generated head erases one or both arguments. The candidate's
    ;; typed bindings feed its selected implementation; a mismatch proceeds
    ;; to the next candidate without constructing a temporary error.

    (define (binary-branch (method String)
                           (inputs (List Type))
                           (args (List Expr))
                           (output Type)
                           (branch BinaryCase)
                           (prefix String)
                           (rest Expr)
                           (loc Loc))
      (→ Expr)
      (let* ((names (list (string-append prefix ".left") (string-append prefix ".right")))
             (converted (map (lambda (i) (if (any-type? (list-ref inputs i))
                                             (reference (list-ref names i) loc) (list-ref args i)))
                             (iota 2)))
             (body (binary-call method converted output branch loc))
             (targets (● branch inputs)))
        (cond ((every? any-type? inputs) (recover-pair args targets names body rest loc))
              (else (let ((index (if (any-type? (list-ref inputs 0)) 0 1)))
                      (recover-value (list-ref args index) (list-ref targets index)
                                     (list-ref names index) body rest loc))))))

    ;; A failed pair names the offending side. When the left type is
    ;; supported, the right side's expected types are restricted to that
    ;; left type; this also explains a missing pair in a nonrectangular domain.

    (define (binary-failure (method String)
                            (inputs (List Type))
                            (args (List Expr))
                            (cases (List BinaryCase))
                            (output Type)
                            (loc Loc))
      (→ Expr)
      (let ((lefts (delete-duplicates type=?
                                      (map (lambda (branch) (list-ref (● branch inputs) 0))
                                           cases))))
        (cond ((not (any-type? (list-ref inputs 0)))
               (binary-side-failure method args cases 1 output loc))
              ((not (any-type? (list-ref inputs 1)))
               (binary-side-failure method args cases 0 output loc))
              (else
               (fold-right (lambda (left rest)
                             (let ((eligible (filter (lambda (branch)
                                                       (type=? left
                                                               (list-ref (● branch inputs)
                                                                         0)))
                                                     cases)))
                               (expression (If (expression (TypeTest (list-ref args 0) left) loc)
                                               (binary-side-failure method
                                                                    args
                                                                    eligible
                                                                    1
                                                                    output
                                                                    loc)
                                               rest)
                                           loc)))
                           (binary-side-failure method args cases 0 output loc) lefts)))))

    (define (binary-side-failure (method String)
                                 (args (List Expr))
                                 (cases (List BinaryCase))
                                 (index I64)
                                 (output Type)
                                 (loc Loc))
      (→ Expr)
      (conversion-failure
       (conversion-error "UnsupportedInstance"
                         (delete-duplicates type=?
                                            (map (lambda (branch)
                                                   (list-ref (● branch inputs) index))
                                                 cases))
                         (list-ref args index) method index loc) output loc))

    (define (binary-call (method String)
                         (args (List Expr))
                         (output Type)
                         (branch BinaryCase)
                         (loc Loc))
      (→ Expr)
      (let* ((implementation (match (assoc-ref (● branch methods) method)
                               ((Some name) name)
                               ((None) (panic "internal error: missing binary implementation"))))
             (call (expression (App (reference implementation loc) args) loc)))
        (if (and (any-type? output) (not (any-type? (● branch output))))
            (expression (Convert call output) loc) call)))
    ))

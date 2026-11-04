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
   GeneratedInstance-instance
   GeneratedInstance-definitions
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

    (: parse-dispatch (-> Class Instance (List Type) Loc Dispatch ! compile))
    (define (parse-dispatch class instance targets loc)
      (unless (and (null? (Instance-vars instance))
                   (null? (Instance-requires instance))
                   (= (length (filter any-type? (Instance-types instance))) 1)
                   (not (lifecycle-class? (Class-name class))))
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

    (: ground-type? (-> Type Bool))
    (define (ground-type? type)
      (match type
        ((TCon _ args) (every? ground-type? args))
        ((TFun params result row)
         (and (every? ground-type? params) (ground-type? result) (ground-type? row)))
        ((TRow _ (None)) #t)
        (_ #f)))

    (: dispatch-variable (-> Class Instance String))
    (define (dispatch-variable class instance)
      (match (find (lambda (pair) (any-type? (Pair-second pair)))
                   (zip (Class-params class) (Instance-types instance)))
        ((Some pair) (Pair-first pair))
        ((None) (panic "internal error: dispatch without Any"))))

    ;; ---- Methods ----

    ;; Keep the erased variable while substituting the fixed arguments.
    ;; This distinguishes a method's own Any parameter from an occurrence
    ;; of the class parameter that this dispatcher erases.
    (: dispatch-method (-> Program Class Instance String Dispatch Loc Expr ! compile))
    (define (dispatch-method program class instance method dispatch loc)
      (let* ((var (Dispatch-variable dispatch))
             (fixed (filter (lambda (pair) (not (string=? var (Pair-first pair))))
                            (zip (Class-params class) (Instance-types instance)))))
        (match (program-value program method)
          ((Some (Method _ (Scheme vars (Cons _ (Nil)) _ type)))
           (unless (= (length vars) (length (Class-params class)))
             (compile-error loc "dispatch does not support independently polymorphic methods"))
           (dispatch-lambda instance
                            method
                            var
                            (substitute fixed type)
                            (Dispatch-targets dispatch)
                            loc))
          (_ (compile-error loc
                            "dispatch does not support methods with additional class requirements")))))

    (: dispatch-lambda (-> Instance String String Type (List Type) Loc Expr ! compile))
    (define (dispatch-lambda instance method var type targets loc)
      (match type
        ((TFun params result _)
         (for-each (lambda (part) (check-dispatch-position var part loc)) (Cons result params))
         (let* ((names (map (lambda (index)
                              (string-append (Instance-name instance) "." (short-name method)
                                             ".argument." (i64->string index)))
                            (iota (length params))))
                (arguments (zip params (map (lambda (name) (reference name loc)) names))))
           (match (list-index (lambda (type) (type=? type (TRigid var))) params)
             ((Some selector)
              (expression (Lambda names
                                  (dispatch-branches method var arguments result
                                                     selector targets loc)
                                  #f)
                          loc))
             ((None)
              (compile-error loc
                             "each dispatched method needs an argument of its erased class type")))))
        (_ (compile-error loc "dispatch needs function methods"))))

    ;; Nested occurrences would require element conversions or function
    ;; wrappers. This feature checks whole values; it never rebuilds them.
    (: check-dispatch-position (-> String Type Loc Unit ! compile))
    (define (check-dispatch-position var type loc)
      (when (and (mentions? var type) (not (type=? type (TRigid var))))
        (compile-error loc
                       "dispatch needs the erased class type as a whole parameter or result")))

    (: mentions? (-> String Type Bool))
    (define (mentions? var type)
      (match type
        ((TRigid name) (string=? var name))
        ((TCon _ args) (any? (lambda (arg) (mentions? var arg)) args))
        ((TFun params result row)
         (any? (lambda (part) (mentions? var part)) (Cons row (Cons result params))))
        ((TRow _ (Some tail)) (mentions? var tail))
        (_ #f)))

    ;; Every selector branch is tested. The final failure describes the
    ;; whole accepted domain, not the last type we happened to try.
    (: dispatch-branches
       (-> String String (List (Pair Type Expr)) Type I64 (List Type) Loc Expr))
    (define (dispatch-branches method var args result index targets loc)
      (let ((selector (Pair-second (list-ref args index))))
        (fold-right (lambda (target rest)
                      (expression (If (expression (TypeTest selector target) loc)
                                      (dispatch-call method var args result target loc) rest) loc))
                    (conversion-failure
                     (conversion-error "UnsupportedInstance" targets selector method index loc)
                     unchecked loc)
                    targets)))

    (: dispatch-argument (-> String String Type I64 (Pair Type Expr) Loc Expr))
    (define (dispatch-argument method var target index argument loc)
      (let ((value (Pair-second argument)))
        (if (type=? (Pair-first argument) (TRigid var))
            (expression (If (expression (TypeTest value target) loc)
                            (expression (Convert value target) loc)
                            (conversion-failure
                             (conversion-error "ArgumentMismatch"
                                               (list target)
                                               value
                                               method
                                               index
                                               loc)
                             target loc)) loc)
            value)))

    (: dispatch-call (-> String String (List (Pair Type Expr)) Type Type Loc Expr))
    (define (dispatch-call method var args result target loc)
      (let* ((arguments (map (lambda (entry)
                               (dispatch-argument method var target
                                                  (Pair-first entry) (Pair-second entry) loc))
                             (zip (iota (length args)) args)))
             (call (expression (App (reference method loc) arguments) loc)))
        (if (type=? result (TRigid var))
            (expression (Convert call (TCon "Any" (Nil))) loc)
            call)))

    (: expression (-> Term Loc Expr))
    (define (expression term loc)
      (Expr term unchecked loc))

    (: reference (-> String Loc Expr))
    (define (reference name loc)
      (expression (Var name (Nil) (Nil)) loc))
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

    (: generate-binary-instances
       (-> Program Class (List (List Type)) (List String) String String Loc
           (List GeneratedInstance) ! compile))
    (define (generate-binary-instances program class domain active owner name loc)
      (check-binary-class program class loc)
      (when (or (null? domain)
                (not (= (length domain) (length (delete-duplicates types=? domain)))))
        (compile-error loc "dynamic-instances needs a nonempty domain of distinct type pairs"))
      (let* ((cases
              (map (lambda (pair) (resolve-binary-case program class pair active loc)) domain))
             (heads (delete-duplicates types=? (concatenate (map erased-heads domain)))))
        (map (lambda (entry)
               (generate-binary-instance class cases (Pair-second entry) owner
                                         (string-append name "." (i64->string (Pair-first entry)))
                                         loc))
             (zip (iota (length heads)) heads))))

    ;; This initial generator covers ordinary binary operation classes.
    ;; Independent method polymorphism and nested erased occurrences would
    ;; require a different conversion contract, so they fail at declaration.
    (: check-binary-class (-> Program Class Loc Unit ! compile))
    (define (check-binary-class program class loc)
      (unless (and (= (length (Class-rows class)) 1)
                   (= (length (Class-outputs class)) 1)
                   (= (length (type-arguments class (map TRigid (Class-params class)))) 2)
                   (not (null? (Class-methods class))))
        (compile-error loc
                       "dynamic-instances needs a binary class with one effect row and one associated output"))
      (for-each (lambda (method) (check-binary-method program class method loc))
                (Class-methods class)))

    (: check-binary-method (-> Program Class String Loc Unit ! compile))
    (define (check-binary-method program class method loc)
      (match (program-value program method)
        ((Some (Method _ (Scheme vars (Cons _ (Nil)) _ (TFun params result row))))
         (unless (and (= (length vars) (length (Class-params class)))
                      (types=? params (type-arguments class (map TRigid (Class-params class))))
                      (type=? result (TRigid (list-ref (Class-outputs class) 0)))
                      (type=? row (TRow (Nil) (Some (TRigid (list-ref (Class-rows class) 0))))))
           (compile-error loc "dynamic-instances needs methods of type (-> A B Output ! e)")))
        (_
         (compile-error loc "dynamic-instances does not support independent method requirements"))))

    (: resolve-binary-case (-> Program Class (List Type) (List String) Loc BinaryCase ! compile))
    (define (resolve-binary-case program class inputs active loc)
      (unless (and (= (length inputs) 2)
                   (every? (lambda (type) (and (ground-type? type) (not (any-type? type)))) inputs))
        (compile-error loc "dynamic-instances domain entries are two concrete, non-Any types"))
      (let ((matches (filter (lambda (instance)
                               (match (match-types (Instance-vars instance)
                                                   (type-arguments class (Instance-types instance))
                                                   inputs (Nil))
                                 ((Some _) #t) ((None) #f)))
                             (visible-instances program (Class-name class) active))))
        (match matches
          ((Cons instance (Nil)) (binary-case class instance inputs loc))
          ((Nil)
           (compile-error loc "dynamic-instances has no active source instance for a domain pair"))
          (_ (compile-error loc "dynamic-instances has overlapping source instances")))))

    (: binary-case (-> Class Instance (List Type) Loc BinaryCase ! compile))
    (define (binary-case class instance inputs loc)
      (unless (null? (Instance-requires instance))
        (compile-error loc "dynamic-instances source instances must have no class prerequisites"))
      (match (match-types (Instance-vars instance)
                          (type-arguments class (Instance-types instance))
                          inputs
                          (Nil))
        ((Some bindings)
         (let* ((head (map (lambda (type) (substitute bindings type)) (Instance-types instance)))
                (output (list-ref (output-arguments class head) 0))
                (row (list-ref (row-arguments class head) 0)))
           (unless (and (ground-type? output) (ground-type? row))
             (compile-error loc "dynamic-instances source outputs and rows must be determined"))
           (match row
             ((TRow labels (None)) (BinaryCase inputs output labels (Instance-methods instance)))
             (_ (compile-error loc "dynamic-instances source effect rows must be closed")))))
        ((None) (panic "internal error: selected binary instance did not match"))))

    (: erased-heads (-> (List Type) (List (List Type))))
    (define (erased-heads inputs)
      (let ((any (TCon "Any" (Nil))))
        (list (list any (list-ref inputs 1)) (list (list-ref inputs 0) any) (list any any))))

    (: accepts-pair? (-> (List Type) BinaryCase Bool))
    (define (accepts-pair? head branch)
      (every? (lambda (pair) (or (any-type? (Pair-first pair))
                                 (type=? (Pair-first pair) (Pair-second pair))))
              (zip head (BinaryCase-inputs branch))))

    (: generate-binary-instance
       (-> Class (List BinaryCase) (List Type) String String Loc GeneratedInstance))
    (define (generate-binary-instance class domain inputs owner name loc)
      (let* ((cases (filter (lambda (branch) (accepts-pair? inputs branch)) domain))
             (outputs (delete-duplicates type=? (map BinaryCase-output cases)))
             (output (if (= (length outputs) 1) (list-ref outputs 0) (TCon "Any" (Nil))))
             (row (TRow (fold-left
                         (lambda (labels branch) (label-union labels (BinaryCase-effects branch)))
                         (list dyn-cast-label) cases) (None)))
             (methods
              (map (lambda (method) (Pair method (string-append name "." (short-name method))))
                   (Class-methods class)))
             (instance (Instance name (Class-name class) (Nil) (binary-head class inputs output row)
                                 (Nil) (Nil) methods (Some owner))))
        (GeneratedInstance instance
                           (map (lambda (method)
                                  (Define (Pair-second method)
                                    (binary-lambda (Pair-first method) inputs output cases
                                                   (Pair-second method) loc))) methods))))

    (: binary-head (-> Class (List Type) Type Type (List Type)))
    (define (binary-head class inputs output row)
      (let ((bindings (zip (filter (lambda (param)
                                     (not (member? param
                                                   (append (Class-rows class)
                                                           (Class-outputs class)))))
                                   (Class-params class)) inputs)))
        (map (lambda (param)
               (cond ((member? param (Class-rows class)) row)
                     ((member? param (Class-outputs class)) output)
                     (else (match (assoc-ref bindings param)
                             ((Some type) type)
                             ((None) (panic "internal error: binary input parameter"))))))
             (Class-params class))))

    (: binary-lambda (-> String (List Type) Type (List BinaryCase) String Loc Expr))
    (define (binary-lambda method inputs output cases name loc)
      (let* ((names (list (string-append name ".left") (string-append name ".right")))
             (args (map (lambda (name) (reference name loc)) names))
             (failure (binary-failure method inputs args cases output loc)))
        (expression (Lambda names
                            (fold-right (lambda (branch rest)
                                          (expression (If (binary-test inputs args branch loc)
                                                          (binary-call method
                                                                       inputs
                                                                       args
                                                                       output
                                                                       branch
                                                                       loc)
                                                          rest)
                                                      loc))
                                        failure cases) #f) loc)))

    ;; A failed pair names the offending side. When the left type is
    ;; supported, the right side's expected types are restricted to that
    ;; left type; this also explains a missing pair in a nonrectangular domain.
    (: binary-failure (-> String (List Type) (List Expr) (List BinaryCase) Type Loc Expr))
    (define (binary-failure method inputs args cases output loc)
      (let ((lefts (delete-duplicates type=?
                                      (map (lambda (branch) (list-ref (BinaryCase-inputs branch) 0))
                                           cases))))
        (cond ((not (any-type? (list-ref inputs 0)))
               (binary-side-failure method args cases 1 output loc))
              ((not (any-type? (list-ref inputs 1)))
               (binary-side-failure method args cases 0 output loc))
              (else
               (fold-right (lambda (left rest)
                             (let ((eligible (filter (lambda (branch)
                                                       (type=? left
                                                               (list-ref (BinaryCase-inputs branch)
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

    (: binary-side-failure (-> String (List Expr) (List BinaryCase) I64 Type Loc Expr))
    (define (binary-side-failure method args cases index output loc)
      (conversion-failure
       (conversion-error "UnsupportedInstance"
                         (delete-duplicates type=?
                                            (map (lambda (branch)
                                                   (list-ref (BinaryCase-inputs branch) index))
                                                 cases))
                         (list-ref args index) method index loc) output loc))

    (: binary-test (-> (List Type) (List Expr) BinaryCase Loc Expr))
    (define (binary-test inputs args branch loc)
      (fold-right (lambda (entry rest)
                    (let ((index (Pair-first entry)) (type (Pair-second entry)))
                      (if (any-type? (list-ref inputs index))
                          (expression (If (expression (TypeTest (list-ref args index) type) loc)
                                          rest (expression (Lit (DBool #f)) loc)) loc)
                          rest)))
                  (expression (Lit (DBool #t)) loc)
                  (zip (iota 2) (BinaryCase-inputs branch))))

    (: binary-call (-> String (List Type) (List Expr) Type BinaryCase Loc Expr))
    (define (binary-call method inputs args output branch loc)
      (let* ((converted (map (lambda (entry)
                               (let ((index (Pair-first entry)) (target (Pair-second entry)))
                                 (if (any-type? (list-ref inputs index))
                                     (expression (Convert (list-ref args index) target) loc)
                                     (list-ref args index))))
                             (zip (iota 2) (BinaryCase-inputs branch))))
             (implementation (match (assoc-ref (BinaryCase-methods branch) method)
                               ((Some name) name)
                               ((None) (panic "internal error: missing binary implementation"))))
             (call (expression (App (reference implementation loc) converted) loc)))
        (if (and (any-type? output) (not (any-type? (BinaryCase-output branch))))
            (expression (Convert call output) loc) call)))
    ))

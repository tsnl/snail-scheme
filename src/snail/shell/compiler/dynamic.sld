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

    (: parse-dispatch (-> Class Instance (List Type) Loc Dispatch ! compile))
    (define (parse-dispatch class instance targets loc)
      (unless (and (null? (::vars instance))
                   (null? (::requires instance))
                   (= (length (filter any-type? (::types instance))) 1)
                   (not (lifecycle-class? (::name class))))
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
      (match (find (lambda (pair) (any-type? (::second pair)))
                   (zip (::params class) (::types instance)))
        ((Some pair) (::first pair))
        ((None) (panic "internal error: dispatch without Any"))))

    ;; ---- Methods ----

    ;; Keep the erased variable while substituting the fixed arguments.
    ;; This distinguishes a method's own Any parameter from an occurrence
    ;; of the class parameter that this dispatcher erases.
    (: dispatch-method (-> Program Class Instance String Dispatch Loc Expr ! compile))
    (define (dispatch-method program class instance method dispatch loc)
      (let* ((var (::variable dispatch))
             (fixed (filter (lambda (pair) (not (string=? var (::first pair))))
                            (zip (::params class) (::types instance)))))
        (match (program-value program method)
          ((Some (Method _ (Scheme vars (Cons _ (Nil)) _ type)))
           (unless (= (length vars) (length (::params class)))
             (compile-error loc "dispatch does not support independently polymorphic methods"))
           (dispatch-lambda instance
                            method
                            var
                            (substitute fixed type)
                            (::targets dispatch)
                            loc))
          (_ (compile-error loc
                            "dispatch does not support methods with additional class requirements")))))

    (: dispatch-lambda (-> Instance String String Type (List Type) Loc Expr ! compile))
    (define (dispatch-lambda instance method var type targets loc)
      (match type
        ((TFun params result _)
         (for-each (lambda (part) (check-dispatch-position var part loc)) (Cons result params))
         (let* ((prefix (string-append (::name instance) "." (short-name method)))
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
       (-> String String String (List (Pair Type Expr)) Type I64 (List Type) Loc Expr))
    (define (dispatch-branches prefix method var args result index targets loc)
      (let ((selector (::second (list-ref args index))))
        (fold-right (lambda (entry rest)
                      (dispatch-case
                       (string-append prefix ".case." (i64->string (::first entry)))
                       method var args result index (::second entry) rest loc))
                    (conversion-failure
                     (conversion-error "UnsupportedInstance" targets selector method index loc)
                     unchecked loc)
                    (zip (iota (length targets)) targets))))

    ;; The selector is already recovered in this branch. Its concrete type
    ;; marks it as an ordinary argument, so the call cannot probe it again.
    (: dispatch-case
       (-> String String String (List (Pair Type Expr)) Type I64 Type Expr Loc Expr))
    (define (dispatch-case prefix method var args result index target rest loc)
      (let* ((name (string-append prefix ".selector"))
             (selected (map-indexed (lambda (i arg)
                                      (if (= i index) (Pair target (reference name loc)) arg))
                                    args)))
        (recover-value (::second (list-ref args index)) target name
                       (dispatch-call prefix method var selected result target loc) rest loc)))

    (: dispatch-argument (-> String String String Type I64 (Pair Type Expr) Loc Expr))
    (define (dispatch-argument prefix method var target index argument loc)
      (let ((value (::second argument)))
        (if (type=? (::first argument) (TRigid var))
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

    (: dispatch-call (-> String String String (List (Pair Type Expr)) Type Type Loc Expr))
    (define (dispatch-call prefix method var args result target loc)
      (let* ((arguments (map (lambda (entry)
                               (dispatch-argument prefix method var target
                                                  (::first entry) (::second entry) loc))
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

    ;; These ordinary matches bind typed values before the method call.
    ;; Conversion lowering consumes their unused wrappers and errors.
    (: conversion-probe (-> Expr Type String Loc (Pair Expr Pattern)))
    (define (conversion-probe value target name loc)
      (Pair (expression (TryConvert value target) loc)
            (PCon "snail.core.base:Ok" (list (PVar name unchecked)) unchecked)))

    (: select-probe (-> (Pair Expr Pattern) Expr Expr Loc Expr))
    (define (select-probe probe success failure loc)
      (expression (Match (::first probe)
                         (list (Clause (::second probe) success)
                               (Clause (PWild unchecked) failure))) loc))

    (: recover-value (-> Expr Type String Expr Expr Loc Expr))
    (define (recover-value value target name success failure loc)
      (select-probe (conversion-probe value target name loc) success failure loc))

    (: recover-pair (-> (List Expr) (List Type) (List String) Expr Expr Loc Expr))
    (define (recover-pair values targets names success failure loc)
      (let* ((probes (map (lambda (index)
                            (conversion-probe (list-ref values index) (list-ref targets index)
                                              (list-ref names index) loc)) (iota 2)))
             (value (expression (App (reference "snail.core.base:Pair" loc)
                                     (map ::first probes)) loc))
             (pattern (PCon "snail.core.base:Pair" (map ::second probes) unchecked)))
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
               (generate-binary-instance class cases (::second entry) owner
                                         (string-append name "." (i64->string (::first entry)))
                                         loc))
             (zip (iota (length heads)) heads))))

    ;; This initial generator covers ordinary binary operation classes.
    ;; Independent method polymorphism and nested erased occurrences would
    ;; require a different conversion contract, so they fail at declaration.
    (: check-binary-class (-> Program Class Loc Unit ! compile))
    (define (check-binary-class program class loc)
      (unless (and (= (length (::rows class)) 1)
                   (= (length (::outputs class)) 1)
                   (= (length (type-arguments class (map TRigid (::params class)))) 2)
                   (not (null? (::methods class))))
        (compile-error loc
                       "dynamic-instances needs a binary class with one effect row and one associated output"))
      (for-each (lambda (method) (check-binary-method program class method loc))
                (::methods class)))

    (: check-binary-method (-> Program Class String Loc Unit ! compile))
    (define (check-binary-method program class method loc)
      (match (program-value program method)
        ((Some (Method _ (Scheme vars (Cons _ (Nil)) _ (TFun params result row))))
         (unless (and (= (length vars) (length (::params class)))
                      (types=? params (type-arguments class (map TRigid (::params class))))
                      (type=? result (TRigid (list-ref (::outputs class) 0)))
                      (type=? row (TRow (Nil) (Some (TRigid (list-ref (::rows class) 0))))))
           (compile-error loc "dynamic-instances needs methods of type (-> A B Output ! e)")))
        (_
         (compile-error loc "dynamic-instances does not support independent method requirements"))))

    (: resolve-binary-case (-> Program Class (List Type) (List String) Loc BinaryCase ! compile))
    (define (resolve-binary-case program class inputs active loc)
      (unless (and (= (length inputs) 2)
                   (every? (lambda (type) (and (ground-type? type) (not (any-type? type)))) inputs))
        (compile-error loc "dynamic-instances domain entries are two concrete, non-Any types"))
      (let ((matches (filter (lambda (instance)
                               (match (match-types (::vars instance)
                                                   (type-arguments class (::types instance))
                                                   inputs (Nil))
                                 ((Some _) #t) ((None) #f)))
                             (visible-instances program (::name class) active))))
        (match matches
          ((Cons instance (Nil)) (binary-case class instance inputs loc))
          ((Nil)
           (compile-error loc "dynamic-instances has no active source instance for a domain pair"))
          (_ (compile-error loc "dynamic-instances has overlapping source instances")))))

    (: binary-case (-> Class Instance (List Type) Loc BinaryCase ! compile))
    (define (binary-case class instance inputs loc)
      (unless (null? (::requires instance))
        (compile-error loc "dynamic-instances source instances must have no class prerequisites"))
      (match (match-types (::vars instance)
                          (type-arguments class (::types instance))
                          inputs
                          (Nil))
        ((Some bindings)
         (let* ((head (map (lambda (type) (substitute bindings type)) (::types instance)))
                (output (list-ref (output-arguments class head) 0))
                (row (list-ref (row-arguments class head) 0)))
           (unless (and (ground-type? output) (ground-type? row))
             (compile-error loc "dynamic-instances source outputs and rows must be determined"))
           (match row
             ((TRow labels (None)) (BinaryCase inputs output labels (::methods instance)))
             (_ (compile-error loc "dynamic-instances source effect rows must be closed")))))
        ((None) (panic "internal error: selected binary instance did not match"))))

    (: erased-heads (-> (List Type) (List (List Type))))
    (define (erased-heads inputs)
      (let ((any (TCon "Any" (Nil))))
        (list (list any (list-ref inputs 1)) (list (list-ref inputs 0) any) (list any any))))

    (: accepts-pair? (-> (List Type) BinaryCase Bool))
    (define (accepts-pair? head branch)
      (every? (lambda (pair) (or (any-type? (::first pair))
                                 (type=? (::first pair) (::second pair))))
              (zip head (::inputs branch))))

    (: generate-binary-instance
       (-> Class (List BinaryCase) (List Type) String String Loc GeneratedInstance))
    (define (generate-binary-instance class domain inputs owner name loc)
      (let* ((cases (filter (lambda (branch) (accepts-pair? inputs branch)) domain))
             (outputs (delete-duplicates type=? (map ::output cases)))
             (output (if (= (length outputs) 1) (list-ref outputs 0) (TCon "Any" (Nil))))
             (row (TRow (fold-left
                         (lambda (labels branch) (label-union labels (::effects branch)))
                         (list dyn-cast-label) cases) (None)))
             (methods
              (map (lambda (method) (Pair method (string-append name "." (short-name method))))
                   (::methods class)))
             (instance (Instance name (::name class) (Nil) (binary-head class inputs output row)
                                 (Nil) (Nil) methods (Some owner))))
        (GeneratedInstance instance
                           (map (lambda (method)
                                  (Define (::second method)
                                    (binary-lambda (::first method) inputs output cases
                                                   (::second method) loc))) methods))))

    (: binary-head (-> Class (List Type) Type Type (List Type)))
    (define (binary-head class inputs output row)
      (let ((bindings (zip (filter (lambda (param)
                                     (not (member? param
                                                   (append (::rows class)
                                                           (::outputs class)))))
                                   (::params class)) inputs)))
        (map (lambda (param)
               (cond ((member? param (::rows class)) row)
                     ((member? param (::outputs class)) output)
                     (else (match (assoc-ref bindings param)
                             ((Some type) type)
                             ((None) (panic "internal error: binary input parameter"))))))
             (::params class))))

    (: binary-lambda (-> String (List Type) Type (List BinaryCase) String Loc Expr))
    (define (binary-lambda method inputs output cases name loc)
      (let* ((names (list (string-append name ".left") (string-append name ".right")))
             (args (map (lambda (name) (reference name loc)) names))
             (failure (binary-failure method inputs args cases output loc)))
        (expression (Lambda names
                            (fold-right (lambda (entry rest)
                                          (binary-branch method
                                                         inputs
                                                         args
                                                         output
                                                         (::second entry)
                                                         (string-append name ".case."
                                                                        (i64->string
                                                                         (::first entry)))
                                                         rest loc))
                                        failure (zip (iota (length cases)) cases)) #f) loc)))

    ;; A generated head erases one or both arguments. The candidate's
    ;; typed bindings feed its selected implementation; a mismatch proceeds
    ;; to the next candidate without constructing a temporary error.
    (: binary-branch (-> String (List Type) (List Expr) Type BinaryCase String Expr Loc Expr))
    (define (binary-branch method inputs args output branch prefix rest loc)
      (let* ((names (list (string-append prefix ".left") (string-append prefix ".right")))
             (converted (map (lambda (i) (if (any-type? (list-ref inputs i))
                                             (reference (list-ref names i) loc) (list-ref args i)))
                             (iota 2)))
             (body (binary-call method converted output branch loc))
             (targets (::inputs branch)))
        (cond ((every? any-type? inputs) (recover-pair args targets names body rest loc))
              (else (let ((index (if (any-type? (list-ref inputs 0)) 0 1)))
                      (recover-value (list-ref args index) (list-ref targets index)
                                     (list-ref names index) body rest loc))))))

    ;; A failed pair names the offending side. When the left type is
    ;; supported, the right side's expected types are restricted to that
    ;; left type; this also explains a missing pair in a nonrectangular domain.
    (: binary-failure (-> String (List Type) (List Expr) (List BinaryCase) Type Loc Expr))
    (define (binary-failure method inputs args cases output loc)
      (let ((lefts (delete-duplicates type=?
                                      (map (lambda (branch) (list-ref (::inputs branch) 0))
                                           cases))))
        (cond ((not (any-type? (list-ref inputs 0)))
               (binary-side-failure method args cases 1 output loc))
              ((not (any-type? (list-ref inputs 1)))
               (binary-side-failure method args cases 0 output loc))
              (else
               (fold-right (lambda (left rest)
                             (let ((eligible (filter (lambda (branch)
                                                       (type=? left
                                                               (list-ref (::inputs branch)
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
                                                   (list-ref (::inputs branch) index))
                                                 cases))
                         (list-ref args index) method index loc) output loc))

    (: binary-call (-> String (List Expr) Type BinaryCase Loc Expr))
    (define (binary-call method args output branch loc)
      (let* ((implementation (match (assoc-ref (::methods branch) method)
                               ((Some name) name)
                               ((None) (panic "internal error: missing binary implementation"))))
             (call (expression (App (reference implementation loc) args) loc)))
        (if (and (any-type? output) (not (any-type? (::output branch))))
            (expression (Convert call output) loc) call)))
    ))

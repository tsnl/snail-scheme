;; A finite dynamic instance becomes ordinary typed methods. Its first
;; parameter of the erased class type selects a branch; every occurrence
;; of that type is checked against the same concrete type in that branch.
;; The checker then supplies ordinary class evidence and checks effects.
;; No instance registry or dictionary crosses a library boundary.
(define-library (snail shell compiler dynamic)
  (export
   Dispatch
   parse-dispatch
   dispatch-method)
  (import
   (snail core base)
   (snail shell compiler read)
   (snail shell compiler core))
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
           (match (find (lambda (pair) (type=? (Pair-first pair) (TRigid var))) arguments)
             ((Some selector)
              (expression (Lambda names
                                  (dispatch-branches method var arguments result
                                                     (Pair-second selector) targets loc)
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

    ;; The last branch still checks its arguments. An unsupported payload
    ;; therefore fails through the ordinary checked-conversion path, as
    ;; does a second argument whose payload differs from the first one's.
    (: dispatch-branches
       (-> String String (List (Pair Type Expr)) Type Expr (List Type) Loc Expr))
    (define (dispatch-branches method var args result selector targets loc)
      (match targets
        ((Cons target rest)
         (let ((body (dispatch-call method var args result target loc)))
           (if (null? rest)
               body
               (expression (If (expression (TypeTest selector target) loc)
                               body
                               (dispatch-branches method var args result selector rest loc))
                           loc))))
        ((Nil) (panic "internal error: empty dispatch"))))

    (: dispatch-call (-> String String (List (Pair Type Expr)) Type Type Loc Expr))
    (define (dispatch-call method var args result target loc)
      (let* ((arguments (map (lambda (pair)
                               (if (type=? (Pair-first pair) (TRigid var))
                                   (expression (Convert (Pair-second pair) target) loc)
                                   (Pair-second pair)))
                             args))
             (call (expression (App (reference method loc) arguments) loc)))
        (if (type=? result (TRigid var))
            (expression (Convert call (TCon "Any" (Nil))) loc)
            call)))

    (: expression (-> Term Loc Expr))
    (define (expression term loc)
      (Expr term unchecked loc))

    (: reference (-> String Loc Expr))
    (define (reference name loc)
      (expression (Var name (Nil) (Nil)) loc))))

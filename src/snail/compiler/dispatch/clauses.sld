;; Dispatch clauses: an instance whose body is `(dispatch T ...)` becomes
;; the instance with a method for each member of its class, as the old
;; compiler's `declare-instance-methods`, `dispatch-instance-method`
;; (src/snail/shell/compiler/expand.sld) and `dispatch-method` (src/snail/
;; shell/compiler/dynamic.sld) write them, every node at the instance.
;;
;; The clause's domain is checked first, and a problem there refuses the
;; library, as the old compiler checks it while it declares the instance.
;; Then each member of the class, as known where the instance is written,
;; in the class's order: a member whose method the clause cannot write is
;; a problem of its own, as the old compiler checks each method as it
;; expands that method's body, and the others are written all the same, so
;; every member's problem is reported. A class of the library declared
;; after the instance has no member there, so its clause instance has no
;; method and is accepted (build/dispatch-design/probes/class-later-
;; dispatch.sld), as in the old compiler, which registers a class's methods
;; only once its declaration is reached.
;;
;; A member's method is a ClosedLambda of its parameters that tries each
;; target in turn on the selecting parameter, as (snail compiler dispatch
;; language) shows. Its implementation's Global is named for the member,
;; then its parameters are numbered, then each target's locals in turn.
(define-library (snail compiler dispatch clauses)
  (export
   ClauseMethods
   clause-methods)
  (import
   (snail core base)
   (snail compiler source)
   (only (snail compiler names globals) Local TopGlobal)
   (prefix (snail compiler declare language) declared-)
   (only (snail compiler declare membership) member-name)
   (snail compiler dispatch runtime)
   (only (snail compiler builtins base)
         unsupported-instance-case
         argument-mismatch-case
         dyn-cast-effect)
   (snail compiler dispatch known)
   (snail compiler dispatch domains)
   (snail compiler names numbering)
   (snail compiler dispatch conversions))
  (begin

    ;; ---- Clauses ----

    ;; The methods written, in the class's order, and the problem of each
    ;; member whose method could not be, in that order.
    (struct ClauseMethods
      ((methods (List declared-InstanceMethod))
       (problems (List Feedback))))

    ;; The methods the clause of `instance`, whose types are `targets`,
    ;; stands for, `class` as known where the instance is written; or the
    ;; domain's problem, at the instance.
    (: clause-methods
       (impl (Fn Numbering KnownClass declared-Instance (List declared-Type)
                 -> (Result (Pair ClauseMethods Numbering) (List Feedback)))))
    (define (clause-methods state class instance targets)
      (let ((loc (::loc instance)))
        (match (clause-domain class instance targets)
          ((Err message) (fail loc message))
          ((Ok domain) (Ok (members-methods state domain (::members class) loc))))))

    (: members-methods
       (impl (Fn Numbering Domain (List (Pair declared-Member declared-Scheme)) Loc
                 -> (Pair ClauseMethods Numbering))))
    (define (members-methods state domain members loc)
      (let loop ((state state)
                 (members members)
                 (methods (Nil))
                 (problems (Nil)))
        (match members
          ((Nil) (Pair (ClauseMethods (reverse methods) (reverse problems)) state))
          ((Cons member rest)
           (match (method-shape domain (::second member))
             ((Err message) (loop state rest methods (Cons (Feedback loc message) problems)))
             ((Ok shape)
              (state-let* ((method state
                                   (written-method state domain (::first member) shape loc)))
                (loop state rest (Cons method methods) problems))))))))

    ;; ---- Methods ----

    ;; One of a method's parameters: its place among them, its local in
    ;; the lambda, and what it is.
    (struct Parameter
      ((index I64)
       (local Local)
       (position Position)))

    ;; What each branch of one method's lambda shares: the member it calls,
    ;; its shape, its parameters, the one it selects by, and where it is.
    (struct Dispatching
      ((member declared-Member)
       (shape MethodShape)
       (parameters (List Parameter))
       (selecting Local)
       (loc Loc)))

    ;; One target's branch: the target, the local the selecting argument is
    ;; recovered as, and the call made with it.
    (struct Branch
      ((target declared-Type)
       (selected Local)
       (call declared-Expr)))

    (: written-method
       (impl (Fn Numbering Domain declared-Member MethodShape Loc
                 -> (Pair declared-InstanceMethod Numbering))))
    (define (written-method state domain member shape loc)
      (state-let* ((implementation state (fresh-global state (member-name member)))
                   (locals state (fresh-locals state "argument" (length (::parameters shape)))))
        (let ((dispatching (method-dispatching member shape locals loc)))
          (state-let* ((branches state
                                 (map-with-state state
                                                 (lambda (state target)
                                                   (branch state dispatching target))
                                                 (::targets domain))))
            (Pair (declared-InstanceMethod member
                                           implementation
                                           (declared-ClosedLambda locals
                                                                  (tried dispatching
                                                                         (::targets domain)
                                                                         branches)
                                                                  loc)
                                           loc)
                  state)))))

    ;; `locals` are one for each of the shape's parameters, and its
    ;; selector is the index of one of them, as `method-shape` found it.
    (: method-dispatching
       (impl (Fn declared-Member MethodShape (List Local) Loc -> Dispatching)))
    (define (method-dispatching member shape locals loc)
      (Dispatching member
                   shape
                   (map (lambda (entry)
                          (Parameter (::first entry)
                                     (::first (::second entry))
                                     (::second (::second entry))))
                        (zip (iota (length locals)) (zip locals (::parameters shape))))
                   (list-ref locals (::selector shape))
                   loc))

    ;; Each branch in turn, then the failure that names every target.
    (: tried (impl (Fn Dispatching (List declared-Type) (List Branch) -> declared-Expr)))
    (define (tried dispatching targets branches)
      (let ((loc (::loc dispatching)))
        (fold-right (lambda (branch rest)
                      (recovered (declared-LocalRef (::selecting dispatching) loc)
                                 (::target branch)
                                 (::selected branch)
                                 (::call branch)
                                 rest
                                 loc))
                    (cast-failure unsupported-instance-case
                                  targets
                                  (declared-LocalRef (::selecting dispatching) loc)
                                  (::member dispatching)
                                  (::selector (::shape dispatching))
                                  loc)
                    branches)))

    (: branch (impl (Fn Numbering Dispatching declared-Type -> (Pair Branch Numbering))))
    (define (branch state dispatching target)
      (state-let* ((selected state (fresh-local state "selected"))
                   (arguments state
                              (map-with-state state
                                              (lambda (state parameter)
                                                (argument state
                                                          dispatching
                                                          target
                                                          selected
                                                          parameter))
                                              (::parameters dispatching))))
        (Pair (Branch target selected (method-call dispatching arguments)) state)))

    ;; The argument for `parameter` in the branch for `target`: the
    ;; selected value; another erased argument, recovered as the same
    ;; target or the dispatch failed for it; or the parameter as it is.
    (: argument
       (impl
        (Fn Numbering Dispatching declared-Type Local Parameter -> (Pair declared-Expr Numbering))))
    (define (argument state dispatching target selected parameter)
      (let ((loc (::loc dispatching))
            (value (declared-LocalRef (::local parameter) (::loc dispatching))))
        (if (= (::index parameter) (::selector (::shape dispatching)))
            (Pair (declared-LocalRef selected loc) state)
            (match (::position parameter)
              ((Fixed) (Pair value state))
              ((Erased)
               (state-let* ((recovery state (fresh-local state "recovered")))
                 (Pair (recovered value
                                  target
                                  recovery
                                  (declared-LocalRef recovery loc)
                                  (cast-failure argument-mismatch-case
                                                (list target)
                                                value
                                                (::member dispatching)
                                                (::index parameter)
                                                loc)
                                  loc)
                       state)))))))

    ;; The class's method called with `arguments`, its result erased again
    ;; when the method returns the erased parameter.
    (: method-call (impl (Fn Dispatching (List declared-Expr) -> declared-Expr)))
    (define (method-call dispatching arguments)
      (let ((call (member-call (::member dispatching) arguments (::loc dispatching))))
        (match (::result (::shape dispatching))
          ((Erased) (declared-Convert call any-type (::loc dispatching)))
          ((Fixed) call))))

    ;; A class's method is called by its Global. A field class's reader
    ;; takes the one record, as `field-reader-scheme` says, so its call is
    ;; the read itself, as `expand` writes `(::label record)`.
    (: member-call (impl (Fn declared-Member (List declared-Expr) Loc -> declared-Expr)))
    (define (member-call member arguments loc)
      (match member
        ((declared-ClassMethod global)
         (declared-Call (declared-TopRef (TopGlobal global) loc) arguments loc))
        ((declared-FieldReader label)
         (match arguments
           ((Cons record (Nil)) (declared-PathApply (list label) record loc))
           (_ (declared-Call (declared-Path (list label) loc) arguments loc))))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-clauses)
    (import
     (only (snail compiler expand language) Dyn FnContract)
     (only (snail compiler names globals) Global ClassGlobal FieldClass)
     (only (snail compiler literals constant) Integer Text)
     (only (snail compiler names libraries) forms-library)
     (only (snail compiler declare schemes) field-class-parameters field-reader-scheme)
     (snail stage0 testing))
    (begin
      (define (test-clauses)
        (test-num)
        (test-describe)
        (test-field)
        (test-members)
        (test-domain))

      (define loc (Loc "t.sld" 4 1))
      (define base (list "snail" "core" "base"))
      (define main (list "main"))

      (define (builtin name)
        (declared-Con (Global forms-library name 0) (list)))

      (define i64 (builtin "I64"))
      (define f64 (builtin "F64"))
      (define string-type (builtin "String"))
      (define t (declared-Var (declared-Written "T")))
      (define dyn-cast-row (declared-Row (declared-Effects (list dyn-cast-effect) (None))))

      (define (list-of type)
        (declared-Con (Global base "List" 0) (list type)))

      ;; `(dyn (Fn parameter ... -> result ! e))`, a method's own type.
      (define (method-type parameters result)
        (declared-Callable (Dyn)
                           (FnContract)
                           (declared-Arrow parameters
                                           result
                                           (declared-Effects (list)
                                                             (Some (declared-Var
                                                                    (declared-Written "e")))))))

      (define (own type)
        (declared-Scheme (list) (list) (list) type))

      (define (class-of members)
        (KnownClass (list (declared-RowParameter "e") (declared-TypeParameter "T")) (list) members))

      (define (method library name type)
        (Pair (declared-ClassMethod (Global library name 0)) (own type)))

      ;; `(instance (Class (! dyn-cast) Any) (dispatch target ...))` at
      ;; line 4.
      (define (clause-instance class targets)
        (declared-Instance (Global main "Clause" 1)
                           class
                           (list)
                           (list dyn-cast-row (declared-Con (Global forms-library "Any" 0) (list)))
                           (list)
                           (list)
                           (list)
                           (declared-Dispatch targets loc)
                           loc))

      (define (written state class class-ref targets)
        (clause-methods state class (clause-instance class-ref targets) targets))

      ;; ---- The expected code, written out with the old compiler's shape ----

      (define (top global)
        (declared-TopRef (TopGlobal global) loc))

      (define (ref local)
        (declared-LocalRef local loc))

      (define (call callee arguments)
        (declared-Call callee arguments loc))

      (define (text value)
        (declared-Literal (Text value) loc))

      ;; `(match (try-convert value target) ((Ok bound) success) (_ failure))`.
      (define (attempt value target bound success failure)
        (declared-Match (declared-TryConvert value target loc)
                        (list
                         (declared-Clause (declared-Destructure (TopGlobal (Global base "Ok" 0))
                                                                (list (declared-Bind bound loc))
                                                                loc)
                                          success
                                          loc)
                         (declared-Clause (declared-Wild loc) failure loc))
                        loc))

      ;; `(match (conversion-failed (CastError (reason) expected ...)))`.
      (define (failed reason expected value method index)
        (declared-Match
         (call (top (Global base "conversion-failed" 0))
               (list (call (top (Global base "CastError" 0))
                           (list (call (top (Global base reason 0)) (list))
                                 (fold-right (lambda (name rest)
                                               (call (top (Global base "Cons" 0))
                                                     (list (text name) rest)))
                                             (call (top (Global base "Nil" 0)) (list))
                                             expected)
                                 (call (top (Global (list "prim") "any-type-id" 0)) (list value))
                                 (text "t.sld:4:1")
                                 (text method)
                                 (declared-Literal (Integer index) loc)))))
         (list)
         loc))

      (define (local name number)
        (Local name number))

      (define (to-any expr)
        (declared-Convert expr (declared-Con (Global forms-library "Any" 0) (list)) loc))

      ;; ---- Num ----

      ;; `(instance (Num (! dyn-cast) Any) (dispatch I64 F64))`, as the old
      ;; `dispatch-method` writes it (build/dispatch-runs/old-dispatch.scm
      ;; prints the old definitions of build/dispatch-probes/num.sld): a
      ;; binary method selects by its first argument and recovers its second
      ;; as the same target, or fails at index 1; it converts its result to
      ;; Any; after the last target it fails at index 0.
      (define (binary-method name first)
        (let* ((left (local "argument" (+ first 1)))
               (right (local "argument" (+ first 2)))
               (plus (top (Global base name 0)))
               (text-of (string-append "snail.core.base:" name))
               (case-of (lambda (target name selected recovered rest)
                          (attempt (ref left)
                                   target
                                   selected
                                   (to-any (call plus
                                                 (list (ref selected)
                                                       (attempt (ref right)
                                                                target
                                                                recovered
                                                                (ref recovered)
                                                                (failed "ArgumentMismatch"
                                                                        (list name)
                                                                        (ref right)
                                                                        text-of
                                                                        1)))))
                                   rest))))
          (declared-InstanceMethod
           (declared-ClassMethod (Global base name 0))
           (Global main name first)
           (declared-ClosedLambda
            (list left right)
            (case-of i64
                     "I64"
                     (local "selected" (+ first 3))
                     (local "recovered" (+ first 4))
                     (case-of f64
                              "F64"
                              (local "selected" (+ first 5))
                              (local "recovered" (+ first 6))
                              (failed "UnsupportedInstance"
                                      (list "I64" "F64")
                                      (ref left)
                                      text-of
                                      0)))
            loc)
           loc)))

      (define (negate-method first)
        (let ((value (local "argument" (+ first 1)))
              (negate (top (Global base "negate" 0)))
              (text-of "snail.core.base:negate"))
          (declared-InstanceMethod
           (declared-ClassMethod (Global base "negate" 0))
           (Global main "negate" first)
           (declared-ClosedLambda
            (list value)
            (attempt (ref value)
                     i64
                     (local "selected" (+ first 2))
                     (to-any (call negate (list (ref (local "selected" (+ first 2))))))
                     (attempt (ref value)
                              f64
                              (local "selected" (+ first 3))
                              (to-any (call negate (list (ref (local "selected" (+ first 3))))))
                              (failed "UnsupportedInstance"
                                      (list "I64" "F64")
                                      (ref value)
                                      text-of
                                      0)))
            loc)
           loc)))

      (define num
        (class-of (list (method base "+" (method-type (list t t) t))
                        (method base "-" (method-type (list t t) t))
                        (method base "*" (method-type (list t t) t))
                        (method base "negate" (method-type (list t) t)))))

      ;; Each method's implementation, then its parameters, then each
      ;; target's locals, numbered in turn from 10.
      (define (test-num)
        (expect (written (Numbering main 10)
                         num
                         (ClassGlobal (Global base "Num" 0))
                         (list i64 f64))
                (Ok (Pair (ClauseMethods (list (binary-method "+" 10)
                                               (binary-method "-" 17)
                                               (binary-method "*" 24)
                                               (negate-method 31))
                                         (list))
                          (Numbering main 35)))))

      ;; ---- Describe ----

      ;; `(instance (Describe (! dyn-cast) Any) (dispatch I64 String (List
      ;; I64)))`, as the old compiler writes it for tests/programs/lib/
      ;; gradual/describe.sld: a result that is no erased parameter is
      ;; returned as the method returns it, and the failure names each
      ;; target as the old compiler writes a type.
      (define (test-describe)
        (let* ((gradual (list "gradual" "describe"))
               (describe (Global gradual "describe" 0))
               (value (local "argument" 6))
               (branch (lambda (target number rest)
                         (attempt (ref value)
                                  target
                                  (local "selected" number)
                                  (call (top describe) (list (ref (local "selected" number))))
                                  rest))))
          (expect (written (Numbering main 5)
                           (class-of
                            (list (method gradual "describe" (method-type (list t) string-type))))
                           (ClassGlobal (Global gradual "Describe" 0))
                           (list i64 string-type (list-of i64)))
                  (Ok (Pair (ClauseMethods
                             (list (declared-InstanceMethod
                                    (declared-ClassMethod describe)
                                    (Global main "describe" 5)
                                    (declared-ClosedLambda
                                     (list value)
                                     (branch i64
                                             7
                                             (branch string-type
                                                     8
                                                     (branch (list-of i64)
                                                             9
                                                             (failed "UnsupportedInstance"
                                                                     (list "I64"
                                                                           "String"
                                                                           "(List I64)")
                                                                     (ref value)
                                                                     "gradual.describe:describe"
                                                                     0))))
                                     loc)
                                    loc))
                             (list))
                            (Numbering main 10))))))

      ;; ---- Field classes ----

      ;; `(instance (::x Any I64) (dispatch Point))`: the reader is called
      ;; by its path, and named by it in a CastError
      ;; (build/dispatch-probes/field-dispatch.sld).
      (define (test-field)
        (let ((point (declared-Con (Global main "Point" 0) (list)))
              (value (local "argument" 2)))
          (expect (clause-methods (Numbering main 1)
                                  (KnownClass field-class-parameters
                                              (list)
                                              (list (Pair (declared-FieldReader "x")
                                                          field-reader-scheme)))
                                  (declared-Instance (Global main "x" 0)
                                                     (FieldClass "x")
                                                     (list)
                                                     (list
                                                      (declared-Con (Global forms-library "Any" 0)
                                                                    (list))
                                                      i64)
                                                     (list)
                                                     (list)
                                                     (list)
                                                     (declared-Dispatch (list point) loc)
                                                     loc)
                                  (list point))
                  (Ok (Pair (ClauseMethods
                             (list (declared-InstanceMethod
                                    (declared-FieldReader "x")
                                    (Global main "x" 1)
                                    (declared-ClosedLambda
                                     (list value)
                                     (attempt (ref value)
                                              point
                                              (local "selected" 3)
                                              (declared-PathApply (list "x")
                                                                  (ref (local "selected" 3))
                                                                  loc)
                                              (failed "UnsupportedInstance"
                                                      (list "Point")
                                                      (ref value)
                                                      "::x"
                                                      0))
                                     loc)
                                    loc))
                             (list))
                            (Numbering main 4))))))

      ;; ---- Members ----

      ;; Each member that cannot be written is a problem of its own, at the
      ;; instance, and the others are written (build/dispatch-design/
      ;; probes/dispatch-per-method.sld, whose instance at 7:1 has two); a
      ;; class known with no member, as one of the library declared after
      ;; the instance is, gives the instance no method and leaves the
      ;; numbers as they were (probes/class-later-dispatch.sld).
      (define (test-members)
        (let ((read (method main "one" (method-type (list string-type) t)))
              (two (method main "two" (method-type (list string-type) t)))
              (show (method main "show" (method-type (list t) string-type)))
              (class-ref (ClassGlobal (Global main "Two" 0))))
          (expect (written (Numbering main 1) (class-of (list read two)) class-ref (list i64))
                  (Ok (Pair (ClauseMethods
                             (list)
                             (list (Feedback loc
                                             "each dispatched method needs an argument of its erased class type")
                                   (Feedback loc
                                             "each dispatched method needs an argument of its erased class type")))
                            (Numbering main 1))))
          (match (written (Numbering main 1) (class-of (list read show)) class-ref (list i64))
            ((Ok (Pair found next))
             (expect (map ::member (::methods found)) (list (::first show)))
             (expect (::problems found)
                     (list (Feedback loc
                                     "each dispatched method needs an argument of its erased class type")))
             (expect next (Numbering main 4)))
            (other (expect other "one method and one problem")))
          (expect (written (Numbering main 1)
                           (KnownClass
                            (list (declared-TypeParameter "e") (declared-TypeParameter "T"))
                            (list)
                            (list))
                           class-ref
                           (list i64))
                  (Ok (Pair (ClauseMethods (list) (list)) (Numbering main 1))))))

      ;; A domain's problem refuses the instance, at its place.
      (define (test-domain)
        (expect (written (Numbering main 1) num (ClassGlobal (Global base "Num" 0)) (list))
                (fail loc "dispatch needs at least one concrete type")))))
   (else)))

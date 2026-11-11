;; Types: a written type becomes a Type, a written scheme a Scheme, and a
;; list of requirements the requirements of a scheme or an instance, as
;; the old compiler resolves them (`resolve-type`, `resolve-scheme` and
;; `resolve-requirements`, src/snail/shell/compiler/expand.sld), in its
;; order, the first problem stopping the rest:
;;
;; - A type's arguments are converted after its arity is checked, and a
;;   projection's before it is looked up.
;; - An alias's use converts its arguments where it is, then its body with
;;   each parameter the type its argument became, where no requirement is
;;   in scope, as the old compiler resolves the body in the alias's own
;;   scope. So a projection in an alias's body is refused, and an argument
;;   the body does not use is still checked.
;; - Each requirement is converted in the scope of those before it: its
;;   types, then the type each output's equation gives, in the class's
;;   order, then the checks of the requirement as a whole. The scheme's
;;   type is converted in the scope of them all, and then made to obey
;;   the rules of callables.
;;
;; What a type means depends on the declarations before it: a class's rows
;; are known only once its declaration is reached. So the pass hands each
;; conversion what is known where the type is written, and the
;; requirements in scope there.
(define-library (snail compiler declare types)
  (export
   Scope
   Required
   declared-type
   declared-types
   declared-scheme
   declared-requirements)
  (import
   (snail core base)
   (snail compiler source)
   (prefix (snail compiler expand language) expanded-)
   (snail compiler declare language)
   (snail compiler declare known)
   (snail compiler declare equality)
   (snail compiler declare requirements)
   (snail compiler declare projections)
   (snail compiler declare callables))
  (begin

    ;; ---- Scope ----

    ;; Where a written type is converted: what is known there of types and
    ;; classes, and the requirements in scope, innermost first, among which
    ;; a projection finds the one it reads. A signature starts with none; a
    ;; class's method has the class's own, `(Class parameter ... output
    ;; ...)`; an instance's head has the instance's requirements; a type in
    ;; an expression has none.
    (struct Scope
      ((known Known)
       (requirements (List Requirement))))

    ;; While an alias's body is converted, the types its use's arguments
    ;; became, each standing for the parameter at its index; outside any
    ;; body, none.
    (struct Converting
      ((scope Scope)
       (arguments (List Type))))

    ;; ---- Types ----

    (: declared-type (impl (Fn Scope expanded-TypeExpr -> (Result Type (List Feedback)))))
    (define (declared-type scope type)
      (type-of (Converting scope (Nil)) type))

    (: declared-types
       (impl (Fn Scope (List expanded-TypeExpr) -> (Result (List Type) (List Feedback)))))
    (define (declared-types scope types)
      (types-of (Converting scope (Nil)) types))

    (: type-of (impl (Fn Converting expanded-TypeExpr -> (Result Type (List Feedback)))))
    (define (type-of converting type)
      (match type
        ((expanded-Applied global written arguments loc)
         (applied-type converting global written arguments loc))
        ((expanded-Variable name _) (Ok (Var (Written name))))
        ((expanded-Projection class output arguments loc)
         (projection-type converting class output arguments loc))
        ((expanded-Callable former contract arrow _)
         (result-let* ((converted (arrow-of converting arrow)))
           (Ok (Callable former contract converted))))
        ((expanded-Code arrow _)
         (result-let* ((converted (arrow-of converting arrow)))
           (Ok (Code converted))))
        ((expanded-Row effects _)
         (result-let* ((converted (effects-of converting effects)))
           (Ok (Row converted))))
        ((expanded-Aliased _ arguments body _) (aliased-type converting arguments body))
        ((expanded-AliasParameter index _) (Ok (alias-argument converting index)))))

    (: types-of
       (impl (Fn Converting (List expanded-TypeExpr) -> (Result (List Type) (List Feedback)))))
    (define (types-of converting types)
      (map-results (lambda (type) (type-of converting type)) types))

    ;; A declared or builtin type, at as many arguments as it takes.
    (: applied-type
       (impl
        (Fn Converting
            expanded-Global
            String
            (List expanded-TypeExpr)
            Loc
            ->
            (Result Type (List Feedback)))))
    (define (applied-type converting global written arguments loc)
      (match (arity-problem (::known (::scope converting)) global written (length arguments))
        ((Some message) (fail loc message))
        ((None)
         (result-let* ((types (types-of converting arguments)))
           (Ok (Con global types))))))

    ;; What the requirement in scope gives the output, its class as known
    ;; here.
    (: projection-type
       (impl
        (Fn Converting
            expanded-Global
            String
            (List expanded-TypeExpr)
            Loc
            ->
            (Result Type (List Feedback)))))
    (define (projection-type converting class output arguments loc)
      (let ((scope (::scope converting)))
        (result-let* ((types (types-of converting arguments)))
          (match (projected (class-shape (::known scope) (expanded-ClassGlobal class))
                            class
                            output
                            types
                            (::requirements scope))
            ((Ok projection) (Ok projection))
            ((Err message) (fail loc message))))))

    ;; The arguments where the use is, then the body with them.
    (: aliased-type
       (impl
        (Fn Converting
            (List expanded-TypeExpr)
            expanded-TypeExpr
            ->
            (Result Type (List Feedback)))))
    (define (aliased-type converting arguments body)
      (result-let* ((types (types-of converting arguments)))
        (type-of (Converting (Scope (::known (::scope converting)) (Nil)) types) body)))

    ;; Expanded guarantees an AliasParameter's index is below the count of
    ;; its alias's arguments, and the innermost alias whose body is being
    ;; converted is its own, so the argument is there.
    (: alias-argument (impl (Fn Converting I64 -> Type)))
    (define (alias-argument converting index)
      (list-ref (::arguments converting) index))

    (: arrow-of (impl (Fn Converting expanded-Arrow -> (Result Arrow (List Feedback)))))
    (define (arrow-of converting arrow)
      (result-let* ((parameters (types-of converting (::parameters arrow)))
                    (result (type-of converting (::result arrow)))
                    (effects (effects-of converting (::effects arrow))))
        (Ok (Arrow parameters result effects))))

    ;; The labels as a set; the tail as written.
    (: effects-of (impl (Fn Converting expanded-Effects -> (Result Effects (List Feedback)))))
    (define (effects-of converting effects)
      (match (::tail effects)
        ((None) (Ok (Effects (effect-set (::labels effects)) (None))))
        ((Some tail)
         (result-let* ((type (type-of converting tail)))
           (Ok (Effects (effect-set (::labels effects)) (Some type)))))))

    ;; ---- Requirements ----

    ;; Requirements converted one after another: the variables so far,
    ;; the requirements with evidence, those `Copy` names apart, and the
    ;; scope they make, each requirement innermost over those before it.
    (struct Required
      ((variables (List TypeVariable))
       (requirements (List Requirement))
       (copied (List TypeVariable))
       (scope Scope)))

    ;; The requirements of a scheme or an instance over the variables
    ;; `names`, in the scope `scope`.
    (: declared-requirements
       (impl
        (Fn Scope (List String) (List expanded-Requirement) -> (Result Required (List Feedback)))))
    (define (declared-requirements scope names requirements)
      (let loop ((required (Required (map Written names) (Nil) (Nil) scope))
                 (requirements requirements))
        (match requirements
          ((Nil) (Ok required))
          ((Cons requirement rest)
           (result-let* ((next (with-requirement required requirement)))
             (loop next rest))))))

    (: with-requirement
       (impl (Fn Required expanded-Requirement -> (Result Required (List Feedback)))))
    (define (with-requirement required requirement)
      (match requirement
        ((expanded-CopyRequirement name _)
         (Ok (Required (::variables required)
                       (::requirements required)
                       (append (::copied required) (list (Written name)))
                       (::scope required))))
        ((expanded-ClassRequirement class types equations loc)
         (result-let* ((converted (class-requirement required class types equations loc)))
           (Ok (with-evidence required (::first converted) (::second converted)))))
        ((expanded-CallableRequirement contract receiver arrow _)
         (let ((converting (Converting (::scope required) (Nil))))
           (result-let* ((receiver-type (type-of converting receiver))
                         (converted (arrow-of converting arrow)))
             (Ok (with-evidence required
                                (CallableRequirement contract receiver-type converted)
                                (Nil))))))))

    ;; `required` with a requirement that has evidence, after those before
    ;; it and in scope over them, and the variables it leaves unwritten.
    ;; As in the old compiler's, the variables are kept once each from the
    ;; first such requirement on, so a variable written twice is then one.
    (: with-evidence (impl (Fn Required Requirement (List TypeVariable) -> Required)))
    (define (with-evidence required requirement hidden)
      (let ((scope (::scope required)))
        (Required (delete-duplicates same-variable? (append (::variables required) hidden))
                  (append (::requirements required) (list requirement))
                  (::copied required)
                  (Scope (::known scope) (Cons requirement (::requirements scope))))))

    ;; A class's requirement, and the variables of the outputs it leaves
    ;; unwritten, each `(Associated n output)` for the requirement's
    ;; position `n` among those with evidence, as the old compiler names it
    ;; `$associated.n.output`.
    (: class-requirement
       (impl
        (Fn Required
            expanded-ClassRef
            (List expanded-TypeExpr)
            (List expanded-Equation)
            Loc
            ->
            (Result (Pair Requirement (List TypeVariable)) (List Feedback)))))
    (define (class-requirement required class types equations loc)
      (let* ((scope (::scope required))
             (shape (class-shape (::known scope) class))
             (number (length (::requirements required))))
        (result-let* ((given (declared-types scope types))
                      (outputs (output-types scope shape number equations)))
          (match (requirement-check shape equations (append given outputs))
            ((Some message) (fail loc message))
            ((None)
             (Ok (Pair (ClassRequirement class (append given outputs))
                       (hidden-outputs shape number equations))))))))

    (: requirement-check
       (impl (Fn ClassShape (List expanded-Equation) (List Type) -> (Option String))))
    (define (requirement-check shape equations types)
      (match (equations-problem shape equations)
        ((Some message) (Some message))
        ((None) (requirement-problem shape types))))

    ;; What each output is: its equation's type, or the variable that
    ;; stands for it.
    (: output-types
       (impl
        (Fn Scope ClassShape I64 (List expanded-Equation) -> (Result (List Type) (List Feedback)))))
    (define (output-types scope shape number equations)
      (map-results (lambda (pair)
                     (match (::second pair)
                       ((Some equation) (declared-type scope (::type equation)))
                       ((None) (Ok (Var (Associated number (::first pair)))))))
                   (zip (::outputs shape) (given-outputs shape equations))))

    (: hidden-outputs
       (impl (Fn ClassShape I64 (List expanded-Equation) -> (List TypeVariable))))
    (define (hidden-outputs shape number equations)
      (concatenate (map (lambda (pair)
                          (match (::second pair)
                            ((Some _) (Nil))
                            ((None) (list (Associated number (::first pair))))))
                        (zip (::outputs shape) (given-outputs shape equations)))))

    ;; ---- Schemes ----

    ;; Its requirements over its variables, its type in their scope, and
    ;; then the rules of callables, refused at the scheme.
    (: declared-scheme (impl (Fn Scope expanded-Scheme -> (Result Scheme (List Feedback)))))
    (define (declared-scheme scope scheme)
      (result-let* ((required (declared-requirements scope
                                                     (::variables scheme)
                                                     (::requirements scheme)))
                    (type (declared-type (::scope required) (::type scheme))))
        (match (callable-scheme (Scheme (::variables required)
                                        (::requirements required)
                                        (::copied required)
                                        type))
          ((Ok lifted) (Ok lifted))
          ((Err message) (fail (::loc scheme) message)))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-types)
    (import
     (snail core table)
     (only (snail compiler expand language)
           Global
           ClassGlobal
           FieldClass
           Label
           Impl
           Dyn
           FnContract
           FnMutContract)
     (snail compiler declare offer)
     (snail compiler declare forms)
     (snail stage0 testing))
    (begin
      (define (test-types)
        (test-applied)
        (test-aliases)
        (test-projections)
        (test-requirements)
        (test-schemes))

      (define (at line)
        (Loc "t.sld" line 1))

      (define loc (at 1))
      (define main (list "main"))
      (define lib (list "lib"))
      (define (global library name)
        (Global library name 0))
      (define (builtin name)
        (Global forms-library name 0))

      (define list-global (global main "List"))
      (define show (global main "Show"))
      (define collect (global lib "Collect"))
      (define store (global lib "Store"))
      (define io (global main "io"))
      (define log (global lib "log"))

      ;; (main) declares (List a) and (Show a), whose output is Out; it
      ;; imports (lib), which declares (Pair a b), the class (Collect c)
      ;; with outputs Item and Key, and the class (Store e s), e a row.
      (define known
        (Known main
               (Scanned (by-name empty-table "List" (ScannedType list-global (list "a")))
                        (by-name empty-table "Show" (ScannedClass show (list "a") (list "Out"))))
               (Declarations main empty-table empty-table empty-table)
               (list (Declarations lib
                                   (by-name empty-table
                                            "Pair"
                                            (Data (global lib "Pair")
                                                  (list "a" "b")
                                                  (list)
                                                  (StructData)
                                                  #f
                                                  #f
                                                  (list)
                                                  loc))
                                   (by-name (by-name empty-table
                                                     "Collect"
                                                     (Class collect
                                                            (list (TypeParameter "c"))
                                                            (list (Output (Label "Item" loc) (list))
                                                                  (Output (Label "Key" loc) (list)))
                                                            (list)
                                                            (list)
                                                            loc))
                                            "Store"
                                            (Class store
                                                   (list (RowParameter "e") (TypeParameter "s"))
                                                   (list)
                                                   (list)
                                                   (list)
                                                   loc))
                                   empty-table))))

      (define top (Scope known (Nil)))

      ;; Written types, by hand.
      (define (applied global arguments line)
        (expanded-Applied global (::name global) arguments (at line)))
      (define (i64-at line)
        (applied (builtin "I64") (list) line))
      (define (variable name)
        (expanded-Variable name loc))
      (define pure (expanded-Effects (list) (None)))
      (define (arrow parameters result)
        (expanded-Arrow parameters result pure))

      (define i64 (Con (builtin "I64") (list)))
      (define (var name)
        (Var (Written name)))
      (define (list-of type)
        (Con list-global (list type)))
      (define no-effects (Effects (list) (None)))

      (define (problem result)
        (match result
          ((Err (Cons feedback (Nil))) (Pair (::line (::loc feedback)) (::message feedback)))
          (_ result)))

      ;; Read off `resolve-type-name`: the arity is checked before any
      ;; argument, by the name as written.
      (define (test-applied)
        (expect (declared-type top (applied list-global (list (i64-at 2)) 1)) (Ok (list-of i64)))
        (expect (problem (declared-type top (expanded-Applied list-global "Seq" (list) (at 3))))
                (Pair 3 "wrong number of type arguments: Seq"))
        (expect (problem (declared-type top
                                        (applied list-global
                                                 (list (i64-at 4) (applied list-global (list) 5))
                                                 6)))
                (Pair 6 "wrong number of type arguments: List"))
        (expect (problem (declared-type top
                                        (applied (global lib "Pair")
                                                 (list (applied list-global (list) 7) (i64-at 8))
                                                 9)))
                (Pair 7 "wrong number of type arguments: List"))
        ;; A row's effects as a set; its tail as written.
        (expect (declared-type top
                               (expanded-Row
                                (expanded-Effects (list log io log) (Some (variable "e")))
                                loc))
                (Ok (Row (Effects (list log io) (Some (var "e"))))))
        (expect (declared-type top
                               (expanded-Callable (Impl)
                                                  (FnMutContract)
                                                  (expanded-Arrow (list (variable "a"))
                                                                  (i64-at 1)
                                                                  (expanded-Effects (list io)
                                                                                    (None)))
                                                  loc))
                (Ok (Callable (Impl)
                              (FnMutContract)
                              (Arrow (list (var "a")) i64 (Effects (list io) (None)))))))

      ;; An alias's arguments first, where the use is, even one its body
      ;; does not use; then its body, with the arguments in place, in a
      ;; scope with no requirement (alias-unused.sld, alias-order.sld and
      ;; alias-projection.sld under build/declare-probes/ are the old
      ;; compiler's refusals).
      (define (test-aliases)
        (let ((twice (lambda (argument)
                       (expanded-Aliased (global main "Twice")
                                         (list argument)
                                         (applied list-global
                                                  (list (applied list-global
                                                                 (list
                                                                  (expanded-AliasParameter 0 loc))
                                                                 2))
                                                  2)
                                         (at 3))))
              (ignore (lambda (argument)
                        (expanded-Aliased (global main "Ignore")
                                          (list argument)
                                          (i64-at 4)
                                          (at 5)))))
          (expect (declared-type top (twice (i64-at 1))) (Ok (list-of (list-of i64))))
          (expect (declared-type top (twice (twice (variable "a"))))
                  (Ok (list-of (list-of (list-of (list-of (var "a")))))))
          (expect (problem (declared-type top (ignore (applied list-global (list) 6))))
                  (Pair 6 "wrong number of type arguments: List"))
          (expect (problem (declared-type top
                                          (expanded-Aliased (global main "Bad")
                                                            (list (applied list-global (list) 7))
                                                            (applied list-global (list) 8)
                                                            (at 9))))
                  (Pair 7 "wrong number of type arguments: List"))
          ;; A parameter ending a row is the argument, kept as written.
          (expect (declared-type top
                                 (expanded-Aliased (global main "Io")
                                                   (list (expanded-Row
                                                          (expanded-Effects (list log) (None))
                                                          loc))
                                                   (expanded-Row (expanded-Effects
                                                                  (list io)
                                                                  (Some
                                                                   (expanded-AliasParameter 0 loc)))
                                                                 loc)
                                                   loc))
                  (Ok (Row (Effects (list io) (Some (Row (Effects (list log) (None))))))))
          (let ((in-scope (Scope known
                                 (list (ClassRequirement (ClassGlobal collect)
                                                         (list (var "a") (var "i") (var "k"))))))
                (item (expanded-Projection collect "Item" (list (variable "a")) (at 10))))
            (expect (declared-type in-scope item) (Ok (var "i")))
            (expect (problem (declared-type in-scope
                                            (expanded-Aliased (global main "Item")
                                                              (list (variable "a"))
                                                              (expanded-Projection collect
                                                                                   "Item"
                                                                                   (list
                                                                                    (expanded-AliasParameter
                                                                                     0
                                                                                     loc))
                                                                                   (at 11))
                                                              (at 12))))
                    (Pair 11 "associated projection needs a matching requires constraint")))))

      ;; Read off `resolve-projection`: the arguments first, then their
      ;; count, then the match.
      (define (test-projections)
        (let ((scope (Scope known
                            (list (ClassRequirement (ClassGlobal collect)
                                                    (list (var "b") (var "j") (var "l")))
                                  (ClassRequirement (ClassGlobal collect)
                                                    (list (var "a") (var "i") (var "k"))))))
              (key
               (lambda (arguments line) (expanded-Projection collect "Key" arguments (at line)))))
          (expect (declared-type scope (key (list (variable "b")) 1)) (Ok (var "l")))
          (expect (problem (declared-type scope (key (list (applied list-global (list) 2)) 3)))
                  (Pair 2 "wrong number of type arguments: List"))
          (expect (problem (declared-type scope (key (list) 4)))
                  (Pair 4 "associated projection gives each declared class parameter"))
          (expect (problem (declared-type scope (key (list (variable "c")) 5)))
                  (Pair 5 "associated projection needs a matching requires constraint"))
          (expect (problem (declared-type (Scope known
                                                 (append (::requirements scope)
                                                         (::requirements scope)))
                                          (key (list (variable "a")) 6)))
                  (Pair 6 "associated projection matches multiple requirements"))))

      (define (requirement class types equations line)
        (expanded-ClassRequirement class types equations (at line)))

      (define (equation name type)
        (expanded-Equation (Label name loc) type))

      (define (required-of names requirements)
        (let ((result (declared-requirements top names requirements)))
          (match result
            ((Ok required) (Pair (::variables required)
                                 (Pair (::requirements required) (::copied required))))
            (_ (problem result)))))

      ;; Read off `resolve-requirement` and `checked-constraint`: an
      ;; unwritten output is `$associated.N.name`, N the count of the
      ;; requirements with evidence before it, Copy not among them; each
      ;; such variable follows those before it; a later requirement sees an
      ;; earlier one's outputs.
      (define (test-requirements)
        (let ((collect-a (requirement (ClassGlobal collect) (list (variable "a")) (list) 1))
              (collect-b (requirement (ClassGlobal collect)
                                      (list (expanded-Projection collect
                                                                 "Item"
                                                                 (list (variable "a"))
                                                                 loc))
                                      (list (equation "Key" (i64-at 2)))
                                      3))
              (callable (expanded-CallableRequirement (FnContract)
                                                      (variable "f")
                                                      (arrow (list (variable "a")) (i64-at 4))
                                                      (at 5))))
          (expect (required-of (list "a" "f")
                               (list (expanded-CopyRequirement "a" loc)
                                     callable
                                     collect-a
                                     collect-b))
                  (Pair (list (Written "a")
                              (Written "f")
                              (Associated 1 "Item")
                              (Associated 1 "Key")
                              (Associated 2 "Item"))
                        (Pair (list (CallableRequirement (FnContract)
                                                         (var "f")
                                                         (Arrow (list (var "a")) i64 no-effects))
                                    (ClassRequirement (ClassGlobal collect)
                                                      (list (var "a")
                                                            (Var (Associated 1 "Item"))
                                                            (Var (Associated 1 "Key"))))
                                    (ClassRequirement (ClassGlobal collect)
                                                      (list (Var (Associated 1 "Item"))
                                                            (Var (Associated 2 "Item"))
                                                            i64)))
                              (list (Written "a")))))
          ;; A variable written twice is one once a requirement is
          ;; resolved, as the old compiler's `delete-duplicates` makes it.
          (expect (::first (required-of (list "a" "a") (list)))
                  (list (Written "a") (Written "a")))
          (expect (::first (required-of (list "a" "a") (list collect-a)))
                  (list (Written "a") (Associated 0 "Item") (Associated 0 "Key")))
          ;; The class's own types first; then each output's equation, in
          ;; the class's order; then the equations; then the count; then
          ;; the rows.
          (expect (required-of (list)
                               (list (requirement (ClassGlobal collect)
                                                  (list (applied list-global (list) 6))
                                                  (list
                                                   (equation "Size" (applied list-global (list) 7)))
                                                  8)))
                  (Pair 6 "wrong number of type arguments: List"))
          (expect (required-of (list)
                               (list (requirement (ClassGlobal collect)
                                                  (list (i64-at 1))
                                                  (list
                                                   (equation "Key" (applied list-global (list) 9))
                                                   (equation "Item"
                                                             (applied list-global (list) 10)))
                                                  11)))
                  (Pair 10 "wrong number of type arguments: List"))
          (expect (required-of (list)
                               (list (requirement (ClassGlobal collect)
                                                  (list)
                                                  (list (equation "Size"
                                                                  (applied list-global (list) 12)))
                                                  13)))
                  (Pair 13 "constraint has an unknown or repeated associated type equality"))
          (expect (required-of (list)
                               (list (requirement (ClassGlobal collect) (list) (list) 14)))
                  (Pair 14
                        "a constraint gives each of the class's parameters, as in (Collect c Item Key)"))
          (expect (required-of (list)
                               (list (requirement (ClassGlobal store)
                                                  (list (i64-at 1) (i64-at 1))
                                                  (list)
                                                  15)))
                  (Pair 15 "a constraint gives the class's row parameter e a row"))
          ;; A class of the library's own, before its declaration, is its
          ;; scanned shape: every parameter a type.
          (expect (required-of (list "a")
                               (list
                                (requirement (ClassGlobal show) (list (variable "a")) (list) 1)))
                  (Pair (list (Written "a") (Associated 0 "Out"))
                        (Pair (list (ClassRequirement (ClassGlobal show)
                                                      (list (var "a") (Var (Associated 0 "Out")))))
                              (list))))
          (expect (required-of (list)
                               (list
                                (requirement (FieldClass "count") (list (i64-at 1)) (list) 16)))
                  (Pair 16
                        "a constraint gives each of the class's parameters, as in (count R T)"))))

      ;; Read off `resolve-scheme` and `callable-signature-parameters`:
      ;; written variables, then outputs, then callable arguments, each
      ;; numbered by the count of variables before it.
      (define (test-schemes)
        (let ((callback (expanded-Callable (Impl) (FnContract) (arrow (list) (variable "a")) loc)))
          (expect (declared-scheme top
                                   (expanded-Scheme
                                    (list "a")
                                    (list (requirement (ClassGlobal collect)
                                                       (list (variable "a"))
                                                       (list)
                                                       1))
                                    (expanded-Callable (Dyn)
                                                       (FnContract)
                                                       (arrow (list callback
                                                                    (expanded-Projection collect
                                                                                         "Key"
                                                                                         (list
                                                                                          (variable
                                                                                           "a"))
                                                                                         loc))
                                                              (variable "a"))
                                                       loc)
                                    (at 2)))
                  (Ok (Scheme (list (Written "a")
                                    (Associated 0 "Item")
                                    (Associated 0 "Key")
                                    (CallableArgument 3))
                              (list (ClassRequirement (ClassGlobal collect)
                                                      (list (var "a")
                                                            (Var (Associated 0 "Item"))
                                                            (Var (Associated 0 "Key"))))
                                    (CallableRequirement (FnContract)
                                                         (Var (CallableArgument 3))
                                                         (Arrow (list) (var "a") no-effects)))
                              (list)
                              (Callable (Dyn)
                                        (FnContract)
                                        (Arrow (list (Var (CallableArgument 3))
                                                     (Var (Associated 0 "Key")))
                                               (var "a")
                                               no-effects)))))
          (expect (problem (declared-scheme top
                                            (expanded-Scheme (list)
                                                             (list)
                                                             (expanded-Code (arrow (list) callback)
                                                                            loc)
                                                             (at 3))))
                  (Pair 3
                        "a returned callable needs explicit dyn storage; impl is an argument or definition contract"))
          (expect (problem (declared-scheme top
                                            (expanded-Scheme (list)
                                                             (list)
                                                             (expanded-Code
                                                              (arrow (list (applied list-global
                                                                                    (list callback)
                                                                                    4))
                                                                     (i64-at 4))
                                                              loc)
                                                             (at 5))))
                  (Pair 5
                        "stored and returned callable types require explicit dyn; impl is a definition or argument contract"))
          ;; A projection's type is checked as the type it stands for.
          (expect (problem (declared-scheme top
                                            (expanded-Scheme
                                             (list "a")
                                             (list (requirement (ClassGlobal collect)
                                                                (list (variable "a"))
                                                                (list (equation "Item" callback))
                                                                1))
                                             (expanded-Code (arrow (list)
                                                                   (expanded-Projection collect
                                                                                        "Item"
                                                                                        (list
                                                                                         (variable
                                                                                          "a"))
                                                                                        loc))
                                                            loc)
                                             (at 6))))
                  (Pair 6
                        "a returned callable needs explicit dyn storage; impl is an argument or definition contract"))))))
   (else)))

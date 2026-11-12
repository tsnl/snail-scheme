;; A Dispatched expression as the old expander writes it, for the old
;; checker, which milestone A hands the program. Every node is the old
;; Expr the old expander writes for the form, at the same place, with the
;; type `unchecked`, which the checker replaces; a variable records no
;; instantiation yet.
;;
;; - A local is `name.number`, unique in the program, as the old
;;   expander's locals are: a library's locals are numbered after those of
;;   the libraries before it. The old checker names the type of a closure
;;   a `let` binds for its local, and such a type can reach a scheme that
;;   another library sees, so two locals of one name and number in two
;;   libraries would give two closures one type. The old `local-name`
;;   drops the text after the last dot, so a message names it as written.
;; - A path of one label is its field class's reader, `::label`; a longer
;;   one is a function of a parameter of its own, which reads each label
;;   in turn, numbered from where the library's numbers stop, as the old
;;   expander makes it. Each label's field class is declared in the old
;;   program, so the conversion hands on the labels its paths and its
;;   local signatures' requirements name.
;; - A `lambda` may capture, a `fn` may not; a function a top-level
;;   definition, a method or a default holds may not, since no local is
;;   around it.
;; - A local signature is its value annotated with the signature's type.
;; - A `case-id` is its TypeId annotated as an I32.
;; - A `with-instances` holds every set active where it is: its own, then
;;   those around it, innermost first, each once, as the old expander
;;   resolves each scope again. Those around an expression are the sets
;;   of the `with-instances` around it, then of the instance scopes
;;   around its top-level declaration, and, in a method of an instance of
;;   a named set, that set first.
(define-library (snail compiler adapter expressions)
  (export
   Converting
   with-labels
   top-level-expr
   old-expr
   active-sets
   expression-loc
   requirement-labels)
  (import
   (snail core base)
   (snail compiler source)
   (only (snail compiler expand language)
         Global
         Local
         Constant
         Integer
         Float
         Text
         Character
         ByteVector
         Boolean
         UnitValue
         FieldClass)
   (only (snail compiler declare language)
         Expr
         Literal
         LocalRef
         TopRef
         Path
         PathApply
         Lambda
         ClosedLambda
         Call
         If
         Seq
         Let
         Match
         Handle
         WithInstances
         Ann
         Convert
         TryConvert
         TypeTest
         CaseId
         Clause
         Implementation
         Pattern
         Wild
         Bind
         Equals
         Destructure
         Type
         Con
         Scheme
         Requirement
         ClassRequirement)
   (only (snail compiler declare equality) same-global?)
   (only (snail compiler declare forms) forms-library)
   (only (snail compiler adapter declaration) old-name old-value-name old-type)
   (only (snail compiler adapter source) loc->old datum->old)
   (prefix (only (snail shell compiler read) Datum DInt DFloat DString DChar DBytes DBool DUnit)
           old:)
   (prefix (only (snail shell compiler core)
                 Expr
                 Term
                 Lit
                 Var
                 Lambda
                 App
                 If
                 Let
                 Seq
                 Match
                 ScopedInstances
                 Ann
                 Handle
                 Convert
                 TryConvert
                 TypeTest
                 Clause
                 Pattern
                 PWild
                 PVar
                 PLit
                 PCon
                 field-class-name
                 unchecked)
           old:))
  (begin

    ;; ---- Converting ----

    ;; What converting a library's expressions hands on, from one to the
    ;; next: the number the library's locals are numbered from in the
    ;; program, the first number in the program no local has, and the
    ;; labels the expressions name, newest first, once or more each.
    (struct Converting
      ((base I64)
       (next I64)
       (labels (List String))))

    ;; `(converting-let* ((name state step) ...) body ...)` evaluates each
    ;; step in order, with the scope of `let*`. A step takes the state and
    ;; returns its value with the new state, as a Pair: each binding names
    ;; the value and the new state, which the steps after it and the body
    ;; see. Both names are the use's, the only ones stage 0's `match` binds.
    (define-syntax converting-let*
      (syntax-rules ()
        ((_ () body ...) (begin body ...))
        ((_ ((name state step) more ...) body ...)
         (match step
           ((Pair name state) (converting-let* (more ...) body ...))))))

    (: with-labels (impl (Fn Converting (List String) -> Converting)))
    (define (with-labels state labels)
      (Converting-labels-set state (append labels (::labels state))))

    ;; ---- Top-level values ----

    ;; The value a top-level definition, a method or a default holds, with
    ;; `around` active: a function there may not capture.
    (: top-level-expr
       (impl (Fn Converting (List Global) Expr -> (Pair old:Expr Converting))))
    (define (top-level-expr state around value)
      (converting-let* ((converted state (old-expr state around value)))
        (Pair (match (::term converted)
                ((old:Lambda parameters body _)
                 (old:Expr (old:Lambda parameters body #f) (::type converted) (::loc converted)))
                (_ converted))
              state)))

    ;; The sets a `with-instances` of `sets` makes active, with `around`
    ;; active outside it: its own, then those around, each once.
    (: active-sets (impl (Fn (List Global) (List Global) -> (List Global))))
    (define (active-sets sets around)
      (delete-duplicates same-global? (append sets around)))

    ;; ---- Expressions ----

    (: at (impl (Fn old:Term Loc -> old:Expr)))
    (define (at term loc)
      (old:Expr term old:unchecked (loc->old loc)))

    (: reference (impl (Fn String Loc -> old:Expr)))
    (define (reference name loc)
      (at (old:Var name (Nil) (Nil)) loc))

    (: old-local-name (impl (Fn Converting Local -> String)))
    (define (old-local-name state local)
      (local-text (::name local) (+ (::base state) (::number local))))

    (: local-text (impl (Fn String I64 -> String)))
    (define (local-text name number)
      (string-append name "." (i64->string number)))

    ;; `expr`, with the sets `around` active where it is.
    (: old-expr (impl (Fn Converting (List Global) Expr -> (Pair old:Expr Converting))))
    (define (old-expr state around expr)
      (match expr
        ((Literal constant loc) (Pair (at (old:Lit (old-constant constant)) loc) state))
        ((LocalRef local loc) (Pair (reference (old-local-name state local) loc) state))
        ((TopRef value loc) (Pair (reference (old-value-name value) loc) state))
        ((Path labels loc) (path (with-labels state labels) labels loc))
        ((PathApply labels record loc)
         (converting-let* ((value state (old-expr state around record)))
           (Pair (applied-path labels value loc) (with-labels state labels))))
        ((Lambda parameters body loc) (old-lambda state around parameters body #t loc))
        ((ClosedLambda parameters body loc) (old-lambda state around parameters body #f loc))
        ((Call callee arguments loc)
         (converting-let* ((callee state (old-expr state around callee))
                           (arguments state (old-exprs state around arguments)))
           (Pair (at (old:App callee arguments) loc) state)))
        ((If test consequent alternative loc)
         (converting-let* ((test state (old-expr state around test))
                           (consequent state (old-expr state around consequent))
                           (alternative state (old-expr state around alternative)))
           (Pair (at (old:If test consequent alternative) loc) state)))
        ((Seq first rest loc)
         (converting-let* ((first state (old-expr state around first))
                           (rest state (old-expr state around rest)))
           (Pair (at (old:Seq first rest) loc) state)))
        ((Let local signature value body loc)
         (converting-let* ((value state (old-expr state around value))
                           (body state (old-expr state around body)))
           (Pair (at (old:Let (old-local-name state local) (signed value signature) body) loc)
                 (with-labels state (signature-labels signature)))))
        ((Match scrutinee clauses loc)
         (converting-let* ((scrutinee state (old-expr state around scrutinee))
                           (clauses state (old-clauses state around clauses)))
           (Pair (at (old:Match scrutinee clauses) loc) state)))
        ((Handle effect implementations body loc)
         (old-handle state around effect implementations body loc))
        ((WithInstances sets body loc)
         (let ((active (active-sets sets around)))
           (converting-let* ((body state (old-expr state active body)))
             (Pair (at (old:ScopedInstances (map old-name active) body) loc) state))))
        ((Ann value type loc)
         (converting-let* ((value state (old-expr state around value)))
           (Pair (at (old:Ann value (old-type type)) loc) state)))
        ((Convert value type loc)
         (converting-let* ((value state (old-expr state around value)))
           (Pair (at (old:Convert value (old-type type)) loc) state)))
        ((TryConvert value type loc)
         (converting-let* ((value state (old-expr state around value)))
           (Pair (at (old:TryConvert value (old-type type)) loc) state)))
        ((TypeTest value type loc)
         (converting-let* ((value state (old-expr state around value)))
           (Pair (at (old:TypeTest value (old-type type)) loc) state)))
        ((CaseId _ id loc)
         (Pair (at (old:Ann (at (old:Lit (old:DInt id)) loc)
                            (old-type (Con (Global forms-library "I32" 0) (Nil))))
                   loc)
               state))))

    ;; Each of `exprs` in turn, threading the state.
    (: old-exprs
       (impl (Fn Converting (List Global) (List Expr) -> (Pair (List old:Expr) Converting))))
    (define (old-exprs state around exprs)
      (let loop ((state state)
                 (exprs exprs)
                 (converted (Nil)))
        (match exprs
          ((Nil) (Pair (reverse converted) state))
          ((Cons expr rest)
           (converting-let* ((value state (old-expr state around expr)))
             (loop state rest (Cons value converted)))))))

    (: old-constant (impl (Fn Constant -> old:Datum)))
    (define (old-constant constant)
      (match constant
        ((Integer value) (old:DInt value))
        ((Float text) (old:DFloat text))
        ((Text text) (old:DString text))
        ((Character char) (old:DChar char))
        ((ByteVector bytes) (old:DBytes bytes))
        ((Boolean value) (old:DBool value))
        ((UnitValue) (old:DUnit))))

    (: old-lambda
       (impl
        (Fn Converting (List Global) (List Local) Expr Bool Loc -> (Pair old:Expr Converting))))
    (define (old-lambda state around parameters body captures? loc)
      (converting-let* ((body state (old-expr state around body)))
        (Pair (at (old:Lambda (map (lambda (local) (old-local-name state local)) parameters)
                              body
                              captures?)
                  loc)
              state)))

    ;; A local definition's value, annotated with its signature's type at
    ;; the value's place.
    (: signed (impl (Fn old:Expr (Option Scheme) -> old:Expr)))
    (define (signed value signature)
      (match signature
        ((Some scheme)
         (old:Expr (old:Ann value (old-type (::type scheme))) old:unchecked (::loc value)))
        ((None) value)))

    (: signature-labels (impl (Fn (Option Scheme) -> (List String))))
    (define (signature-labels signature)
      (match signature
        ((Some scheme) (requirement-labels (::requirements scheme)))
        ((None) (Nil))))

    ;; The labels of the field classes `requirements` name.
    (: requirement-labels (impl (Fn (List Requirement) -> (List String))))
    (define (requirement-labels requirements)
      (concatenate (map (lambda (requirement)
                          (match requirement
                            ((ClassRequirement (FieldClass label) _) (list label))
                            (_ (Nil))))
                        requirements)))

    (: old-handle
       (impl (Fn Converting
                 (List Global)
                 Global
                 (List Implementation)
                 Expr
                 Loc
                 ->
                 (Pair old:Expr Converting))))
    (define (old-handle state around effect implementations body loc)
      (converting-let* ((values state (old-exprs state around (map ::value implementations)))
                        (body state (old-expr state around body)))
        (Pair (at (old:Handle (old-name effect)
                              (map (lambda (pair)
                                     (Pair (old-name (::operation (::first pair))) (::second pair)))
                                   (zip implementations values))
                              body)
                  loc)
              state)))

    ;; ---- Paths ----

    ;; A path of one label is its reader; of more, a function of its own
    ;; parameter, which takes the next number.
    (: path (impl (Fn Converting (List String) Loc -> (Pair old:Expr Converting))))
    (define (path state labels loc)
      (match labels
        ((Cons label (Nil)) (Pair (field-reader label loc) state))
        (_ (let ((parameter (local-text "path" (::next state))))
             (Pair (at (old:Lambda (list parameter)
                                   (applied-path labels (reference parameter loc) loc)
                                   #t)
                       loc)
                   (Converting-next-set state (+ (::next state) 1)))))))

    ;; `value` read by each label in turn.
    (: applied-path (impl (Fn (List String) old:Expr Loc -> old:Expr)))
    (define (applied-path labels value loc)
      (fold-left (lambda (value label) (at (old:App (field-reader label loc) (list value)) loc))
                 value
                 labels))

    (: field-reader (impl (Fn String Loc -> old:Expr)))
    (define (field-reader label loc)
      (reference (old:field-class-name label) loc))

    ;; ---- Patterns ----

    (: old-clauses
       (impl (Fn Converting (List Global) (List Clause) -> (Pair (List old:Clause) Converting))))
    (define (old-clauses state around clauses)
      (let loop ((state state)
                 (clauses clauses)
                 (converted (Nil)))
        (match clauses
          ((Nil) (Pair (reverse converted) state))
          ((Cons clause rest)
           (converting-let* ((body state (old-expr state around (::body clause))))
             (loop state
                   rest
                   (Cons (old:Clause (old-pattern state (::pattern clause)) body) converted)))))))

    ;; A pattern has no place in the old language.
    (: old-pattern (impl (Fn Converting Pattern -> old:Pattern)))
    (define (old-pattern state pattern)
      (match pattern
        ((Wild _) (old:PWild old:unchecked))
        ((Bind local _) (old:PVar (old-local-name state local) old:unchecked))
        ((Equals datum _) (old:PLit (datum->old datum) old:unchecked))
        ((Destructure constructor arguments _)
         (old:PCon (old-value-name constructor)
                   (map (lambda (argument) (old-pattern state argument)) arguments)
                   old:unchecked))))

    ;; ---- Places ----

    (: expression-loc (impl (Fn Expr -> Loc)))
    (define (expression-loc expr)
      (match expr
        ((Literal _ loc) loc)
        ((LocalRef _ loc) loc)
        ((TopRef _ loc) loc)
        ((Path _ loc) loc)
        ((PathApply _ _ loc) loc)
        ((Lambda _ _ loc) loc)
        ((ClosedLambda _ _ loc) loc)
        ((Call _ _ loc) loc)
        ((If _ _ _ loc) loc)
        ((Seq _ _ loc) loc)
        ((Let _ _ _ _ loc) loc)
        ((Match _ _ loc) loc)
        ((Handle _ _ _ loc) loc)
        ((WithInstances _ _ loc) loc)
        ((Ann _ _ loc) loc)
        ((Convert _ _ loc) loc)
        ((TryConvert _ _ loc) loc)
        ((TypeTest _ _ loc) loc)
        ((CaseId _ _ loc) loc)))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-expressions)
    (import
     (only (snail compiler expand language) TopGlobal FieldFunction Accessor)
     (prefix (only (snail compiler read language) Integer) syntax-)
     (prefix (only (snail shell compiler read) Loc) old:)
     (prefix (only (snail shell compiler core) TCon) old:)
     (snail stage0 testing))
    (begin
      (define (test-expressions)
        (test-forms)
        (test-numbers)
        (test-paths)
        (test-scopes)
        (test-top-level))

      (define loc (Loc "t.sld" 3 5))
      (define inner (Loc "t.sld" 3 9))
      (define old-loc (old:Loc "t.sld" 3 5))
      (define old-inner (old:Loc "t.sld" 3 9))
      (define main (list "main"))
      (define state (Converting 0 40 (list)))

      (define (old at-loc term)
        (old:Expr term old:unchecked at-loc))

      (define (converted expr)
        (::first (old-expr state (list) expr)))

      (define i64 (Con (Global forms-library "I64" 0) (list)))

      ;; Each form is the old expander's, at its place.
      (define (test-forms)
        (let ((x (Local "x" 3))
              (point (Global main "Point" 0))
              (log (Global main "log" 0))
              (write (Global main "write" 2)))
          (expect (converted (Literal (Integer 7) loc)) (old old-loc (old:Lit (old:DInt 7))))
          (expect (converted (Literal (UnitValue) loc)) (old old-loc (old:Lit (old:DUnit))))
          (expect (converted (LocalRef x loc)) (old old-loc (old:Var "x.3" (list) (list))))
          (expect (converted (TopRef (FieldFunction point "x" (Accessor)) loc))
                  (old old-loc (old:Var "main:Point-x" (list) (list))))
          (expect (converted (Call (TopRef (TopGlobal write) inner) (list (LocalRef x inner)) loc))
                  (old old-loc
                       (old:App (old old-inner (old:Var "main:write%2" (list) (list)))
                                (list (old old-inner (old:Var "x.3" (list) (list)))))))
          ;; A signature annotates the value, at the value's place.
          (expect (converted (Let x
                                  (Some (Scheme (list) (list) (list) i64))
                                  (Literal (Integer 1) inner)
                                  (LocalRef x inner)
                                  loc))
                  (old old-loc
                       (old:Let "x.3"
                                (old old-inner
                                     (old:Ann (old old-inner (old:Lit (old:DInt 1)))
                                              (old:TCon "I64" (list))))
                                (old old-inner (old:Var "x.3" (list) (list))))))
          (expect (converted (CaseId point -12 loc))
                  (old old-loc
                       (old:Ann (old old-loc (old:Lit (old:DInt -12))) (old:TCon "I32" (list)))))
          (expect (converted (Match (LocalRef x inner)
                                    (list (Clause (Destructure (TopGlobal point)
                                                               (list (Bind (Local "y" 4) inner)
                                                                     (Wild inner))
                                                               inner)
                                                  (Literal (Boolean #t) inner)
                                                  inner)
                                          (Clause (Equals (syntax-Integer 2) inner)
                                                  (Literal (Boolean #f) inner)
                                                  inner))
                                    loc))
                  (old old-loc
                       (old:Match (old old-inner (old:Var "x.3" (list) (list)))
                                  (list (old:Clause (old:PCon "main:Point"
                                                              (list (old:PVar "y.4" old:unchecked)
                                                                    (old:PWild old:unchecked))
                                                              old:unchecked)
                                                    (old old-inner (old:Lit (old:DBool #t))))
                                        (old:Clause (old:PLit (old:DInt 2) old:unchecked)
                                                    (old old-inner (old:Lit (old:DBool #f))))))))
          (expect (converted (Handle log
                                     (list (Implementation write (LocalRef x inner) inner))
                                     (Literal (Integer 1) inner)
                                     loc))
                  (old old-loc
                       (old:Handle "main:log"
                                   (list (Pair "main:write%2"
                                               (old old-inner (old:Var "x.3" (list) (list)))))
                                   (old old-inner (old:Lit (old:DInt 1))))))
          (expect (converted (Lambda (list x) (LocalRef x inner) loc))
                  (old old-loc
                       (old:Lambda (list "x.3") (old old-inner (old:Var "x.3" (list) (list))) #t)))
          (expect (converted (ClosedLambda (list x) (LocalRef x inner) loc))
                  (old old-loc
                       (old:Lambda (list "x.3")
                                   (old old-inner (old:Var "x.3" (list) (list)))
                                   #f)))))

      ;; A library's locals are numbered after the locals of the libraries
      ;; before it, and a path's parameter takes the next number free in
      ;; the program.
      (define (test-numbers)
        (let ((later (Converting 100 140 (list))))
          (expect (::first (old-expr later (list) (LocalRef (Local "x" 3) loc)))
                  (old old-loc (old:Var "x.103" (list) (list))))
          (expect (old-expr later (list) (Path (list "a" "b") loc))
                  (Pair (old old-loc
                             (old:Lambda
                              (list "path.140")
                              (old old-loc
                                   (old:App (old old-loc (old:Var "::b" (list) (list)))
                                            (list (old old-loc
                                                       (old:App (old old-loc
                                                                     (old:Var "::a" (list) (list)))
                                                                (list (old old-loc
                                                                           (old:Var "path.140"
                                                                                    (list)
                                                                                    (list)))))))))
                              #t))
                        (Converting 100 141 (list "a" "b"))))))

      ;; A path of one label reads it; of more, it is a function of a
      ;; parameter numbered where the library's numbers stop. Each label
      ;; is handed on, for its field class.
      (define (test-paths)
        (let ((reader (lambda (label) (old old-loc (old:Var label (list) (list))))))
          (expect (old-expr state (list) (Path (list "x") loc))
                  (Pair (reader "::x") (Converting 0 40 (list "x"))))
          (expect (old-expr state (list) (Path (list "a" "b") loc))
                  (Pair (old old-loc
                             (old:Lambda (list "path.40")
                                         (old old-loc
                                              (old:App (reader "::b")
                                                       (list (old old-loc
                                                                  (old:App (reader "::a")
                                                                           (list
                                                                            (reader "path.40")))))))
                                         #t))
                        (Converting 0 41 (list "a" "b"))))
          (expect (old-expr state (list) (PathApply (list "a") (LocalRef (Local "r" 2) inner) loc))
                  (Pair (old old-loc
                             (old:App (reader "::a")
                                      (list (old old-inner (old:Var "r.2" (list) (list))))))
                        (Converting 0 40 (list "a"))))
          (expect (::second (old-expr state
                                      (list)
                                      (Let (Local "f" 1)
                                           (Some (Scheme (list)
                                                         (list
                                                          (ClassRequirement (FieldClass "count")
                                                                            (list i64 i64)))
                                                         (list)
                                                         i64))
                                           (Literal (Integer 1) inner)
                                           (Literal (Integer 2) inner)
                                           loc)))
                  (Converting 0 40 (list "count")))))

      ;; A `with-instances` holds its own sets, then those around, each
      ;; once; its body is converted with them all around.
      (define (test-scopes)
        (let ((a (Global main "A" 0))
              (b (Global main "B" 0))
              (c (Global main "C" 0)))
          (expect (active-sets (list a b a) (list c a)) (list a b c))
          (expect (converted (WithInstances (list a)
                                            (WithInstances (list b)
                                                           (Literal (Integer 1) inner)
                                                           inner)
                                            loc))
                  (old old-loc
                       (old:ScopedInstances
                        (list "main:A")
                        (old old-inner
                             (old:ScopedInstances (list "main:B" "main:A")
                                                  (old old-inner (old:Lit (old:DInt 1))))))))
          (expect (::first (old-expr state
                                     (list c)
                                     (WithInstances (list a) (Literal (Integer 1) inner) loc)))
                  (old old-loc
                       (old:ScopedInstances (list "main:A" "main:C")
                                            (old old-inner (old:Lit (old:DInt 1))))))))

      ;; A function a top-level declaration holds may not capture.
      (define (test-top-level)
        (let ((x (Local "x" 3)))
          (expect (::first (top-level-expr state (list) (Lambda (list x) (LocalRef x inner) loc)))
                  (old old-loc
                       (old:Lambda (list "x.3") (old old-inner (old:Var "x.3" (list) (list))) #f)))
          (expect (::first (top-level-expr state (list) (Literal (Integer 1) loc)))
                  (old old-loc (old:Lit (old:DInt 1))))))))
   (else)))

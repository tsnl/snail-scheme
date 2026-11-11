;; Types: type syntax becomes a TypeExpr, and a signature's syntax a
;; Scheme, with every name in them resolved. A name in type position is a
;; declared or builtin type, a class's associated output, a type variable a
;; binder in scope names, or an alias, which is expanded where it is used:
;; its arguments in the use's scope, then its body in the top level of the
;; library defining it, with each parameter standing for its argument, as
;; a macro's template stands for its use. Types expand no macros.
;;
;; What needs a declaration's content is left to `declare`: how many
;; arguments a type takes, what a class's members and outputs are, which
;; requirement a projection reads, and the rules callable types obey. What
;; is checked here needs only the syntax and what names mean, in the old
;; expander's order: each part of a type is expanded before a problem
;; after it is reported.
(define-library (snail compiler expand types)
  (export
   expand-type
   expand-scheme
   expand-requirements
   with-variables)
  (import
   (snail core base)
   (snail compiler source)
   (only (snail compiler outline language) LibraryName)
   (snail compiler expand language)
   (snail compiler expand marked)
   (snail compiler expand offer)
   (snail compiler expand forms)
   (snail compiler expand scopes)
   (snail compiler expand paths)
   (snail compiler expand type-shapes))
  (begin

    ;; ---- Typing ----

    ;; Where a type is expanded: the scopes and environment its names
    ;; resolve in, and the aliases whose bodies are being expanded,
    ;; innermost first, so an alias that reaches itself is refused.
    (struct Typing
      ((scopes Scopes)
       (env Env)
       (aliases (List Global))))

    (: expand-type (impl (Fn Scopes Env Marked -> (Result TypeExpr (List Feedback)))))
    (define (expand-type scopes env syntax)
      (type-of (Typing scopes env (Nil)) syntax))

    (: type-of (impl (Fn Typing Marked -> (Result TypeExpr (List Feedback)))))
    (define (type-of typing syntax)
      (match (type-shape syntax)
        ((NamedType identifier arguments loc) (named-type typing identifier arguments loc))
        ((CallableType former contract loc) (callable-type typing former contract loc))
        ((CodeType items loc)
         (result-let* ((arrow (arrow-of typing items loc)))
           (Ok (Code arrow loc))))
        ((RowType labels loc)
         (result-let* ((effects (effects-of typing labels loc)))
           (Ok (Row effects loc))))
        ((MalformedType loc message) (fail loc message))))

    (: types-of (impl (Fn Typing (List Marked) -> (Result (List TypeExpr) (List Feedback)))))
    (define (types-of typing items)
      (map-results (lambda (item) (type-of typing item)) items))

    ;; ---- Names ----

    ;; What a name means decides the type; arguments are expanded after
    ;; that, but not for a type variable, which takes none.
    (: named-type
       (impl (Fn Typing Identifier (List Marked) Loc -> (Result TypeExpr (List Feedback)))))
    (define (named-type typing identifier arguments loc)
      (match (resolve (::scopes typing) (::env typing) identifier)
        ((BoundAtTop (TypeName global _))
         (result-let* ((types (types-of typing arguments)))
           (Ok (Applied global (::name identifier) types loc))))
        ((BoundAtTop (Associated class member))
         (result-let* ((types (types-of typing arguments)))
           (Ok (Projection class member types loc))))
        ((BoundLocally (TypeVariable name) _) (unapplied (Variable name loc) arguments loc))
        ((BoundLocally (TypeArgument index) _) (unapplied (AliasParameter index loc) arguments loc))
        ((BoundAtTop (TypeAlias global parameters body scope))
         (alias-type typing identifier (AliasUse global parameters body scope) arguments loc))
        (_ (fail loc (string-append "not a type: " (::name identifier))))))

    (: unapplied (impl (Fn TypeExpr (List Marked) Loc -> (Result TypeExpr (List Feedback)))))
    (define (unapplied type arguments loc)
      (if (null? arguments) (Ok type) (fail loc "a type variable takes no arguments")))

    ;; ---- Aliases ----

    (struct AliasUse
      ((global Global)
       (parameters (List Identifier))
       (body Marked)
       (scope LibraryName)))

    ;; An alias's use is its arguments, expanded where the use is, and its
    ;; body, expanded at the top level of the alias's library with each
    ;; parameter bound to the argument at its index.
    (: alias-type
       (impl
        (Fn Typing Identifier AliasUse (List Marked) Loc -> (Result TypeExpr (List Feedback)))))
    (define (alias-type typing identifier alias arguments loc)
      (cond ((not (= (length (::parameters alias)) (length arguments)))
             (fail loc (string-append "wrong number of alias arguments: " (::name identifier))))
            ((any? (lambda (other) (same-global? other (::global alias))) (::aliases typing))
             (fail loc (string-append "type alias refers to itself: " (::name identifier))))
            (else
             (result-let* ((types (types-of typing arguments))
                           (body (type-of (Typing (::scopes typing)
                                                  (Env (alias-frames (::parameters alias))
                                                       (::scope alias))
                                                  (Cons (::global alias) (::aliases typing)))
                                          (::body alias))))
               (Ok (Aliased (::global alias) types body loc))))))

    ;; Each parameter bound to its index, the last innermost.
    (: alias-frames (impl (Fn (List Identifier) -> (List Frame))))
    (define (alias-frames parameters)
      (let loop ((parameters parameters)
                 (index 0)
                 (frames (Nil)))
        (match parameters
          ((Nil) frames)
          ((Cons parameter rest)
           (loop rest (+ index 1) (Cons (Frame parameter (TypeArgument index)) frames))))))

    ;; ---- Callables ----

    (: callable-type
       (impl (Fn Typing Former Marked Loc -> (Result TypeExpr (List Feedback)))))
    (define (callable-type typing former contract loc)
      (match (contract-shape contract)
        ((WellFormedContract kind items)
         (result-let* ((arrow (arrow-of typing items loc)))
           (Ok (Callable former kind arrow loc))))
        ((MalformedContract message) (fail loc message))))

    ;; The parameters, then the result, then the effects; a malformed
    ;; arrow's parameters before its problem are expanded first.
    (: arrow-of (impl (Fn Typing (List Marked) Loc -> (Result Arrow (List Feedback)))))
    (define (arrow-of typing items loc)
      (match (arrow-shape items)
        ((WellFormedArrow parameters result effects)
         (result-let* ((parameter-types (types-of typing parameters))
                       (result-type (type-of typing result))
                       (row (effects-after typing effects loc)))
           (Ok (Arrow parameter-types result-type row))))
        ((MalformedArrow parameters message)
         (result-let* ((parameter-types (types-of typing parameters)))
           (fail loc message)))))

    (: effects-after
       (impl (Fn Typing (Option (List Marked)) Loc -> (Result Effects (List Feedback)))))
    (define (effects-after typing labels loc)
      (match labels
        ((Some written) (effects-of typing written loc))
        ((None) (Ok (Effects (Nil) (None))))))

    ;; ---- Rows ----

    ;; Effects in the order written, and a type variable or an alias's
    ;; parameter last.
    (: effects-of (impl (Fn Typing (List Marked) Loc -> (Result Effects (List Feedback)))))
    (define (effects-of typing items loc)
      (let loop ((items items)
                 (labels (Nil)))
        (match items
          ((Nil) (Ok (Effects (reverse labels) (None))))
          ((Cons (Ident identifier item-loc) rest)
           (match (resolve (::scopes typing) (::env typing) identifier)
             ((BoundAtTop (EffectName global)) (loop rest (Cons global labels)))
             ((BoundLocally (TypeVariable name) _)
              (row-tail (reverse labels) (Variable name item-loc) rest loc))
             ((BoundLocally (TypeArgument index) _)
              (row-tail (reverse labels) (AliasParameter index item-loc) rest loc))
             (_ (fail item-loc (string-append "not an effect: " (::name identifier))))))
          ((Cons item _) (fail (marked-loc item) "expected an effect label")))))

    (: row-tail
       (impl (Fn (List Global) TypeExpr (List Marked) Loc -> (Result Effects (List Feedback)))))
    (define (row-tail labels tail rest loc)
      (if (null? rest)
          (Ok (Effects labels (Some tail)))
          (fail loc "a row variable must come last")))

    ;; ---- Schemes ----

    ;; A scheme binds its variables over its requirements and its type.
    ;; Its requirements are expanded before the rest is found to be one
    ;; type, as the old expander expands them.
    (: expand-scheme (impl (Fn Scopes Env Marked -> (Result Scheme (List Feedback)))))
    (define (expand-scheme scopes env syntax)
      (match (scheme-shape syntax)
        ((Unquantified type)
         (result-let* ((expanded (expand-type scopes env type)))
           (Ok (Scheme (Nil) (Nil) expanded (marked-loc syntax)))))
        ((MalformedScheme loc message) (fail loc message))
        ((Quantified variables requirements type loc)
         (let ((typing (Typing scopes (with-variables env variables) (Nil)))
               (names (map ::name variables)))
           (result-let* ((expanded (map-results (lambda (requirement)
                                                  (requirement-of typing names requirement))
                                                requirements))
                         (body (quantified-type typing type loc)))
             (Ok (Scheme names expanded body loc)))))))

    (: quantified-type
       (impl (Fn Typing (Result Marked String) Loc -> (Result TypeExpr (List Feedback)))))
    (define (quantified-type typing type loc)
      (match type
        ((Ok written) (type-of typing written))
        ((Err message) (fail loc message))))

    ;; Requirements over the variables `names`, which `env` binds, as an
    ;; instance's head writes them.
    (: expand-requirements
       (impl
        (Fn Scopes Env (List String) (List Marked) -> (Result (List Requirement) (List Feedback)))))
    (define (expand-requirements scopes env names requirements)
      (let ((typing (Typing scopes env (Nil))))
        (map-results (lambda (requirement) (requirement-of typing names requirement))
                     requirements)))

    ;; `env` with each variable bound, the last innermost.
    (: with-variables (impl (Fn Env (List Identifier) -> Env)))
    (define (with-variables env variables)
      (Env (fold-left (lambda (frames variable)
                        (Cons (Frame variable (TypeVariable (::name variable))) frames))
                      (::frames env)
                      variables)
           (::library env)))

    ;; ---- Requirements ----

    ;; `(Copy variable)` names one of the scheme's variables. A class is a
    ;; declared class, one of the callable classes, whose requirement is a
    ;; receiver and an arrow, or the field class `::label`.
    (: requirement-of
       (impl (Fn Typing (List String) Marked -> (Result Requirement (List Feedback)))))
    (define (requirement-of typing names syntax)
      (match (requirement-shape syntax)
        ((CopyOf name loc)
         (if (member? name names)
             (Ok (CopyRequirement name loc))
             (fail loc (string-append "Copy names a quantified type variable, not " name))))
        ((ClassApplied class class-loc arguments loc)
         (class-requirement typing class class-loc arguments loc))
        ((MalformedRequirement loc message) (fail loc message))))

    (: class-requirement
       (impl (Fn Typing Identifier Loc (List Marked) Loc -> (Result Requirement (List Feedback)))))
    (define (class-requirement typing class class-loc arguments loc)
      (match (resolve (::scopes typing) (::env typing) class)
        ((BoundAtTop (ClassName global))
         (match (callable-contract global)
           ((Some contract) (callable-requirement typing contract arguments loc))
           ((None) (applied-class typing (ClassGlobal global) arguments loc))))
        (_
         (match (field-path (::name class))
           ((NotAPath) (fail loc "expected a typeclass constraint"))
           ((PathLabels (Cons label (Nil))) (applied-class typing (FieldClass label) arguments loc))
           ((PathLabels _)
            (fail class-loc (string-append "a field class names one label, not " (::name class))))
           ((EmptyLabel message) (fail class-loc message))))))

    (: callable-requirement
       (impl (Fn Typing Contract (List Marked) Loc -> (Result Requirement (List Feedback)))))
    (define (callable-requirement typing contract arguments loc)
      (match arguments
        ((Cons receiver signature)
         (result-let* ((receiver-type (type-of typing receiver))
                       (arrow (arrow-of typing signature loc)))
           (Ok (CallableRequirement contract receiver-type arrow loc))))
        ((Nil) (fail loc "a callable requirement names its receiver type before its arguments"))))

    ;; The class's types, then its equations' shapes, then their types.
    ;; The old expander expands an equation's type only for an output of
    ;; the class, in the class's order, which `declare` knows; here each is
    ;; expanded as it is written.
    (: applied-class
       (impl (Fn Typing ClassRef (List Marked) Loc -> (Result Requirement (List Feedback)))))
    (define (applied-class typing class arguments loc)
      (let ((parts (class-arguments arguments)))
        (result-let* ((types (types-of typing (::types parts)))
                      (forms (map-results equation-shape (::equations parts)))
                      (equations (map-results (lambda (form) (equation-of typing form)) forms)))
          (Ok (ClassRequirement class types equations loc)))))

    (: equation-shape (impl (Fn Marked -> (Result EquationForm (List Feedback)))))
    (define (equation-shape syntax)
      (match (equation-form syntax)
        ((Ok form) (Ok form))
        ((Err message) (fail (marked-loc syntax) message))))

    (: equation-of (impl (Fn Typing EquationForm -> (Result Equation (List Feedback)))))
    (define (equation-of typing form)
      (result-let* ((type (type-of typing (::type form))))
        (Ok (Equation (Label (::name form) (::name-loc form)) type))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-types)
    (import
     (only (scheme base) pair? symbol? symbol->string string? exact-integer? boolean?)
     (snail core table)
     (prefix (snail compiler read language) syntax-)
     (snail stage0 testing))
    (begin
      (define (test-types)
        (test-names)
        (test-variables)
        (test-aliases)
        (test-callables)
        (test-rows)
        (test-schemes)
        (test-requirements))

      ;; ---- Helpers ----

      (define loc (Loc "t.sld" 1 1))

      (define (at line)
        (Loc "t.sld" line 1))

      (define main (list "main"))
      (define lib (list "lib"))
      (define base (list "snail" "core" "base"))

      (define (marked datum)
        (marked-at loc datum))

      (define (marked-at here datum)
        (cond ((or (null? datum) (pair? datum))
               (Form (map (lambda (item) (marked-at here item)) datum) here))
              ((symbol? datum) (Ident (Identifier (symbol->string datum) (Nil)) here))
              ((string? datum) (Atom (syntax-Text datum) here))
              ((exact-integer? datum) (Atom (syntax-Integer datum) here))
              (else (panic "no syntax for this datum"))))

      (define (plain name)
        (Identifier name (Nil)))

      (define (global library name)
        (Global library name 0))

      (define (table-of pairs)
        (fold-left (lambda (table pair)
                     (table-set table
                                (::first pair)
                                (list (Binding (plain (::first pair)) (::second pair)))))
                   empty-table
                   pairs))

      (define (i64 here)
        (Applied (Global forms-library "I64" 0) "I64" (list) here))

      ;; (main) defines List, Show, Fresh, the aliases Twice, Ignore, which
      ;; uses no parameter, and Io, whose parameter ends a row, and an
      ;; effect io, and imports Fn and Show.Output; (lib) defines the alias
      ;; Box over its own type Cell and the alias Loop, which uses itself.
      (define loop
        (TypeAlias (global lib "Loop") (list) (marked-at (at 7) '(List Loop)) lib))

      (define main-top
        (TopScope (table-of (list (Pair "List" (TypeName (global main "List") #f))
                                  (Pair "Show" (ClassName (global main "Show")))
                                  (Pair "Fresh" (TypeName (global main "Fresh") #t))
                                  (Pair "io" (EffectName (global main "io")))
                                  (Pair "x" (Value (TopGlobal (global main "x"))))
                                  (Pair "Twice"
                                        (TypeAlias (global main "Twice")
                                                   (list (plain "a"))
                                                   (marked-at (at 5) '(List (List a)))
                                                   main))
                                  (Pair "Ignore"
                                        (TypeAlias (global main "Ignore")
                                                   (list (plain "a"))
                                                   (marked-at (at 8) 'I64)
                                                   main))
                                  (Pair "Io"
                                        (TypeAlias (global main "Io")
                                                   (list (plain "e"))
                                                   (marked-at (at 9) '(! io e))
                                                   main))))
                  (table-of (list (Pair "Fn" (ClassName (global base "Fn")))
                                  (Pair "Show.Output" (Associated (global main "Show") "Output"))
                                  (Pair "I64" (TypeName (global forms-library "I64") #f))
                                  (Pair "Box"
                                        (TypeAlias (global lib "Box")
                                                   (list (plain "t"))
                                                   (marked-at (at 6) '(Cell t))
                                                   lib))
                                  (Pair "Loop" loop)))))


      (define offers
        (list (Offered forms-library forms-offer)
              (Offered lib
                       (Offer (list)
                              (TopScope
                               (table-of (list (Pair "Cell" (TypeName (global lib "Cell") #f))
                                               (Pair "List" (TypeName (global lib "List") #f))
                                               (Pair "Loop" loop)))
                               empty-table)))))

      (define scopes
        (Scopes main main-top offers))

      (define top
        (Env (list) main))

      ;; `a` and `e` as type variables, and `v` as a value.
      (define inner
        (Env (list (Frame (plain "a") (TypeVariable "a"))
                   (Frame (plain "e") (TypeVariable "e"))
                   (Frame (plain "v") (LocalValue (Local "v" 1))))
             main))

      (define (type-in env datum)
        (expand-type scopes env (marked datum)))

      (define (type datum)
        (type-in top datum))

      (define (list-of type)
        (Applied (global main "List") "List" (list type) loc))

      ;; ---- Cases ----

      ;; A name is its declaration, applied to its arguments in order; any
      ;; other meaning is not a type.
      (define (test-names)
        (expect (type 'I64) (Ok (i64 loc)))
        (expect (type '(List I64)) (Ok (list-of (i64 loc))))
        (expect (type '(List I64 I64))
                (Ok (Applied (global main "List") "List" (list (i64 loc) (i64 loc)) loc)))
        ;; How many arguments a declared type takes is `declare`'s to check,
        ;; after the arguments; the old expander counted them first, and
        ;; said "wrong number of type arguments: List" here.
        (expect (type '(List Missing Missing)) (fail loc "not a type: Missing"))
        (expect (type '(Show.Output I64))
                (Ok (Projection (global main "Show") "Output" (list (i64 loc)) loc)))
        (expect (type 'Show) (fail loc "not a type: Show"))
        (expect (type 'x) (fail loc "not a type: x"))
        (expect (type 'Missing) (fail loc "not a type: Missing"))
        (expect (type '(List Missing)) (fail loc "not a type: Missing"))
        (expect (type '(Missing I64)) (fail loc "not a type: Missing"))
        (expect (type-in inner 'v) (fail loc "not a type: v"))
        (expect (type '((List) I64)) (fail loc "expected a type constructor"))
        (expect (type '()) (fail loc "expected a type"))
        (expect (type 1) (fail loc "expected a type")))

      ;; A variable takes no arguments, and those are never expanded.
      (define (test-variables)
        (expect (type-in inner 'a) (Ok (Variable "a" loc)))
        (expect (type-in inner '(List a)) (Ok (list-of (Variable "a" loc))))
        (expect (type-in inner '(a Missing)) (fail loc "a type variable takes no arguments")))

      ;; An alias's use is its arguments and its body, expanded at its own
      ;; library's top level over its parameters, each standing for the
      ;; argument at its index; an alias that reaches itself is refused.
      (define (test-aliases)
        (define (twice-of argument)
          (Aliased (global main "Twice")
                   (list argument)
                   (Applied (global main "List")
                            "List"
                            (list (Applied (global main "List")
                                           "List"
                                           (list (AliasParameter 0 (at 5)))
                                           (at 5)))
                            (at 5))
                   loc))
        (define (box-of argument)
          (Aliased (global lib "Box")
                   (list argument)
                   (Applied (global lib "Cell") "Cell" (list (AliasParameter 0 (at 6))) (at 6))
                   loc))
        (expect (type '(Twice I64)) (Ok (twice-of (i64 loc))))
        (expect (type '(Box I64)) (Ok (box-of (i64 loc))))
        (expect (type '(Twice (Box I64))) (Ok (twice-of (box-of (i64 loc)))))
        ;; An argument the body does not use is kept, as the old expander
        ;; resolves every argument; a parameter may end a row.
        (expect (type '(Ignore (List I64)))
                (Ok (Aliased (global main "Ignore") (list (list-of (i64 loc))) (i64 (at 8)) loc)))
        (expect (type '(Io I64))
                (Ok (Aliased (global main "Io")
                             (list (i64 loc))
                             (Row
                              (Effects (list (global main "io")) (Some (AliasParameter 0 (at 9))))
                              (at 9))
                             loc)))
        (expect (type '(Twice I64 I64)) (fail loc "wrong number of alias arguments: Twice"))
        (expect (type 'Twice) (fail loc "wrong number of alias arguments: Twice"))
        (expect (type '(Twice Missing)) (fail loc "not a type: Missing"))
        (expect (type 'Loop) (fail (at 7) "type alias refers to itself: Loop"))
        (expect (type '(Box (Twice x))) (fail loc "not a type: x")))

      (define (test-callables)
        (let ((arrow (Arrow (list (i64 loc)) (i64 loc) (Effects (list) (None)))))
          (expect (type '(impl (Fn I64 -> I64))) (Ok (Callable (Impl) (FnContract) arrow loc)))
          (expect (type '(dyn (FnOnce I64 -> I64)))
                  (Ok (Callable (Dyn) (FnOnceContract) arrow loc)))
          (expect (type '(fn I64 -> I64)) (Ok (Code arrow loc)))
          (expect (type '(fn -> I64 ! io))
                  (Ok
                   (Code (Arrow (list) (i64 loc) (Effects (list (global main "io")) (None))) loc)))
          (expect (type '(impl (Thunk I64)))
                  (fail loc "impl and dyn require an Fn, FnMut or FnOnce contract"))
          (expect (type '(dyn I64))
                  (fail loc "expected (impl (Fn argument ... -> result ! effects)) or dyn"))
          (expect (type '(Fn I64 -> I64))
                  (fail loc
                        "a callable type requires impl or dyn around its Fn, FnMut or FnOnce contract"))
          (expect (type '(-> I64))
                  (fail loc
                        "use (impl (Fn arguments -> result ! effects)) for a callable contract, or dyn for storage"))
          (expect (type '(fn Missing ! io -> I64)) (fail loc "not a type: Missing"))
          (expect (type '(fn I64 ! io -> I64))
                  (fail loc
                        "a callable signature puts -> before its result and ! before its effects"))
          (expect (type '(fn I64))
                  (fail loc "a callable signature needs -> followed by one result type"))
          (expect (type '(fn -> -> I64)) (fail loc "a callable signature has only one ->"))
          (expect (type '(fn -> ! io)) (fail loc "a callable signature needs a result before !"))
          (expect (type '(fn -> I64 I64))
                  (fail loc "expected one result type after ->, optionally followed by ! effects"))
          (expect (type '(fn -> Missing ! nothing)) (fail loc "not a type: Missing"))))

      ;; A row's labels are effects; a type variable may end it.
      (define (test-rows)
        (expect (type '(! io io))
                (Ok (Row (Effects (list (global main "io") (global main "io")) (None)) loc)))
        (expect (type '(!)) (Ok (Row (Effects (list) (None)) loc)))
        (expect (type-in inner '(! io e))
                (Ok (Row (Effects (list (global main "io")) (Some (Variable "e" loc))) loc)))
        (expect (type-in inner '(! e io)) (fail loc "a row variable must come last"))
        (expect (type '(! io I64)) (fail loc "not an effect: I64"))
        (expect (type '(! (io))) (fail loc "expected an effect label")))

      ;; A scheme's requirements come before its one type is looked for.
      (define (test-schemes)
        (define (scheme datum)
          (expand-scheme scopes top (marked datum)))
        (expect (scheme 'I64) (Ok (Scheme (list) (list) (i64 loc) loc)))
        (expect (scheme '(All (a) (List a)))
                (Ok (Scheme (list "a") (list) (list-of (Variable "a" loc)) loc)))
        (expect (scheme '(All (a) (requires (Copy a)) a))
                (Ok (Scheme (list "a") (list (CopyRequirement "a" loc)) (Variable "a" loc) loc)))
        (expect (scheme '(All (a) (requires (Copy b)) a))
                (fail loc "Copy names a quantified type variable, not b"))
        (expect (scheme '(All (a) (requires (Copy b)) a b))
                (fail loc "Copy names a quantified type variable, not b"))
        (expect (scheme '(All (a) a b))
                (fail loc "expected (All (variable ...) [(requires constraint ...)] type)"))
        (expect (scheme '(All (a 1) a)) (fail loc "expected a type variable"))
        (expect (scheme '(All a a)) (fail loc "not a type: All"))
        ;; Where a callable scheme may hold `impl` is `declare`'s to check,
        ;; with the rest of what the scheme's definition needs; the old
        ;; expander refused this returned `impl` as it read the signature.
        (expect (scheme '(impl (Fn -> (impl (Fn -> I64)))))
                (Ok (Scheme (list)
                            (list)
                            (Callable (Impl)
                                      (FnContract)
                                      (Arrow (list)
                                             (Callable (Impl)
                                                       (FnContract)
                                                       (Arrow (list)
                                                              (i64 loc)
                                                              (Effects (list) (None)))
                                                       loc)
                                             (Effects (list) (None)))
                                      loc)
                            loc))))

      (define (test-requirements)
        (define (requirement datum)
          (match (expand-scheme scopes top (marked (list 'All '(a) (list 'requires datum) 'a)))
            ((Ok scheme) (Ok (::requirements scheme)))
            ((Err feedback) (Err feedback))))
        (expect (requirement '(Show a (type Output I64)))
                (Ok (list (ClassRequirement (ClassGlobal (global main "Show"))
                                            (list (Variable "a" loc))
                                            (list (Equation (Label "Output" loc) (i64 loc)))
                                            loc))))
        (expect (requirement '(::count a I64))
                (Ok (list (ClassRequirement (FieldClass "count")
                                            (list (Variable "a" loc) (i64 loc))
                                            (list)
                                            loc))))
        (expect (requirement '(Fn a I64 -> I64))
                (Ok (list (CallableRequirement (FnContract)
                                               (Variable "a" loc)
                                               (Arrow (list (i64 loc))
                                                      (i64 loc)
                                                      (Effects (list) (None)))
                                               loc))))
        (expect (requirement '(Fn))
                (fail loc "a callable requirement names its receiver type before its arguments"))
        (expect (requirement '(Show Missing (type Output (bad)))) (fail loc "not a type: Missing"))
        (expect (requirement '(Show a (type (Output) I64)))
                (fail loc "expected (type Output Type)"))
        (expect (requirement '(Show a (type Output Missing))) (fail loc "not a type: Missing"))
        ;; Equations' types are expanded in the order written. The old
        ;; expander expanded those of the class's outputs, in the class's
        ;; order, and said "not a type: Other" here; `declare`, which has
        ;; the class, finds an equation that is unknown or repeated.
        (expect (requirement '(Show a (type Item Missing) (type Output Other)))
                (fail loc "not a type: Missing"))
        (expect (requirement '(x a)) (fail loc "expected a typeclass constraint"))
        (expect (requirement '(::a::b a)) (fail loc "a field class names one label, not ::a::b"))
        (expect (requirement '(::a:: a)) (fail loc "empty field label in ::a::"))
        (expect (requirement '(Copy)) (fail loc "expected (Copy variable)"))
        (expect (requirement '()) (fail loc "expected (Class type ...)"))
        (expect (requirement '(1 a)) (fail loc "expected a typeclass")))))
   (else)))

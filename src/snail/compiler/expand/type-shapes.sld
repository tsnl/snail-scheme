;; The shape of type syntax. Its keywords, `impl`, `dyn`, `fn`, `->`, `!`,
;; `Fn`, `FnMut`, `FnOnce`, `All`, `requires`, `Copy` and `type`, are
;; known by name, whatever binds them, as the old expander knows them;
;; every other name in a type is resolved by the part (snail compiler
;; expand types), which acts on these answers. Each answer carries the
;; syntax its parts still are, so the part expands them in the old order,
;; or what to say of a shape that is malformed, which the part places.
(define-library (snail compiler expand type-shapes)
  (export
   TypeShape
   NamedType
   CallableType
   CodeType
   RowType
   MalformedType
   type-shape
   ContractShape
   WellFormedContract
   MalformedContract
   contract-shape
   ArrowShape
   WellFormedArrow
   MalformedArrow
   arrow-shape
   SchemeShape
   Quantified
   MalformedScheme
   Unquantified
   scheme-shape
   RequirementShape
   CopyOf
   ClassApplied
   MalformedRequirement
   requirement-shape
   Arguments
   class-arguments
   EquationForm
   equation-form
   callable-contract)
  (import
   (snail core base)
   (snail compiler source)
   (snail compiler names libraries)
   (snail compiler expand language)
   (only (snail compiler types type)
         Former
         Impl
         Dyn
         Contract
         FnContract
         FnMutContract
         FnOnceContract)
   (snail compiler expand marked)
   (only (snail compiler expand scopes) marked-loc)
   (only (snail compiler names globals) Global))
  (begin

    ;; ---- Types ----

    ;; A name, alone or applied; `(impl contract)` or `(dyn contract)`;
    ;; `(fn item ...)`; `(! label ...)`; or a refused shape: `(-> ...)`, a
    ;; callable contract without `impl` or `dyn`, a form whose head is not
    ;; a name, and anything else.
    (enum TypeShape
      (NamedType
       ((identifier Identifier)
        (arguments (List Marked))
        (loc Loc)))
      (CallableType
       ((former Former)
        (contract Marked)
        (loc Loc)))
      (CodeType
       ((items (List Marked))
        (loc Loc)))
      (RowType
       ((labels (List Marked))
        (loc Loc)))
      (MalformedType
       ((loc Loc)
        (message String))))

    (: type-shape (impl (Fn Marked -> TypeShape)))
    (define (type-shape syntax)
      (match syntax
        ((Ident identifier loc) (NamedType identifier (Nil) loc))
        ((Form (Cons (Ident (Identifier "impl" _) _) (Cons contract (Nil))) loc)
         (CallableType (Impl) contract loc))
        ((Form (Cons (Ident (Identifier "dyn" _) _) (Cons contract (Nil))) loc)
         (CallableType (Dyn) contract loc))
        ((Form (Cons (Ident (Identifier "fn" _) _) items) loc) (CodeType items loc))
        ((Form (Cons (Ident (Identifier "->" _) _) _) loc)
         (MalformedType loc
                        "use (impl (Fn arguments -> result ! effects)) for a callable contract, or dyn for storage"))
        ((Form (Cons (Ident (Identifier "!" _) _) labels) loc) (RowType labels loc))
        ((Form (Cons (Ident identifier _) arguments) loc)
         (if (contract-name? (::name identifier))
             (MalformedType loc
                            "a callable type requires impl or dyn around its Fn, FnMut or FnOnce contract")
             (NamedType identifier arguments loc)))
        ((Form (Cons head _) _) (MalformedType (marked-loc head) "expected a type constructor"))
        ((Form (Nil) loc) (MalformedType loc "expected a type"))
        ((Atom _ loc) (MalformedType loc "expected a type"))))

    (: contract-name? (impl (Fn String -> Bool)))
    (define (contract-name? name)
      (member? name (list "Fn" "FnMut" "FnOnce")))

    ;; ---- Contracts ----

    ;; What `impl` or `dyn` holds: `(Fn item ...)`, `(FnMut item ...)` or
    ;; `(FnOnce item ...)`, or what to say of anything else, at the type.
    (enum ContractShape
      (WellFormedContract
       ((contract Contract)
        (items (List Marked))))
      (MalformedContract
       ((message String))))

    (: contract-shape (impl (Fn Marked -> ContractShape)))
    (define (contract-shape syntax)
      (match syntax
        ((Form (Cons (Ident identifier _) items) _)
         (match (named-contract (::name identifier))
           ((Some contract) (WellFormedContract contract items))
           ((None) (MalformedContract "impl and dyn require an Fn, FnMut or FnOnce contract"))))
        (_ (MalformedContract "expected (impl (Fn argument ... -> result ! effects)) or dyn"))))

    (: named-contract (impl (Fn String -> (Option Contract))))
    (define (named-contract name)
      (cond ((string=? name "Fn") (Some (FnContract)))
            ((string=? name "FnMut") (Some (FnMutContract)))
            ((string=? name "FnOnce") (Some (FnOnceContract)))
            (else (None))))

    ;; The callable classes of (snail core base), which a requirement
    ;; names, and the contract each is.
    (: callable-contract (impl (Fn Global -> (Option Contract))))
    (define (callable-contract global)
      (if (and (same-library? (::library global) base-library)
               (= (::serial global) 0))
          (named-contract (::name global))
          (None)))

    ;; ---- Arrows ----

    ;; `parameter ... -> result` with `! label ...` after it or not. A
    ;; malformed arrow keeps the parameters written before its problem,
    ;; which the old expander resolves before it meets the problem, and
    ;; what to say of it, at the type: `!` before any `->`, no `->`, a
    ;; second `->`, `!` straight after `->`, or anything but one result
    ;; after `->`.
    (enum ArrowShape
      (WellFormedArrow
       ((parameters (List Marked))
        (result Marked)
        (effects (Option (List Marked)))))
      (MalformedArrow
       ((parameters (List Marked))
        (message String))))

    (: arrow-shape (impl (Fn (List Marked) -> ArrowShape)))
    (define (arrow-shape items)
      (let loop ((items items)
                 (parameters (Nil)))
        (match items
          ((Cons (Ident (Identifier "->" _) _) rest) (arrow-result (reverse parameters) rest))
          ((Cons (Ident (Identifier "!" _) _) _)
           (MalformedArrow (reverse parameters)
                           "a callable signature puts -> before its result and ! before its effects"))
          ((Cons parameter rest) (loop rest (Cons parameter parameters)))
          ((Nil)
           (MalformedArrow (reverse parameters)
                           "a callable signature needs -> followed by one result type")))))

    (: arrow-result (impl (Fn (List Marked) (List Marked) -> ArrowShape)))
    (define (arrow-result parameters items)
      (match items
        ((Cons (Ident (Identifier "->" _) _) _)
         (MalformedArrow parameters "a callable signature has only one ->"))
        ((Cons (Ident (Identifier "!" _) _) _)
         (MalformedArrow parameters "a callable signature needs a result before !"))
        ((Cons result (Nil)) (WellFormedArrow parameters result (None)))
        ((Cons result (Cons (Ident (Identifier "!" _) _) labels))
         (WellFormedArrow parameters result (Some labels)))
        (_
         (MalformedArrow parameters
                         "expected one result type after ->, optionally followed by ! effects"))))

    ;; ---- Schemes ----

    ;; `(All (variable ...) (requires requirement ...) type)`, where the
    ;; requirements may be absent, or a type alone. Its rest is one type,
    ;; or what to say of it, at the scheme, once the requirements are
    ;; expanded.
    (enum SchemeShape
      (Quantified
       ((variables (List Identifier))
        (requirements (List Marked))
        (type (Result Marked String))
        (loc Loc)))
      (MalformedScheme
       ((loc Loc)
        (message String)))
      (Unquantified
       ((type Marked))))

    (: scheme-shape (impl (Fn Marked -> SchemeShape)))
    (define (scheme-shape syntax)
      (match syntax
        ((Form (Cons (Ident (Identifier "All" _) _) (Cons (Form variables _) rest)) loc)
         (match (identifiers-of variables)
           ((Ok identifiers) (quantified identifiers rest loc))
           ((Err place) (MalformedScheme place "expected a type variable"))))
        (_ (Unquantified syntax))))

    (: quantified (impl (Fn (List Identifier) (List Marked) Loc -> SchemeShape)))
    (define (quantified variables rest loc)
      (match rest
        ((Cons (Form (Cons (Ident (Identifier "requires" _) _) requirements) _) after)
         (Quantified variables requirements (one-type after) loc))
        (_ (Quantified variables (Nil) (one-type rest) loc))))

    (: one-type (impl (Fn (List Marked) -> (Result Marked String))))
    (define (one-type items)
      (match items
        ((Cons item (Nil)) (Ok item))
        (_ (Err "expected (All (variable ...) [(requires constraint ...)] type)"))))

    ;; Each item's identifier, or where the first that is not one is.
    (: identifiers-of (impl (Fn (List Marked) -> (Result (List Identifier) Loc))))
    (define (identifiers-of items)
      (match items
        ((Nil) (Ok (Nil)))
        ((Cons (Ident identifier _) rest)
         (match (identifiers-of rest)
           ((Ok identifiers) (Ok (Cons identifier identifiers)))
           ((Err place) (Err place))))
        ((Cons (Atom _ loc) _) (Err loc))
        ((Cons (Form _ loc) _) (Err loc))))

    ;; ---- Requirements ----

    ;; `(Copy variable)`; `(Class argument ...)`, whose class must be a
    ;; name; or what to say of anything else, and where.
    (enum RequirementShape
      (CopyOf
       ((name String)
        (loc Loc)))
      (ClassApplied
       ((class Identifier)
        (class-loc Loc)
        (arguments (List Marked))
        (loc Loc)))
      (MalformedRequirement
       ((loc Loc)
        (message String))))

    (: requirement-shape (impl (Fn Marked -> RequirementShape)))
    (define (requirement-shape syntax)
      (match syntax
        ((Form (Cons (Ident (Identifier "Copy" _) _) (Cons (Ident identifier _) (Nil))) loc)
         (CopyOf (::name identifier) loc))
        ((Form (Cons (Ident (Identifier "Copy" _) _) _) loc)
         (MalformedRequirement loc "expected (Copy variable)"))
        ((Form (Cons (Ident identifier class-loc) arguments) loc)
         (ClassApplied identifier class-loc arguments loc))
        ((Form (Cons class _) _) (MalformedRequirement (marked-loc class) "expected a typeclass"))
        (_ (MalformedRequirement (marked-loc syntax) "expected (Class type ...)"))))

    ;; A class's arguments: its types, and its equations `(type Output
    ;; type)`, each in the order written.
    (struct Arguments
      ((types (List Marked))
       (equations (List Marked))))

    (: class-arguments (impl (Fn (List Marked) -> Arguments)))
    (define (class-arguments items)
      (Arguments (filter (lambda (item) (not (equation? item))) items) (filter equation? items)))

    (: equation? (impl (Fn Marked -> Bool)))
    (define (equation? item)
      (match item
        ((Form (Cons (Ident (Identifier "type" _) _) _) _) #t)
        (_ #f)))

    ;; `(type Output type)`, or what to say of an equation that is not, at
    ;; the equation.
    (struct EquationForm
      ((name String)
       (name-loc Loc)
       (type Marked)))

    (: equation-form (impl (Fn Marked -> (Result EquationForm String))))
    (define (equation-form syntax)
      (match syntax
        ((Form (Cons _ (Cons (Ident identifier name-loc) (Cons type (Nil)))) _)
         (Ok (EquationForm (::name identifier) name-loc type)))
        (_ (Err "expected (type Output Type)"))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-type-shapes)
    (import
     (only (scheme base) pair? symbol? symbol->string string? exact-integer? boolean?)
     (prefix (snail compiler literals datum) datum-)
     (snail stage0 testing))
    (begin
      (define (test-type-shapes)
        (test-types)
        (test-contracts)
        (test-arrows)
        (test-schemes)
        (test-requirements))

      (define loc (Loc "t.sld" 1 1))

      (define (marked datum)
        (cond ((or (null? datum) (pair? datum)) (Form (map marked datum) loc))
              ((symbol? datum) (Ident (Identifier (symbol->string datum) (Nil)) loc))
              ((string? datum) (Atom (datum-Text datum) loc))
              ((exact-integer? datum) (Atom (datum-Integer datum) loc))
              (else (panic "no syntax for this datum"))))

      (define (plain name)
        (Identifier name (Nil)))

      ;; Keywords are known by name, marks and all.
      (define (test-types)
        (let ((marked-impl
               (Ident (Identifier "impl" (list (Mark (list "m") 1 (TopLevel (list "m")))))
                      loc)))
          (expect (type-shape (marked 'I64)) (NamedType (plain "I64") (list) loc))
          (expect (type-shape (marked '(List a))) (NamedType (plain "List") (list (marked 'a)) loc))
          (expect (type-shape (marked '(impl c))) (CallableType (Impl) (marked 'c) loc))
          (expect (type-shape (Form (list marked-impl (marked 'c)) loc))
                  (CallableType (Impl) (marked 'c) loc))
          (expect (type-shape (marked '(dyn c))) (CallableType (Dyn) (marked 'c) loc))
          (expect (type-shape (marked '(impl c d)))
                  (NamedType (plain "impl") (list (marked 'c) (marked 'd)) loc))
          (expect (type-shape (marked '(fn a -> b)))
                  (CodeType (list (marked 'a) (marked '->) (marked 'b)) loc))
          (expect (type-shape (marked '(-> a)))
                  (MalformedType loc
                                 "use (impl (Fn arguments -> result ! effects)) for a callable contract, or dyn for storage"))
          (expect (type-shape (marked '(! io))) (RowType (list (marked 'io)) loc))
          (expect (type-shape (marked '(FnMut a -> b)))
                  (MalformedType loc
                                 "a callable type requires impl or dyn around its Fn, FnMut or FnOnce contract"))
          (expect (type-shape (marked '((List) a)))
                  (MalformedType loc "expected a type constructor"))
          (expect (type-shape (marked '())) (MalformedType loc "expected a type"))
          (expect (type-shape (marked 1)) (MalformedType loc "expected a type"))))

      (define (test-contracts)
        (expect (contract-shape (marked '(FnOnce a -> b)))
                (WellFormedContract (FnOnceContract) (list (marked 'a) (marked '->) (marked 'b))))
        (expect (contract-shape (marked '(Fn))) (WellFormedContract (FnContract) (list)))
        (expect (contract-shape (marked '(Thunk a)))
                (MalformedContract "impl and dyn require an Fn, FnMut or FnOnce contract"))
        (expect (contract-shape (marked 'Fn))
                (MalformedContract "expected (impl (Fn argument ... -> result ! effects)) or dyn"))
        (expect (contract-shape (marked '((Fn) a)))
                (MalformedContract "expected (impl (Fn argument ... -> result ! effects)) or dyn"))
        (expect (callable-contract (Global (list "snail" "core" "base") "FnMut" 0))
                (Some (FnMutContract)))
        (expect (callable-contract (Global (list "snail" "core" "base") "Show" 0)) (None))
        (expect (callable-contract (Global (list "snail" "core" "base") "Fn" 3)) (None))
        (expect (callable-contract (Global (list "other") "Fn" 0)) (None)))

      ;; A problem keeps the parameters before it.
      (define (test-arrows)
        (define (arrow datum)
          (arrow-shape (map marked datum)))
        (expect (arrow '(a b -> c))
                (WellFormedArrow (list (marked 'a) (marked 'b)) (marked 'c) (None)))
        (expect (arrow '(-> c ! io st))
                (WellFormedArrow (list) (marked 'c) (Some (list (marked 'io) (marked 'st)))))
        (expect (arrow '(-> c !)) (WellFormedArrow (list) (marked 'c) (Some (list))))
        (expect (arrow '(a ! io -> c))
                (MalformedArrow (list (marked 'a))
                                "a callable signature puts -> before its result and ! before its effects"))
        (expect (arrow '(a b))
                (MalformedArrow (list (marked 'a) (marked 'b))
                                "a callable signature needs -> followed by one result type"))
        (expect (arrow '(a -> -> c))
                (MalformedArrow (list (marked 'a)) "a callable signature has only one ->"))
        (expect (arrow '(a -> ! io))
                (MalformedArrow (list (marked 'a)) "a callable signature needs a result before !"))
        (expect (arrow '(a ->))
                (MalformedArrow (list (marked 'a))
                                "expected one result type after ->, optionally followed by ! effects"))
        (expect (arrow '(-> c d))
                (MalformedArrow (list)
                                "expected one result type after ->, optionally followed by ! effects")))

      (define (test-schemes)
        (expect (scheme-shape (marked '(All (a b) (requires (Show a)) (f a))))
                (Quantified (list (plain "a") (plain "b"))
                            (list (marked '(Show a)))
                            (Ok (marked '(f a)))
                            loc))
        (expect (scheme-shape (marked '(All () t)))
                (Quantified (list) (list) (Ok (marked 't)) loc))
        (expect (scheme-shape (marked '(All (a) (requires) t u)))
                (Quantified (list (plain "a"))
                            (list)
                            (Err "expected (All (variable ...) [(requires constraint ...)] type)")
                            loc))
        (expect (scheme-shape (Form (list (marked 'All)
                                          (Form (list (marked 'a)
                                                      (Atom (datum-Integer 2) (Loc "t.sld" 2 2)))
                                                loc)
                                          (marked 't))
                                    loc))
                (MalformedScheme (Loc "t.sld" 2 2) "expected a type variable"))
        (expect (scheme-shape (marked '(All a t))) (Unquantified (marked '(All a t))))
        (expect (scheme-shape (marked 'I64)) (Unquantified (marked 'I64))))

      (define (test-requirements)
        (expect (requirement-shape (marked '(Copy a))) (CopyOf "a" loc))
        (expect (requirement-shape (marked '(Copy a b)))
                (MalformedRequirement loc "expected (Copy variable)"))
        (expect (requirement-shape (marked '(Copy (a))))
                (MalformedRequirement loc "expected (Copy variable)"))
        (expect (requirement-shape (marked '(Show a (type Output b))))
                (ClassApplied (plain "Show") loc (list (marked 'a) (marked '(type Output b))) loc))
        (expect (requirement-shape (Form (list (Atom (datum-Integer 5) (Loc "t.sld" 4 4))) loc))
                (MalformedRequirement (Loc "t.sld" 4 4) "expected a typeclass"))
        (expect (requirement-shape (marked '()))
                (MalformedRequirement loc "expected (Class type ...)"))
        (expect (requirement-shape (marked 'Show))
                (MalformedRequirement loc "expected (Class type ...)"))
        (expect (class-arguments (map marked '(a (type X b) c (type Y))))
                (Arguments (list (marked 'a) (marked 'c))
                           (list (marked '(type X b)) (marked '(type Y)))))
        (expect (equation-form (marked '(type X b))) (Ok (EquationForm "X" loc (marked 'b))))
        (expect (equation-form (marked '(type Y))) (Err "expected (type Output Type)"))
        (expect (equation-form (marked '(type (X) b))) (Err "expected (type Output Type)")))))
   (else)))

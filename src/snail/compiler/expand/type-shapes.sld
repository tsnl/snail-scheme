;; The shape of type syntax. Its keywords, `impl`, `dyn`, `fn`, `->`, `!`,
;; `Fn`, `FnMut`, `FnOnce`, `All`, `requires`, `Copy` and `type`, are
;; known by name, whatever binds them, as the old expander knows them;
;; every other name in a type is resolved by the part (snail compiler
;; expand types), which acts on these answers. Each answer carries the
;; syntax its parts still are, so the part expands them in the old order.
(define-library (snail compiler expand type-shapes)
  (export
   TypeShape
   NamedType
   CallableType
   CodeType
   RowType
   OldArrow
   BareCallable
   NoConstructor
   NotAType
   type-shape
   ContractShape
   WellFormedContract
   NotAContract
   MalformedContract
   contract-shape
   ArrowShape
   WellFormedArrow
   MalformedArrow
   ArrowProblem
   BangBeforeArrow
   NoArrow
   TwoArrows
   BangBeforeResult
   NotOneResult
   arrow-shape
   SchemeShape
   Quantified
   VariableNotIdentifier
   Unquantified
   scheme-shape
   RequirementShape
   CopyOf
   MalformedCopy
   ClassApplied
   ClassNotIdentifier
   NotARequirement
   requirement-shape
   Arguments
   class-arguments
   EquationForm
   equation-form
   callable-contract)
  (import
   (snail core base)
   (snail compiler source)
   (only (snail compiler outline names) same-library?)
   (snail compiler expand language)
   (snail compiler expand marked)
   (only (snail compiler expand scopes) marked-loc))
  (begin

    ;; ---- Types ----

    ;; A name, alone or applied; `(impl contract)` or `(dyn contract)`;
    ;; `(fn item ...)`; `(! label ...)`; or one of the refused shapes:
    ;; `(-> ...)`, a callable contract without `impl` or `dyn`, a form
    ;; whose head is not a name, and anything else.
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
      (OldArrow
       ((loc Loc)))
      (BareCallable
       ((loc Loc)))
      (NoConstructor
       ((head Marked)))
      (NotAType
       ((loc Loc))))

    (: type-shape (impl (Fn Marked -> TypeShape)))
    (define (type-shape syntax)
      (match syntax
        ((Ident identifier loc) (NamedType identifier (Nil) loc))
        ((Form (Cons (Ident (Identifier "impl" _) _) (Cons contract (Nil))) loc)
         (CallableType (Impl) contract loc))
        ((Form (Cons (Ident (Identifier "dyn" _) _) (Cons contract (Nil))) loc)
         (CallableType (Dyn) contract loc))
        ((Form (Cons (Ident (Identifier "fn" _) _) items) loc) (CodeType items loc))
        ((Form (Cons (Ident (Identifier "->" _) _) _) loc) (OldArrow loc))
        ((Form (Cons (Ident (Identifier "!" _) _) labels) loc) (RowType labels loc))
        ((Form (Cons (Ident identifier _) arguments) loc)
         (if (contract-name? (::name identifier))
             (BareCallable loc)
             (NamedType identifier arguments loc)))
        ((Form (Cons head _) _) (NoConstructor head))
        ((Form (Nil) loc) (NotAType loc))
        ((Atom _ loc) (NotAType loc))))

    (: contract-name? (impl (Fn String -> Bool)))
    (define (contract-name? name)
      (member? name (list "Fn" "FnMut" "FnOnce")))

    ;; ---- Contracts ----

    ;; What `impl` or `dyn` holds: `(Fn item ...)`, `(FnMut item ...)` or
    ;; `(FnOnce item ...)`; another name's form; or anything else.
    (enum ContractShape
      (WellFormedContract
       ((contract Contract)
        (items (List Marked))))
      (NotAContract)
      (MalformedContract))

    (: contract-shape (impl (Fn Marked -> ContractShape)))
    (define (contract-shape syntax)
      (match syntax
        ((Form (Cons (Ident identifier _) items) _)
         (match (named-contract (::name identifier))
           ((Some contract) (WellFormedContract contract items))
           ((None) (NotAContract))))
        (_ (MalformedContract))))

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
      (if (and (same-library? (::library global) (list "snail" "core" "base"))
               (= (::serial global) 0))
          (named-contract (::name global))
          (None)))

    ;; ---- Arrows ----

    ;; `parameter ... -> result` with `! label ...` after it or not. A
    ;; malformed arrow keeps the parameters written before its problem,
    ;; which the old expander resolves before it meets the problem.
    (enum ArrowShape
      (WellFormedArrow
       ((parameters (List Marked))
        (result Marked)
        (effects (Option (List Marked)))))
      (MalformedArrow
       ((parameters (List Marked))
        (problem ArrowProblem))))

    ;; `!` before any `->`; no `->`; a second `->`; `!` straight after
    ;; `->`; or anything but one result after `->`, with `!` or not.
    (enum ArrowProblem
      (BangBeforeArrow)
      (NoArrow)
      (TwoArrows)
      (BangBeforeResult)
      (NotOneResult))

    (: arrow-shape (impl (Fn (List Marked) -> ArrowShape)))
    (define (arrow-shape items)
      (let loop ((items items)
                 (parameters (Nil)))
        (match items
          ((Cons (Ident (Identifier "->" _) _) rest) (arrow-result (reverse parameters) rest))
          ((Cons (Ident (Identifier "!" _) _) _)
           (MalformedArrow (reverse parameters) (BangBeforeArrow)))
          ((Cons parameter rest) (loop rest (Cons parameter parameters)))
          ((Nil) (MalformedArrow (reverse parameters) (NoArrow))))))

    (: arrow-result (impl (Fn (List Marked) (List Marked) -> ArrowShape)))
    (define (arrow-result parameters items)
      (match items
        ((Cons (Ident (Identifier "->" _) _) _) (MalformedArrow parameters (TwoArrows)))
        ((Cons (Ident (Identifier "!" _) _) _) (MalformedArrow parameters (BangBeforeResult)))
        ((Cons result (Nil)) (WellFormedArrow parameters result (None)))
        ((Cons result (Cons (Ident (Identifier "!" _) _) labels))
         (WellFormedArrow parameters result (Some labels)))
        (_ (MalformedArrow parameters (NotOneResult)))))

    ;; ---- Schemes ----

    ;; `(All (variable ...) (requires requirement ...) type)`, where the
    ;; requirements may be absent, or a type alone. Its rest is one type,
    ;; or None when it is not, which is reported once the requirements are
    ;; expanded.
    (enum SchemeShape
      (Quantified
       ((variables (List Identifier))
        (requirements (List Marked))
        (type (Option Marked))
        (loc Loc)))
      (VariableNotIdentifier
       ((loc Loc)))
      (Unquantified
       ((type Marked))))

    (: scheme-shape (impl (Fn Marked -> SchemeShape)))
    (define (scheme-shape syntax)
      (match syntax
        ((Form (Cons (Ident (Identifier "All" _) _) (Cons (Form variables _) rest)) loc)
         (match (non-identifier variables)
           ((Some loc) (VariableNotIdentifier loc))
           ((None) (quantified (map identifier-of variables) rest loc))))
        (_ (Unquantified syntax))))

    (: quantified (impl (Fn (List Identifier) (List Marked) Loc -> SchemeShape)))
    (define (quantified variables rest loc)
      (match rest
        ((Cons (Form (Cons (Ident (Identifier "requires" _) _) requirements) _) after)
         (Quantified variables requirements (one-item after) loc))
        (_ (Quantified variables (Nil) (one-item rest) loc))))

    (: one-item (impl (Fn (List Marked) -> (Option Marked))))
    (define (one-item items)
      (match items
        ((Cons item (Nil)) (Some item))
        (_ (None))))

    ;; Where the first item that is not an identifier is, if one is.
    (: non-identifier (impl (Fn (List Marked) -> (Option Loc))))
    (define (non-identifier items)
      (match items
        ((Nil) (None))
        ((Cons (Ident _ _) rest) (non-identifier rest))
        ((Cons (Atom _ loc) _) (Some loc))
        ((Cons (Form _ loc) _) (Some loc))))

    (: identifier-of (impl (Fn Marked -> Identifier)))
    (define (identifier-of syntax)
      (match syntax
        ((Ident identifier _) identifier)
        (_ (panic "internal error: checked to be an identifier"))))

    ;; ---- Requirements ----

    ;; `(Copy variable)`, malformed or not; `(Class argument ...)`, whose
    ;; class must be a name; or anything else.
    (enum RequirementShape
      (CopyOf
       ((name String)
        (loc Loc)))
      (MalformedCopy
       ((loc Loc)))
      (ClassApplied
       ((class Identifier)
        (class-loc Loc)
        (arguments (List Marked))
        (loc Loc)))
      (ClassNotIdentifier
       ((loc Loc)))
      (NotARequirement
       ((loc Loc))))

    (: requirement-shape (impl (Fn Marked -> RequirementShape)))
    (define (requirement-shape syntax)
      (match syntax
        ((Form (Cons (Ident (Identifier "Copy" _) _) (Cons (Ident identifier _) (Nil))) loc)
         (CopyOf (::name identifier) loc))
        ((Form (Cons (Ident (Identifier "Copy" _) _) _) loc) (MalformedCopy loc))
        ((Form (Cons (Ident identifier class-loc) arguments) loc)
         (ClassApplied identifier class-loc arguments loc))
        ((Form (Cons class _) _) (ClassNotIdentifier (marked-loc class)))
        ((Form (Nil) loc) (NotARequirement loc))
        ((Atom _ loc) (NotARequirement loc))
        ((Ident _ loc) (NotARequirement loc))))

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

    ;; `(type Output type)`, or None.
    (struct EquationForm
      ((name String)
       (name-loc Loc)
       (type Marked)))

    (: equation-form (impl (Fn Marked -> (Option EquationForm))))
    (define (equation-form syntax)
      (match syntax
        ((Form (Cons _ (Cons (Ident identifier name-loc) (Cons type (Nil)))) _)
         (Some (EquationForm (::name identifier) name-loc type)))
        (_ (None))))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-type-shapes)
    (import
     (only (scheme base) pair? symbol? symbol->string string? exact-integer? boolean?)
     (prefix (snail compiler read language) syntax-)
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
              ((string? datum) (Atom (syntax-Text datum) loc))
              ((exact-integer? datum) (Atom (syntax-Integer datum) loc))
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
          (expect (type-shape (marked '(-> a))) (OldArrow loc))
          (expect (type-shape (marked '(! io))) (RowType (list (marked 'io)) loc))
          (expect (type-shape (marked '(FnMut a -> b))) (BareCallable loc))
          (expect (type-shape (marked '((List) a))) (NoConstructor (marked '(List))))
          (expect (type-shape (marked '())) (NotAType loc))
          (expect (type-shape (marked 1)) (NotAType loc))))

      (define (test-contracts)
        (expect (contract-shape (marked '(FnOnce a -> b)))
                (WellFormedContract (FnOnceContract) (list (marked 'a) (marked '->) (marked 'b))))
        (expect (contract-shape (marked '(Fn))) (WellFormedContract (FnContract) (list)))
        (expect (contract-shape (marked '(Thunk a))) (NotAContract))
        (expect (contract-shape (marked 'Fn)) (MalformedContract))
        (expect (contract-shape (marked '((Fn) a))) (MalformedContract))
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
        (expect (arrow '(a ! io -> c)) (MalformedArrow (list (marked 'a)) (BangBeforeArrow)))
        (expect (arrow '(a b)) (MalformedArrow (list (marked 'a) (marked 'b)) (NoArrow)))
        (expect (arrow '(a -> -> c)) (MalformedArrow (list (marked 'a)) (TwoArrows)))
        (expect (arrow '(a -> ! io)) (MalformedArrow (list (marked 'a)) (BangBeforeResult)))
        (expect (arrow '(a ->)) (MalformedArrow (list (marked 'a)) (NotOneResult)))
        (expect (arrow '(-> c d)) (MalformedArrow (list) (NotOneResult))))

      (define (test-schemes)
        (expect (scheme-shape (marked '(All (a b) (requires (Show a)) (f a))))
                (Quantified (list (plain "a") (plain "b"))
                            (list (marked '(Show a)))
                            (Some (marked '(f a)))
                            loc))
        (expect (scheme-shape (marked '(All () t)))
                (Quantified (list) (list) (Some (marked 't)) loc))
        (expect (scheme-shape (marked '(All (a) (requires) t u)))
                (Quantified (list (plain "a")) (list) (None) loc))
        (expect (scheme-shape (Form (list (marked 'All)
                                          (Form (list (marked 'a)
                                                      (Atom (syntax-Integer 2) (Loc "t.sld" 2 2)))
                                                loc)
                                          (marked 't))
                                    loc))
                (VariableNotIdentifier (Loc "t.sld" 2 2)))
        (expect (scheme-shape (marked '(All a t))) (Unquantified (marked '(All a t))))
        (expect (scheme-shape (marked 'I64)) (Unquantified (marked 'I64))))

      (define (test-requirements)
        (expect (requirement-shape (marked '(Copy a))) (CopyOf "a" loc))
        (expect (requirement-shape (marked '(Copy a b))) (MalformedCopy loc))
        (expect (requirement-shape (marked '(Copy (a)))) (MalformedCopy loc))
        (expect (requirement-shape (marked '(Show a (type Output b))))
                (ClassApplied (plain "Show") loc (list (marked 'a) (marked '(type Output b))) loc))
        (expect (requirement-shape (Form (list (Atom (syntax-Integer 5) (Loc "t.sld" 4 4))) loc))
                (ClassNotIdentifier (Loc "t.sld" 4 4)))
        (expect (requirement-shape (marked '())) (NotARequirement loc))
        (expect (requirement-shape (marked 'Show)) (NotARequirement loc))
        (expect (class-arguments (map marked '(a (type X b) c (type Y))))
                (Arguments (list (marked 'a) (marked 'c))
                           (list (marked '(type X b)) (marked '(type Y)))))
        (expect (equation-form (marked '(type X b))) (Some (EquationForm "X" loc (marked 'b))))
        (expect (equation-form (marked '(type Y))) (None))
        (expect (equation-form (marked '(type (X) b))) (None)))))
   (else)))

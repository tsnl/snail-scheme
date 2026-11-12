;; What a dispatch clause covers, and what each method of its class must be
;; for the clause to write it, as the old compiler's `parse-dispatch`,
;; `dispatch-method` and `dispatch-lambda` (src/snail/shell/compiler/
;; dynamic.sld) decide it, each refusal the old message.
;;
;; A clause's instance erases one parameter of its class: the head is
;; ground but for exactly one Any, among its types and outputs, and the
;; class is no lifecycle class. The erased parameter is the class's
;; parameter, its outputs last, that the head gives Any; the others are
;; fixed at the head's types. Its targets, the types written in the clause,
;; are at least one, each ground and none Any, and no two the same. These
;; are the domain's checks, in that order, and each refuses the library,
;; as the old compiler makes them while it declares the instance.
;;
;; A method is written for the clause when it is a function of the class's
;; parameters alone, with no requirement of its own and no variable of its
;; own, whose result and each parameter, at the fixed types, either is the
;; erased parameter or does not mention it, and one of whose parameters is
;; it, the first such being the one the dispatch selects by. These are the
;; method's checks, in that order; each refuses that method alone, as the
;; old compiler checks a method as it expands its body.
(define-library (snail compiler dispatch domains)
  (export
   Domain
   Position
   Erased
   Fixed
   MethodShape
   clause-domain
   method-shape
   ground?
   concrete?)
  (import
   (snail core base)
   (prefix (snail compiler declare language) declared-)
   (only (snail compiler types equality) same-type? same-variable?)
   (only (snail compiler names globals) ClassRef)
   (only (snail compiler declare schemes) class-variables)
   (only (snail compiler types type)
         Type
         Con
         Callable
         Code
         Row
         Var
         Arrow
         Effects
         TypeVariable
         Written
         Dyn
         FnContract)
   (only (snail compiler types scheme) Scheme ClassRequirement)
   (only (snail compiler types substitution) substituted)
   (snail compiler dispatch known)
   (snail compiler types builtins)
   (only (snail compiler builtins base) instance-lifecycle dyn-cast-effect))
  (begin

    ;; ---- Domains ----

    ;; The class's parameter the clause erases, the others at the head's
    ;; types, and the targets, in the order written.
    (struct Domain
      ((erased TypeVariable)
       (fixed (List (Pair TypeVariable Type)))
       (targets (List Type))))

    ;; `instance` is the clause's, written for `class` as known there, and
    ;; `targets` the clause's types. Declared gives the instance's head
    ;; exactly the class's parameters and outputs as known where it is
    ;; written, which is `class`, so they pair up.
    (: clause-domain
       (impl (Fn KnownClass declared-Instance (List Type) -> (Result Domain String))))
    (define (clause-domain class instance targets)
      (let ((head (zip (class-variables (::parameters class) (::outputs class))
                       (append (::types instance) (::outputs instance)))))
        (match (filter (lambda (pair) (any-type? (::second pair))) head)
          ((Cons (Pair erased _) (Nil))
           (if (and (null? (::variables instance))
                    (null? (::requirements instance))
                    (not (lifecycle? (::class instance))))
               (match (targets-problem targets)
                 ((Some problem) (Err problem))
                 ((None)
                  (Ok (Domain erased
                              (filter (lambda (pair) (not (same-variable? (::first pair) erased)))
                                      head)
                              targets))))
               (Err ground-head-problem)))
          (_ (Err ground-head-problem)))))

    (: ground-head-problem String)
    (define ground-head-problem
      "dispatch needs a ground instance head with exactly one Any type argument")

    ;; Drop and Clone are found from a type's structure, never dispatched.
    (: lifecycle? (impl (Fn ClassRef -> Bool)))
    (define (lifecycle? class)
      (match (instance-lifecycle class)
        ((Some _) #t)
        ((None) #f)))

    (: targets-problem (impl (Fn (List Type) -> (Option String))))
    (define (targets-problem targets)
      (cond ((null? targets) (Some "dispatch needs at least one concrete type"))
            ((not (every? concrete? targets))
             (Some "dispatch accepts concrete types, not Any or type variables"))
            ((not (= (length targets) (length (delete-duplicates same-type? targets))))
             (Some "dispatch repeats a concrete type"))
            (else (None))))

    ;; A type a value can be recovered as, as a clause's targets and a
    ;; `dynamic-instances` form's pairs must be: ground, and not Any itself.
    (: concrete? (impl (Fn Type -> Bool)))
    (define (concrete? type)
      (and (ground? type) (not (any-type? type))))

    ;; A type with no variable, and no row that ends with one, as the old
    ;; compiler's `ground-type?` says.
    (: ground? (impl (Fn Type -> Bool)))
    (define (ground? type)
      (match type
        ((Con _ arguments) (every? ground? arguments))
        ((Callable _ _ arrow) (ground-arrow? arrow))
        ((Code arrow) (ground-arrow? arrow))
        ((Row effects) (closed? effects))
        ((Var _) #f)))

    (: ground-arrow? (impl (Fn Arrow -> Bool)))
    (define (ground-arrow? arrow)
      (and (every? ground? (::parameters arrow))
           (ground? (::result arrow))
           (closed? (::effects arrow))))

    (: closed? (impl (Fn Effects -> Bool)))
    (define (closed? effects)
      (match (::tail effects)
        ((None) #t)
        ((Some _) #f)))

    ;; ---- Methods ----

    ;; Each of a method's parameters, and its result: the erased
    ;; parameter, which is recovered from Any, or a type that does not
    ;; mention it.
    (enum Position
      (Erased)
      (Fixed))

    ;; A method the clause writes: what each of its parameters is, the
    ;; index of the one it selects by, and what its result is.
    (struct MethodShape
      ((parameters (List Position))
       (selector I64)
       (result Position)))

    ;; `own` is the method's own scheme, over the class's parameters and
    ;; outputs.
    (: method-shape (impl (Fn Domain Scheme -> (Result MethodShape String))))
    (define (method-shape domain own)
      (cond ((not (null? (::requirements own)))
             (Err "dispatch does not support methods with additional class requirements"))
            ((not (null? (::variables own)))
             (Err "dispatch does not support independently polymorphic methods"))
            (else
             (match (substituted (::fixed domain) (::type own))
               ((Callable (Dyn) (FnContract) arrow)
                (arrow-shape (::erased domain) (::parameters arrow) (::result arrow)))
               (_ (Err "dispatch needs function methods"))))))

    (: arrow-shape
       (impl (Fn TypeVariable (List Type) Type
                 -> (Result MethodShape String))))
    (define (arrow-shape erased parameters result)
      (let ((positions (map (lambda (type) (position erased type)) (Cons result parameters))))
        (if (every? (lambda (found) (match found ((Some _) #t) ((None) #f))) positions)
            (match (list-index (lambda (type) (erased? erased type)) parameters)
              ((Some selector)
               (Ok (MethodShape (map (lambda (type) (whole erased type)) parameters)
                                selector
                                (whole erased result))))
              ((None) (Err "each dispatched method needs an argument of its erased class type")))
            (Err "dispatch needs the erased class type as a whole parameter or result"))))

    ;; The position a part of the method's type is, if it is one: the
    ;; erased parameter whole, or a type that does not mention it.
    (: position (impl (Fn TypeVariable Type -> (Option Position))))
    (define (position erased type)
      (cond ((erased? erased type) (Some (Erased)))
            ((mentions? erased type) (None))
            (else (Some (Fixed)))))

    (: whole (impl (Fn TypeVariable Type -> Position)))
    (define (whole erased type)
      (if (erased? erased type) (Erased) (Fixed)))

    (: erased? (impl (Fn TypeVariable Type -> Bool)))
    (define (erased? erased type)
      (same-type? type (Var erased)))

    ;; Whether `type` mentions the erased parameter anywhere the old
    ;; compiler's `mentions?` looks: a type's arguments, a callable's or
    ;; code's parameters, result and row, and a row's tail.
    (: mentions? (impl (Fn TypeVariable Type -> Bool)))
    (define (mentions? erased type)
      (match type
        ((Var variable) (same-variable? variable erased))
        ((Con _ arguments)
         (any? (lambda (argument) (mentions? erased argument)) arguments))
        ((Callable _ _ arrow) (arrow-mentions? erased arrow))
        ((Code arrow) (arrow-mentions? erased arrow))
        ((Row effects) (tail-mentions? erased effects))))

    (: arrow-mentions? (impl (Fn TypeVariable Arrow -> Bool)))
    (define (arrow-mentions? erased arrow)
      (or (tail-mentions? erased (::effects arrow))
          (mentions? erased (::result arrow))
          (any? (lambda (parameter) (mentions? erased parameter)) (::parameters arrow))))

    (: tail-mentions? (impl (Fn TypeVariable Effects -> Bool)))
    (define (tail-mentions? erased effects)
      (match (::tail effects)
        ((Some tail) (mentions? erased tail))
        ((None) #f)))

    )

  ;; ---- Tests ----

  (cond-expand
   (snail-tests
    (export
     test-domains)
    (import
     (snail compiler source)
     (only (snail compiler types type) FnMutContract)
     (only (snail compiler names globals) Global ClassGlobal Label)
     (only (snail compiler names libraries) forms-library)
     (only (snail compiler builtins base) drop-class)
     (snail stage0 testing))
    (begin
      (define (test-domains)
        (test-heads)
        (test-targets)
        (test-requirements)
        (test-positions))

      (define loc (Loc "t.sld" 4 1))
      (define main (list "main"))
      (define base (list "snail" "core" "base"))

      (define (builtin name)
        (Con (Global forms-library name 0) (list)))

      (define i64 (builtin "I64"))
      (define f64 (builtin "F64"))
      (define t (Written "T"))
      (define e (Written "e"))
      (define dyn-cast-row (Row (Effects (list dyn-cast-effect) (None))))

      (define (list-of type)
        (Con (Global base "List" 0) (list type)))

      ;; (Num e T), whose e is a row.
      (define num
        (KnownClass (list (declared-RowParameter "e") (declared-TypeParameter "T")) (list) (list)))

      (define (instance class variables requirements types outputs)
        (declared-Instance (Global main "Num" 1)
                           class
                           variables
                           types
                           outputs
                           requirements
                           (list)
                           (declared-Dispatch (list) loc)
                           loc))

      (define num-class (ClassGlobal (Global base "Num" 0)))

      (define (num-at row type)
        (instance num-class (list) (list) (list row type) (list)))

      ;; The head is ground with one Any, outputs counted, and the class
      ;; no lifecycle class; the erased parameter is the one at Any.
      (define (test-heads)
        (expect (clause-domain num (num-at dyn-cast-row any-type) (list i64))
                (Ok (Domain t (list (Pair e dyn-cast-row)) (list i64))))
        (expect (clause-domain num (num-at dyn-cast-row i64) (list i64))
                (Err "dispatch needs a ground instance head with exactly one Any type argument"))
        (expect (clause-domain (KnownClass (list (declared-TypeParameter "A")
                                                 (declared-TypeParameter "B"))
                                           (list)
                                           (list))
                               (instance num-class (list) (list) (list any-type any-type) (list))
                               (list i64))
                (Err "dispatch needs a ground instance head with exactly one Any type argument"))
        (expect (clause-domain num
                               (instance num-class
                                 (list e)
                                 (list)
                                 (list (Var e) any-type)
                                 (list))
                               (list i64))
                (Err "dispatch needs a ground instance head with exactly one Any type argument"))
        (expect (clause-domain (KnownClass (list (declared-TypeParameter "T"))
                                           (list (declared-Output (Label "Out" loc) (list)))
                                           (list))
                               (instance (ClassGlobal (Global main "Read" 0))
                                 (list)
                                 (list)
                                 (list i64)
                                 (list any-type))
                               (list i64))
                (Ok (Domain (Written "Out") (list (Pair t i64)) (list i64))))
        (expect (clause-domain num
                               (instance (ClassGlobal drop-class)
                                 (list)
                                 (list)
                                 (list dyn-cast-row any-type)
                                 (list))
                               (list i64))
                (Err "dispatch needs a ground instance head with exactly one Any type argument")))

      ;; At least one target, each ground and none Any, none repeated, in
      ;; that order (error-dynamic-instance-empty.sld, -any.sld and
      ;; -duplicate.sld).
      (define (test-targets)
        (let ((domain
               (lambda (targets) (clause-domain num (num-at dyn-cast-row any-type) targets))))
          (expect (domain (list)) (Err "dispatch needs at least one concrete type"))
          (expect (domain (list any-type))
                  (Err "dispatch accepts concrete types, not Any or type variables"))
          (expect (domain (list (list-of (Var t))))
                  (Err "dispatch accepts concrete types, not Any or type variables"))
          (expect (domain (list (Row (Effects (list) (Some (Var e))))))
                  (Err "dispatch accepts concrete types, not Any or type variables"))
          (expect (domain (list i64 i64)) (Err "dispatch repeats a concrete type"))
          (expect (domain (list i64 any-type i64))
                  (Err "dispatch accepts concrete types, not Any or type variables"))
          (expect (domain (list i64 (list-of i64) dyn-cast-row))
                  (Ok
                   (Domain t (list (Pair e dyn-cast-row)) (list i64 (list-of i64) dyn-cast-row))))))

      (define (function parameters result)
        (Callable (Dyn)
                  (FnContract)
                  (Arrow parameters
                         result
                         (Effects (list) (Some (Var e))))))

      (define num-domain (Domain t (list (Pair e dyn-cast-row)) (list i64 f64)))

      (define (own variables requirements type)
        (Scheme variables requirements (list) type))

      ;; A method of its own requirements is refused before one of its own
      ;; variables; a method that is no function after that.
      (define (test-requirements)
        (expect (method-shape num-domain
                              (own (list (Written "b"))
                                   (list (ClassRequirement num-class
                                                           (list dyn-cast-row
                                                                 (Var
                                                                  (Written
                                                                   "b")))))
                                   (function (list (Var t)) (Var t))))
                (Err "dispatch does not support methods with additional class requirements"))
        (expect (method-shape num-domain
                              (own (list (Written "b"))
                                   (list)
                                   (function (list (Var t)) (Var t))))
                (Err "dispatch does not support independently polymorphic methods"))
        (expect (method-shape num-domain
                              (own (list)
                                   (list)
                                   (Callable (Dyn)
                                             (FnMutContract)
                                             (Arrow (list (Var t))
                                                    i64
                                                    (Effects (list)
                                                             (None))))))
                (Err "dispatch needs function methods"))
        (expect (method-shape num-domain (own (list) (list) (Var t)))
                (Err "dispatch needs function methods")))

      ;; The result and each parameter whole or apart from the erased
      ;; parameter, the result first; the first parameter that is it
      ;; selects (error-dynamic-instance-nested.sld and -result.sld).
      (define (test-positions)
        (let ((shape (lambda (parameters result)
                       (method-shape num-domain (own (list) (list) (function parameters result))))))
          (expect (shape (list (Var t) (Var t)) (Var t))
                  (Ok (MethodShape (list (Erased) (Erased)) 0 (Erased))))
          (expect (shape (list i64 (Var t)) (builtin "String"))
                  (Ok (MethodShape (list (Fixed) (Erased)) 1 (Fixed))))
          (expect (shape (list (list-of (Var t))) (builtin "String"))
                  (Err "dispatch needs the erased class type as a whole parameter or result"))
          (expect (shape (list (builtin "String")) (Var t))
                  (Err "each dispatched method needs an argument of its erased class type"))
          (expect (shape (list (builtin "String")) (list-of (Var t)))
                  (Err "dispatch needs the erased class type as a whole parameter or result"))
          (expect (shape (list (function (list (Var t)) i64) (Var t)) i64)
                  (Err "dispatch needs the erased class type as a whole parameter or result"))))))
   (else)))
